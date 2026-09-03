/// HTTP Range-aware downloader for ASR model files.
library;

import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../manifest/model_manifest.dart';
import '../source/model_source_client.dart';

/// Progress information emitted during download.
class DownloadProgress {
  const DownloadProgress({
    required this.downloadedBytes,
    required this.totalBytes,
    required this.speedBytesPerSecond,
    required this.currentFileName,
    required this.completedFiles,
    required this.totalFiles,
  });

  final int downloadedBytes;
  final int totalBytes;
  final double speedBytesPerSecond;
  final String currentFileName;
  final int completedFiles;
  final int totalFiles;

  double get fraction {
    if (totalBytes <= 0) return 0.0;
    return (downloadedBytes / totalBytes).clamp(0.0, 1.0);
  }
}

/// Download cancellation exception.
class DownloadCanceledException implements Exception {
  const DownloadCanceledException();

  @override
  String toString() => 'Download was canceled by user';
}

/// Error during download execution.
class DownloadFailedException implements Exception {
  const DownloadFailedException(
    this.message, {
    this.statusCode,
    this.transient = false,
  });

  final String message;
  final int? statusCode;

  /// Whether the failure is a network-level hiccup a resumable retry can
  /// plausibly heal: a dropped body, a stalled connection, a server error.
  /// The downloader retries transient failures automatically; permanent
  /// ones (4xx, checksum mismatch) fail immediately.
  final bool transient;

  @override
  String toString() => statusCode != null
      ? 'DownloadFailedException(HTTP $statusCode: $message)'
      : 'DownloadFailedException($message)';
}

/// Downloads model artifacts with HTTP Range resumption, bounded automatic
/// retries where every retry resumes from the bytes already on disk,
/// SHA-256 verification, and throttled progress reporting.
class AsrDownloader {
  AsrDownloader({
    http.Client? httpClient,
    this.maxAttemptsPerFile = defaultMaxAttemptsPerFile,
    this.stallTimeout = defaultStallTimeout,
    Future<void> Function(int failedAttempt)? retryDelayHandler,
  }) : assert(maxAttemptsPerFile >= 1),
       _httpClient = httpClient ?? http.Client(),
       _retryDelayHandler = retryDelayHandler ?? _defaultRetryDelay;

  /// Retry budget per file before the download fails outright. Each retry
  /// resumes from the partial `.downloading` file, so the budget bounds
  /// wasted attempts, never already-transferred bytes.
  static const int defaultMaxAttemptsPerFile = 4;

  /// A response body that stays silent for this long counts as a stalled
  /// connection and fails the attempt into a resumable retry instead of
  /// hanging the progress bar forever.
  static const Duration defaultStallTimeout = Duration(seconds: 45);

  final http.Client _httpClient;
  final int maxAttemptsPerFile;
  final Duration stallTimeout;
  final Future<void> Function(int failedAttempt) _retryDelayHandler;
  bool _isCanceled = false;

  /// Cancels the in-flight download.
  void cancel() {
    _isCanceled = true;
  }

  /// Default wait before the next attempt: linear backoff capped at 4 s.
  static Future<void> _defaultRetryDelay(int failedAttempt) async {
    final int milliseconds = (500 * failedAttempt).clamp(500, 4000);
    await Future<void>.delayed(Duration(milliseconds: milliseconds));
  }

  /// Sums bytes already on disk for [files]: finished files plus partial
  /// `.downloading` files. This is the single source of progress truth; a
  /// failed attempt reconciles against it so resuming never double-counts.
  static Future<int> _existingBytes(
    Directory targetDir,
    List<AsrModelFile> files,
  ) async {
    int total = 0;
    for (final AsrModelFile file in files) {
      final File finished = File('${targetDir.path}/${file.name}');
      if (await finished.exists()) {
        total += await finished.length();
        continue;
      }
      final File partial = File('${targetDir.path}/${file.name}.downloading');
      if (await partial.exists()) {
        total += await partial.length();
      }
    }
    return total;
  }

  /// Whether [error] is worth retrying: raw network exceptions
  /// (`ClientException`, `SocketException`, `TimeoutException`), a
  /// truncated body, or a transient status (5xx, 408, 429). Permanent
  /// failures — 4xx, checksum mismatch — rethrow immediately.
  static bool _isRetryableFailure(Object error) {
    if (error is! DownloadFailedException) return true;
    final int? statusCode = error.statusCode;
    if (statusCode != null) {
      return statusCode >= 500 || statusCode == 408 || statusCode == 429;
    }
    return error.transient;
  }

