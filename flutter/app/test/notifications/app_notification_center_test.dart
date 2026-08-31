/// AppNotificationCenter wiring tests: the center folds the session stream
/// and routes events to the foreground (toast) stream or the background
/// callback per the app's foreground state, and reconciles the ongoing
/// per-session work notifications through the notifier seam (posting,
/// updating, promoting, and cancelling only where the desired state
/// changed). The repository double only implements `observeSessions` and
/// the notifier double only implements the work methods; every other member
/// falls through to `noSuchMethod` (this test never touches them).
library;

import 'dart:async';

import 'package:app/notifications/app_notification_center.dart';
import 'package:app/notifications/notification_events.dart';
import 'package:app/notifications/system_notifier.dart';
import 'package:app/notifications/working_sessions_fold.dart';
import 'package:app/ui/state_stream.dart';
import 'package:domain/model/session.dart';
import 'package:domain/repository/chat_repository.dart';
import 'package:flutter_test/flutter_test.dart';

SessionSummary _session(
  String id, {
  String? title,
  bool running = false,
  SessionPendingInteraction? pending,
  bool completed = false,
  String? parent,
}) => SessionSummary(
  id: id,
  title: title,
  running: running,
  blank: false,
  pendingInteraction: pending,
  completed: completed,
  parentSessionId: parent,
);

WorkingSessionDecision _decision(
  String id, {
  required WorkingSessionState state,
  String title = 'Work',
  SessionPendingInteraction? pending,
}) => WorkingSessionDecision(
  sessionId: id,
  sessionTitle: title,
  state: state,
  pending: pending,
);

/// Session-list-only repository double.
class _SessionsRepository implements ChatRepository {
  _SessionsRepository(List<SessionSummary> initial)
    : sessions = AppStateStream<List<SessionSummary>>(initial);

  final AppStateStream<List<SessionSummary>> sessions;

  @override
  Stream<List<SessionSummary>> observeSessions() => sessions.stream;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Work-lifecycle-only notifier double.
class _RecordingNotifier implements SystemNotifier {
  final shown = <WorkingSessionDecision>[];
  final updated = <WorkingSessionDecision>[];
  final promoted = <WorkingSessionDecision>[];
  final cancelled = <String>[];

  @override
  Future<void> showWork({
    required String backendId,
    required WorkingSessionDecision work,
  }) async => shown.add(work);

  @override
  Future<void> updateWorkBody({
    required String backendId,
    required WorkingSessionDecision work,
  }) async => updated.add(work);

  @override
  Future<void> promoteWorkToDone({
    required String backendId,
    required WorkingSessionDecision work,
  }) async => promoted.add(work);

  @override
  Future<void> cancelWork({
    required String backendId,
    required String sessionId,
  }) async => cancelled.add(sessionId);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _SessionsRepository repository;
  late List<AppNotificationEvent> background;
  late AppNotificationCenter center;

  setUp(() {
    repository = _SessionsRepository(const <SessionSummary>[]);
    background = <AppNotificationEvent>[];
    center = AppNotificationCenter(
      repository: repository,
      backendId: 'b1',
      isForegrounded: () => true,
      selectedSessionIdOf: () => 's1',
      onBackground: background.add,
      notifier: _RecordingNotifier(),
    );
  });

  tearDown(() => center.dispose());

  test(
    'other-session turn completion flows to the foreground toast stream',
    () async {
      repository.sessions.value = [
        _session('s2', title: 'Other', running: true),
      ];
      await pumpEventQueue();
      final events = <AppNotificationEvent>[];
      center.foregroundEvents.listen(events.add);

      repository.sessions.value = [
        _session('s2', title: 'Other', running: false),
      ];
      await pumpEventQueue();

      expect(events, hasLength(1));
      expect(events.single.kind, AppNotificationKind.otherTurnComplete);
      expect(events.single.sessionTitle, 'Other');
      expect(background, isEmpty);
    },
  );

  test('turn completion of a subagent child is silent (not a first-class '
      'notification subject)', () async {
    repository.sessions.value = [
      _session('s2', title: 'Root', running: true),
      _session('c1', title: 'Child', running: true, parent: 's2'),
    ];
    await pumpEventQueue();
    final events = <AppNotificationEvent>[];
    center.foregroundEvents.listen(events.add);

    repository.sessions.value = [
      _session('s2', title: 'Root', running: false),
      _session('c1', title: 'Child', running: false, parent: 's2'),
    ];
    await pumpEventQueue();

    // Only the root's completion surfaces; the child's transition never
    // enters the detector.
    expect(events.map((e) => e.sessionId), ['s2']);
    expect(background, isEmpty);
  });

