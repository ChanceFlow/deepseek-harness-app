import 'dart:async';

import 'package:domain/model/connection_state.dart';
import 'package:fake_async/fake_async.dart';
import 'package:network/dsh_event_socket.dart';
import 'package:network/rpc_envelope.dart';
import 'package:test/test.dart';

import 'package:harness_adapter/src/adapter_diagnostics.dart';
import 'package:harness_adapter/src/dsh_connection_manager.dart';

/// The `$events` registration answer the gateway sends over `/api/remote.mux`
/// (`reference/deepseek-harness/packages/api/gateway/src/stream-protocol.ts`
/// `RemoteEventReadyFrame` -> `RemoteEventHostInfo`).
ServerRequest readyFrame({String home = '/home/tester'}) => ServerRequest(
  rpcId: 'remote-events',
  method: 'item',
  payload: <String, Object?>{
    'type': 'ready',
    'clientId': 'client-1',
    'host': <String, Object?>{'home': home},
  },
);

/// A socket that opens the path, delivers the generation's frames, then stays
/// open until the generation is cancelled.
class ScriptedSocket implements DshEventSocket {
  ScriptedSocket({this.frames = const <ServerRequest>[], this.autoOpen = true});

  final List<ServerRequest> frames;
  final bool autoOpen;
  final List<String> paths = <String>[];
  final List<Completer<void>> _closures = <Completer<void>>[];

  int get connectCount => paths.length;

  @override
  Stream<ServerRequest> connect(String path, {void Function()? onOpen}) async* {
    paths.add(path);
    if (autoOpen) {
      onOpen?.call();
      for (final frame in frames) {
        yield frame;
      }
    }
    final closed = Completer<void>();
    _closures.add(closed);
    await closed.future;
  }

  void closeAllStreams() {
    for (final closure in List<Completer<void>>.of(_closures)) {
      if (!closure.isCompleted) closure.complete();
    }
  }
}

/// A socket whose nth connection delivers the nth frame list, so a test can
/// make one generation fail and the next succeed.
class SequencedSocket implements DshEventSocket {
  SequencedSocket(this.framesByGeneration);

  final List<List<ServerRequest>> framesByGeneration;
  final List<String> paths = <String>[];
  final List<Completer<void>> _closures = <Completer<void>>[];
  int _generation = 0;

  int get connectCount => paths.length;

  @override
  Stream<ServerRequest> connect(String path, {void Function()? onOpen}) async* {
    paths.add(path);
    onOpen?.call();
    final index = _generation < framesByGeneration.length
        ? _generation
        : framesByGeneration.length - 1;
    _generation += 1;
    for (final frame in framesByGeneration[index]) {
      yield frame;
    }
    final closed = Completer<void>();
    _closures.add(closed);
    await closed.future;
  }

  void closeAllStreams() {
    for (final closure in List<Completer<void>>.of(_closures)) {
      if (!closure.isCompleted) closure.complete();
    }
  }
}

class StreamErrorSocket implements DshEventSocket {
  StreamErrorSocket({required this.errorPath, required this.error});

  final String errorPath;
  final Object error;
  final List<String> paths = <String>[];

  @override
  Stream<ServerRequest> connect(String path, {void Function()? onOpen}) {
    paths.add(path);
    final controller = StreamController<ServerRequest>();
    if (path == errorPath) {
      scheduleMicrotask(() {
        if (!controller.isClosed) {
          controller.addError(error);
        }
      });
    } else {
      scheduleMicrotask(() {
        onOpen?.call();
      });
    }
    return controller.stream;
  }
}

class ThrowingWritableSocket implements DshWritableEventSocket {
  @override
  Stream<ServerRequest> connect(String path, {void Function()? onOpen}) {
    return const Stream<ServerRequest>.empty();
  }

  @override
  void send(String path, String message) {
    throw StateError('simulated socket send failure');
  }
}

