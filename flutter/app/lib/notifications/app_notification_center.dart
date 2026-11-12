/// Per-backend notification center: folds the session-list stream through
/// [NotificationDetector] and routes each event to the foreground (in-app
/// toast) or background (system notification) channel, and through
/// [foldWorkingSessions] to reconcile the ongoing per-session work
/// notifications. Only root sessions are ever notification subjects: a
/// subagent child's progress is its parent's story (_onSessions drops child
/// rows before either fold).
///
/// Channel selection for transient events is a pure lifecycle decision made
/// here at emit time: an app the user is actively looking at gets a
/// tappable toast, an app that is not resumed gets a system notification.
/// The one product carve-out — the watched session's own turn completing
/// while the app is foregrounded — is silent because the user is already
/// watching it: the watched fact is the selection only while the Chat
/// destination covers the screen (`watchedSessionId`), so the same turn
/// finishing while the user reads another destination still surfaces.
///
/// Ongoing notifications are declarative: the fold says what each session's
/// row should look like now, and the center posts, updates, promotes, or
/// cancels only where the desired state differs from what it last applied.
/// That diff is also what makes a user-swiped-away completion notice stay
/// away — an OS dismiss is not observable here, and an unchanged desired
/// state produces no re-post. The pending-interaction row (approval / plan
/// review) follows the same diff: an event that posts it records the
/// interaction it names, and the first reconcile whose session no longer
/// waits on that interaction cancels it — answered in the app, on the web,
/// or on another device. Selection and lifecycle changes reach the center as
/// invalidation signals; the fold re-reads both facts from the polling
/// closures, so a dropped signal self-heals on the next snapshot.
library;

import 'dart:async';

import 'package:domain/model/session.dart';
import 'package:domain/repository/chat_repository.dart';

import 'notification_events.dart';
import 'turn_outcome_probe.dart';
import 'system_notifier.dart';
import 'working_sessions_fold.dart';

/// Decides whether the app is currently in the foreground.
typedef ForegroundCheck = bool Function();

class AppNotificationCenter {
  AppNotificationCenter({
    required this._repository,
    required this._backendId,
    required this._isForegrounded,
    required this._selectedSessionIdOf,
    required this._onBackground,
    required this._notifier,
    this.notificationsEnabled,
    this.allowsNotification,
    this.turnProbe,
    this._hostLabelOf,
    Stream<void>? selectionChanges,
    Stream<void>? foregroundChanges,
  }) {
    _subscription = _repository.observeSessions().listen(_onSessions);
    _selectionSub = selectionChanges?.listen((_) => _reconcileWorking());
    _foregroundSub = foregroundChanges?.listen((_) => _reconcileWorking());
  }

  final ChatRepository _repository;
  final String _backendId;
  final ForegroundCheck _isForegrounded;
  final String? Function() _selectedSessionIdOf;
  final void Function(AppNotificationEvent event) _onBackground;
  final SystemNotifier _notifier;

  /// Master switch: false stops both the shade and the banner.
  final bool Function()? notificationsEnabled;

  /// Per-kind switch; null allows every kind.
  final bool Function(AppNotificationKind kind)? allowsNotification;

  /// Reads how a completed turn ended (failed/stopped) and its reply's
  /// opening line; null keeps the completion wording and adds no preview.
  final TurnOutcomeProbe? turnProbe;

  /// The registry's current display label for this center's backend, when it
  /// has resolved one. Read at emit time so a rename shows up on the next
  /// notification without rebuilding the center.
  final String? Function()? _hostLabelOf;
  final NotificationDetector _detector = NotificationDetector();

  /// Latest session snapshot; the invalidation-driven reconciles re-fold it
  /// with the current selection/foreground facts.
  List<SessionSummary> _lastSessions = const <SessionSummary>[];

  /// The last decision applied to the OS per session id. Only present for
  /// sessions whose desired state is non-gone.
  final Map<String, WorkingSessionDecision> _applied =
      <String, WorkingSessionDecision>{};

  /// The pending-interaction row last posted per session id: the interaction
  /// the row names. Only approvals and plan reviews own a row; questions
  /// have none, and turn completions ride the work row above.
  final Map<String, SessionPendingInteraction> _appliedPending =
      <String, SessionPendingInteraction>{};

  /// Foreground channel: events the UI should surface as tappable toasts.
  /// A broadcast so multiple surfaces can listen without re-running the fold.
  final StreamController<AppNotificationEvent> _foreground =
      StreamController<AppNotificationEvent>.broadcast();

  /// Fires with the new value whenever any root session starts or stops
  /// having work in flight (running or waiting on the user). The keep-alive
  /// coordinator merges this across backends; only changes are emitted, and
  /// [hasWorkInFlight] carries the current value for a late subscriber.
  final StreamController<bool> _workInFlight =
      StreamController<bool>.broadcast();

  bool _hasWorkInFlight = false;

  /// Whether any root session of this backend has work in flight right now.
  bool get hasWorkInFlight => _hasWorkInFlight;