  /// Downloads all files for [model] from [sourceClient] into [targetDir].
  ///
  /// Emits progress via [onProgress] at most once every 500ms (and upon
  /// completion). A failed attempt (connection drop mid-body, stalled
  /// stream, transient HTTP status) is retried up to [maxAttemptsPerFile]
  /// times per file with backoff, each retry resuming via HTTP Range from
  /// the bytes already on disk.
  Future<void> downloadModel({
    required AsrModelInfo model,
    required ModelSourceClient sourceClient,
    required Directory targetDir,
    required void Function(DownloadProgress) onProgress,
  }) async {
    if (_isCanceled) throw const DownloadCanceledException();
    _isCanceled = false;
    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
    }

    final int totalModelBytes = model.files.fold<int>(
      0,
      (int sum, AsrModelFile f) => sum + f.sizeBytes,
    );

    int modelDownloadedBytes = await _existingBytes(targetDir, model.files);

    DateTime lastEmitTime = DateTime.now();
    int lastEmitBytes = modelDownloadedBytes;
    double currentSpeed = 0.0;

    void emitProgress(
      String currentFileName,
      int completedFiles, {
      bool force = false,
    }) {
      final DateTime now = DateTime.now();
      final int elapsedMs = now.difference(lastEmitTime).inMilliseconds;
      if (force || elapsedMs >= 500) {
        if (elapsedMs > 0) {
          final int deltaBytes = modelDownloadedBytes - lastEmitBytes;
          currentSpeed = (deltaBytes / elapsedMs) * 1000.0;
        }
        lastEmitTime = now;
        lastEmitBytes = modelDownloadedBytes;
        onProgress(
          DownloadProgress(
            downloadedBytes: modelDownloadedBytes,
            totalBytes: totalModelBytes,
            speedBytesPerSecond: currentSpeed,
            currentFileName: currentFileName,
            completedFiles: completedFiles,
            totalFiles: model.files.length,
          ),
        );
      }
    }

