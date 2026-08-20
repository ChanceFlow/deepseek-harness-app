/// App notification vocabulary — the neutral events a detector folds from
/// session-list snapshots and the toast/system channels render.
///
/// The model carries facts only (kind + the session the event belongs to);
/// user-facing copy is composed in the rendering layers (the toast widget
/// localizes through `AppLocalizations`, the system notifier resolves copy
/// once at initialize). No dsh wire vocabulary crosses this boundary.
library;

import 'package:domain/model/session.dart';

/// What happened that a user might want to be told about.
enum AppNotificationKind {
  /// The session the user is currently watching finished its turn. Per the
  /// product rule the foreground channel stays silent for this kind (the
  /// user is already watching); the background channel still posts.
  selectedTurnComplete,

  /// A session the user is NOT watching finished a turn — the observable
  /// "unread new content" signal (the wire carries no per-message read
  /// state; a completed turn in another session is the cheapest reliable
  /// proxy for "new content arrived").
  otherTurnComplete,

  /// A session started waiting on a user approval (a permission request the
  /// user must answer).
  approvalRequested,

  /// A session started waiting on a plan review (a plan-mode review the
  /// user must answer).
  planReviewRequested,
}

/// One notification-worthy occurrence, with the navigation target.
final class AppNotificationEvent {
  const AppNotificationEvent({
    required this.kind,
    required this.backendId,
    required this.sessionId,
    required this.sessionTitle,
  });

  final AppNotificationKind kind;
  final String backendId;
  final String sessionId;
  final String sessionTitle;

  @override
  bool operator ==(Object other) =>
      other is AppNotificationEvent &&
      other.kind == kind &&
      other.backendId == backendId &&
      other.sessionId == sessionId &&
      other.sessionTitle == sessionTitle;

  @override
  int get hashCode => Object.hash(kind, backendId, sessionId, sessionTitle);
}

/// Pure fold that turns successive [SessionSummary] snapshots into
/// [AppNotificationEvent]s. The first snapshot seeds the baseline and emits
/// nothing (a session that was already running or already waiting when the
/// observer attached is not "new"); every later snapshot emits the deltas.
///
/// Kept stateless apart from the tracked last-state maps so tests can drive
/// it with plain lists and assert the exact event stream.
class NotificationDetector {
  final Map<String, bool> _lastRunning = <String, bool>{};
  final Map<String, SessionPendingInteraction?> _lastPending =
      <String, SessionPendingInteraction?>{};
  bool _seeded = false;

  /// Folds one snapshot into the events it newly produced.
  /// @param sessions - the full session list as observed.
  /// @param selectedSessionId - the session the user is currently watching
  ///   (drives the selected-vs-other turn classification).
  /// @param backendId - the backend the snapshot belongs to (navigation).
  List<AppNotificationEvent> fold({
    required List<SessionSummary> sessions,
    required String? selectedSessionId,
    required String backendId,
  }) {
    if (!_seeded) {
      _seed(sessions);
      _seeded = true;
      return const <AppNotificationEvent>[];
    }

    final events = <AppNotificationEvent>[];
    final liveIds = <String>{};
    for (final session in sessions) {
      liveIds.add(session.id);
      final wasRunning = _lastRunning[session.id];
      final wasPending = _lastPending[session.id];

      // Running → idle means the session produced a finished turn.
      if (wasRunning == true && !session.running) {
        final selected = session.id == selectedSessionId;
        events.add(
          AppNotificationEvent(
            kind: selected
                ? AppNotificationKind.selectedTurnComplete
                : AppNotificationKind.otherTurnComplete,
            backendId: backendId,
            sessionId: session.id,
            sessionTitle: session.displayTitle,
          ),
        );
      }

      // A session that newly started waiting on the user.
      if (wasPending != session.pendingInteraction) {
        switch (session.pendingInteraction) {
          case SessionPendingInteraction.approval:
            events.add(
              AppNotificationEvent(
                kind: AppNotificationKind.approvalRequested,
                backendId: backendId,
                sessionId: session.id,
                sessionTitle: session.displayTitle,
              ),
            );
          case SessionPendingInteraction.planReview:
            events.add(
              AppNotificationEvent(
                kind: AppNotificationKind.planReviewRequested,
                backendId: backendId,
                sessionId: session.id,
                sessionTitle: session.displayTitle,
              ),
            );
          case SessionPendingInteraction.question:
          case null:
            break;
        }
      }

      _lastRunning[session.id] = session.running;
      _lastPending[session.id] = session.pendingInteraction;
    }

    // Dropped sessions stop being tracked; their transitions can never fire.
    _lastRunning.removeWhere((id, _) => !liveIds.contains(id));
    _lastPending.removeWhere((id, _) => !liveIds.contains(id));
    return events;
  }

  void _seed(List<SessionSummary> sessions) {
    for (final session in sessions) {
      _lastRunning[session.id] = session.running;
      _lastPending[session.id] = session.pendingInteraction;
    }
  }
}
