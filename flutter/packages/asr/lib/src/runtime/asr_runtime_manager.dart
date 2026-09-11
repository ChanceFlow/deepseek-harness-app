/// Installs and locates the on-device ASR runtime.
///
/// The runtime is the sherpa-onnx pair the offline engine maps
/// ([kAsrRuntimeArtifacts]): it is not in the APK, so the engine can only
/// start once this manager has put the libraries on disk and handed their
/// directory to `sherpa.initBindings`.
///
/// The download reuses [AsrDownloader]: the same bounded retries, HTTP Range
/// resumption, stall detection and SHA-256 verification the model downloads
/// get. A release asset is served raw (no archive layer), so the verified
/// bytes are the bytes the loader maps — there is no unpack step whose output
/// an attacker could swap after verification.
///
/// Storage layout (per ABI and per sherpa release, so a version bump installs
/// beside the old set instead of half-overwriting it):
///
///     <baseDir>/sherpa-onnx/<kSherpaOnnxVersion>/<abi>/
///       libonnxruntime.so
///       libsherpa-onnx-c-api.so
///       .complete            ← written last; the install marker
library;

import 'dart:async';
import 'dart:io';

import 'package:meta/meta.dart';

import '../downloader/asr_downloader.dart';
import '../manifest/model_manifest.dart';
import '../source/model_source_client.dart';
import 'asr_runtime_manifest.dart';

/// Where a runtime install stands.
enum AsrRuntimeStatus {
  /// Not asked yet; [AsrRuntimeManager.refresh] publishes the real answer.
  unknown,
  missing,
  downloading,
  ready,
  failed,
}

/// One observable runtime state.
final class AsrRuntimeState {
  const AsrRuntimeState({
    required this.status,
    this.downloadedBytes = 0,
    this.totalBytes = 0,
    this.errorMessage,
  });

  final AsrRuntimeStatus status;
  final int downloadedBytes;
  final int totalBytes;
  final String? errorMessage;

  bool get isReady => status == AsrRuntimeStatus.ready;
  bool get isDownloading => status == AsrRuntimeStatus.downloading;

  double get fraction =>
      totalBytes <= 0 ? 0 : (downloadedBytes / totalBytes).clamp(0.0, 1.0);

  AsrRuntimeState copyWith({
    AsrRuntimeStatus? status,
    int? downloadedBytes,
    int? totalBytes,
    String? errorMessage,
    bool clearError = false,
  }) => AsrRuntimeState(
    status: status ?? this.status,
    downloadedBytes: downloadedBytes ?? this.downloadedBytes,
    totalBytes: totalBytes ?? this.totalBytes,
    errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
  );
}

/// Serves the runtime asset URLs: the release page of the build that needs
/// them, one asset per library.
final class _ReleaseSourceClient implements ModelSourceClient {
  const _ReleaseSourceClient();

  @override
  ModelSource get source => ModelSource.huggingFace;

  @override
  String buildFileUrl(AsrModelInfo model, AsrModelFile file) =>
      file.huggingFaceUrl;

  @override
  Map<String, String> getHeaders() => <String, String>{
    'User-Agent': 'DeepSeekHarness-Android/1.0',
    'Accept': '*/*',
  };
}

/// Owns one ABI's runtime install for the process.
class AsrRuntimeManager {
  AsrRuntimeManager({
    required this.baseDir,
    required this.baseUrl,
    required this.tag,
    required this.abi,
    AsrDownloader? downloader,
    this.artifactOverride,
  }) : _downloader = downloader ?? AsrDownloader();

  /// App-writable root (the ASR models directory's parent).
  final Directory baseDir;

  /// Release-download base, e.g.
  /// `https://github.com/ChanceFlow/deepseek-harness-app/releases/download`.
  final String baseUrl;

  /// The release tag whose assets this build installs from (`dev`, `v0.1.3`).
  final String tag;

  /// Device ABI (`arm64-v8a`, `armeabi-v7a`, `x86_64`).
  final String abi;

  final AsrDownloader _downloader;

  /// A test's stand-in for the published manifest: the real libraries are
  /// tens of megabytes with pinned hashes, so the download path is exercised
  /// against a tiny artifact instead.
  @visibleForTesting
  final AsrRuntimeArtifact? artifactOverride;
  final StreamController<AsrRuntimeState> _states =
      StreamController<AsrRuntimeState>.broadcast();
  AsrRuntimeState _state = const AsrRuntimeState(
    status: AsrRuntimeStatus.unknown,
  );

  /// The ABI's artifact, or null on a device this app does not ship for —
  /// in which case the runtime can never be installed and the offline engine
  /// stays unavailable.
  AsrRuntimeArtifact? get artifact =>
      artifactOverride ?? asrRuntimeArtifactFor(abi);

  AsrRuntimeState get state => _state;
  Stream<AsrRuntimeState> get states => _states.stream;

  Directory get runtimeDir =>
      Directory('${baseDir.path}/sherpa-onnx/$kSherpaOnnxVersion/$abi');

