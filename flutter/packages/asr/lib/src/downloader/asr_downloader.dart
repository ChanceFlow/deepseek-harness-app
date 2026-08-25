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
  const DownloadFailedException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => statusCode != null
      ? 'DownloadFailedException(HTTP $statusCode: $message)'
      : 'DownloadFailedException($message)';
}

/// Downloads model artifacts with HTTP Range resumption, SHA-256 verification,
/// and throttled progress reporting.
class AsrDownloader {
  AsrDownloader({http.Client? httpClient})
      : _httpClient = httpClient ?? http.Client();

  final http.Client _httpClient;
  bool _isCanceled = false;

  /// Cancels the in-flight download.
  void cancel() {
    _isCanceled = true;
  }

  /// Downloads all files for [model] from [sourceClient] into [targetDir].
  ///
  /// Emits progress via [onProgress] at most once every 500ms (and upon completion).
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

    int modelDownloadedBytes = 0;
    // Calculate already-downloaded bytes from previously completed files and partial downloads
    for (final AsrModelFile file in model.files) {
      final File finishedFile = File('${targetDir.path}/${file.name}');
      final File partialFile = File('${targetDir.path}/${file.name}.downloading');
      if (await finishedFile.exists()) {
        modelDownloadedBytes += await finishedFile.length();
      } else if (await partialFile.exists()) {
        modelDownloadedBytes += await partialFile.length();
      }
    }

    DateTime lastEmitTime = DateTime.now();
    int lastEmitBytes = modelDownloadedBytes;
    double currentSpeed = 0.0;

    void emitProgress(String currentFileName, int completedFiles, {bool force = false}) {
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
      final File partialFile = File('${targetDir.path}/${fileSpec.name}.downloading');

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
      int startByte = 0;
      if (await partialFile.exists()) {
        startByte = await partialFile.length();
        if (startByte > fileSpec.sizeBytes) {
          // Truncate or reset if temp file is somehow bigger than expected
          await partialFile.delete();
          startByte = 0;
        }
      }

      final http.Request request = http.Request('GET', Uri.parse(fileUrl));
      request.headers.addAll(sourceClient.getHeaders());
      if (startByte > 0) {
        request.headers['Range'] = 'bytes=$startByte-';
      }

      http.StreamedResponse response;
      try {
        response = await _httpClient.send(request);
      } catch (e) {
        if (_isCanceled) throw const DownloadCanceledException();
        throw DownloadFailedException('Connection failed: $e');
      }

      if (_isCanceled) throw const DownloadCanceledException();

      FileMode writeMode = FileMode.write;
      if (response.statusCode == 206) {
        // Range accepted, append to partial file
        writeMode = FileMode.append;
      } else if (response.statusCode == 200) {
        // Full response, restart from 0
        writeMode = FileMode.write;
        if (startByte > 0) {
          modelDownloadedBytes -= startByte;
          startByte = 0;
        }
      } else if (response.statusCode == 416) {
        // Range not satisfiable, reset partial file and re-request full
        if (await partialFile.exists()) {
          await partialFile.delete();
        }
        modelDownloadedBytes -= startByte;
        startByte = 0;
        final http.Request freshRequest = http.Request('GET', Uri.parse(fileUrl));
        freshRequest.headers.addAll(sourceClient.getHeaders());
        response = await _httpClient.send(freshRequest);
        if (response.statusCode != 200) {
          throw DownloadFailedException('HTTP error', statusCode: response.statusCode);
        }
        writeMode = FileMode.write;
      } else {
        throw DownloadFailedException(
          response.reasonPhrase ?? 'HTTP Error',
          statusCode: response.statusCode,
        );
      }

      final IOSink sink = partialFile.openWrite(mode: writeMode);

      try {
        await for (final List<int> chunk in response.stream) {
          if (_isCanceled) {
            throw const DownloadCanceledException();
          }
          sink.add(chunk);
          modelDownloadedBytes += chunk.length;
          emitProgress(fileSpec.name, completedCount);
        }
        await sink.flush();
      } catch (e) {
        if (_isCanceled || e is DownloadCanceledException) {
          throw const DownloadCanceledException();
        }
        rethrow;
      } finally {
        await sink.close();
      }

      if (_isCanceled) {
        throw const DownloadCanceledException();
      }

      // Verification: Check size and rename .downloading -> final filename
      if (_isCanceled) {
        throw const DownloadCanceledException();
      }

      final int partialLen = await partialFile.length();
      if (partialLen != fileSpec.sizeBytes) {
        throw DownloadFailedException(
          'File size mismatch for ${fileSpec.name}: expected ${fileSpec.sizeBytes}, got $partialLen',
        );
      }

      // Content verification: runs only when the manifest carries a real
      // checksum; an unprovisioned (empty) hash falls back to the size
      // check above. A failed digest deletes the partial file so a retry
      // downloads from scratch instead of resuming corrupt bytes.
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
      completedCount++;
      emitProgress(fileSpec.name, completedCount, force: true);
    }
  }

  /// Verifies the SHA-256 checksum of an on-disk file against the expected hash.
  static Future<bool> verifySha256(File file, String expectedSha256) async {
    if (!await file.exists()) return false;
    final Digest digest = await sha256.bind(file.openRead()).first;
    return digest.toString().toLowerCase() == expectedSha256.toLowerCase();
  }
}
