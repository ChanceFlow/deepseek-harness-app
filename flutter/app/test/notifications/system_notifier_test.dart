/// System-notifier tests: the notification-tap target codec and the
/// ongoing-work posting contract (driven through a recording plugin fake —
/// the seams assert exactly what would reach Android: id, tag, channel,
/// ongoing/autoCancel/onlyAlertOnce flags, localized body, deep-link
/// payload). OS rendering itself is real-device evidence, see the decision
/// note.
library;

import 'package:app/l10n/app_localizations.dart';
import 'package:app/notifications/notification_key.dart';
import 'package:app/notifications/system_notifier.dart'
    show NotificationTarget, SystemNotifier;
import 'package:app/notifications/working_sessions_fold.dart';
import 'package:domain/model/session.dart';
import 'package:flutter/widgets.dart' show WidgetsBinding;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';

/// Plugin double: records show/cancel, everything else falls through to
/// `noSuchMethod` (this test never touches the other members).
class _RecordingPlugin implements FlutterLocalNotificationsPlugin {
  final posted =
      <
        ({
          int id,
          String? title,
          String? body,
          NotificationDetails? details,
          String? payload,
        })
      >[];
  final cancelled = <({int id, String? tag})>[];

  @override
  Future<void> show(
    int id,
    String? title,
    String? body,
    NotificationDetails? notificationDetails, {
    String? payload,
  }) async {
    posted.add((
      id: id,
      title: title,
      body: body,
      details: notificationDetails,
      payload: payload,
    ));
  }

  @override
  Future<void> cancel(int id, {String? tag}) async {
    cancelled.add((id: id, tag: tag));
  }

  @override
  T? resolvePlatformSpecificImplementation<
    T extends FlutterLocalNotificationsPlatform
  >() => null;

  @override
  Future<bool?> initialize(
    InitializationSettings initializationSettings, {
    DidReceiveNotificationResponseCallback? onDidReceiveNotificationResponse,
    DidReceiveBackgroundNotificationResponseCallback?
    onDidReceiveBackgroundNotificationResponse,
  }) async => true;

  @override
  Future<NotificationAppLaunchDetails?>
  getNotificationAppLaunchDetails() async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

WorkingSessionDecision _work(
  String sessionId, {
  required WorkingSessionState state,
  String title = 'Work',
  SessionPendingInteraction? pending,
}) => WorkingSessionDecision(
  sessionId: sessionId,
  sessionTitle: title,
  state: state,
  pending: pending,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _RecordingPlugin plugin;
  late SystemNotifier notifier;
  late AppLocalizations l10n;

  setUp(() async {
    plugin = _RecordingPlugin();
    notifier = SystemNotifier(plugin: plugin);
    // Resolve copy the same way initialize() does, so expectations track
    // the test host's platform locale instead of a hard-coded English.
    l10n = lookupAppLocalizations(
      WidgetsBinding.instance.platformDispatcher.locale,
    );
    await notifier.initialize();
    plugin.posted.clear();
    plugin.cancelled.clear();
  });

  group('ongoing work notifications', () {
    test(
      'showWork posts an ongoing silent row on the working channel',
      () async {
        await notifier.showWork(
          backendId: 'b1',
          work: _work('s1', state: WorkingSessionState.working),
        );
        final post = plugin.posted.single;
        expect(post.id, workingNotificationId('b1', 's1'));
        final android = post.details!.android!;
        expect(android.channelId, 'working');
        expect(android.ongoing, isTrue);
        expect(android.onlyAlertOnce, isTrue);
        expect(android.autoCancel, isFalse);
        expect(android.importance, Importance.low);
        expect(android.tag, 'b1/s1');
        expect(post.title, 'Work');
        expect(post.body, l10n.workingNotificationBody);
        expect(
          NotificationTarget.decode(post.payload!),
          const NotificationTarget(backendId: 'b1', sessionId: 's1'),
        );
      },
    );

    test('the waiting substates name what the session waits on', () async {
      final cases = {
        SessionPendingInteraction.approval: l10n.waitingApprovalBody,
        SessionPendingInteraction.planReview: l10n.waitingPlanReviewBody,
        SessionPendingInteraction.question: l10n.waitingAnswerBody,
      };
      for (final entry in cases.entries) {
        plugin.posted.clear();
        await notifier.updateWorkBody(
          backendId: 'b1',
          work: _work(
            's1',
            state: WorkingSessionState.waiting,
            pending: entry.key,
          ),
        );
        final post = plugin.posted.single;
        expect(post.body, entry.value, reason: '${entry.key} body');
        final android = post.details!.android!;
        expect(android.ongoing, isTrue, reason: '${entry.key} stays ongoing');
      }
    });

    test(
      'promoteWorkToDone replaces the same id non-ongoing on turns',
      () async {
        await notifier.promoteWorkToDone(
          backendId: 'b1',
          work: _work('s1', state: WorkingSessionState.done),
        );
        final post = plugin.posted.single;
        expect(post.id, workingNotificationId('b1', 's1'));
        final android = post.details!.android!;
        expect(android.channelId, 'turns');
        expect(android.ongoing, isFalse);
        expect(android.autoCancel, isTrue);
        expect(android.tag, 'b1/s1');
        expect(post.title, 'Work');
        expect(post.body, l10n.turnCompleteTitle);
      },
    );

    test('cancelWork cancels by (id, tag)', () async {
      await notifier.cancelWork(backendId: 'b1', sessionId: 's2');
      final cancel = plugin.cancelled.single;
      expect(cancel.id, workingNotificationId('b1', 's2'));
      expect(cancel.tag, 'b1/s2');
    });

    test('posts are no-ops before initialize', () async {
      final coldPlugin = _RecordingPlugin();
      final cold = SystemNotifier(plugin: coldPlugin);
      await cold.showWork(
        backendId: 'b1',
        work: _work('s1', state: WorkingSessionState.working),
      );
      await cold.cancelWork(backendId: 'b1', sessionId: 's1');
      expect(coldPlugin.posted, isEmpty);
      expect(coldPlugin.cancelled, isEmpty);
    });
  });

  group('NotificationTarget codec', () {
    test('round-trips backend + session ids', () {
      const target = NotificationTarget(backendId: 'b-1', sessionId: 's-2');
      expect(NotificationTarget.decode(target.encode()), target);
    });

    test('decodes a malformed payload to null', () {
      expect(NotificationTarget.decode('not json'), isNull);
      expect(NotificationTarget.decode('{"backendId":1}'), isNull);
      expect(
        NotificationTarget.decode('{"backendId":"b","sessionId":2}'),
        isNull,
      );
      expect(NotificationTarget.decode('[]'), isNull);
    });

    test('ignores unknown extra fields', () {
      const target = NotificationTarget(backendId: 'b', sessionId: 's');
      expect(
        NotificationTarget.decode(
          '{"backendId":"b","sessionId":"s","extra":true}',
        ),
        target,
      );
    });
  });
}