  test(
    'the approval of a subagent child never raises a transient notice',
    () async {
      repository.sessions.value = [
        _session('s1', title: 'Root'),
        _session('c1', title: 'Child', parent: 's1'),
      ];
      await pumpEventQueue();
      final events = <AppNotificationEvent>[];
      center.foregroundEvents.listen(events.add);

      repository.sessions.value = [
        _session('s1', title: 'Root'),
        _session(
          'c1',
          title: 'Child',
          parent: 's1',
          pending: SessionPendingInteraction.approval,
        ),
      ];
      await pumpEventQueue();

      expect(events, isEmpty);
      expect(background, isEmpty);
    },
  );

  test(
    'selected-session turn completion is silent while foregrounded',
    () async {
      final events = <AppNotificationEvent>[];
      center.foregroundEvents.listen(events.add);

      repository.sessions.value = [
        _session('s1', title: 'Selected', running: true),
      ];
      await pumpEventQueue();
      repository.sessions.value = [
        _session('s1', title: 'Selected', running: false),
      ];
      await pumpEventQueue();

      expect(events, isEmpty);
      expect(background, isEmpty);
    },
  );

  test('approval request flows to the foreground toast stream', () async {
    final events = <AppNotificationEvent>[];
    center.foregroundEvents.listen(events.add);

    repository.sessions.value = [
      _session(
        's1',
        title: 'Perm',
        pending: SessionPendingInteraction.approval,
      ),
    ];
    await pumpEventQueue();

    expect(events, hasLength(1));
    expect(events.single.kind, AppNotificationKind.approvalRequested);
    expect(background, isEmpty);
  });

  test('backgrounded events route to the system callback', () async {
    final center2 = AppNotificationCenter(
      repository: repository,
      backendId: 'b1',
      isForegrounded: () => false,
      selectedSessionIdOf: () => 's1',
      onBackground: background.add,
      notifier: _RecordingNotifier(),
    );
    repository.sessions.value = [
      _session(
        's3',
        title: 'Review',
        pending: SessionPendingInteraction.planReview,
      ),
    ];
    await pumpEventQueue();

    expect(background, hasLength(1));
    expect(background.single.kind, AppNotificationKind.planReviewRequested);

    center2.dispose();
  });

  test(
    'backgrounded selected-session turn completion posts a system notification',
    () async {
      final center2 = AppNotificationCenter(
        repository: repository,
        backendId: 'b1',
        isForegrounded: () => false,
        selectedSessionIdOf: () => 's1',
        onBackground: background.add,
        notifier: _RecordingNotifier(),
      );
      repository.sessions.value = [
        _session('s1', title: 'Selected', running: true),
      ];
      await pumpEventQueue();
      repository.sessions.value = [
        _session('s1', title: 'Selected', running: false),
      ];
      await pumpEventQueue();

      expect(background, hasLength(1));
      expect(background.single.kind, AppNotificationKind.selectedTurnComplete);

      center2.dispose();
    },
  );

  test(
    'a new subscriber does not replay old events (broadcast semantics)',
    () async {
      final first = <AppNotificationEvent>[];
      center.foregroundEvents.listen(first.add);
      repository.sessions.value = [
        _session('s2', title: 'Other', running: true),
      ];
      await pumpEventQueue();
      repository.sessions.value = [
        _session('s2', title: 'Other', running: false),
      ];
      await pumpEventQueue();
      expect(first, hasLength(1));

      // A second listener attached after the event sees nothing new.
      final second = <AppNotificationEvent>[];
      center.foregroundEvents.listen(second.add);
      await pumpEventQueue();
      expect(second, isEmpty);
    },
  );

