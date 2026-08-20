/// AppNotificationCenter wiring tests: the center folds the session stream
/// and routes events to the foreground (toast) stream or the background
/// callback per the app's foreground state. The repository double only
/// implements `observeSessions`; every other member falls through to
/// `noSuchMethod` (this test never touches them).
library;

import 'package:app/notifications/app_notification_center.dart';
import 'package:app/notifications/notification_events.dart';
import 'package:app/ui/state_stream.dart';
import 'package:domain/model/session.dart';
import 'package:domain/repository/chat_repository.dart';
import 'package:flutter_test/flutter_test.dart';

SessionSummary _session(
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
    );
  });

  tearDown(() => center.dispose());

  test('other-session turn completion flows to the foreground toast stream',
      () async {
    repository.sessions.value = [_session('s2', title: 'Other', running: true)];
    await pumpEventQueue();
    final events = <AppNotificationEvent>[];
    center.foregroundEvents.listen(events.add);

    repository.sessions.value = [_session('s2', title: 'Other', running: false)];
    await pumpEventQueue();

    expect(events, hasLength(1));
    expect(events.single.kind, AppNotificationKind.otherTurnComplete);
    expect(events.single.sessionTitle, 'Other');
    expect(background, isEmpty);
  });

  test('selected-session turn completion is silent while foregrounded',
      () async {
    final events = <AppNotificationEvent>[];
    center.foregroundEvents.listen(events.add);

    repository.sessions.value = [_session('s1', title: 'Selected', running: true)];
    await pumpEventQueue();
    repository.sessions.value = [_session('s1', title: 'Selected', running: false)];
    await pumpEventQueue();

    expect(events, isEmpty);
    expect(background, isEmpty);
  });

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
    );
    repository.sessions.value = [
      _session('s3', title: 'Review', pending: SessionPendingInteraction.planReview),
    ];
    await pumpEventQueue();

    expect(background, hasLength(1));
    expect(background.single.kind, AppNotificationKind.planReviewRequested);

    center2.dispose();
  });

  test('backgrounded selected-session turn completion posts a system notification',
      () async {
    final center2 = AppNotificationCenter(
      repository: repository,
      backendId: 'b1',
      isForegrounded: () => false,
      selectedSessionIdOf: () => 's1',
      onBackground: background.add,
    );
    repository.sessions.value = [_session('s1', title: 'Selected', running: true)];
    await pumpEventQueue();
    repository.sessions.value = [_session('s1', title: 'Selected', running: false)];
    await pumpEventQueue();

    expect(background, hasLength(1));
    expect(background.single.kind, AppNotificationKind.selectedTurnComplete);

    center2.dispose();
  });

  test('a new subscriber does not replay old events (broadcast semantics)',
      () async {
    final first = <AppNotificationEvent>[];
    center.foregroundEvents.listen(first.add);
    repository.sessions.value = [_session('s2', title: 'Other', running: true)];
    await pumpEventQueue();
    repository.sessions.value = [_session('s2', title: 'Other', running: false)];
    await pumpEventQueue();
    expect(first, hasLength(1));

    // A second listener attached after the event sees nothing new.
    final second = <AppNotificationEvent>[];
    center.foregroundEvents.listen(second.add);
    await pumpEventQueue();
    expect(second, isEmpty);
  });
}