  File get _marker => File('${runtimeDir.path}/.complete');

  /// Publishes the install state by looking at the disk (marker plus each
  /// library's size). Runs on every surface that can show or start the
  /// offline engine, so it does no hashing: the download verified content
  /// hashes when it landed, and a size check catches truncation.
  Future<AsrRuntimeState> refresh() async {
    final bool installed = await isInstalled();
    _emit(
      _state.copyWith(
        status: installed ? AsrRuntimeStatus.ready : AsrRuntimeStatus.missing,
        downloadedBytes: installed ? (_artifactBytes ?? 0) : 0,
        totalBytes: _artifactBytes ?? 0,
        clearError: true,
      ),
    );
    return _state;
  }

  int? get _artifactBytes => artifact?.totalBytes;

  /// Whether every library of this ABI is present and plausible.
  Future<bool> isInstalled() async {
    final AsrRuntimeArtifact? artifact = this.artifact;
    if (artifact == null) return false;
    if (!await _marker.exists()) return false;
    for (final AsrRuntimeLib lib in artifact.libs) {
      final File file = File('${runtimeDir.path}/${lib.name}');
      if (!await file.exists()) return false;
      if (await file.length() != lib.sizeBytes) return false;
    }
    return true;
  }

  /// The directory to hand `sherpa.initBindings`, or null while the runtime
  /// is not installed.
  Future<String?> installedLibraryDir() async =>
      await isInstalled() ? runtimeDir.path : null;

  /// Downloads and installs the runtime, publishing progress as it goes.
  ///
  /// A failure leaves whatever arrived on disk without the marker, so the
  /// next attempt resumes from the partial file (HTTP Range) and a half
  /// install never reads as ready.
  Future<void> install() async {
    final AsrRuntimeArtifact? artifact = this.artifact;
    if (artifact == null) {
      throw StateError('no ASR runtime is published for ABI "$abi"');
    }
    if (_state.isDownloading) return;
    if (!await runtimeDir.exists()) {
      await runtimeDir.create(recursive: true);
    }
    if (await _marker.exists()) await _marker.delete();

    _emit(
      AsrRuntimeState(
        status: AsrRuntimeStatus.downloading,
        totalBytes: artifact.totalBytes,
      ),
    );
    try {
      await _downloader.downloadModel(
        model: _runtimeModel(artifact),
        sourceClient: const _ReleaseSourceClient(),
        targetDir: runtimeDir,
        onProgress: (DownloadProgress progress) {
          _emit(
            _state.copyWith(
              status: AsrRuntimeStatus.downloading,
              downloadedBytes: progress.downloadedBytes,
              totalBytes: progress.totalBytes,
            ),
          );
        },
      );
      await _marker.writeAsString('$kSherpaOnnxVersion\n$abi\n', flush: true);
      _emit(
        AsrRuntimeState(
          status: AsrRuntimeStatus.ready,
          downloadedBytes: artifact.totalBytes,
          totalBytes: artifact.totalBytes,
        ),
      );
    } on DownloadCanceledException {
      await refresh();
      rethrow;
    } catch (error) {
      _emit(
        _state.copyWith(
          status: AsrRuntimeStatus.failed,
          errorMessage: error.toString(),
        ),
      );
      rethrow;
    }
  }

  /// Removes the installed runtime; the offline engine stops being available
  /// until the next install.
  Future<void> uninstall() async {
    if (await runtimeDir.exists()) {
      await runtimeDir.delete(recursive: true);
    }
    await refresh();
  }

  /// The downloader's model shape for one ABI's library set: every file's URL
  /// is its release asset, and the pinned size/hash are the library's own, so
  /// [AsrDownloader] verifies exactly the bytes the loader maps.
  AsrModelInfo _runtimeModel(AsrRuntimeArtifact artifact) => AsrModelInfo(
    id: 'asr-runtime-$kSherpaOnnxVersion-$abi',
    name: 'sherpa-onnx $kSherpaOnnxVersion',
    descriptionZh: '离线语音识别运行时（sherpa-onnx + onnxruntime）',
    descriptionEn:
        'On-device speech recognition runtime (sherpa-onnx + onnxruntime)',
    languages: '',
    estimatedSizeBytes: artifact.totalBytes,
    license: 'Apache-2.0',
    huggingFaceRepo: '',
    files: <AsrModelFile>[
      for (final AsrRuntimeLib lib in artifact.libs)
        AsrModelFile(
          name: lib.name,
          sizeBytes: lib.sizeBytes,
          sha256: lib.sha256,
          huggingFaceUrl: _assetUrl(lib),
          hfMirrorUrl: _assetUrl(lib),
        ),
    ],
  );

  String _assetUrl(AsrRuntimeLib lib) => '$baseUrl/$tag/${lib.assetName(abi)}';

  void _emit(AsrRuntimeState next) {
    _state = next;
    if (!_states.isClosed) _states.add(next);
  }

  Future<void> dispose() async {
    await _states.close();
  }
}
