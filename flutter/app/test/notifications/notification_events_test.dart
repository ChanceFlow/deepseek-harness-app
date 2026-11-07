/// Notification vocabulary tests: the pure [NotificationDetector] fold and
/// the foreground/background routing decision. Both are driven with plain
/// session lists and asserted on the exact event stream — no plugin, no UI.
library;

import 'package:app/notifications/app_notification_center.dart'
    show announcementFor;
import 'package:app/notifications/notification_events.dart';
import 'package:domain/model/session.dart';
import 'package:flutter_test/flutter_test.dart';

/// One session summary with the fields the fold reads.
SessionSummary session(
  String id, {
  String? title,
  bool running = false,
  SessionPendingInteraction? pending,
  String? cwd,
}) => SessionSummary(
  id: id,
  title: title,
  running: running,
  blank: false,
  pendingInteraction: pending,
  cwd: cwd,
);

void main() {
  group('NotificationDetector', () {
    test('first snapshot seeds the baseline and emits nothing', () {
      final detector = NotificationDetector();
      final events = detector.fold(
        sessions: [
          session('s1', title: 'Running', running: true),
          session('s2', pending: SessionPendingInteraction.approval),
        ],
        selectedSessionId: 's1',
        backendId: 'b1',
      );
      expect(events, isEmpty);
    });

    test('selected session running → idle emits selectedTurnComplete', () {
      final detector = NotificationDetector();
      detector.fold(
        sessions: [session('s1', title: 'Work', running: true)],
        selectedSessionId: 's1',
        backendId: 'b1',
      );
      final events = detector.fold(
        sessions: [session('s1', title: 'Work', running: false)],
        selectedSessionId: 's1',
        backendId: 'b1',
      );
      expect(events, [
        const AppNotificationEvent(
          kind: AppNotificationKind.selectedTurnComplete,
          backendId: 'b1',
          sessionId: 's1',
          sessionTitle: 'Work',
        ),
      ]);
    });

    test('non-selected session running → idle emits otherTurnComplete', () {
      final detector = NotificationDetector();
      detector.fold(
        sessions: [session('s2', title: 'Other', running: true)],
        selectedSessionId: 's1',
        backendId: 'b1',
      );
      final events = detector.fold(
        sessions: [session('s2', title: 'Other', running: false)],
        selectedSessionId: 's1',
        backendId: 'b1',
      );
      expect(events, [
        const AppNotificationEvent(
          kind: AppNotificationKind.otherTurnComplete,
          backendId: 'b1',
          sessionId: 's2',
          sessionTitle: 'Other',
        ),
      ]);
    });

    test('idle → idle does not re-fire', () {
      final detector = NotificationDetector();
      detector.fold(
        sessions: [session('s1', title: 'Work')],
        selectedSessionId: 's1',
        backendId: 'b1',
      );
      final events = detector.fold(
        sessions: [session('s1', title: 'Work')],
        selectedSessionId: 's1',
        backendId: 'b1',
      );
      expect(events, isEmpty);
    });

    test('running → idle then again emits each completion once', () {
      final detector = NotificationDetector();
      detector.fold(
        sessions: [session('s1', title: 'Work')],
        selectedSessionId: 's1',
        backendId: 'b1',
      );
      detector.fold(
        sessions: [session('s1', title: 'Work', running: true)],
        selectedSessionId: 's1',
        backendId: 'b1',
      );
      final first = detector.fold(
        sessions: [session('s1', title: 'Work', running: false)],
        selectedSessionId: 's1',
        backendId: 'b1',
      );
      expect(first, hasLength(1));
      detector.fold(
        sessions: [session('s1', title: 'Work', running: true)],
        selectedSessionId: 's1',
        backendId: 'b1',
      );
      final second = detector.fold(
        sessions: [session('s1', title: 'Work', running: false)],
        selectedSessionId: 's1',
        backendId: 'b1',
      );
      expect(second, hasLength(1));
    });

    test('pending → approval emits approvalRequested', () {
      final detector = NotificationDetector();
      detector.fold(
        sessions: [session('s1', title: 'Perm')],
        selectedSessionId: 's1',
        backendId: 'b1',
      );
      final events = detector.fold(
        sessions: [
          session(
            's1',
            title: 'Perm',
            pending: SessionPendingInteraction.approval,
          ),
        ],
        selectedSessionId: 's1',
        backendId: 'b1',
      );
      expect(events, [
        const AppNotificationEvent(
          kind: AppNotificationKind.approvalRequested,
          backendId: 'b1',
          sessionId: 's1',
          sessionTitle: 'Perm',
        ),
      ]);
    });

    test('pending → planReview emits planReviewRequested', () {
      final detector = NotificationDetector();
      detector.fold(
        sessions: [session('s1', title: 'Plan')],
        selectedSessionId: 's1',
        backendId: 'b1',
      );
      final events = detector.fold(
        sessions: [
          session(
            's1',
            title: 'Plan',
            pending: SessionPendingInteraction.planReview,
          ),
        ],
        selectedSessionId: 's1',
        backendId: 'b1',
      );
      expect(events, [
        const AppNotificationEvent(
          kind: AppNotificationKind.planReviewRequested,
          backendId: 'b1',
          sessionId: 's1',
          sessionTitle: 'Plan',
        ),
      ]);
    });

    test('plain question pending does not emit a notification', () {
      final detector = NotificationDetector();
      detector.fold(
        sessions: [session('s1', title: 'Q')],
        selectedSessionId: 's1',
        backendId: 'b1',
      );
      final events = detector.fold(
        sessions: [
          session(
            's1',
            title: 'Q',
            pending: SessionPendingInteraction.question,
          ),
        ],
        selectedSessionId: 's1',
        backendId: 'b1',
      );
      expect(events, isEmpty);
    });

    test(
      'a session removed while running emits nothing and stops tracking',
      () {
        final detector = NotificationDetector();
        detector.fold(
          sessions: [session('s1', title: 'Gone', running: true)],
          selectedSessionId: 's1',
          backendId: 'b1',
        );
        // The session disappears; no transition is reported.
        final events = detector.fold(
          sessions: const <SessionSummary>[],
          selectedSessionId: 's1',
          backendId: 'b1',
        );
        expect(events, isEmpty);
        // A re-added session is treated as a fresh baseline, not a completion.
        final reAdded = detector.fold(
          sessions: [session('s1', title: 'Gone', running: false)],
          selectedSessionId: 's1',
          backendId: 'b1',
        );
        expect(reAdded, isEmpty);
      },
    );

    test('multiple transitions in one snapshot all surface', () {
      final detector = NotificationDetector();
      detector.fold(
        sessions: [
          session('s1', title: 'Selected', running: true),
          session('s2', title: 'Other', running: true),
          session('s3', title: 'Perm'),
        ],
        selectedSessionId: 's1',
        backendId: 'b1',
      );
      final events = detector.fold(
        sessions: [
          session('s1', title: 'Selected', running: false),
          session('s2', title: 'Other', running: false),
          session(
            's3',
            title: 'Perm',
            pending: SessionPendingInteraction.approval,
          ),
        ],
        selectedSessionId: 's1',
        backendId: 'b1',
      );
      expect(events.map((e) => e.kind), [
        AppNotificationKind.selectedTurnComplete,
        AppNotificationKind.otherTurnComplete,
        AppNotificationKind.approvalRequested,
      ]);
    });

    test('the event carries the workspace when it tells sessions apart', () {
      final detector = NotificationDetector();
      detector.fold(
        sessions: [
          session('s1', title: 'Work', running: true, cwd: '/home/me/proj-a'),
        ],
        selectedSessionId: 's1',
        backendId: 'b1',
      );
      final events = detector.fold(
        sessions: [session('s1', title: 'Work', cwd: '/home/me/proj-a')],
        selectedSessionId: 's1',
        backendId: 'b1',
      );
      expect(events.single.sessionContext, 'proj-a');
    });

    test('no context when the workspace basename is already the title', () {
      // A titleless session displays its workspace path, so repeating it in
      // the body would crowd the notification with the same word twice.
      final detector = NotificationDetector();
      detector.fold(
        sessions: [session('s1', running: true, cwd: '/home/me/proj-a')],
        selectedSessionId: 's1',
        backendId: 'b1',
      );
      final events = detector.fold(
        sessions: [session('s1', cwd: '/home/me/proj-a')],
        selectedSessionId: 's1',
        backendId: 'b1',
      );
      expect(events.single.sessionTitle, 'proj-a');
      expect(events.single.sessionContext, isNull);
    });

    test('no context when the session has no workspace path', () {
      final detector = NotificationDetector();
      detector.fold(
        sessions: [session('s1', title: 'Work', running: true)],
        selectedSessionId: 's1',
        backendId: 'b1',
      );
      final events = detector.fold(
        sessions: [session('s1', title: 'Work')],
        selectedSessionId: 's1',
        backendId: 'b1',
      );
      expect(events.single.sessionContext, isNull);
    });
  });

  group('announcementFor', () {
    AppNotificationEvent eventOf(AppNotificationKind kind) =>
        AppNotificationEvent(
          kind: kind,
          backendId: 'b1',
          sessionId: 's1',
          sessionTitle: 'Work',
        );

    test('backgrounded events always reach the shade, never the banner', () {
      for (final kind in AppNotificationKind.values) {
        expect(announcementFor(eventOf(kind), false), (
          system: true,
          toast: false,
        ), reason: '$kind must leave a row while backgrounded');
      }
    });

    test('the watched session keeps its row but stays off the banner', () {
      expect(
        announcementFor(
          eventOf(AppNotificationKind.selectedTurnComplete),
          true,
        ),
        (system: true, toast: false),
      );
    });

    test('other foregrounded events reach both surfaces', () {
      for (final kind in [
        AppNotificationKind.otherTurnComplete,
        AppNotificationKind.approvalRequested,
        AppNotificationKind.planReviewRequested,
      ]) {
        expect(announcementFor(eventOf(kind), true), (
          system: true,
          toast: true,
        ), reason: '$kind must expose a row and a banner');
      }
    });
  });
}