  /// Change stream for [hasWorkInFlight]; no value is replayed on listen.
  Stream<bool> get workInFlightChanges => _workInFlight.stream;

  StreamSubscription<List<SessionSummary>>? _subscription;
  StreamSubscription<void>? _selectionSub;
  StreamSubscription<void>? _foregroundSub;

  /// The foreground channel stream (in-app toasts).
  Stream<AppNotificationEvent> get foregroundEvents => _foreground.stream;

  /// Stops folding; cancels any ongoing and pending rows posted by this
  /// center and closes channels.
  void dispose() {
    for (final sessionId in _applied.keys.toList()) {
      unawaited(
        _notifier.cancelWork(backendId: _backendId, sessionId: sessionId),
      );
    }
    _applied.clear();
    for (final sessionId in _appliedPending.keys.toList()) {
      unawaited(
        _notifier.cancelPending(backendId: _backendId, sessionId: sessionId),
      );
    }
    _appliedPending.clear();
    unawaited(_subscription?.cancel());
    unawaited(_selectionSub?.cancel());
    unawaited(_foregroundSub?.cancel());
    unawaited(_foreground.close());
    unawaited(_workInFlight.close());
  }

  void _onSessions(List<SessionSummary> sessions) {
    // Subagent child sessions are not first-class notification subjects: a
    // delegated turn speaks through its root parent (the host keeps the
    // parent running while its children work), so child rows never reach
    // the transient detector or the ongoing fold — no toast, no system
    // notice, no ongoing row. Filtering here means their ids also leave
    // `live` in the reconcile below, so an ongoing row a pre-filter build
    // left posted is cancelled on the next snapshot.
    //
    // Archived sessions are the same: they stay in the roster so the
    // browsing surfaces can show them under their own filter, but they are
    // not notification subjects — the behavior the adapter's own filtering
    // produced before the archive fact reached this fold.
    _lastSessions = <SessionSummary>[
      for (final session in sessions)
        if (session.parentSessionId == null && !session.archived) session,
    ];
    // The connection fact, emitted on its own edges: the keep-alive service
    // is a process-lifetime decision, so it must not re-run on every
    // snapshot the way the declarative notification reconcile does.
    final inFlight = _lastSessions.any(sessionHasWorkInFlight);
    if (inFlight != _hasWorkInFlight) {
      _hasWorkInFlight = inFlight;
      if (!_workInFlight.isClosed) _workInFlight.add(inFlight);
    }
    // Reconcile the ongoing rows BEFORE routing this snapshot's transient
    // events. A turn-complete post rides the session's own (id, tag), so the
    // order decides the outcome: reconciling first lets the fold promote the
    // done row (or cancel a row the session no longer wants), and the
    // transient post then lands on the settled state. Routing first would
    // let a `gone` decision cancel the very notice just delivered — which is
    // what happens to the open session, whose `completed` bit never arms.
    _reconcileWorking();
    final events = _detector.fold(
      sessions: _lastSessions,
      selectedSessionId: _selectedSessionIdOf(),
      backendId: _backendId,
      hostLabel: _hostLabelOf?.call(),
    );
    for (final event in events) {
      if (turnProbe != null && _isCompletion(event.kind)) {
        unawaited(_announceWithFacts(event));
      } else {
        _route(event);
      }
    }
  }

  /// Re-announces a completion with the facts the timeline carries: a failed
  /// or stopped turn says so, and a finished reply carries its opening line.
  /// A probe that reads nothing leaves the event exactly as the fold made it.
  Future<void> _announceWithFacts(AppNotificationEvent event) async {
    TurnOutcomeFacts? facts;
    try {
      facts = await turnProbe!.probe(event.sessionId);
    } catch (_) {
      // A probe failure is not a notification failure: keep the plain event.
      facts = null;
    }
    if (facts == null) {
      _route(event);
      return;
    }
    final kind = switch (facts.outcome) {
      TurnOutcome.failed => AppNotificationKind.turnFailed,
      TurnOutcome.stopped => AppNotificationKind.turnStopped,
      TurnOutcome.completed => event.kind,
    };
    _route(event.copyWith(kind: kind, replyPreview: facts.replyPreview));
  }

  static bool _isCompletion(AppNotificationKind kind) => switch (kind) {
    AppNotificationKind.selectedTurnComplete ||
    AppNotificationKind.otherTurnComplete => true,
    AppNotificationKind.turnFailed ||
    AppNotificationKind.turnStopped ||
    AppNotificationKind.approvalRequested ||
    AppNotificationKind.planReviewRequested => false,
  };

  void _route(AppNotificationEvent event) {
    if (notificationsEnabled?.call() == false) return;
    if (allowsNotification?.call(event.kind) == false) return;
    final announcement = announcementFor(event, _isForegrounded());
    if (announcement.system) {
      _onBackground(event);
      // The row is posted (or the callback owns it): record the interaction
      // it names so the next reconcile that no longer waits on it cancels
      // exactly that row instead of leaving it in the shade.
      final pending = _pendingOf(event.kind);
      if (pending != null) _appliedPending[event.sessionId] = pending;
    }
    if (announcement.toast) _foreground.add(event);
  }

