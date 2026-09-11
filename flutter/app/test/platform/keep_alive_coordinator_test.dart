/// Keep-alive coordinator tests: the service is started once for sustained
/// work, held across the linger window, stopped when the last session
/// settles, and never retried in a spin when the host refuses or lacks the
/// channel. Timing is asserted with `fake_async`, so the linger is exact.
library;

import 'dart:async';

import 'package:app/platform/keep_alive_coordinator.dart';
import 'package:app/platform/keep_alive_service.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const KeepAliveNotificationCopy _copy = KeepAliveNotificationCopy(
  title: 'Keeping your session connected',
  text: 'Agent work continues in the background.',
  channelName: 'Background connection',
  channelDescription: 'Keeps the connection open.',
);

/// Seam double: records what the coordinator asked for and can fail either
/// call, so both the accepted and the refused paths are observable.
final class _RecordingService implements KeepAliveService {
  final List<KeepAliveNotificationCopy> started = <KeepAliveNotificationCopy>[];
  int stops = 0;
  Object? startFailure;
  Object? stopFailure;

  @override
  Future<void> start(KeepAliveNotificationCopy copy) async {
    final Object? failure = startFailure;
    if (failure != null) throw failure;
    started.add(copy);
  }

  @override
  Future<void> stop() async {
    stops += 1;
    final Object? failure = stopFailure;
    if (failure != null) throw failure;
  }
}

void main() {
  test('starts once for sustained work and never re-starts', () {
    fakeAsync((FakeAsync async) {
      final service = _RecordingService();
      final coordinator = KeepAliveCoordinator(
        service: service,
        copy: () => _copy,
      );

      coordinator.update(workInFlight: true);
      async.flushMicrotasks();
      expect(service.started, equals(<KeepAliveNotificationCopy>[_copy]));
      expect(coordinator.isRunning, isTrue);

      coordinator.update(workInFlight: true);
      async.flushMicrotasks();
      expect(service.started, hasLength(1));
      expect(service.stops, 0);
    });
  });

  test('holds the service through the linger, then stops it', () {
    fakeAsync((FakeAsync async) {
      final service = _RecordingService();
      final coordinator = KeepAliveCoordinator(
        service: service,
        copy: () => _copy,
      );

      coordinator.update(workInFlight: true);
      async.flushMicrotasks();
      coordinator.update(workInFlight: false);
      async.elapse(kKeepAliveLinger - const Duration(seconds: 1));

      expect(coordinator.isRunning, isTrue);
      expect(service.stops, 0);

      async.elapse(const Duration(seconds: 2));
      expect(coordinator.isRunning, isFalse);
      expect(service.stops, 1);
    });
  });

  test('a turn starting inside the linger keeps the same service', () {
    fakeAsync((FakeAsync async) {
      final service = _RecordingService();
      final coordinator = KeepAliveCoordinator(
        service: service,
        copy: () => _copy,
      );

      coordinator.update(workInFlight: true);
      async.flushMicrotasks();
      coordinator.update(workInFlight: false);
      async.elapse(const Duration(seconds: 10));
      coordinator.update(workInFlight: true);
      async.elapse(const Duration(minutes: 5));

      expect(service.started, hasLength(1));
      expect(service.stops, 0);
      expect(coordinator.isRunning, isTrue);
    });
  });

  test('a settle with nothing running never calls the host', () {
    fakeAsync((FakeAsync async) {
      final service = _RecordingService();
      final coordinator = KeepAliveCoordinator(
        service: service,
        copy: () => _copy,
      );

      coordinator.update(workInFlight: false);
      async.elapse(const Duration(minutes: 5));

      expect(service.started, isEmpty);
      expect(service.stops, 0);
    });
  });

  test('a refused start is reported and retried on the next fact', () {
    fakeAsync((FakeAsync async) {
      final failures = <Object>[];
      final service = _RecordingService()
        ..startFailure = PlatformException(code: 'start_refused');
      final coordinator = KeepAliveCoordinator(
        service: service,
        copy: () => _copy,
        onFailure: (Object error, StackTrace stackTrace) => failures.add(error),
      );

      coordinator.update(workInFlight: true);
      async.flushMicrotasks();
      expect(failures, hasLength(1));
      expect(coordinator.isRunning, isFalse);

      service.startFailure = null;
      coordinator.update(workInFlight: true);
      async.flushMicrotasks();
      expect(service.started, hasLength(1));
      expect(coordinator.isRunning, isTrue);
    });
  });

  test('a host without the channel is inert and silent', () {
    fakeAsync((FakeAsync async) {
      final failures = <Object>[];
      final service = _RecordingService()
        ..startFailure = MissingPluginException('no host');
      final coordinator = KeepAliveCoordinator(
        service: service,
        copy: () => _copy,
        onFailure: (Object error, StackTrace stackTrace) => failures.add(error),
      );

      coordinator.update(workInFlight: true);
      async.flushMicrotasks();
      coordinator.update(workInFlight: true);
      async.flushMicrotasks();

      expect(failures, isEmpty);
      expect(coordinator.isRunning, isFalse);
    });
  });

  test('a failed stop is reported and still settles', () {
    fakeAsync((FakeAsync async) {
      final failures = <Object>[];
      final service = _RecordingService()..stopFailure = StateError('gone');
      final coordinator = KeepAliveCoordinator(
        service: service,
        copy: () => _copy,
        onFailure: (Object error, StackTrace stackTrace) => failures.add(error),
      );

      coordinator.update(workInFlight: true);
      async.flushMicrotasks();
      coordinator.update(workInFlight: false);
      async.elapse(kKeepAliveLinger);

      expect(failures, hasLength(1));
      expect(coordinator.isRunning, isFalse);
    });
  });

  test('dispose stops a running service and is idempotent', () {
    fakeAsync((FakeAsync async) {
      final service = _RecordingService();
      final coordinator = KeepAliveCoordinator(
        service: service,
        copy: () => _copy,
      );

      coordinator.update(workInFlight: true);
      async.flushMicrotasks();
      unawaited(coordinator.dispose());
      async.flushMicrotasks();
      unawaited(coordinator.dispose());
      async.flushMicrotasks();

      expect(service.stops, 1);
      expect(coordinator.isRunning, isFalse);
    });
  });
}
