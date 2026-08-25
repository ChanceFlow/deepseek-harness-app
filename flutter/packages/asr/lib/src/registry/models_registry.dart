/// Registry for installed and downloading ASR models.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../manifest/model_manifest.dart';

/// Execution and storage lifecycle state of an ASR model.
enum AsrModelStatus {
  idle('idle'),
  downloading('downloading'),
  downloaded('downloaded'),
  failed('failed'),
  canceled('canceled'),
  deleting('deleting');

  const AsrModelStatus(this.id);

  final String id;

  static AsrModelStatus fromId(String id) {
    for (final AsrModelStatus status in AsrModelStatus.values) {
      if (status.id == id) return status;
    }
    return AsrModelStatus.idle;
  }
}

/// A persisted registry record for one model.
class ModelRegistryEntry {
  const ModelRegistryEntry({
    required this.modelId,
    required this.source,
    required this.localDir,
    required this.status,
    this.totalBytes = 0,
    this.downloadedBytes = 0,
    this.lastError,
    this.downloadedAt,
    this.versionHash,
  });

  final String modelId;
  final ModelSource source;
  final String localDir;
  final AsrModelStatus status;
  final int totalBytes;
  final int downloadedBytes;
  final String? lastError;
  final DateTime? downloadedAt;
  final String? versionHash;

  double get progress {
    if (totalBytes <= 0) return 0.0;
    final double p = downloadedBytes / totalBytes;
    return p.clamp(0.0, 1.0);
  }

  bool get isDownloaded => status == AsrModelStatus.downloaded;
  bool get isDownloading => status == AsrModelStatus.downloading;

  ModelRegistryEntry copyWith({
    String? modelId,
    ModelSource? source,
    String? localDir,
    AsrModelStatus? status,
    int? totalBytes,
    int? downloadedBytes,
    String? lastError,
    DateTime? downloadedAt,
    String? versionHash,
    bool clearError = false,
  }) {
    return ModelRegistryEntry(
      modelId: modelId ?? this.modelId,
      source: source ?? this.source,
      localDir: localDir ?? this.localDir,
      status: status ?? this.status,
      totalBytes: totalBytes ?? this.totalBytes,
      downloadedBytes: downloadedBytes ?? this.downloadedBytes,
      lastError: clearError ? null : (lastError ?? this.lastError),
      downloadedAt: downloadedAt ?? this.downloadedAt,
      versionHash: versionHash ?? this.versionHash,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'modelId': modelId,
    'source': source.id,
    'localDir': localDir,
    'status': status.id,
    'totalBytes': totalBytes,
    'downloadedBytes': downloadedBytes,
    if (lastError != null) 'lastError': lastError,
    if (downloadedAt != null) 'downloadedAt': downloadedAt!.toIso8601String(),
    if (versionHash != null) 'versionHash': versionHash,
  };

  factory ModelRegistryEntry.fromJson(Map<String, dynamic> json) {
    return ModelRegistryEntry(
      modelId: json['modelId'] as String? ?? '',
      source: ModelSource.fromId(json['source'] as String? ?? ''),
      localDir: json['localDir'] as String? ?? '',
      status: AsrModelStatus.fromId(json['status'] as String? ?? ''),
      totalBytes: (json['totalBytes'] as num?)?.toInt() ?? 0,
      downloadedBytes: (json['downloadedBytes'] as num?)?.toInt() ?? 0,
      lastError: json['lastError'] as String?,
      downloadedAt: json['downloadedAt'] != null
          ? DateTime.tryParse(json['downloadedAt'] as String)
          : null,
      versionHash: json['versionHash'] as String?,
    );
  }
}

/// Durable store for tracking installed model artifacts on device.
class ModelsRegistry {
  ModelsRegistry({required this.registryFile});

  final File registryFile;
  final Map<String, ModelRegistryEntry> _entries =
      <String, ModelRegistryEntry>{};
  String? _activeModelId;
  final StreamController<Map<String, ModelRegistryEntry>> _streamController =
      StreamController<Map<String, ModelRegistryEntry>>.broadcast();