  /// The pending-interaction row [kind] announces, or null when the kind
  /// owns no pending row (turn completions ride the work row, and questions
  /// raise no system row).
  static SessionPendingInteraction? _pendingOf(AppNotificationKind kind) =>
      switch (kind) {
        AppNotificationKind.approvalRequested =>
          SessionPendingInteraction.approval,
        AppNotificationKind.planReviewRequested =>
          SessionPendingInteraction.planReview,
        AppNotificationKind.selectedTurnComplete ||
        AppNotificationKind.otherTurnComplete ||
        AppNotificationKind.turnFailed ||
        AppNotificationKind.turnStopped => null,
      };

  /// Cancels every row this center owns; called when notifications are
  /// switched off, so a silent or stale row does not outlive the choice.
  void _cancelAppliedRows() {
    for (final sessionId in _applied.keys.toList()) {
      unawaited(
        _notifier.cancelWork(backendId: _backendId, sessionId: sessionId),
      );
    }
    _applied.clear();
    for (final sessionId in _appliedPending.keys.toList()) {
      unawaited(
        _notifier.cancelPending(backendId: _backendId, sessionId: sessionId),
      );
    }
    _appliedPending.clear();
  }

  /// Applies the fold's desired per-session states as notifier calls,
  /// touching only the sessions whose state changed.
  void _reconcileWorking() {
    if (notificationsEnabled?.call() == false) {
      _cancelAppliedRows();
      return;
    }
    final decisions = foldWorkingSessions(
      sessions: _lastSessions,
      selectedSessionId: _selectedSessionIdOf(),
      isForegrounded: _isForegrounded(),
      hostLabel: _hostLabelOf?.call(),
    );
    final live = <String>{};
    for (final decision in decisions) {
      live.add(decision.sessionId);
    }
    // The alert row follows the session's raw waiting fact, not the fold's
    // display suppression. The watched-session rule silences the *silent*
    // work row for the page on screen; the pending row is the shade's alert
    // that a person still owes an answer, so a foreground watch must not
    // cancel it (a later backgrounding would then leave only the silent row).
    final desiredPending = <String, SessionPendingInteraction?>{
      for (final session in _lastSessions)
        session.id:
            !session.blank &&
                (session.pendingInteraction ==
                        SessionPendingInteraction.approval ||
                    session.pendingInteraction ==
                        SessionPendingInteraction.planReview)
            ? session.pendingInteraction
            : null,
    };
    for (final decision in decisions) {
      final applied = _applied[decision.sessionId];
      final nothingToShow = decision.state == WorkingSessionState.gone;
      if (applied == decision || (nothingToShow && applied == null)) {
        continue;
      }
      switch (decision.state) {
        case WorkingSessionState.gone:
          _applied.remove(decision.sessionId);
          unawaited(
            _notifier.cancelWork(
              backendId: _backendId,
              sessionId: decision.sessionId,
            ),
          );
        case WorkingSessionState.working || WorkingSessionState.waiting:
          _applied[decision.sessionId] = decision;
          if (applied == null || applied.state == WorkingSessionState.done) {
            unawaited(
              _notifier.showWork(backendId: _backendId, work: decision),
            );
          } else {
            unawaited(
              _notifier.updateWorkBody(backendId: _backendId, work: decision),
            );
          }
        case WorkingSessionState.done:
          _applied[decision.sessionId] = decision;
          unawaited(
            _notifier.promoteWorkToDone(backendId: _backendId, work: decision),
          );
      }
    }
    // The pending row is a separate OS row from the work row, so it has its
    // own diff. A session whose raw row no longer waits on the recorded
    // interaction — resolved in the app, on the web, or on another device —
    // or waits on a different one has its old row cancelled. A changed
    // interaction is dropped here, before the detector emits this
    // snapshot's event, so the post that follows lands as the new row.
    for (final entry in _appliedPending.entries.toList()) {
      if (desiredPending[entry.key] == entry.value) continue;
      _appliedPending.remove(entry.key);
      unawaited(
        _notifier.cancelPending(backendId: _backendId, sessionId: entry.key),
      );
    }
    for (final sessionId in _applied.keys.toList()) {
      if (live.contains(sessionId)) continue;
      // Deleted or archived sessions drop out of the snapshot; their row
      // goes with them.
      _applied.remove(sessionId);
      unawaited(
        _notifier.cancelWork(backendId: _backendId, sessionId: sessionId),
      );
    }
  }
}

/// What one event announces, per surface.
///
/// The shade is always told; the banner is an addition while the app is in
/// front. The watched session's own completion stays off the banner (the
/// user is already looking at it) but still leaves a row: banner silence
/// must never mean a lost event — a peer shipped that bug and had to fix it.
({bool system, bool toast}) announcementFor(
  AppNotificationEvent event,
  bool isForegrounded,
) {
  if (!isForegrounded) return (system: true, toast: false);
  if (event.kind == AppNotificationKind.selectedTurnComplete) {
    return (system: true, toast: false);
  }
  return (system: true, toast: true);
}
