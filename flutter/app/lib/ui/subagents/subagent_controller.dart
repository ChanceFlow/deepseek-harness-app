/// Subagents screen controller — catalog tree, child detail, and their
/// actions, mirroring the web subagent session services
/// (reference/deepseek-harness/packages/client/ui-subagent/src/client/):
/// `SubagentCatalogAction.tsx` branch expansion loads the child's own
/// catalog, and the child conversation binds the plan projection the same
/// way `ChatController` binds the selected session's.
library;

import 'dart:async';

import 'package:domain/model/plan.dart';
import 'package:domain/model/session.dart';
import 'package:domain/model/subagent.dart';
import 'package:domain/model/timeline_item.dart';
import 'package:domain/repository/chat_repository.dart';

import '../state_stream.dart';
import 'subagent_ui_state.dart';

class SubagentController {
  SubagentController(this._repository, {String? initialSessionId})
    : _selectedParentId = initialSessionId {
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
  final Map<String, SubagentCatalog> _branchCatalogs =
      <String, SubagentCatalog>{};
  final Set<String> _branchFailures = <String>{};
  String? _selectedChildId;
  List<TimelineItem> _childTimeline = const <TimelineItem>[];
  StreamSubscription<void>? _planSub;
  PlanState? _childPlan;
  int _childLoadSeq = 0;
  int _catalogLoadSeq = 0;
  bool _isChildLoading = false;
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
    unawaited(_planSub?.cancel());
    _planSub = null;
  }

  void _publish() {
    final visible = _sessions
        .where((session) => !session.blank || session.id == _selectedParentId)
        .toList();
    _state.value = SubagentUiState(
      sessions: visible,
      selectedParentId: _selectedParentId,
      catalog: _catalog,
      branchCatalogs: Map.unmodifiable(_branchCatalogs),
      branchFailures: Set.unmodifiable(_branchFailures),
      selectedChildId: _selectedChildId,
      childTimeline: _childTimeline,
      childPlan: _childPlan,
      isChildLoading: _isChildLoading,
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
      case LoadSubagentBranch():
        unawaited(_loadBranch(action.childSessionId));
      case CloseChildView():
        _closeChild();
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
    _isChildLoading = false;
    ++_childLoadSeq;
    _branchCatalogs.clear();
    _branchFailures.clear();
    _bindChildPlan(null);
    _publish();
    unawaited(_loadCatalog(sessionId));
  }

  void _openChild(String childSessionId) {
    final parentId = _selectedParentId;
    if (parentId == null) return;
    _selectedChildId = childSessionId;
    _childTimeline = const <TimelineItem>[];
    _bindChildPlan(childSessionId);
    _publish();
    // History loads are superseded by a later open of another child; only
    // the newest request may land its timeline.
    final seq = ++_childLoadSeq;
    unawaited(() async {
      _isChildLoading = true;
      _publish();
      try {
        final result = await _runCatchingForUi(
          () => _repository.loadSubagentHistory(parentId, childSessionId),
        );
        if (seq != _childLoadSeq) return;
        _childTimeline = result ?? const <TimelineItem>[];
      } finally {
        if (seq == _childLoadSeq) {
          _isChildLoading = false;
          _publish();
        }
      }
    }());
  }

  void _closeChild() {
    if (_selectedChildId == null) return;
    _selectedChildId = null;
    _childTimeline = const <TimelineItem>[];
    _isChildLoading = false;
    // A closed record is no longer the newest request; its in-flight
    // history load must not land.
    ++_childLoadSeq;
    _bindChildPlan(null);
    _publish();
  }

  /// Re-subscribes the opened child's plan projection (the ChatController
  /// `_bindSelected` plan seat, aimed at the child session id).
  void _bindChildPlan(String? childSessionId) {
    unawaited(_planSub?.cancel());
    _planSub = null;
    _childPlan = null;
    if (childSessionId == null) return;
    _planSub = _repository.observePlan(childSessionId).listen((plan) {
      _childPlan = plan;
      _publish();
    });
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
        if (reloaded != null && _selectedChildId == childId) {
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

  /// Loads the catalog one expanded branch node owns as its children
  /// (web `setCatalogOpen(childSessionId, true)` refresh). A failed load
  /// marks the branch so the tree shows the error + retry instead of a
  /// permanent loading row. Results from a tree the user has already left
  /// (parent switched mid-flight) are dropped.
  Future<void> _loadBranch(String branchParentId) async {
    final treeRoot = _selectedParentId;
    _branchFailures.remove(branchParentId);
    _publish();
    final loaded = await _runCatchingForUi(
      () => _repository.loadSubagents(branchParentId),
    );
    if (_selectedParentId != treeRoot) return;
    if (loaded != null) {
      _branchCatalogs[branchParentId] = loaded;
    } else {
      _branchFailures.add(branchParentId);
    }
    _publish();
  }

  void _refresh() {
    final parentId = _selectedParentId;
    if (parentId == null) return;
    unawaited(_loadCatalog(parentId));
  }

  Future<void> _loadCatalog(String parentId) async {
    // Catalog loads are superseded by selecting another parent; only the
    // newest request may land its catalog or clear the loading flag.
    final seq = ++_catalogLoadSeq;
    _isLoading = true;
    _publish();
    try {
      final loaded = await _runCatchingForUi(
        () => _repository.loadSubagents(parentId),
      );
      if (seq != _catalogLoadSeq) return;
      if (loaded != null) {
        _catalog = loaded;
      }
    } finally {
      if (seq == _catalogLoadSeq) {
        _isLoading = false;
        _publish();
      }
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
