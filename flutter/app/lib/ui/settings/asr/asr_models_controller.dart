/// UDF Controller and UI state for the ASR model management screen.
library;

import 'dart:async';

import 'package:asr/asr.dart';

/// Card-level presentation state for a single ASR model.
class AsrModelCardState {
  const AsrModelCardState({
    required this.info,
    required this.entry,
    this.diskUsageBytes,
    this.speedBytesPerSecond = 0.0,
  });

  final AsrModelInfo info;
  final ModelRegistryEntry entry;
  final int? diskUsageBytes;
  final double speedBytesPerSecond;

  AsrModelStatus get status => entry.status;
  bool get isDownloaded => status == AsrModelStatus.downloaded;
  bool get isDownloading => status == AsrModelStatus.downloading;
  bool get isFailed => status == AsrModelStatus.failed;
  bool get isCanceled => status == AsrModelStatus.canceled;
  double get progress => entry.progress;
  String? get errorMessage => entry.lastError;
  ModelSource get source => entry.source;
}

/// UI State for the ASR models management screen.
class AsrModelsUiState {
  const AsrModelsUiState({
    this.models = const <AsrModelCardState>[],
    this.defaultSource = ModelSource.hfMirror,
    this.allowCellular = false,
    this.installedCount = 0,
    this.totalCount = 0,
    this.activeDownloadingId,
    this.errorMessage,
    this.isLoading = false,
  });

  final List<AsrModelCardState> models;
  final ModelSource defaultSource;
  final bool allowCellular;
  final int installedCount;
  final int totalCount;
  final String? activeDownloadingId;
  final String? errorMessage;
  final bool isLoading;

  AsrModelsUiState copyWith({
    List<AsrModelCardState>? models,
    ModelSource? defaultSource,
    bool? allowCellular,
    int? installedCount,
    int? totalCount,
    String? activeDownloadingId,
    String? errorMessage,
    bool clearError = false,
    bool? isLoading,
  }) {
    return AsrModelsUiState(
      models: models ?? this.models,
      defaultSource: defaultSource ?? this.defaultSource,
      allowCellular: allowCellular ?? this.allowCellular,
      installedCount: installedCount ?? this.installedCount,
      totalCount: totalCount ?? this.totalCount,
      activeDownloadingId: activeDownloadingId ?? this.activeDownloadingId,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

/// Actions dispatched from the ASR models UI.
sealed class AsrModelsAction {
  const AsrModelsAction();
}

class StartDownloadAction extends AsrModelsAction {
  const StartDownloadAction(this.modelId, {this.sourceOverride});
  final String modelId;
  final ModelSource? sourceOverride;
}

class CancelDownloadAction extends AsrModelsAction {
  const CancelDownloadAction(this.modelId);
  final String modelId;
}

class RetryWithSourceAction extends AsrModelsAction {
  const RetryWithSourceAction(this.modelId, this.targetSource);
  final String modelId;
  final ModelSource targetSource;
}

class DeleteModelAction extends AsrModelsAction {
  const DeleteModelAction(this.modelId);
  final String modelId;
}

class SetDefaultSourceAction extends AsrModelsAction {
  const SetDefaultSourceAction(this.source);
  final ModelSource source;
}

class SetAllowCellularAction extends AsrModelsAction {
  const SetAllowCellularAction(this.allow);
  final bool allow;
}

class DismissAsrErrorAction extends AsrModelsAction {
  const DismissAsrErrorAction();
}

class RefreshAsrStateAction extends AsrModelsAction {
  const RefreshAsrStateAction();
}

/// Controller managing ASR models UI lifecycle.
class AsrModelsController {
  AsrModelsController({this.manager}) {
    _init();
  }

  final AsrModelManager? manager;
  final StreamController<AsrModelsUiState> _stateController =
      StreamController<AsrModelsUiState>.broadcast();
  StreamSubscription<Map<String, ModelRegistryEntry>>? _registrySub;

  AsrModelsUiState _state = const AsrModelsUiState(isLoading: true);
  AsrModelsUiState get state => _state;
  Stream<AsrModelsUiState> get uiState => _stateController.stream;

  void _init() {
    if (manager == null) {
      _emit(_state.copyWith(isLoading: false));
      return;
    }

    _registrySub = manager!.updates.listen((_) {
      _refresh();
    });
    _refresh();
  }

  Future<void> _refresh() async {
    if (manager == null) return;

    final List<AsrModelCardState> cards = <AsrModelCardState>[];
    for (final AsrModelInfo info in AsrModelManifest.all) {
      final ModelRegistryEntry entry = manager!.getStatus(info.id);
      int? diskBytes;
      if (entry.isDownloaded) {
        diskBytes = await manager!.getActualDiskUsage(info.id);
      }
      cards.add(
        AsrModelCardState(
          info: info,
          entry: entry,
          diskUsageBytes: diskBytes,
        ),
      );
    }

    _emit(
      _state.copyWith(
        models: cards,
        defaultSource: manager!.defaultSource,
        allowCellular: manager!.allowCellular,
        installedCount: manager!.installedCount,
        totalCount: manager!.totalCount,
        activeDownloadingId: manager!.activeDownloadingModelId,
        isLoading: false,
      ),
    );
  }

  void _emit(AsrModelsUiState next) {
    _state = next;
    if (!_stateController.isClosed) {
      _stateController.add(next);
    }
  }

  void onAction(AsrModelsAction action) {
    switch (action) {
      case StartDownloadAction(:final String modelId, :final ModelSource? sourceOverride):
        _startDownload(modelId, sourceOverride: sourceOverride);
      case CancelDownloadAction(:final String modelId):
        _cancelDownload(modelId);
      case RetryWithSourceAction(:final String modelId, :final ModelSource targetSource):
        _retryWithSource(modelId, targetSource);
      case DeleteModelAction(:final String modelId):
        _deleteModel(modelId);
      case SetDefaultSourceAction(:final ModelSource source):
        _setDefaultSource(source);
      case SetAllowCellularAction(:final bool allow):
        _setAllowCellular(allow);
      case DismissAsrErrorAction():
        _emit(_state.copyWith(clearError: true));
      case RefreshAsrStateAction():
        _refresh();
    }
  }

  Future<void> _startDownload(String modelId, {ModelSource? sourceOverride}) async {
    if (manager == null) return;
    try {
      await manager!.startDownload(modelId, sourceOverride: sourceOverride);
    } catch (e) {
      _emit(_state.copyWith(errorMessage: e.toString()));
    }
  }

  Future<void> _cancelDownload(String modelId) async {
    if (manager == null) return;
    await manager!.cancelDownload(modelId);
  }

  Future<void> _retryWithSource(String modelId, ModelSource targetSource) async {
    if (manager == null) return;
    try {
      await manager!.retryWithSource(modelId, targetSource);
    } catch (e) {
      _emit(_state.copyWith(errorMessage: e.toString()));
    }
  }

  Future<void> _deleteModel(String modelId) async {
    if (manager == null) return;
    await manager!.deleteModel(modelId);
    await _refresh();
  }

  void _setDefaultSource(ModelSource source) {
    if (manager == null) return;
    manager!.setDefaultSource(source);
    _emit(_state.copyWith(defaultSource: source));
  }

  void _setAllowCellular(bool allow) {
    if (manager == null) return;
    manager!.setAllowCellular(allow);
    _emit(_state.copyWith(allowCellular: allow));
  }

  void dispose() {
    _registrySub?.cancel();
    _stateController.close();
  }
}
