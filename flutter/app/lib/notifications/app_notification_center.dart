/// Per-backend notification center: folds the session-list stream through
/// [NotificationDetector] and routes each event to the foreground (in-app
/// toast) or background (system notification) channel.
///
/// Channel selection is a pure lifecycle decision made here at emit time:
/// an app the user is actively looking at gets a tappable toast, an app
/// that is not resumed gets a system notification. The one product carve-out
/// — a selected session's own turn completing while the app is foregrounded
/// — is silent because the user is already watching it.
library;

import 'dart:async';

import 'package:domain/model/session.dart';
import 'package:domain/repository/chat_repository.dart';

import 'notification_events.dart';

/// Decides whether the app is currently in the foreground.
typedef ForegroundCheck = bool Function();

/// Navigation target carried with a foreground toast event.
class AppNotificationCenter {
  AppNotificationCenter({
    required this._repository,
    required this._backendId,
    required this._isForegrounded,
    required this._selectedSessionIdOf,
    required this._onBackground,
  }) {
    _subscription = _repository.observeSessions().listen(_onSessions);
  }

  final ChatRepository _repository;
  final String _backendId;
  final ForegroundCheck _isForegrounded;
  final String? Function() _selectedSessionIdOf;
  final void Function(AppNotificationEvent event) _onBackground;
  final NotificationDetector _detector = NotificationDetector();

  /// Foreground channel: events the UI should surface as tappable toasts.
  /// A broadcast so multiple surfaces can listen without re-running the fold.
  final StreamController<AppNotificationEvent> _foreground =
      StreamController<AppNotificationEvent>.broadcast();

  StreamSubscription<List<SessionSummary>>? _subscription;

  /// The foreground channel stream (in-app toasts).
  Stream<AppNotificationEvent> get foregroundEvents => _foreground.stream;

  /// Stops folding; no further events are emitted.
  void dispose() {
    unawaited(_subscription?.cancel());
    unawaited(_foreground.close());
  }

  void _onSessions(List<SessionSummary> sessions) {
    final events = _detector.fold(
      sessions: sessions,
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
}

/// Where one event should surface, decided at emit time.
enum NotificationChannel { foregroundToast, systemNotification, none }

/// Selects the channel for [event]: backgrounded events are always system
/// notifications; a foregrounded app toasts everything except the selected
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