  Stream<Map<String, ModelRegistryEntry>> get updates =>
      _streamController.stream;

  Map<String, ModelRegistryEntry> get entries =>
      Map<String, ModelRegistryEntry>.unmodifiable(_entries);

  /// ID of the currently selected active speech model for voice input.
  String? get activeModelId => _activeModelId;

  int get installedCount => _entries.values
      .where((ModelRegistryEntry e) => e.status == AsrModelStatus.downloaded)
      .length;

  int get totalCount => AsrModelManifest.all.length;

  /// Loads registry from disk. Rebuilds cleanly on file corruption.
  Future<void> load() async {
    _entries.clear();
    if (!await registryFile.exists()) {
      _notify();
      return;
    }

    try {
      final String content = await registryFile.readAsString();
      if (content.trim().isEmpty) {
        _notify();
        return;
      }
      final dynamic decoded = jsonDecode(content);
      if (decoded is Map<String, dynamic>) {
        _activeModelId = decoded['activeModelId'] as String?;
        final dynamic list = decoded['models'];
        if (list is List<dynamic>) {
          for (final dynamic item in list) {
            if (item is Map<String, dynamic>) {
              final ModelRegistryEntry entry = ModelRegistryEntry.fromJson(
                item,
              );
              if (entry.modelId.isNotEmpty) {
                // If the app was killed while downloading, treat as failed/canceled
                if (entry.status == AsrModelStatus.downloading) {
                  _entries[entry.modelId] = entry.copyWith(
                    status: AsrModelStatus.canceled,
                    lastError: 'Download interrupted',
                  );
                } else {
                  _entries[entry.modelId] = entry;
                }
              }
            }
          }
        }
      }
    } catch (_) {
      // Corrupted file: ignore and recreate on next save
    }
    _notify();
  }

  /// Atomically saves registry to disk.
  Future<void> save() async {
    final Map<String, dynamic> doc = <String, dynamic>{
      'version': 1,
      'updatedAt': DateTime.now().toIso8601String(),
      if (_activeModelId != null) 'activeModelId': _activeModelId,
      'models': _entries.values
          .map((ModelRegistryEntry e) => e.toJson())
          .toList(),
    };

    final String jsonStr = const JsonEncoder.withIndent('  ').convert(doc);
    final Directory parent = registryFile.parent;
    if (!await parent.exists()) {
      await parent.create(recursive: true);
    }

    try {
      final File tempFile = File('${registryFile.path}.tmp');
      await tempFile.writeAsString(jsonStr, flush: true);
      await tempFile.rename(registryFile.path);
    } catch (_) {
      // Fallback direct write if atomic rename is not supported by filesystem
      await registryFile.writeAsString(jsonStr, flush: true);
    }
    _notify();
  }

  ModelRegistryEntry getEntry(
    String modelId, {
    required String defaultLocalDir,
  }) {
    final ModelRegistryEntry? existing = _entries[modelId];
    if (existing != null) return existing;
    return ModelRegistryEntry(
      modelId: modelId,
      source: ModelSource.hfMirror,
      localDir: defaultLocalDir,
      status: AsrModelStatus.idle,
    );
  }

  Future<void> updateEntry(ModelRegistryEntry entry) async {
    _entries[entry.modelId] = entry;
    await save();
  }

  /// Sets the user-selected active speech recognition model.
  Future<void> setActiveModelId(String? modelId) async {
    if (_activeModelId != modelId) {
      _activeModelId = modelId;
      await save();
    }
  }

  Future<void> removeEntry(String modelId) async {
    if (_activeModelId == modelId) {
      _activeModelId = null;
    }
    if (_entries.remove(modelId) != null) {
      await save();
    }
  }

  void _notify() {
    if (!_streamController.isClosed) {
      _streamController.add(
        Map<String, ModelRegistryEntry>.unmodifiable(_entries),
      );
    }
  }

  Future<void> dispose() async {
    await _streamController.close();
  }
}
