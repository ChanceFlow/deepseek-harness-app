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

import '../logging/error_log_collector.dart';
import '../logging/error_log_entry.dart';
import 'notification_events.dart';
import 'notification_key.dart';
import 'notification_ledger.dart';
import 'notification_localizations.dart';
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

  /// Whether the Android notification permission has been granted. Starts
  /// true (nothing known to be denied); [ensurePermissionRequested] settles
  /// it against the host's answer.
  bool _permissionGranted = true;

  /// Whether this process already spent its one system permission ask.
  bool _permissionAsked = false;

  /// Whether the host has granted the notification permission.
  bool get permissionGranted => _permissionGranted;

  /// Re-resolves notification copy for [locale]: the app's own language
  /// choice, or the device locale when none is pinned.
  ///
  /// Notifications are composed outside the widget tree, so they cannot read
  /// `MaterialApp.locale` the way in-app surfaces do — without this call an
  /// in-app language switch would leave notification copy in the old
  /// language until the process restarted ([initialize] resolves nothing
  /// after its first read).
  void applyLocale(Locale? locale) {
    _l10n = resolveAppLocalizations(
      locale ?? WidgetsBinding.instance.platformDispatcher.locale,
    );
  }

  /// Asks the host for the notification permission, at most once per process,
  /// and reports whether it is granted.
  ///
  /// Never called from startup: the ask belongs where the user can see why
  /// (see [NotificationPermissionGate]). A denial is recorded — the ask
  /// itself is not repeated, because Android stops showing its dialog after
  /// a couple of declines.
  Future<bool> ensurePermissionRequested() async {
    if (_permissionAsked) return _permissionGranted;
    _permissionAsked = true;
    try {
      _permissionGranted =
          await _plugin
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >()
              ?.requestNotificationsPermission() ??
          true;
    } catch (error) {
      _permissionGranted = false;
      _reportFailure('requestPermission', error);
      return false;
    }
    if (!_permissionGranted) {
      ErrorLogCollector.instance.addBreadcrumb(
        'Notification permission denied; system notifications stay silent.',
        level: 'warning',
      );
    }
    return _permissionGranted;
  }

  /// Initializes the plugin, resolves the launch-time locale, creates the
  /// silent working channel, and captures a cold-start launch target if this
  /// app run began from a notification tap.
  ///
  /// Deliberately does not ask for the notification permission; that ask is
  /// spent later, where the user can see why (see
  /// [ensurePermissionRequested]).
  /// @returns the cold-start target, if the app was launched by a tap.
  Future<NotificationTarget?> initialize() async {
    if (_initialized) return _launchTarget;
    // A monochrome silhouette, not the launcher icon: Android draws a
    // notification small icon from its alpha channel and tints the rest, so
    // a full-colour launcher asset renders as a white blob. The same glyph
    // the keep-alive foreground service notification uses.
    const android = AndroidInitializationSettings('@drawable/ic_stat_dsh');
    await _plugin.initialize(
      const InitializationSettings(android: android),
      onDidReceiveNotificationResponse: _onResponse,
    );
    // Resolve the launch-time locale so notifications render in the app's
    // language without context plumbing into the DI layer. The resolver
    // clamps an unsupported platform language to the app's supported set; a
    // raw lookup would throw here, before runApp, and strand the splash.
    // [applyLocale] re-resolves this when the in-app language choice changes.
    _l10n = resolveAppLocalizations(
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
    } catch (error) {
      // Launch-detail queries must never block startup; the failure is
      // recorded rather than swallowed so a lost cold-start deep link is
      // diagnosable.
      _reportFailure('launchDetails', error);
    }
    _initialized = true;
    return _launchTarget;
  }

  /// Posts the system notification for [event]. Failures are swallowed —
  /// a notification never breaks the chat surface that raised it.
  ///
  /// Turn completions address the session's deterministic (id, tag) — the
  /// same row the ongoing fold owns — so one finished turn produces one
  /// notification instead of a working row plus a separate completion row.
  /// Approvals and reviews keep counter ids: they are distinct facts that
  /// coexist with the session's ongoing row.
  Future<void> show(AppNotificationEvent event) async {
    if (kDebugMode && !_initialized) {
      // Tests and headless hosts never initialize the plugin.
      return;
    }
    final copy = _copyFor(event.kind);
    final sessionScoped = _isTurnComplete(event.kind);
    try {
      await _plugin.show(
        sessionScoped
            ? workingNotificationId(event.backendId, event.sessionId)
            : _nextId++,
        copy,
        notificationBodyLine(event.sessionTitle, event.sessionContext),
        NotificationDetails(
          android: AndroidNotificationDetails(
            _channelFor(event.kind),
            _channelNameFor(event.kind),
            channelDescription: _channelDescriptionFor(event.kind),
            importance: _importanceFor(event.kind),
            priority: _priorityFor(event.kind),
            ongoing: false,
            autoCancel: true,
            onlyAlertOnce: sessionScoped,
            tag: sessionScoped
                ? workingNotificationTag(event.backendId, event.sessionId)
                : null,
          ),
        ),
        payload: NotificationTarget(
          backendId: event.backendId,
          sessionId: event.sessionId,
        ).encode(),
      );
    } catch (error) {
      _reportFailure('show', error);
    }
  }

  /// Whether [kind]'s row is owned by the session's ongoing lifecycle: the
  /// completion notice replaces that session's working row in place.
  static bool _isTurnComplete(AppNotificationKind kind) => switch (kind) {
    AppNotificationKind.selectedTurnComplete ||
    AppNotificationKind.otherTurnComplete => true,
    AppNotificationKind.approvalRequested ||
    AppNotificationKind.planReviewRequested => false,
  };

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
    } catch (error) {
      _reportFailure('cancelWork', error);
    }
  }

  /// Clears every row a previous process posted.
  ///
  /// An ongoing row is not swipeable, so a leftover one is a permanent scar
  /// in the shade, and nothing in this process can confirm it: the session
  /// may have finished, or the host may be unreachable so no snapshot will
  /// ever say either way. The ledger therefore records what the *last*
  /// process posted, and this treats all of it as unconfirmed — the first
  /// real snapshot re-arms whatever is genuinely still running. The cost is
  /// one disappear/reappear of a row that was genuinely live.
  Future<void> clearUnconfirmedRows() async {
    final ledger = _ledger;
    if (ledger == null) return;
    final entries = ledger.readEntries();
    if (entries.isEmpty) return;
    for (final entry in entries) {
      await cancelWork(backendId: entry.backendId, sessionId: entry.sessionId);
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
    // The done notice is the session's turn-completion news, so it wears the
    // same title/body convention the transient turn-complete post does: one
    // fact, one wording, whichever of the two lands first.
    final done = work.state == WorkingSessionState.done;
    final title = done ? _l10n.turnCompleteTitle : work.sessionTitle;
    final body = done
        ? notificationBodyLine(work.sessionTitle, work.sessionContext)
        : _workingBody(work);
    try {
      await _plugin.show(
        workingNotificationId(backendId, work.sessionId),
        title,
        body,
        NotificationDetails(android: details),
        payload: NotificationTarget(
          backendId: backendId,
          sessionId: work.sessionId,
        ).encode(),
      );
    } catch (error) {
      _reportFailure('showWork', error);
    }
  }

  /// Records a swallowed notification failure. Chat surfaces must never see
  /// a notification error, but it must not disappear either: a revoked
  /// permission or a disabled channel is otherwise undiagnosable in the
  /// field (the error log is the app's only in-product trace).
  void _reportFailure(String call, Object error) {
    ErrorLogCollector.instance.captureError(
      error,
      stackTrace: StackTrace.current,
      level: ErrorLogLevel.warning,
      context: <String, Object?>{'component': 'systemNotifier', 'call': call},
    );
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

  /// The localized title for one transient event; the body always composes
  /// through [notificationBodyLine], so only the "what happened" half is
  /// kind-specific.
  String _copyFor(AppNotificationKind kind) => switch (kind) {
    AppNotificationKind.selectedTurnComplete => _l10n.turnCompleteTitle,
    AppNotificationKind.otherTurnComplete => _l10n.otherTurnCompleteTitle,
    AppNotificationKind.approvalRequested => _l10n.approvalRequestedTitle,
    AppNotificationKind.planReviewRequested => _l10n.planReviewRequestedTitle,
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
