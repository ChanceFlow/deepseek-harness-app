/// System (OS-level) notifications for the app's notification events.
///
/// Posts a notification for each [AppNotificationEvent] that arrives while
/// the app is backgrounded, with a JSON payload identifying the session so a
/// tap can deep-link back into it. Copy resolves once at [initialize] from
/// the platform locale — an app restart is what picks up a device-language
/// change, which matches how the plugin caches its Android channel metadata.
///
/// Also owns the ongoing per-session work lifecycle ([showWork],
/// [updateWorkBody], [promoteWorkToDone], [cancelWork]): a silent
/// persistent row while a session works or waits, replaced in place by a
/// dismissible completion notice when it finishes. Every row addresses the
/// session through the deterministic (id, tag) of `notification_key.dart`
/// and carries the same deep-link payload as the transient posts.
library;

import 'dart:async';
import 'dart:convert';

import 'package:app/l10n/app_localizations.dart';
import 'package:domain/model/session.dart' show SessionPendingInteraction;
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show Locale, WidgetsBinding;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'notification_events.dart';
import 'notification_key.dart';
import 'notification_ledger.dart';
import 'working_sessions_fold.dart';

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
  /// [plugin] is the injection seam for tests and headless hosts; production
  /// wiring (main, DI) leaves it null and gets the real plugin.
  SystemNotifier({
    FlutterLocalNotificationsPlugin? plugin,
    NotificationLedger? ledger,
  }) : _plugin = plugin ?? FlutterLocalNotificationsPlugin() {
    _ledger = ledger;
  }

  /// The silent, low-importance channel hosting ongoing work notifications.
  static const String _workingChannelId = 'working';

  /// The turn-completion channel the promoted done notice rides (shared with
  /// the [AppNotificationKind] turn-complete posts).
  static const String _turnsChannelId = 'turns';

  final FlutterLocalNotificationsPlugin _plugin;
  NotificationLedger? _ledger;
  bool _initialized = false;
  int _nextId = 1;

  /// Attaches a [NotificationLedger] to record posted ongoing rows across
  /// app restarts.
  void attachLedger(NotificationLedger ledger) {
    _ledger = ledger;
  }

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
    // Create the working channel explicitly: its silent low importance must
    // not depend on which show call happens to bootstrap it first.
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(
          AndroidNotificationChannel(
            _workingChannelId,
            _l10n.workingChannel,
            description: _l10n.workingChannelDescription,
            importance: Importance.low,
            playSound: false,
            enableVibration: false,
          ),
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

  /// Arms the silent ongoing notification for a running or waiting session
  /// ([work] carries the desired working/waiting state and the session
  /// title). Posting and re-posting share the deterministic (id, tag) of
  /// [work.sessionId], so a process restart replaces the previous process's
  /// row instead of stranding an orphan.
  Future<void> showWork({
    required String backendId,
    required WorkingSessionDecision work,
  }) async {
    _ledger?.record(backendId: backendId, sessionId: work.sessionId);
    await _postOngoing(backendId: backendId, work: work);
  }

  /// Updates an already-armed ongoing notification in place: the same
  /// (id, tag) with `onlyAlertOnce` keeps it silent and non-bumping as the
  /// WORKING body turns WAITING (or a rename lands).
  Future<void> updateWorkBody({
    required String backendId,
    required WorkingSessionDecision work,
  }) async {
    _ledger?.record(backendId: backendId, sessionId: work.sessionId);
    await _postOngoing(backendId: backendId, work: work);
  }

  /// Replaces the session's ongoing notification — under the same id and
  /// tag — with a non-ongoing, swipe-away, auto-canceling completion notice
  /// on the turns channel. Re-showing an existing id replaces it in place
  /// including the ongoing flag; `onlyAlertOnce` keeps the promotion silent
  /// because the transient turn-complete event already announces it.
  Future<void> promoteWorkToDone({
    required String backendId,
    required WorkingSessionDecision work,
  }) async {
    _ledger?.record(backendId: backendId, sessionId: work.sessionId);
    if (kDebugMode && !_initialized) return;
    await _postWork(
      backendId: backendId,
      work: work,
      details: AndroidNotificationDetails(
        _turnsChannelId,
        _l10n.turnCompletionChannel,
        channelDescription: _l10n.turnCompletionChannelDescription,
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
        ongoing: false,
        autoCancel: true,
        onlyAlertOnce: true,
        tag: workingNotificationTag(backendId, work.sessionId),
      ),
    );
  }

  /// Cancels the session's ongoing/done notification by (id, tag). Safe on
  /// an already-swiped row: the OS dismiss is unobservable, so cancellation
  /// is how the fold's `gone` (and session removal) tears the row down.
  Future<void> cancelWork({
    required String backendId,
    required String sessionId,
  }) async {
    _ledger?.remove(backendId: backendId, sessionId: sessionId);
    if (kDebugMode && !_initialized) return;
    try {
      await _plugin.cancel(
        workingNotificationId(backendId, sessionId),
        tag: workingNotificationTag(backendId, sessionId),
      );
    } catch (_) {
      // Notification failures never surface in the chat UI.
    }
  }

  /// Sweeps the posted-rows ledger at startup: cancels any ongoing/done
  /// notification belonging to a backend that is NOT in [enabledBackendIds]
  /// (disabled or removed backends) so orphaned rows do not survive process
  /// restarts.
  Future<void> sweepStaleRows({required Set<String> enabledBackendIds}) async {
    final ledger = _ledger;
    if (ledger == null) return;
    final entries = ledger.readEntries();
    for (final entry in entries) {
      if (!enabledBackendIds.contains(entry.backendId)) {
        await cancelWork(
          backendId: entry.backendId,
          sessionId: entry.sessionId,
        );
      }
    }
  }

  Future<void> _postOngoing({
    required String backendId,
    required WorkingSessionDecision work,
  }) async {
    if (kDebugMode && !_initialized) return;
    await _postWork(
      backendId: backendId,
      work: work,
      details: AndroidNotificationDetails(
        _workingChannelId,
        _l10n.workingChannel,
        channelDescription: _l10n.workingChannelDescription,
        importance: Importance.low,
        priority: Priority.low,
        ongoing: true,
        autoCancel: false,
        onlyAlertOnce: true,
        tag: workingNotificationTag(backendId, work.sessionId),
      ),
    );
  }

  Future<void> _postWork({
    required String backendId,
    required WorkingSessionDecision work,
    required AndroidNotificationDetails details,
  }) async {
    try {
      await _plugin.show(
        workingNotificationId(backendId, work.sessionId),
        work.sessionTitle,
        _workingBody(work),
        NotificationDetails(android: details),
        payload: NotificationTarget(
          backendId: backendId,
          sessionId: work.sessionId,
        ).encode(),
      );
    } catch (_) {
      // Notification failures never surface in the chat UI.
    }
  }

  /// The localized body for one ongoing/done decision: the waiting substate
  /// names what the session waits on; done reuses the turn-complete copy.
  String _workingBody(WorkingSessionDecision work) {
    if (work.state == WorkingSessionState.done) {
      return _l10n.turnCompleteTitle;
    }
    final pending = work.pending;
    if (work.state == WorkingSessionState.waiting && pending != null) {
      return switch (pending) {
        SessionPendingInteraction.approval => _l10n.waitingApprovalBody,
        SessionPendingInteraction.planReview => _l10n.waitingPlanReviewBody,
        SessionPendingInteraction.question => _l10n.waitingAnswerBody,
      };
    }
    return _l10n.workingNotificationBody;
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
    AppNotificationKind.otherTurnComplete => _turnsChannelId,
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
