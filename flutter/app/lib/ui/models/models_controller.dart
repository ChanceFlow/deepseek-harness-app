/// Models screen controller — port of the legacy ModelsViewModel.
library;

import 'dart:async';

import 'package:domain/model/model_catalog.dart';
import 'package:domain/model/session.dart';
import 'package:domain/repository/chat_repository.dart';

import '../state_stream.dart';
import 'models_ui_state.dart';

class ModelsController {
  ModelsController(this._repository) {
    _subs.add(_repository.observeSessions().listen((sessions) {
      _sessions = sessions;
      _publish();
    }));
  }

  final ChatRepository _repository;
  final AppStateStream<ModelsUiState> _state =
      AppStateStream<ModelsUiState>(const ModelsUiState());
  final List<StreamSubscription<void>> _subs = <StreamSubscription<void>>[];

  List<SessionSummary> _sessions = const <SessionSummary>[];
  String? _selectedSessionId;
  SessionModels? _models;
  ModelSelection? _selected;
  bool _isLoading = false;
  String? _errorMessage;

  ModelsUiState get state => _state.value;
  Stream<ModelsUiState> get uiState => _state.stream;

  void dispose() {
    for (final sub in _subs) {
      unawaited(sub.cancel());
    }
    _subs.clear();
  }

  void _publish() {
    // Same blank-session visibility rule as the chat list.
    final visible = _sessions
        .where((session) => !session.blank || session.id == _selectedSessionId)
        .toList();
    _state.value = ModelsUiState(
      sessions: visible,
      selectedSessionId: _selectedSessionId,
      models: _models,
      selected: _selected,
      isLoading: _isLoading,
      errorMessage: _errorMessage,
    );
  }

  void onAction(ModelsAction action) {
    switch (action) {
      case SelectModelsSession():
        _selectSession(action.sessionId);
      case SelectModelAction():
        _selectModel(action.provider, action.model, action.reasoningEffort);
      case RefreshModelsAction():
        _refresh();
      case DismissModelsError():
        _errorMessage = null;
        _publish();
    }
  }

  void _refresh() {
    final sessionId = _selectedSessionId;
    if (sessionId == null) return;
    unawaited(_loadModels(sessionId));
  }

  void _selectSession(String sessionId) {
    _selectedSessionId = sessionId;
    _publish();
    unawaited(_loadModels(sessionId));
  }

  void _selectModel(String provider, String model, String? reasoningEffort) {
    final sessionId = _selectedSessionId;
    if (sessionId == null) return;
    unawaited(() async {
      final selection = await _runCatchingForUi(() => _repository.selectModel(
            sessionId,
            ModelSelection(
              provider: provider,
              model: model,
              reasoningEffort: reasoningEffort,
            ),
          ));
      if (selection != null) {
        _selected = selection;
        _publish();
      }
    }());
  }

  Future<void> _loadModels(String sessionId) async {
    _isLoading = true;
    _publish();
    try {
      final loaded =
          await _runCatchingForUi(() => _repository.loadModels(sessionId));
      if (loaded != null) {
        _models = loaded;
        _selected = loaded.current;
      }
    } finally {
      _isLoading = false;
      _publish();
    }
  }

  Future<T?> _runCatchingForUi<T>(Future<T> Function() block) async {
    try {
      _errorMessage = null;
      _publish();
      return await block();
    } catch (error) {
      _errorMessage = error.toString();
      _publish();
      return null;
    }
  }
}
