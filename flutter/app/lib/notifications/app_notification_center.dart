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
/// state produces no re-post. Selection and lifecycle changes reach the
/// center as invalidation signals; the fold re-reads both facts from the
/// polling closures, so a dropped signal self-heals on the next snapshot.
library;

import 'dart:async';

import 'package:domain/model/session.dart';
import 'package:domain/repository/chat_repository.dart';

import 'notification_events.dart';
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
  final NotificationDetector _detector = NotificationDetector();

  /// Latest session snapshot; the invalidation-driven reconciles re-fold it
  /// with the current selection/foreground facts.
  List<SessionSummary> _lastSessions = const <SessionSummary>[];

  /// The last decision applied to the OS per session id. Only present for
  /// sessions whose desired state is non-gone.
  final Map<String, WorkingSessionDecision> _applied =
      <String, WorkingSessionDecision>{};

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

  /// Stops folding; cancels any ongoing rows posted by this center and
  /// closes channels.
  void dispose() {
    for (final sessionId in _applied.keys.toList()) {
      unawaited(
        _notifier.cancelWork(backendId: _backendId, sessionId: sessionId),
      );
    }
    _applied.clear();
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
    _lastSessions = <SessionSummary>[
      for (final session in sessions)
        if (session.parentSessionId == null) session,
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
    );
    for (final event in events) {
      _route(event);
    }
  }

  void _route(AppNotificationEvent event) {
    switch (channelFor(event, _isForegrounded())) {
      case NotificationChannel.foregroundToast:
        _foreground.add(event);
      case NotificationChannel.systemNotification:
        _onBackground(event);
      case NotificationChannel.none:
        break;
    }
  }

  /// Applies the fold's desired per-session states as notifier calls,
  /// touching only the sessions whose state changed.
  void _reconcileWorking() {
    final decisions = foldWorkingSessions(
      sessions: _lastSessions,
      selectedSessionId: _selectedSessionIdOf(),
      isForegrounded: _isForegrounded(),
    );
    final live = <String>{};
    for (final decision in decisions) {
      live.add(decision.sessionId);
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

/// Where one transient event should surface, decided at emit time.
enum NotificationChannel { foregroundToast, systemNotification, none }

/// Selects the channel for [event]: backgrounded events are always system
/// notifications; a foregrounded app toasts everything except the watched
/// session's own turn completing, which is silent because the user is
/// already watching it.
NotificationChannel channelFor(
  AppNotificationEvent event,
  bool isForegrounded,
) {
  if (!isForegrounded) return NotificationChannel.systemNotification;
  if (event.kind == AppNotificationKind.selectedTurnComplete) {
    return NotificationChannel.none;
  }
  return NotificationChannel.foregroundToast;
}
