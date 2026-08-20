/// Goal screen UI state and intents — port of GoalUiState.kt.
library;

import 'package:domain/model/goal.dart';
import 'package:domain/model/session.dart';

final class GoalUiState {
  const GoalUiState({
    this.sessions = const <SessionSummary>[],
    this.selectedSessionId,
    this.goal,
    this.isLoading = false,
    this.errorMessage,
  });

  final List<SessionSummary> sessions;
  final String? selectedSessionId;
  final GoalProjection? goal;
  final bool isLoading;
  final String? errorMessage;
}

sealed class GoalAction {
  const GoalAction();
}

final class SelectGoalSession extends GoalAction {
  const SelectGoalSession(this.sessionId);

  final String sessionId;

  @override
  bool operator ==(Object other) =>
      other is SelectGoalSession && other.sessionId == sessionId;

  @override
  int get hashCode => sessionId.hashCode;
}

final class CreateGoalAction extends GoalAction {
  const CreateGoalAction(this.objective, this.maxRounds);

  final String objective;
  final int? maxRounds;

  @override
  bool operator ==(Object other) =>
      other is CreateGoalAction &&
      other.objective == objective &&
      other.maxRounds == maxRounds;

  @override
  int get hashCode => Object.hash(objective, maxRounds);
}

final class EditGoalAction extends GoalAction {
  const EditGoalAction(this.objective);

  final String objective;

  @override
  bool operator ==(Object other) =>
      other is EditGoalAction && other.objective == objective;

  @override
  int get hashCode => objective.hashCode;
}

final class PauseGoalAction extends GoalAction {
  const PauseGoalAction();

  @override
  bool operator ==(Object other) => other is PauseGoalAction;

  @override
  int get hashCode => 'pause-goal'.hashCode;
}

final class ResumeGoalAction extends GoalAction {
  const ResumeGoalAction();

  @override
  bool operator ==(Object other) => other is ResumeGoalAction;

  @override
  int get hashCode => 'resume-goal'.hashCode;
}

final class CompleteGoalAction extends GoalAction {
  const CompleteGoalAction();

  @override
  bool operator ==(Object other) => other is CompleteGoalAction;

  @override
  int get hashCode => 'complete-goal'.hashCode;
}

final class ClearGoalAction extends GoalAction {
  const ClearGoalAction();

  @override
  bool operator ==(Object other) => other is ClearGoalAction;

  @override
  int get hashCode => 'clear-goal'.hashCode;
}

final class DismissGoalError extends GoalAction {
  const DismissGoalError();

  @override
  bool operator ==(Object other) => other is DismissGoalError;

  @override
  int get hashCode => 'dismiss-goal-error'.hashCode;
}

final class RefreshGoalAction extends GoalAction {
  const RefreshGoalAction();

  @override
  bool operator ==(Object other) => other is RefreshGoalAction;

  @override
  int get hashCode => 'refresh-goal'.hashCode;
}
