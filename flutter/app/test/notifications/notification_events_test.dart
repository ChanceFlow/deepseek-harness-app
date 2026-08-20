/// Notification vocabulary tests: the pure [NotificationDetector] fold and
/// the foreground/background routing decision. Both are driven with plain
/// session lists and asserted on the exact event stream — no plugin, no UI.
library;

import 'package:app/notifications/app_notification_center.dart'
    show NotificationChannel, channelFor;
import 'package:app/notifications/notification_events.dart';
import 'package:domain/model/session.dart';
import 'package:flutter_test/flutter_test.dart';

/// One session summary with the fields the fold reads.
SessionSummary session(
  String id, {
  String? title,
  bool running = false,
  SessionPendingInteraction? pending,
}) => SessionSummary(
  id: id,
  title: title,
  running: running,
  blank: false,
  pendingInteraction: pending,
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
          session('s1', title: 'Perm', pending: SessionPendingInteraction.approval),
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
          session('s1', title: 'Plan', pending: SessionPendingInteraction.planReview),
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
          session('s1', title: 'Q', pending: SessionPendingInteraction.question),
        ],
        selectedSessionId: 's1',
        backendId: 'b1',
      );
      expect(events, isEmpty);
    });

    test('a session removed while running emits nothing and stops tracking', () {
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
    });

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
          session('s3', title: 'Perm', pending: SessionPendingInteraction.approval),
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
  });

  group('channelFor', () {
    AppNotificationEvent eventOf(AppNotificationKind kind) =>
        AppNotificationEvent(
          kind: kind,
          backendId: 'b1',
          sessionId: 's1',
          sessionTitle: 'Work',
        );

    test('backgrounded routes every event to the system channel', () {
      for (final kind in AppNotificationKind.values) {
        expect(channelFor(eventOf(kind), false), NotificationChannel.systemNotification,
            reason: '$kind must be a system notification while backgrounded');
      }
    });

    test('foregrounded selected-turn-complete is silent', () {
      expect(
        channelFor(
          eventOf(AppNotificationKind.selectedTurnComplete),
          true,
        ),
        NotificationChannel.none,
      );
    });

    test('foregrounded other events toast', () {
      for (final kind in [
        AppNotificationKind.otherTurnComplete,
        AppNotificationKind.approvalRequested,
        AppNotificationKind.planReviewRequested,
      ]) {
        expect(channelFor(eventOf(kind), true), NotificationChannel.foregroundToast,
            reason: '$kind must toast while foregrounded');
      }
    });
  });
}