  group('ongoing work reconciliation', () {
    late _RecordingNotifier notifier;
    late bool foreground;
    late String? selected;
    late StreamController<void> selectionChanges;
    late StreamController<void> foregroundChanges;
    late AppNotificationCenter ongoingCenter;

    setUp(() {
      notifier = _RecordingNotifier();
      foreground = true;
      selected = 's1';
      selectionChanges = StreamController<void>.broadcast();
      foregroundChanges = StreamController<void>.broadcast();
    });

    tearDown(() async {
      ongoingCenter.dispose();
      await selectionChanges.close();
      await foregroundChanges.close();
    });

    /// Builds a center over [initial]; the state-stream seed reconciles.
    void start(List<SessionSummary> initial) {
      ongoingCenter = AppNotificationCenter(
        repository: _SessionsRepository(initial),
        backendId: 'b1',
        isForegrounded: () => foreground,
        selectedSessionIdOf: () => selected,
        onBackground: (_) {},
        notifier: notifier,
        selectionChanges: selectionChanges.stream,
        foregroundChanges: foregroundChanges.stream,
      );
    }

    test(
      'a snapshot that is already running arms the ongoing row (cold start)',
      () async {
        start([_session('s2', title: 'Other', running: true)]);
        await pumpEventQueue();
        expect(notifier.shown, [
          _decision('s2', state: WorkingSessionState.working, title: 'Other'),
        ]);
        expect(notifier.cancelled, isEmpty);
      },
    );

    test('a subagent child arms nothing; its root carries the story', () async {
      start([
        _session('s2', title: 'Root', running: true),
        _session('c1', title: 'Child', running: true, parent: 's2'),
        _session(
          'c2',
          title: 'Waiting child',
          pending: SessionPendingInteraction.approval,
          parent: 's2',
        ),
      ]);
      await pumpEventQueue();
      expect(notifier.shown, [
        _decision('s2', state: WorkingSessionState.working, title: 'Root'),
      ]);
      expect(notifier.cancelled, isEmpty);
    });

    test('a completed child at cold start promotes nothing', () async {
      start([
        _session('s2', title: 'Root'),
        _session('c1', title: 'Child', completed: true, parent: 's2'),
      ]);
      await pumpEventQueue();
      expect(notifier.promoted, isEmpty);
      expect(notifier.shown, isEmpty);
    });

    test(
      'a completed-unviewed session at cold start shows done directly',
      () async {
        start([_session('s2', title: 'Other', completed: true)]);
        await pumpEventQueue();
        expect(notifier.promoted, [
          _decision('s2', state: WorkingSessionState.done, title: 'Other'),
        ]);
        expect(notifier.shown, isEmpty);
      },
    );

    test('the foregrounded selected session arms nothing; others do', () async {
      start([
        _session('s1', title: 'Viewed', running: true),
        _session('s2', title: 'Other', running: true),
      ]);
      await pumpEventQueue();
      expect(notifier.shown, [
        _decision('s2', state: WorkingSessionState.working, title: 'Other'),
      ]);
      expect(notifier.cancelled, isEmpty);
    });

    test(
      'backgrounding arms the selected session; returning foregrounds cancels '
      'it and leaves the rest applied',
      () async {
        start([
          _session('s1', title: 'Viewed', running: true),
          _session('s2', title: 'Other', running: true),
        ]);
        await pumpEventQueue();
        expect(notifier.shown, hasLength(1)); // only s2 while foregrounded

        foreground = false;
        foregroundChanges.add(null);
        await pumpEventQueue();
        expect(notifier.shown, [
          _decision('s2', state: WorkingSessionState.working, title: 'Other'),
          _decision('s1', state: WorkingSessionState.working, title: 'Viewed'),
        ]);

        foreground = true;
        foregroundChanges.add(null);
        await pumpEventQueue();
        expect(notifier.cancelled, ['s1']);
        // s2 keeps its applied row: identical desired state posts nothing.
        expect(notifier.shown, hasLength(2));
      },
    );

    test('pending turns the row into waiting exactly once', () async {
      final repository2 = _SessionsRepository(const <SessionSummary>[]);
      ongoingCenter = AppNotificationCenter(
        repository: repository2,
        backendId: 'b1',
        isForegrounded: () => true,
        selectedSessionIdOf: () => 's1',
        onBackground: (_) {},
        notifier: notifier,
        selectionChanges: selectionChanges.stream,
        foregroundChanges: foregroundChanges.stream,
      );
      repository2.sessions.value = [
        _session('s2', title: 'Other', running: true),
      ];
      await pumpEventQueue();
      repository2.sessions.value = [
        _session(
          's2',
          title: 'Other',
          running: true,
          pending: SessionPendingInteraction.approval,
        ),
      ];
      await pumpEventQueue();
      repository2.sessions.value = [
        _session(
          's2',
          title: 'Other',
          running: true,
          pending: SessionPendingInteraction.approval,
        ),
      ];
      await pumpEventQueue();

      expect(notifier.shown, [
        _decision('s2', state: WorkingSessionState.working, title: 'Other'),
      ]);
      expect(notifier.updated, [
        _decision(
          's2',
          state: WorkingSessionState.waiting,
          title: 'Other',
          pending: SessionPendingInteraction.approval,
        ),
      ]);
    });

    test('working → done promotes once; re-snapshots do not re-post '
        '(swiped-away stays away)', () async {
      final repository2 = _SessionsRepository(const <SessionSummary>[]);
      ongoingCenter = AppNotificationCenter(
        repository: repository2,
        backendId: 'b1',
        isForegrounded: () => true,
        selectedSessionIdOf: () => 's1',
        onBackground: (_) {},
        notifier: notifier,
        selectionChanges: selectionChanges.stream,
        foregroundChanges: foregroundChanges.stream,
      );
      repository2.sessions.value = [
        _session('s2', title: 'Other', running: true),
      ];
      await pumpEventQueue();
      repository2.sessions.value = [
        _session('s2', title: 'Other', completed: true),
      ];
      await pumpEventQueue();
      repository2.sessions.value = [
        _session('s2', title: 'Other', completed: true),
      ];
      await pumpEventQueue();
      selectionChanges.add(null);
      await pumpEventQueue();

      expect(notifier.promoted, [
        _decision('s2', state: WorkingSessionState.done, title: 'Other'),
      ]);
      expect(notifier.shown, hasLength(1));
      expect(notifier.cancelled, isEmpty);
    });

    test(
      'reading the done session (openSession clears completed) cancels it',
      () async {
        final repository2 = _SessionsRepository(const <SessionSummary>[]);
        ongoingCenter = AppNotificationCenter(
          repository: repository2,
          backendId: 'b1',
          isForegrounded: () => true,
          selectedSessionIdOf: () => 's1',
          onBackground: (_) {},
          notifier: notifier,
          selectionChanges: selectionChanges.stream,
          foregroundChanges: foregroundChanges.stream,
        );
        repository2.sessions.value = [
          _session('s2', title: 'Other', completed: true),
        ];
        await pumpEventQueue();
        expect(notifier.promoted, hasLength(1));

        // The user selects s2: the selection signal fires, then openSession
        // re-publishes the snapshot with the completed bit consumed.
        selected = 's2';
        selectionChanges.add(null);
        await pumpEventQueue();
        repository2.sessions.value = [_session('s2', title: 'Other')];
        await pumpEventQueue();

        expect(notifier.cancelled, ['s2']);
        expect(notifier.promoted, hasLength(1));
      },
    );

    test('a running again after done re-arms the ongoing row', () async {
      final repository2 = _SessionsRepository(const <SessionSummary>[]);
      ongoingCenter = AppNotificationCenter(
        repository: repository2,
        backendId: 'b1',
        isForegrounded: () => true,
        selectedSessionIdOf: () => 's1',
        onBackground: (_) {},
        notifier: notifier,
        selectionChanges: selectionChanges.stream,
        foregroundChanges: foregroundChanges.stream,
      );
      repository2.sessions.value = [
        _session('s2', title: 'Other', completed: true),
      ];
      await pumpEventQueue();
      repository2.sessions.value = [
        _session('s2', title: 'Other', running: true),
      ];
      await pumpEventQueue();

      expect(notifier.promoted, hasLength(1));
      expect(notifier.shown, [
        _decision('s2', state: WorkingSessionState.working, title: 'Other'),
      ]);
      expect(notifier.updated, isEmpty);
    });

    test('a deleted or archived session cancels its row', () async {
      final repository2 = _SessionsRepository(const <SessionSummary>[]);
      ongoingCenter = AppNotificationCenter(
        repository: repository2,
        backendId: 'b1',
        isForegrounded: () => true,
        selectedSessionIdOf: () => 's1',
        onBackground: (_) {},
        notifier: notifier,
        selectionChanges: selectionChanges.stream,
        foregroundChanges: foregroundChanges.stream,
      );
      repository2.sessions.value = [
        _session('s2', title: 'Other', running: true),
      ];
      await pumpEventQueue();
      repository2.sessions.value = const <SessionSummary>[];
      await pumpEventQueue();

      expect(notifier.shown, hasLength(1));
      expect(notifier.cancelled, ['s2']);
    });

    test('a gone session that never had a row is not cancelled', () async {
      start([_session('s3', title: 'Idle')]);
      await pumpEventQueue();
      expect(notifier.cancelled, isEmpty);
      expect(notifier.shown, isEmpty);
    });

    test(
      'disposing the center cancels all currently applied ongoing rows',
      () async {
        start([
          _session('s2', title: 'Other', running: true),
          _session('s3', title: 'Done session', completed: true),
        ]);
        await pumpEventQueue();
        expect(notifier.shown, [
          _decision('s2', state: WorkingSessionState.working, title: 'Other'),
        ]);
        expect(notifier.promoted, [
          _decision(
            's3',
            state: WorkingSessionState.done,
            title: 'Done session',
          ),
        ]);
        expect(notifier.cancelled, isEmpty);

        ongoingCenter.dispose();
        await pumpEventQueue();

        expect(notifier.cancelled, containsAll(<String>['s2', 's3']));
      },
    );
  });
}