    int completedCount = 0;
    for (int i = 0; i < model.files.length; i++) {
      if (_isCanceled) throw const DownloadCanceledException();

      final AsrModelFile fileSpec = model.files[i];
      final File finishedFile = File('${targetDir.path}/${fileSpec.name}');
      final File partialFile = File(
        '${targetDir.path}/${fileSpec.name}.downloading',
      );

      // If finished file already exists and matches expected size, skip downloading it
      if (await finishedFile.exists()) {
        final int len = await finishedFile.length();
        if (len == fileSpec.sizeBytes) {
          completedCount++;
          emitProgress(fileSpec.name, completedCount);
          continue;
        }
      }

      final String fileUrl = sourceClient.buildFileUrl(model, fileSpec);

      for (int attempt = 1; ; attempt++) {
        if (_isCanceled) throw const DownloadCanceledException();

        // Re-derive the resume position and byte accounting from disk
        // before every attempt: the previous attempt left the partial
        // file behind, and resuming must neither double-count nor lose
        // those bytes.
        int startByte = 0;
        if (await partialFile.exists()) {
          startByte = await partialFile.length();
          if (startByte > fileSpec.sizeBytes) {
            // Truncate or reset if temp file is somehow bigger than expected
            await partialFile.delete();
            startByte = 0;
          }
        }
        modelDownloadedBytes = await _existingBytes(targetDir, model.files);

        try {
          await _attemptFile(
            fileSpec: fileSpec,
            fileUrl: fileUrl,
            headers: sourceClient.getHeaders(),
            startByte: startByte,
            partialFile: partialFile,
            finishedFile: finishedFile,
            onChunk: (int chunkBytes) {
              modelDownloadedBytes += chunkBytes;
              emitProgress(fileSpec.name, completedCount);
            },
            onRestart: (int discardedBytes) {
              modelDownloadedBytes -= discardedBytes;
            },
          );
          break;
        } catch (e) {
          if (_isCanceled || e is DownloadCanceledException) {
            throw const DownloadCanceledException();
          }
          if (attempt >= maxAttemptsPerFile || !_isRetryableFailure(e)) {
            rethrow;
          }
          await _retryDelayHandler(attempt);
          if (_isCanceled) throw const DownloadCanceledException();
        }
      }

      completedCount++;
      emitProgress(fileSpec.name, completedCount, force: true);
    }
  }

  /// One download attempt for [fileSpec]: send the request (with a Range
  /// header when [startByte] > 0), stream the body into [partialFile], and
  /// verify + promote on completion. Throws on failure; transient failures
  /// are classified by [_isRetryableFailure] by the caller.
  Future<void> _attemptFile({
    required AsrModelFile fileSpec,
    required String fileUrl,
    required Map<String, String> headers,
    required int startByte,
    required File partialFile,
    required File finishedFile,
    required void Function(int chunkBytes) onChunk,
    required void Function(int discardedBytes) onRestart,
  }) async {
    http.StreamedResponse response;
    try {
      final http.Request request = http.Request('GET', Uri.parse(fileUrl));
      request.headers.addAll(headers);
      if (startByte > 0) {
        request.headers['Range'] = 'bytes=$startByte-';
      }
      response = await _httpClient.send(request);
    } catch (e) {
      if (_isCanceled) throw const DownloadCanceledException();
      throw DownloadFailedException('Connection failed: $e', transient: true);
    }

    if (_isCanceled) throw const DownloadCanceledException();

    FileMode writeMode;
    if (response.statusCode == 206) {
      // Range accepted, append to partial file
      writeMode = FileMode.append;
    } else if (response.statusCode == 200) {
      // Full response, restart from 0
      writeMode = FileMode.write;
      if (startByte > 0) {
        onRestart(startByte);
      }
    } else if (response.statusCode == 416) {
      // Range not satisfiable: the partial is stale. Drop it and re-request
      // the whole body within this same attempt.
      if (await partialFile.exists()) {
        await partialFile.delete();
      }
      if (startByte > 0) {
        onRestart(startByte);
      }
      try {
        final http.Request freshRequest = http.Request(
          'GET',
          Uri.parse(fileUrl),
        );
        freshRequest.headers.addAll(headers);
        response = await _httpClient.send(freshRequest);
      } catch (e) {
        if (_isCanceled) throw const DownloadCanceledException();
        throw DownloadFailedException('Connection failed: $e', transient: true);
      }
      if (_isCanceled) throw const DownloadCanceledException();
      if (response.statusCode != 200) {
        throw DownloadFailedException(
          response.reasonPhrase ?? 'HTTP Error',
          statusCode: response.statusCode,
        );
      }
      writeMode = FileMode.write;
    } else {
      throw DownloadFailedException(
        response.reasonPhrase ?? 'HTTP Error',
        statusCode: response.statusCode,
        transient: response.statusCode >= 500,
      );
    }

    final IOSink sink = partialFile.openWrite(mode: writeMode);

    try {
      // A body that stays silent beyond [stallTimeout] is a stalled
      // connection: surface it as a retryable failure instead of hanging
      // the session forever.
      await for (final List<int> chunk in response.stream.timeout(
        stallTimeout,
      )) {
        if (_isCanceled) {
          throw const DownloadCanceledException();
        }
        sink.add(chunk);
        onChunk(chunk.length);
      }
      await sink.flush();
    } catch (e) {
      if (_isCanceled || e is DownloadCanceledException) {
        throw const DownloadCanceledException();
      }
      // Chunks received this attempt are already flushed into the partial
      // file (the finally below closes the sink first); the next attempt
      // resumes from there via Range.
      throw DownloadFailedException(
        'Connection interrupted while receiving ${fileSpec.name}: $e',
        transient: true,
      );
    } finally {
      await sink.close();
    }

    if (_isCanceled) {
      throw const DownloadCanceledException();
    }

    // Verification: Check size and rename .downloading -> final filename
    final int partialLen = await partialFile.length();
    if (partialLen != fileSpec.sizeBytes) {
      // A body that ended early without an exception still leaves a
      // resumable partial: retrying continues from here.
      throw DownloadFailedException(
        'File size mismatch for ${fileSpec.name}: expected ${fileSpec.sizeBytes}, got $partialLen',
        transient: true,
      );
    }

    // Content verification: runs only when the manifest carries a real
    // checksum; an unprovisioned (empty) hash falls back to the size
    // check above. A failed digest deletes the partial file so a retry
    // downloads from scratch instead of resuming corrupt bytes — and it
    // is not transient: deterministic corruption will not heal itself.
    if (fileSpec.sha256.isNotEmpty &&
        !await verifySha256(partialFile, fileSpec.sha256)) {
      try {
        await partialFile.delete();
      } catch (_) {
        // Best-effort cleanup; a stale partial is truncated on retry.
      }
      throw DownloadFailedException(
        'SHA-256 mismatch for ${fileSpec.name}: expected ${fileSpec.sha256}',
      );
    }

    if (await finishedFile.exists()) {
      await finishedFile.delete();
    }
    await partialFile.rename(finishedFile.path);
  }

  /// Verifies the SHA-256 checksum of an on-disk file against the expected hash.
  static Future<bool> verifySha256(File file, String expectedSha256) async {
    if (!await file.exists()) return false;
    final Digest digest = await sha256.bind(file.openRead()).first;
    return digest.toString().toLowerCase() == expectedSha256.toLowerCase();
  }
}
