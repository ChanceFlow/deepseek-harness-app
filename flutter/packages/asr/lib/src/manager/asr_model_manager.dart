/// High-level orchestration manager for ASR models.
library;

import 'dart:async';
import 'dart:io';

import '../downloader/asr_downloader.dart';
import '../manifest/model_manifest.dart';
import '../registry/models_registry.dart';
import '../source/model_source_client.dart';

/// Function signature for inspecting available disk space in bytes.
typedef DiskSpaceChecker = Future<int> Function(String directoryPath);

/// Manages ASR model lifecycles, single-concurrency downloads, and storage.
class AsrModelManager {
  AsrModelManager({
    required this.baseModelsDir,
    required this.registry,
    AsrDownloader? downloader,
    DiskSpaceChecker? diskSpaceChecker,
    this.defaultSource = ModelSource.hfMirror,
    this.allowCellular = false,
  })  : _downloader = downloader ?? AsrDownloader(),
        _diskSpaceChecker = diskSpaceChecker ?? _defaultDiskSpaceChecker;

  final Directory baseModelsDir;
  final ModelsRegistry registry;
  final AsrDownloader _downloader;
  final DiskSpaceChecker _diskSpaceChecker;

  ModelSource defaultSource;
  bool allowCellular;

  String? _activeDownloadingModelId;
  String? get activeDownloadingModelId => _activeDownloadingModelId;

  static Future<int> _defaultDiskSpaceChecker(String path) async {
    // Default fallback returns a generous 10 GB if native statvfs isn't available
    return 10 * 1024 * 1024 * 1024;
  }

  void setDefaultSource(ModelSource source) {
    defaultSource = source;
  }

  void setAllowCellular(bool allow) {
    allowCellular = allow;
  }

  Directory getModelDir(String modelId) =>
      Directory('${baseModelsDir.path}/$modelId');

  ModelRegistryEntry getStatus(String modelId) {
    return registry.getEntry(
      modelId,
      defaultLocalDir: getModelDir(modelId).path,
    );
  }

  int get installedCount => registry.installedCount;
  int get totalCount => registry.totalCount;

  /// ID of the currently active model selected for speech recognition.
  String? get activeModelId => registry.activeModelId;

  /// Sets the active speech recognition model.
  Future<void> setActiveModelId(String? modelId) async {
    await registry.setActiveModelId(modelId);
  }

  /// Returns the configured active model if installed, or the first
  /// installed model from the manifest, or null if no models are installed.
  AsrModelInfo? getActiveModel() {
    final activeId = registry.activeModelId;
    if (activeId != null) {
      final entry = getStatus(activeId);
      if (entry.isDownloaded) {
        return AsrModelManifest.findById(activeId);
      }
    }
    // Fallback: pick first downloaded model
    for (final info in AsrModelManifest.all) {
      final entry = getStatus(info.id);
      if (entry.isDownloaded) {
        return info;
      }
    }
    return null;
  }

  Stream<Map<String, ModelRegistryEntry>> get updates => registry.updates;

  /// Starts downloading [modelId] using [sourceOverride] or [defaultSource].
  Future<void> startDownload(
    String modelId, {
    ModelSource? sourceOverride,
    bool isCellular = false,
  }) async {
    final AsrModelInfo? model = AsrModelManifest.findById(modelId);
    if (model == null) {
      throw ArgumentError('Unknown ASR model id: $modelId');
    }

    if (_activeDownloadingModelId != null && _activeDownloadingModelId != modelId) {
      throw StateError('Another download is currently in progress: $_activeDownloadingModelId');
    }

    if (isCellular && !allowCellular) {
      throw const DownloadFailedException(
        'Cellular download is disabled by default. Please enable cellular downloads in settings.',
      );
    }

    final Directory modelDir = getModelDir(modelId);
    final int requiredBytes = (model.estimatedSizeBytes * 1.3).round();
    final int availableBytes = await _diskSpaceChecker(baseModelsDir.path);
    if (availableBytes < requiredBytes) {
      final ModelRegistryEntry failedEntry = getStatus(modelId).copyWith(
        status: AsrModelStatus.failed,
        lastError: 'Insufficient storage space: required ${(requiredBytes / (1024 * 1024)).toStringAsFixed(1)} MB',
      );
      await registry.updateEntry(failedEntry);
      throw const DownloadFailedException('Insufficient storage space');
    }

    final ModelSource source = sourceOverride ?? defaultSource;
    final ModelSourceClient sourceClient = source == ModelSource.hfMirror
        ? const HfMirrorSourceClient()
        : const HuggingFaceSourceClient();

    _activeDownloadingModelId = modelId;
    ModelRegistryEntry entry = getStatus(modelId).copyWith(
      source: source,
      localDir: modelDir.path,
      status: AsrModelStatus.downloading,
      totalBytes: model.estimatedSizeBytes,
      clearError: true,
    );
    await registry.updateEntry(entry);

    try {
      await _downloader.downloadModel(
        model: model,
        sourceClient: sourceClient,
        targetDir: modelDir,
        onProgress: (DownloadProgress p) {
          entry = entry.copyWith(
            downloadedBytes: p.downloadedBytes,
            totalBytes: p.totalBytes,
          );
          registry.updateEntry(entry);
        },
      );

      final int actualDiskBytes = await getActualDiskUsage(modelId);
      entry = entry.copyWith(
        status: AsrModelStatus.downloaded,
        downloadedBytes: actualDiskBytes,
        totalBytes: actualDiskBytes,
        downloadedAt: DateTime.now(),
        clearError: true,
      );
      await registry.updateEntry(entry);
    } on DownloadCanceledException {
      entry = entry.copyWith(
        status: AsrModelStatus.canceled,
        clearError: true,
      );
      await registry.updateEntry(entry);
      rethrow;
    } catch (e) {
      entry = entry.copyWith(
        status: AsrModelStatus.failed,
        lastError: e.toString(),
      );
      await registry.updateEntry(entry);
      rethrow;
    } finally {
      if (_activeDownloadingModelId == modelId) {
        _activeDownloadingModelId = null;
      }
    }
  }

  /// Retries a failed or canceled download by switching to [targetSource].
  Future<void> retryWithSource(
    String modelId,
    ModelSource targetSource, {
    bool isCellular = false,
  }) async {
    await startDownload(
      modelId,
      sourceOverride: targetSource,
      isCellular: isCellular,
    );
  }

  /// Cancels an in-flight download.
  Future<void> cancelDownload(String modelId) async {
    if (_activeDownloadingModelId == modelId) {
      _downloader.cancel();
      _activeDownloadingModelId = null;
    }
    final ModelRegistryEntry entry = getStatus(modelId).copyWith(
      status: AsrModelStatus.canceled,
      clearError: true,
    );
    await registry.updateEntry(entry);
  }

  /// Deletes an installed or partially downloaded model from disk and updates registry.
  Future<void> deleteModel(String modelId) async {
    if (_activeDownloadingModelId == modelId) {
      _downloader.cancel();
      _activeDownloadingModelId = null;
    }

    final Directory dir = getModelDir(modelId);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }

    await registry.removeEntry(modelId);
  }

  /// Computes actual disk usage of the model folder in bytes.
  Future<int> getActualDiskUsage(String modelId) async {
    final Directory dir = getModelDir(modelId);
    if (!await dir.exists()) return 0;

    int total = 0;
    try {
      await for (final FileSystemEntity entity in dir.list(recursive: true)) {
        if (entity is File) {
          total += await entity.length();
        }
      }
    } catch (_) {}
    return total;
  }
}
