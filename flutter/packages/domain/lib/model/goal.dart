/// Goal-round vocabulary mirrored from the `goal` session projection.
library;

final class GoalRef {
  const GoalRef({required this.id, required this.revision});

  final String id;
  final int revision;

  @override
  bool operator ==(Object other) =>
      other is GoalRef && other.id == id && other.revision == revision;

  @override
  int get hashCode => Object.hash(id, revision);
}

enum GoalPhase { active, paused, blocked, complete }

final class GoalSnapshot {
  const GoalSnapshot({
    required this.id,
    required this.revision,
    required this.objective,
    required this.phase,
    this.blockedReason,
    required this.maxGoalRounds,
  });

  final String id;
  final int revision;
  final String objective;
  final GoalPhase phase;
  final String? blockedReason;
  final int maxGoalRounds;

  @override
  bool operator ==(Object other) =>
      other is GoalSnapshot &&
      other.id == id &&
      other.revision == revision &&
      other.objective == objective &&
      other.phase == phase &&
      other.blockedReason == blockedReason &&
      other.maxGoalRounds == maxGoalRounds;

  @override
  int get hashCode =>
      Object.hash(id, revision, objective, phase, blockedReason, maxGoalRounds);
}

final class GoalProjection {
  const GoalProjection({
    required this.goal,
    required this.roundsStarted,
    required this.createdAt,
    required this.updatedAt,
  });

  final GoalSnapshot goal;
  final int roundsStarted;
  final int createdAt;
  final int updatedAt;

  @override
  bool operator ==(Object other) =>
      other is GoalProjection &&
      other.goal == goal &&
      other.roundsStarted == roundsStarted &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(goal, roundsStarted, createdAt, updatedAt);
}
