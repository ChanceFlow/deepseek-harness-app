/// Goal screen controller — port of the legacy GoalViewModel.
library;

import 'dart:async';

import 'package:domain/model/goal.dart';
import 'package:domain/model/session.dart';
import 'package:domain/repository/chat_repository.dart';

import '../state_stream.dart';
import 'goal_ui_state.dart';

class GoalController {
  GoalController(this._repository) {
    _subs.add(_repository.observeSessions().listen((sessions) {
      _sessions = sessions;
      _publish();
    }));
  }

  final ChatRepository _repository;
  final AppStateStream<GoalUiState> _state =
      AppStateStream<GoalUiState>(const GoalUiState());
  final List<StreamSubscription<void>> _subs = <StreamSubscription<void>>[];

  List<SessionSummary> _sessions = const <SessionSummary>[];
  String? _selectedSessionId;
  GoalProjection? _goal;
  bool _isLoading = false;
  String? _errorMessage;

  StreamSubscription<GoalProjection?>? _goalSub;

  GoalUiState get state => _state.value;
  Stream<GoalUiState> get uiState => _state.stream;

  void dispose() {
    for (final sub in _subs) {
      unawaited(sub.cancel());
    }
    _subs.clear();
    unawaited(_goalSub?.cancel());
  }

  void _publish() {
    final visible = _sessions
        .where((session) => !session.blank || session.id == _selectedSessionId)
        .toList();
    _state.value = GoalUiState(
      sessions: visible,
      selectedSessionId: _selectedSessionId,
      goal: _goal,
      isLoading: _isLoading,
      errorMessage: _errorMessage,
    );
  }

  /// flatMapLatest equivalent over the selected session's goal stream.
  void _bindGoal(String? sessionId) {
    unawaited(_goalSub?.cancel());
    if (sessionId == null) {
      _goal = null;
      _goalSub = null;
      return;
    }
    _goalSub = _repository.observeGoal(sessionId).listen((projection) {
      _goal = projection;
      _publish();
    });
  }

  void onAction(GoalAction action) {
    switch (action) {
      case SelectGoalSession():
        _selectSession(action.sessionId);
      case CreateGoalAction():
        _create(action.objective, action.maxRounds);
      case EditGoalAction():
        _edit(action.objective);
      case PauseGoalAction():
        _mutateGoal((ref) => _repository.pauseGoal(_selectedSessionId!, ref));
      case ResumeGoalAction():
        _mutateGoal((ref) => _repository.resumeGoal(_selectedSessionId!, ref));
      case CompleteGoalAction():
        _mutateGoal(
            (ref) => _repository.completeGoal(_selectedSessionId!, ref));
      case ClearGoalAction():
        _clear();
      case DismissGoalError():
        _errorMessage = null;
        _publish();
      case RefreshGoalAction():
        _refresh();
    }
  }

  void _selectSession(String sessionId) {
    if (_selectedSessionId == sessionId) return;
    _selectedSessionId = sessionId;
    _goal = null;
    _bindGoal(sessionId);
    _publish();
  }

  void _create(String objective, int? maxRounds) {
    if (objective.trim().isEmpty) return;
    final sessionId = _selectedSessionId;
    if (sessionId == null) return;
    unawaited(() async {
      _isLoading = true;
      _publish();
      try {
        await _runCatchingForUi(() => _repository.createGoal(
              sessionId,
              objective.trim(),
              maxGoalRounds: maxRounds,
            ));
      } finally {
        _isLoading = false;
        _publish();
      }
    }());
  }

  void _edit(String objective) {
    if (objective.trim().isEmpty) return;
    final sessionId = _selectedSessionId;
    if (sessionId == null) return;
    final current = _goal?.goal;
    if (current == null) return;
    unawaited(() async {
      _isLoading = true;
      _publish();
      try {
        await _runCatchingForUi(() => _repository.editGoal(
              sessionId,
              GoalRef(id: current.id, revision: current.revision),
              objective.trim(),
            ));
      } finally {
        _isLoading = false;
        _publish();
      }
    }());
  }

  void _mutateGoal(Future<GoalRef> Function(GoalRef ref) block) {
    final sessionId = _selectedSessionId;
    if (sessionId == null) return;
    final current = _goal?.goal;
    if (current == null) return;
    unawaited(_runCatchingForUi(
        () => block(GoalRef(id: current.id, revision: current.revision))));
  }

  void _clear() {
    final sessionId = _selectedSessionId;
    if (sessionId == null) return;
    final current = _goal?.goal;
    if (current == null) return;
    unawaited(_runCatchingForUi(() => _repository.clearGoal(
          sessionId,
          GoalRef(id: current.id, revision: current.revision),
        )));
  }

  void _refresh() {
    final sessionId = _selectedSessionId;
    if (sessionId == null) return;
    unawaited(() async {
      await _runCatchingForUi(_repository.refreshSessions);
      await _runCatchingForUi(() => _repository.openSession(sessionId));
    }());
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
