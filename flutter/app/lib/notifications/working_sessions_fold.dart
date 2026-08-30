/// Desired per-session state for the ongoing "working session" system
/// notifications.
///
/// Pure functions over a `SessionSummary` snapshot plus the two viewing
/// facts (selected session, foreground state): no Flutter imports, no state
/// carried between snapshots. The edge semantics the lifecycle needs — the
/// running→idle transition that arms the done notice, and its consumption
/// when the user opens the session — come from the domain's `completed`
/// bit (the harness adapter folds exactly those edges), so this fold stays
/// stateless and directly testable; see the decision note.
library;

import 'package:domain/model/session.dart';

/// What notification presence one session should currently have.
enum WorkingSessionState {
  /// No notification for this session.
  gone,

  /// A silent ongoing notification: the session is running.
  working,

  /// The ongoing notification, its body naming the interaction the session
  /// waits on ([WorkingSessionDecision.pending]: approval, plan review, or
  /// question).
  waiting,

  /// A dismissible, auto-canceling completion notice that replaces the
  /// session's ongoing notification under the same id.
  done,
}

/// The desired notification state for one session.
final class WorkingSessionDecision {
  const WorkingSessionDecision({
    required this.sessionId,
    required this.sessionTitle,
    required this.state,
    this.pending,
  });

  final String sessionId;
  final String sessionTitle;
  final WorkingSessionState state;

  /// The interaction being waited on; set exactly when [state] is
  /// [WorkingSessionState.waiting].
  final SessionPendingInteraction? pending;

  @override
  bool operator ==(Object other) =>
      other is WorkingSessionDecision &&
      other.sessionId == sessionId &&
      other.sessionTitle == sessionTitle &&
      other.state == state &&
      other.pending == pending;

  @override
  int get hashCode => Object.hash(sessionId, sessionTitle, state, pending);
}

/// Folds one snapshot into the desired per-session notification state.
///
/// Priority per session: a blank placeholder is [WorkingSessionState.gone];
/// else a non-null `pendingInteraction` is [WorkingSessionState.waiting]
/// (pending outranks running — the agent waits on the user while the turn
/// is still open); else `running` is [WorkingSessionState.working]; else the
/// domain's `completed` bit is [WorkingSessionState.done]; else gone.
///
/// While the app is foregrounded, the selected session — the one the user
/// is watching — is suppressed to gone for [WorkingSessionState.working]
/// and [WorkingSessionState.waiting] (the standing "selected stays silent"
/// rule). [WorkingSessionState.done] is exempt: the `completed` bit already
/// never arms for the session the adapter has open, and opening the session
/// clears the bit, which routes the done notice to gone (the cancel side is
/// idempotent).
List<WorkingSessionDecision> foldWorkingSessions({
  required List<SessionSummary> sessions,
  required String? selectedSessionId,
  required bool isForegrounded,
}) {
  return [
    for (final session in sessions)
      _decisionFor(
        session,
        suppressed: isForegrounded && session.id == selectedSessionId,
      ),
  ];
}

/// The desired decision for one session row.
WorkingSessionDecision _decisionFor(
  SessionSummary session, {
  required bool suppressed,
}) {
  final gone = WorkingSessionDecision(
    sessionId: session.id,
    sessionTitle: session.displayTitle,
    state: WorkingSessionState.gone,
  );
  if (session.blank) return gone;
  final pending = session.pendingInteraction;
  if (pending != null) {
    return suppressed
        ? gone
        : WorkingSessionDecision(
            sessionId: session.id,
            sessionTitle: session.displayTitle,
            state: WorkingSessionState.waiting,
            pending: pending,
          );
  }
  if (session.running) {
    return suppressed
        ? gone
        : WorkingSessionDecision(
            sessionId: session.id,
            sessionTitle: session.displayTitle,
            state: WorkingSessionState.working,
          );
  }
  if (session.completed) {
    return WorkingSessionDecision(
      sessionId: session.id,
      sessionTitle: session.displayTitle,
      state: WorkingSessionState.done,
    );
  }
  return gone;
}