void main() {
  test('connected after the mux open and the ready frame', () {
    fakeAsync((async) {
      final socket = ScriptedSocket(frames: <ServerRequest>[readyFrame()]);
      final manager = DshConnectionManager(socket, (_) => 1000);

      manager.start();
      expect(manager.state.value.phase, ConnectionPhase.disconnected);
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 5));

      final state = manager.state.value;
      expect(state.phase, ConnectionPhase.connected);
      expect(state.generation, 1);
      // The ready frame's host facts are the only host-level facts the pinned
      // contract publishes; nothing is fabricated beside them.
      expect(state.hostDescription?.home, '/home/tester');
      expect(state.hostDescription?.version, isNull);
      expect(socket.paths, <String>['/api/remote.mux']);
      manager.stop();
    });
  });

  test('a ready frame without host.home fails the generation loudly', () {
    fakeAsync((async) {
      final diagnostics = <AdapterDiagnostic>[];
      final socket = ScriptedSocket(
        frames: <ServerRequest>[
          ServerRequest(
            rpcId: 'remote-events',
            method: 'item',
            payload: <String, Object?>{
              'type': 'ready',
              'clientId': 'client-1',
              'host': <String, Object?>{},
            },
          ),
        ],
      );
      final manager = DshConnectionManager(
        socket,
        (_) => 5000,
        onDiagnostic: diagnostics.add,
      );

      manager.start();
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 1));

      expect(manager.state.value.phase, isNot(ConnectionPhase.connected));
      expect(manager.hostDescription.value, isNull);
      final failure = diagnostics.firstWhere(
        (d) => d.message.startsWith('Generation handshake failed:'),
      );
      expect(failure.message, contains('home'));
      manager.stop();
    });
  });

  test('a ready frame with no host object fails the generation loudly', () {
    fakeAsync((async) {
      final diagnostics = <AdapterDiagnostic>[];
      final socket = ScriptedSocket(
        frames: <ServerRequest>[
          ServerRequest(
            rpcId: 'remote-events',
            method: 'item',
            payload: <String, Object?>{'type': 'ready', 'clientId': 'client-1'},
          ),
        ],
      );
      final manager = DshConnectionManager(
        socket,
        (_) => 5000,
        onDiagnostic: diagnostics.add,
      );

      manager.start();
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 1));

      expect(manager.state.value.phase, isNot(ConnectionPhase.connected));
      final failure = diagnostics.firstWhere(
        (d) => d.message.startsWith('Generation handshake failed:'),
      );
      expect(failure.message, contains('host'));
      manager.stop();
    });
  });

  test('a mux failure never dials a removed fallback path', () {
    fakeAsync((async) {
      final socket = StreamErrorSocket(
        errorPath: '/api/remote.mux',
        error: Exception('HTTP 404 Not Found'),
      );
      final manager = DshConnectionManager(socket, (_) => 5000);

      manager.start();
      async.flushMicrotasks();
      async.elapse(const Duration(milliseconds: 3100));

      expect(socket.paths, isNot(contains('/api/events.mux')));
      expect(socket.paths, isNot(contains('/api/events.host')));
      expect(
        socket.paths.where((p) => p == '/api/remote.mux'),
        hasLength(1),
        reason: 'a failed generation must not redial mux as a fallback',
      );
      expect(manager.state.value.phase, isNot(ConnectionPhase.connected));

      manager.stop();
    });
  });

  test('backoff attempt resets after a generation reached connected', () {
    fakeAsync((async) {
      // First generation opens the socket but its stream closes before the
      // ready frame; the retry publishes connected. The 5s loss delay is
      // still pending when the reset is asserted.
      final backoffAttempts = <int>[];
      final socket = SequencedSocket(<List<ServerRequest>>[
        const <ServerRequest>[],
        <ServerRequest>[readyFrame()],
      ]);
      final manager = DshConnectionManager(socket, (attempt) {
        backoffAttempts.add(attempt);
        return backoffAttempts.length == 1 ? 0 : 5000;
      });

      manager.start();
      async.flushMicrotasks();
      socket.closeAllStreams();
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 1));

      expect(manager.state.value.phase, ConnectionPhase.connected);
      expect(socket.connectCount, 2);

      // Lose the healthy generation and process only tasks due now. The 5s
      // delay must not elapse yet, so this isolates the attempt-number reset.
      socket.closeAllStreams();
      async.flushMicrotasks();

      expect(manager.state.value.phase, ConnectionPhase.reconnecting);
      expect(backoffAttempts, <int>[0, 0]);
      manager.stop();
    });
  });

  test('missing socket open keeps generation from publishing connected', () {
    fakeAsync((async) {
      final socket = ScriptedSocket(autoOpen: false);
      final manager = DshConnectionManager(socket, (_) => 5000);
      manager.start();
      async.flushMicrotasks();
      async.elapse(const Duration(milliseconds: 3001));
      async.flushMicrotasks();

      // The exact transient phase depends on when the timed-out generation
      // is swept; the invariant is that CONNECTED is never published.
      expect(socket.connectCount, greaterThanOrEqualTo(1));
      expect(manager.hostDescription.value, isNull);
      expect(manager.state.value.phase, isNot(ConnectionPhase.connected));
      manager.stop();
    });
  });

  test(
    'reconnectNow skips a pending backoff and restarts the sequence at 0',
    () {
      fakeAsync((async) {
        final attempts = <int>[];
        final socket = ScriptedSocket();
        final manager = DshConnectionManager(socket, (attempt) {
          attempts.add(attempt);
          return 1000;
        });

        manager.start();
        async.flushMicrotasks();
        // Two consecutive losses raise the sequence to attempt 1, leaving a 1s
        // backoff wait pending.
        socket.closeAllStreams();
        async.flushMicrotasks();
        expect(attempts, <int>[0]);
        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();
        socket.closeAllStreams();
        async.flushMicrotasks();
        expect(attempts, <int>[0, 1]);
        expect(manager.state.value.phase, ConnectionPhase.reconnecting);
        expect(socket.connectCount, 2);

        // No time passes: the request itself starts the next generation.
        manager.reconnectNow();
        async.flushMicrotasks();

        expect(
          socket.connectCount,
          3,
          reason: 'the generation dials on the interrupt, not after 1s',
        );

        // The next loss backs off from the base again, not from attempt 2.
        socket.closeAllStreams();
        async.flushMicrotasks();
        expect(attempts, <int>[0, 1, 0]);
        manager.stop();
      });
    },
  );

  test('reconnectNow tears a live generation down and reconnects at once', () {
    fakeAsync((async) {
      final diagnostics = <AdapterDiagnostic>[];
      final attempts = <int>[];
      final socket = SequencedSocket(<List<ServerRequest>>[
        <ServerRequest>[readyFrame(home: '/first')],
        <ServerRequest>[readyFrame(home: '/second')],
      ]);
      final manager = DshConnectionManager(socket, (attempt) {
        attempts.add(attempt);
        return 5000;
      }, onDiagnostic: diagnostics.add);

      manager.start();
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 1));
      expect(manager.state.value.phase, ConnectionPhase.connected);
      expect(manager.state.value.hostDescription?.home, '/first');
      expect(socket.connectCount, 1);

      manager.reconnectNow();
      async.flushMicrotasks();

      expect(
        socket.connectCount,
        2,
        reason: 'the live generation was torn down',
      );
      expect(manager.state.value.phase, ConnectionPhase.connected);
      expect(manager.state.value.generation, 2);
      expect(manager.state.value.hostDescription?.home, '/second');
      expect(
        attempts,
        isEmpty,
        reason:
            'a reconnect request skips the retry policy, it does not delay it',
      );
      final request = diagnostics.firstWhere(
        (d) => d.message.startsWith('Immediate reconnect requested'),
      );
      expect(request.level, AdapterDiagnosticLevel.debug);
      expect(request.context, 'connection_manager');
      expect(request.message, contains('tearing down the live generation'));
      manager.stop();
    });
  });

  test('reconnectNow before start leaves the first generation untouched', () {
    fakeAsync((async) {
      final socket = ScriptedSocket(frames: <ServerRequest>[readyFrame()]);
      final manager = DshConnectionManager(socket, (_) => 1000);

      manager.reconnectNow();
      async.elapse(const Duration(seconds: 1));
      expect(socket.connectCount, 0);

      manager.start();
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 1));

      expect(socket.connectCount, 1);
      expect(manager.state.value.phase, ConnectionPhase.connected);
      expect(manager.state.value.generation, 1);
      manager.stop();
    });
  });

  test('reconnectNow is a no-op after stop', () {
    fakeAsync((async) {
      final attempts = <int>[];
      final socket = ScriptedSocket(frames: <ServerRequest>[readyFrame()]);
      final manager = DshConnectionManager(socket, (attempt) {
        attempts.add(attempt);
        return 1000;
      });

      manager.start();
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 1));
      expect(socket.connectCount, 1);

      manager.stop();
      manager.reconnectNow();
      async.elapse(const Duration(seconds: 30));

      expect(socket.connectCount, 1, reason: 'a stopped manager dials nothing');
      expect(attempts, isEmpty);
    });
  });

  test('exponential backoff reaches its configured cap', () {
    for (final injectedRandom in <int Function(int)>[
      (_) => 0,
      (max) => max - 1,
      (max) => max ~/ 2,
    ]) {
      int delay(int attempt) => exponentialDshBackoffDelay(
        attempt,
        baseMillis: 10,
        maxMillis: 80,
        random: injectedRandom,
      );
      for (var i = 0; i < 20; i++) {
        final value = delay(10000);
        expect(
          value,
          inInclusiveRange(40, 80),
          reason: 'expected capped delay, got $value',
        );
      }
    }
  });

  test('sendMuxMessage error emits diagnostic', () {
    final diagnostics = <AdapterDiagnostic>[];
    final socket = ThrowingWritableSocket();
    final manager = DshConnectionManager(
      socket,
      (_) => 1000,
      onDiagnostic: diagnostics.add,
    );

    manager.sendMuxMessage('{"action":"ping"}');

    expect(diagnostics, hasLength(1));
    final diagnostic = diagnostics.single;
    expect(diagnostic.level, AdapterDiagnosticLevel.warning);
    expect(diagnostic.context, 'connection_manager:sendMuxMessage');
    expect(
      diagnostic.message,
      'Failed to send mux message: Bad state: simulated socket send failure',
    );
    expect(diagnostic.error, isA<StateError>());
    expect(diagnostic.stackTrace, isNotNull);
  });

  test('stream error emits diagnostic', () {
    fakeAsync((async) {
      final diagnostics = <AdapterDiagnostic>[];
      final errorMux = Exception('mux network failure');
      final socket = StreamErrorSocket(
        errorPath: '/api/remote.mux',
        error: errorMux,
      );
      final manager = DshConnectionManager(
        socket,
        (_) => 5000,
        onDiagnostic: diagnostics.add,
      );

      manager.start();
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 1));

      final streamDiagnostics = diagnostics
          .where(
            (d) =>
                d.context == 'connection_manager:stream:/api/remote.mux' &&
                d.message.startsWith('Downlink stream error on'),
          )
          .toList();
      expect(streamDiagnostics, hasLength(1));
      final diag = streamDiagnostics.single;
      expect(diag.level, AdapterDiagnosticLevel.warning);
      expect(
        diag.message,
        'Downlink stream error on /api/remote.mux: Exception: mux network failure',
      );
      expect(diag.error, errorMux);

      manager.stop();
    });
  });

  test('stream onDone emits diagnostic', () {
    fakeAsync((async) {
      final diagnostics = <AdapterDiagnostic>[];
      final socket = ScriptedSocket(frames: <ServerRequest>[readyFrame()]);
      final manager = DshConnectionManager(
        socket,
        (_) => 5000,
        onDiagnostic: diagnostics.add,
      );

      manager.start();
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 1));

      socket.closeAllStreams();
      async.flushMicrotasks();

      final doneDiagnostics = diagnostics
          .where((d) => d.message.contains('Downlink stream closed on'))
          .toList();
      expect(doneDiagnostics, isNotEmpty);
      for (final diag in doneDiagnostics) {
        expect(diag.level, AdapterDiagnosticLevel.debug);
        expect(diag.context, startsWith('connection_manager:stream:'));
      }

      manager.stop();
    });
  });

  test('reconnection backoff in connectLoop emits diagnostic', () {
    fakeAsync((async) {
      final diagnostics = <AdapterDiagnostic>[];
      final socket = ScriptedSocket(frames: <ServerRequest>[readyFrame()]);
      final manager = DshConnectionManager(
        socket,
        (attempt) => attempt == 0 ? 300 : 1000,
        onDiagnostic: diagnostics.add,
      );

      manager.start();
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 1));

      socket.closeAllStreams();
      async.flushMicrotasks();

      final retryDiagnostics = diagnostics
          .where(
            (d) =>
                d.context == 'connection_manager' &&
                d.message.startsWith('Generation lost, reconnecting'),
          )
          .toList();
      expect(retryDiagnostics, hasLength(1));
      final diag = retryDiagnostics.first;
      expect(diag.level, AdapterDiagnosticLevel.warning);
      expect(
        diag.message,
        'Generation lost, reconnecting (attempt: 0, delay: 300ms)',
      );

      manager.stop();
    });
  });
}
