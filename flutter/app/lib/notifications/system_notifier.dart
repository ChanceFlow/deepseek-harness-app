/// System (OS-level) notifications for the app's notification events.
///
/// Posts a notification for each [AppNotificationEvent] that arrives while
/// the app is backgrounded, with a JSON payload identifying the session so a
/// tap can deep-link back into it. Copy resolves once at [initialize] from
/// the platform locale — an app restart is what picks up a device-language
/// change, which matches how the plugin caches its Android channel metadata.
library;

import 'dart:async';
import 'dart:convert';

import 'package:app/l10n/app_localizations.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show Locale, WidgetsBinding;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'notification_events.dart';

/// Where a notification tap should take the user.
final class NotificationTarget {
  const NotificationTarget({required this.backendId, required this.sessionId});

  final String backendId;
  final String sessionId;

  @override
  bool operator ==(Object other) =>
      other is NotificationTarget &&
      other.backendId == backendId &&
      other.sessionId == sessionId;

  @override
  int get hashCode => Object.hash(backendId, sessionId);

  String encode() => jsonEncode(<String, String>{
    'backendId': backendId,
    'sessionId': sessionId,
  });

  /// Decodes a [target] previously [encode]d; null for malformed payloads
  /// (a foreign/legacy notification we do not understand is ignored).
  static NotificationTarget? decode(String target) {
    try {
      final json = jsonDecode(target);
      if (json is! Map<String, dynamic>) return null;
      final backendId = json['backendId'];
      final sessionId = json['sessionId'];
      if (backendId is! String || sessionId is! String) return null;
      return NotificationTarget(backendId: backendId, sessionId: sessionId);
    } on FormatException {
      return null;
    }
  }
}

class SystemNotifier {
  SystemNotifier();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  int _nextId = 1;

  /// Tap and launch-destination notifications, emitted when the user
  /// interacts with a posted notification. Fed by the plugin's response
  /// callbacks wired in [initialize]; null entries are never emitted.
  final StreamController<NotificationTarget> _targets =
      StreamController<NotificationTarget>.broadcast();

  /// Notification copy for the launch-time device locale; the English seat
  /// is the pre-initialize default (posts are no-ops before initialize in
  /// debug builds).
  AppLocalizations _l10n = lookupAppLocalizations(const Locale('en'));

  /// Destinations the user asked for by tapping a notification.
  Stream<NotificationTarget> get targets => _targets.stream;

  /// Whether a notification tap cold-launched the app; the caller reads this
  /// once at startup to navigate after the first frame.
  NotificationTarget? takeLaunchTarget() => _launchTarget;
  NotificationTarget? _launchTarget;

  /// Initializes the plugin, resolves the launch-time locale, requests the
  /// Android 13+ notification permission, and captures a cold-start launch
  /// target if this app run began from a notification tap.
  /// @returns the cold-start target, if the app was launched by a tap.
  Future<NotificationTarget?> initialize() async {
    if (_initialized) return _launchTarget;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(
      const InitializationSettings(android: android),
      onDidReceiveNotificationResponse: _onResponse,
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();
    // Resolve the launch-time device locale so notifications render in the
    // app's language without context plumbing into the DI layer.
    _l10n = lookupAppLocalizations(
      WidgetsBinding.instance.platformDispatcher.locale,
    );
    try {
      final launchDetails = await _plugin.getNotificationAppLaunchDetails();
      if (launchDetails?.didNotificationLaunchApp == true) {
        final payload = launchDetails?.notificationResponse?.payload;
        if (payload != null) {
          _launchTarget = NotificationTarget.decode(payload);
        }
      }
    } catch (_) {
      // Launch-detail queries must never block startup.
    }
    _initialized = true;
    return _launchTarget;
  }

  /// Posts the system notification for [event]. Failures are swallowed —
  /// a notification never breaks the chat surface that raised it.
  Future<void> show(AppNotificationEvent event) async {
    if (kDebugMode && !_initialized) {
      // Tests and headless hosts never initialize the plugin.
      return;
    }
    final copy = _copyFor(event.kind);
    try {
      await _plugin.show(
        _nextId++,
        copy.title,
        copy.body(event.sessionTitle),
        NotificationDetails(
          android: AndroidNotificationDetails(
            _channelFor(event.kind),
            _channelNameFor(event.kind),
            channelDescription: _channelDescriptionFor(event.kind),
            importance: _importanceFor(event.kind),
            priority: _priorityFor(event.kind),
          ),
        ),
        payload: NotificationTarget(
          backendId: event.backendId,
          sessionId: event.sessionId,
        ).encode(),
      );
    } catch (_) {
      // Notification failures never surface in the chat UI.
    }
  }

  void _onResponse(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null) return;
    final target = NotificationTarget.decode(payload);
    if (target != null) _targets.add(target);
  }

  ({String title, String Function(String sessionTitle) body}) _copyFor(
    AppNotificationKind kind,
  ) => switch (kind) {
    AppNotificationKind.selectedTurnComplete => (
      title: _l10n.turnCompleteTitle,
      body: (sessionTitle) => sessionTitle,
    ),
    AppNotificationKind.otherTurnComplete => (
      title: _l10n.otherTurnCompleteTitle,
      body: (sessionTitle) => sessionTitle,
    ),
    AppNotificationKind.approvalRequested => (
      title: _l10n.approvalRequestedTitle,
      body: (sessionTitle) => sessionTitle,
    ),
    AppNotificationKind.planReviewRequested => (
      title: _l10n.planReviewRequestedTitle,
      body: (sessionTitle) => sessionTitle,
    ),
  };

  String _channelFor(AppNotificationKind kind) => switch (kind) {
    AppNotificationKind.selectedTurnComplete ||
    AppNotificationKind.otherTurnComplete => 'turns',
    AppNotificationKind.approvalRequested => 'approvals',
    AppNotificationKind.planReviewRequested => 'reviews',
  };

  String _channelNameFor(AppNotificationKind kind) => switch (kind) {
    AppNotificationKind.selectedTurnComplete ||
    AppNotificationKind.otherTurnComplete => _l10n.turnCompletionChannel,
    AppNotificationKind.approvalRequested => _l10n.approvalChannel,
    AppNotificationKind.planReviewRequested => _l10n.planReviewChannel,
  };

  String _channelDescriptionFor(AppNotificationKind kind) => switch (kind) {
    AppNotificationKind.selectedTurnComplete ||
    AppNotificationKind.otherTurnComplete =>
      _l10n.turnCompletionChannelDescription,
    AppNotificationKind.approvalRequested => _l10n.approvalChannelDescription,
    AppNotificationKind.planReviewRequested =>
      _l10n.planReviewChannelDescription,
  };

  Importance _importanceFor(AppNotificationKind kind) => switch (kind) {
    // Pending user actions need attention over a finished turn.
    AppNotificationKind.approvalRequested ||
    AppNotificationKind.planReviewRequested => Importance.high,
    AppNotificationKind.selectedTurnComplete ||
    AppNotificationKind.otherTurnComplete => Importance.defaultImportance,
  };

  Priority _priorityFor(AppNotificationKind kind) => switch (kind) {
    AppNotificationKind.approvalRequested ||
    AppNotificationKind.planReviewRequested => Priority.high,
    AppNotificationKind.selectedTurnComplete ||
    AppNotificationKind.otherTurnComplete => Priority.defaultPriority,
  };
}
