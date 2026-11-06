/// The notification center's provider wiring under the WebView shell: the
/// center builds from the repository and the watched-session seam alone — no
/// chat controller, destination, or widget tree — and folds each backend's
/// session snapshot stream. Nothing is pumped: these are `ProviderContainer`
/// tests; the test binding exists only for the lifecycle reads the center
/// already needs.
library;

import 'dart:async';

import 'package:app/di/providers.dart';
import 'package:app/notifications/app_notification_center.dart';
import 'package:app/notifications/notification_events.dart';
import 'package:app/platform/keep_alive_service.dart';
import 'package:domain/model/backend.dart';
import 'package:domain/model/session.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState, WidgetsBinding;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'sessions_repository_fake.dart';

final _backend = BackendConfig(
  id: 'b1',
  label: 'Alpha',
  baseUri: Uri.parse('http://alpha:3080'),
);

SessionSummary _session(String id, {bool running = false}) =>
    SessionSummary(id: id, title: id, running: running, blank: false);

/// No foreground service on a host without the channel; this is the seam
/// widget tests and desktop hosts override.
class _NoopKeepAliveService extends KeepAliveService {
  const _NoopKeepAliveService();

  @override
  Future<void> start(KeepAliveNotificationCopy copy) async {}

  @override
  Future<void> stop() async {}
}

/// Fails the test if the notification path reads a chat controller: a
/// throwing factory is only invoked on a read, so an unexpected dependency
/// surfaces as an error instead of a silently constructed controller.
Never _noChatController(Ref ref) =>
    throw StateError('the notification path must not build a chat controller');

/// Holds [backendIds]' centers with listeners — an autoDispose read alone
/// does not keep a Riverpod provider alive — and releases them with the test.
void _holdCenters(ProviderContainer container, List<String> backendIds) {
  for (final backendId in backendIds) {
    final subscription = container.listen<AppNotificationCenter>(
      appNotificationCenterProvider(backendId),
      (_, _) {},
    );
    addTearDown(subscription.close);
  }
}

/// Let Riverpod's batched scheduler settle: timer turns for stream delivery
/// plus microtask drains for the provider rebuilds each schedules. One bare
/// flush loses updates when a second stream event lands in the same batch.
Future<void> _settle() async {
  for (var i = 0; i < 3; i++) {
    await Future<void>.delayed(Duration.zero);
    await pumpEventQueue();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the center folds snapshots with no native controller built', () async {
    final repository = SessionsRepositoryFake(const <SessionSummary>[]);
    final container = ProviderContainer(
      overrides: [
        chatRepositoryProvider('b1').overrideWithValue(repository),
        chatControllerProvider('b1').overrideWith(_noChatController),
      ],
    );
    addTearDown(container.dispose);
    _holdCenters(container, ['b1']);

    final center = container.read(appNotificationCenterProvider('b1'));
    expect(center.hasWorkInFlight, isFalse);

    repository.sessions.value = [_session('s1', running: true)];
    await _settle();
    expect(
      center.hasWorkInFlight,
      isTrue,
      reason: 'the center subscribed to the repository snapshot stream',
    );

    repository.sessions.value = [_session('s1')];
    await _settle();
    expect(center.hasWorkInFlight, isFalse);
  });

  test('every enabled backend gets its own center over its own repo', () async {
    final repositoryA = SessionsRepositoryFake(const <SessionSummary>[]);
    final repositoryB = SessionsRepositoryFake(const <SessionSummary>[]);
    final container = ProviderContainer(
      overrides: [
        chatRepositoryProvider('b1').overrideWithValue(repositoryA),
        chatRepositoryProvider('b2').overrideWithValue(repositoryB),
        chatControllerProvider('b1').overrideWith(_noChatController),
        chatControllerProvider('b2').overrideWith(_noChatController),
      ],
    );
    addTearDown(container.dispose);
    _holdCenters(container, ['b1', 'b2']);

    final centerA = container.read(appNotificationCenterProvider('b1'));
    final centerB = container.read(appNotificationCenterProvider('b2'));

    repositoryA.sessions.value = [_session('s1', running: true)];
    await _settle();
    expect(centerA.hasWorkInFlight, isTrue);
    expect(centerB.hasWorkInFlight, isFalse);

    repositoryB.sessions.value = [_session('s2', running: true)];
    await _settle();
    expect(centerB.hasWorkInFlight, isTrue);
    expect(
      centerA.hasWorkInFlight,
      isTrue,
      reason: 'B starting does not disturb A’s applied work',
    );
  });

  test(
    'the keep-alive facts build with no AppRoot and no chat controller',
    () async {
      final repository = SessionsRepositoryFake(const <SessionSummary>[]);
      final container = ProviderContainer(
        overrides: [
          backendRegistryStateProvider.overrideWith(
            (ref) => Stream<BackendRegistryState>.value(
              BackendRegistryState(backends: [_backend]),
            ),
          ),
          keepAliveServiceProvider.overrideWithValue(
            const _NoopKeepAliveService(),
          ),
          chatRepositoryProvider('b1').overrideWithValue(repository),
          chatControllerProvider('b1').overrideWith(_noChatController),
        ],
      );
      addTearDown(container.dispose);

      // The shell watches this stream; holding it keeps the coordinator (and
      // through it, the enabled backend's center) alive with no widget tree.
      final changes = container.listen(workInFlightChangesProvider, (_, _) {});
      addTearDown(changes.close);
      await _settle();

      final coordinator = container.read(keepAliveCoordinatorProvider);
      expect(coordinator.hasWorkInFlight, isFalse);
      expect(coordinator.isRunning, isFalse);
    },
  );

  group('watched-session seam', () {
    setUp(() {
      // The center's foreground route is a binding read, not a widget: pin
      // the lifecycle so foreground events run the toast channel.
      WidgetsBinding.instance.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      );
    });

    test(
      'the shell default watches nothing, so every completion toasts',
      () async {
        final repository = SessionsRepositoryFake(const <SessionSummary>[]);
        final container = ProviderContainer(
          overrides: [
            chatRepositoryProvider('b1').overrideWithValue(repository),
            chatControllerProvider('b1').overrideWith(_noChatController),
          ],
        );
        addTearDown(container.dispose);
        _holdCenters(container, ['b1']);

        final events = <AppNotificationEvent>[];
        container
            .read(appNotificationCenterProvider('b1'))
            .foregroundEvents
            .listen(events.add);

        repository.sessions.value = [_session('s1', running: true)];
        await _settle();
        repository.sessions.value = [_session('s1')];
        await _settle();

        expect(events.map((event) => event.sessionId), ['s1']);
        expect(events.single.kind, AppNotificationKind.otherTurnComplete);
      },
    );

    test('an override supplies the fact the center classifies with', () async {
      final repository = SessionsRepositoryFake(const <SessionSummary>[]);
      final container = ProviderContainer(
        overrides: [
          chatRepositoryProvider('b1').overrideWithValue(repository),
          chatControllerProvider('b1').overrideWith(_noChatController),
          watchedSessionIdProvider('b1').overrideWith((ref) => 's1'),
        ],
      );
      addTearDown(container.dispose);
      _holdCenters(container, ['b1']);

      final events = <AppNotificationEvent>[];
      container
          .read(appNotificationCenterProvider('b1'))
          .foregroundEvents
          .listen(events.add);

      repository.sessions.value = [_session('s1', running: true)];
      await _settle();
      repository.sessions.value = [_session('s1')];
      await _settle();

      expect(
        events,
        isEmpty,
        reason: 'the watched session’s own turn completion stays silent',
      );
    });
  });
}
