/// Subagents screen controller — port of the legacy SubagentViewModel.
library;

import 'dart:async';

import 'package:domain/model/session.dart';
import 'package:domain/model/subagent.dart';
import 'package:domain/model/timeline_item.dart';
import 'package:domain/repository/chat_repository.dart';

import '../state_stream.dart';
import 'subagent_ui_state.dart';

class SubagentController {
  SubagentController(this._repository) {
    _subs.add(
      _repository.observeSessions().listen((sessions) {
        _sessions = sessions;
        _publish();
      }),
    );
  }

  final ChatRepository _repository;
  final AppStateStream<SubagentUiState> _state =
      AppStateStream<SubagentUiState>(const SubagentUiState());
  final List<StreamSubscription<void>> _subs = <StreamSubscription<void>>[];

  List<SessionSummary> _sessions = const <SessionSummary>[];
  String? _selectedParentId;
  SubagentCatalog _catalog = const SubagentCatalog();
  String? _selectedChildId;
  List<TimelineItem> _childTimeline = const <TimelineItem>[];
  bool _isSendingChild = false;
  bool _isLoading = false;
  String? _errorMessage;

  SubagentUiState get state => _state.value;
  Stream<SubagentUiState> get uiState => _state.stream;

  void dispose() {
    for (final sub in _subs) {
      unawaited(sub.cancel());
    }
    _subs.clear();
  }

  void _publish() {
    final visible = _sessions
        .where((session) => !session.blank || session.id == _selectedParentId)
        .toList();
    _state.value = SubagentUiState(
      sessions: visible,
      selectedParentId: _selectedParentId,
      catalog: _catalog,
      selectedChildId: _selectedChildId,
      childTimeline: _childTimeline,
      isSendingChild: _isSendingChild,
      isLoading: _isLoading,
      errorMessage: _errorMessage,
    );
  }

  void onAction(SubagentAction action) {
    switch (action) {
      case SelectParent():
        _selectParent(action.sessionId);
      case OpenChild():
        _openChild(action.childSessionId);
      case SendSubagentPrompt():
        _sendPrompt(action.text);
      case InterruptSubagent():
        _interrupt(action.childSessionId);
      case RefreshSubagentsAction():
        _refresh();
      case DismissSubagentError():
        _errorMessage = null;
        _publish();
    }
  }

  void _selectParent(String sessionId) {
    if (_selectedParentId == sessionId) return;
    _selectedParentId = sessionId;
    _selectedChildId = null;
    _childTimeline = const <TimelineItem>[];
    _publish();
    unawaited(_loadCatalog(sessionId));
  }

  void _openChild(String childSessionId) {
    final parentId = _selectedParentId;
    if (parentId == null) return;
    _selectedChildId = childSessionId;
    _childTimeline = const <TimelineItem>[];
    _publish();
    unawaited(() async {
      final result = await _runCatchingForUi(
        () => _repository.loadSubagentHistory(parentId, childSessionId),
      );
      _childTimeline = result ?? const <TimelineItem>[];
      _publish();
    }());
  }

  void _sendPrompt(String text) {
    final parentId = _selectedParentId;
    final childId = _selectedChildId;
    if (parentId == null || childId == null) return;
    if (text.trim().isEmpty) return;
    unawaited(() async {
      _isSendingChild = true;
      _publish();
      try {
        await _runCatchingForUi(
          () => _repository.sendSubagentPrompt(parentId, childId, text.trim()),
        );
        final reloaded = await _runCatchingForUi(
          () => _repository.loadSubagentHistory(parentId, childId),
        );
        if (reloaded != null) {
          _childTimeline = reloaded;
        }
      } finally {
        _isSendingChild = false;
        _publish();
      }
    }());
  }

  void _interrupt(String childSessionId) {
    final parentId = _selectedParentId;
    if (parentId == null) return;
    unawaited(() async {
      await _runCatchingForUi(
        () => _repository.interruptSubagent(parentId, childSessionId),
      );
      await _loadCatalog(parentId);
    }());
  }

  void _refresh() {
    final parentId = _selectedParentId;
    if (parentId == null) return;
    unawaited(_loadCatalog(parentId));
  }

  Future<void> _loadCatalog(String parentId) async {
    _isLoading = true;
    _publish();
    try {
      final loaded = await _runCatchingForUi(
        () => _repository.loadSubagents(parentId),
      );
      if (loaded != null) {
        _catalog = loaded;
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
