/// Session list vocabulary.
library;

/// A session's outstanding wait for a user action, mirrored from the
/// registry-global pending-interaction set (the web's
/// `PendingInteractionStatus`). Present when the host has an unanswered
/// approval, a plan review, or a question for the user; null when nothing
/// blocks on the user. Navigation surfaces rank sessions by this fact and
/// light the amber status dot; notification detection reads it to raise
/// approval/plan-review alerts.
enum SessionPendingInteraction { approval, planReview, question }

final class SessionSummary {
  const SessionSummary({
    required this.id,
    this.title,
    this.running = false,
    this.blank = true,
    this.updatedAtEpochMs = 0,
    this.cwd,
    this.agentPreset,
    this.origin,
    this.parentSessionId,
    this.pendingInteraction,
    this.completed = false,
  });

  final String id;
  final String? title;
  final bool running;
  final bool blank;
  final int updatedAtEpochMs;
  final String? cwd;
  final String? agentPreset;

  /// Coarse durable origin used by navigation surfaces; `subagent` marks a
  /// subagent child (absent for root sessions).
  final String? origin;

  /// The session that spawned this one as a subagent child (the wire
  /// `sessionSummarySchema.parentSessionId`); null on root sessions. The
  /// Subagents screen keys its event-driven catalog refreshes on this
  /// lineage.
  final String? parentSessionId;

  /// Pending user interaction (approval / plan-review / question); null
  /// while nothing blocks on the user. A derived fact: the wire session
  /// summary carries no such field, so it is folded from the live
  /// approval/question frame stream (see the harness adapter).
  final SessionPendingInteraction? pendingInteraction;

  /// Finished-but-unviewed reminder: the session stopped running while
  /// it was not the selected/opened session (web SessionManager
  /// `completedNotifications`). The green status dot renders only while
  /// this is true; opening the session or it running again clears it.
  /// Also derived — the wire summary has no such field (see the harness
  /// adapter).
  final bool completed;

  /// Same label rule as the Web client: durable title first, then the
  /// canonical workspace path basename, then the raw session id.
  String get displayTitle {
    final durable = title;
    if (durable != null && durable.trim().isNotEmpty) return durable;
    final path = cwd;
    if (path != null) {
      final segments = path.split(RegExp(r'[/\\]'));
      for (final segment in segments.reversed) {
        if (segment.trim().isNotEmpty) return segment;
      }
    }
    return id;
  }

  @override
  bool operator ==(Object other) =>
      other is SessionSummary &&
      other.id == id &&
      other.title == title &&
      other.running == running &&
      other.blank == blank &&
      other.updatedAtEpochMs == updatedAtEpochMs &&
      other.cwd == cwd &&
      other.agentPreset == agentPreset &&
      other.origin == origin &&
      other.parentSessionId == parentSessionId &&
      other.pendingInteraction == pendingInteraction &&
      other.completed == completed;

  @override
  int get hashCode => Object.hash(
    id,
    title,
    running,
    blank,
    updatedAtEpochMs,
    cwd,
    agentPreset,
    origin,
    parentSessionId,
    pendingInteraction,
    completed,
  );
}

final class CreateSessionRequest {
  const CreateSessionRequest({
    this.sessionId,
    this.workspaceId,
    this.cwd,
    this.agentPreset,
  });

  final String? sessionId;
  final String? workspaceId;
  final String? cwd;
  final String? agentPreset;

  @override
  bool operator ==(Object other) =>
      other is CreateSessionRequest &&
      other.sessionId == sessionId &&
      other.workspaceId == workspaceId &&
      other.cwd == cwd &&
      other.agentPreset == agentPreset;

  @override
  int get hashCode => Object.hash(sessionId, workspaceId, cwd, agentPreset);
}

enum QueuePlacement { queued, steering, context }

enum QueueUpdateKind { remove, steer, edit }

final class QueueUpdateRequest {
  const QueueUpdateRequest({
    required this.sessionId,
    required this.itemId,
    required this.kind,
    this.text,
  });

  final String sessionId;
  final String itemId;
  final QueueUpdateKind kind;
  final String? text;

  @override
  bool operator ==(Object other) =>
      other is QueueUpdateRequest &&
      other.sessionId == sessionId &&
      other.itemId == itemId &&
      other.kind == kind &&
      other.text == text;

  @override
  int get hashCode => Object.hash(sessionId, itemId, kind, text);
}
