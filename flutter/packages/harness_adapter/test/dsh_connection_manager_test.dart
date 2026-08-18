import 'dart:async';

import 'package:domain/model/connection_state.dart';
import 'package:fake_async/fake_async.dart';
import 'package:network/dsh_event_socket.dart';
import 'package:network/dsh_rpc_client.dart';
import 'package:network/rpc_envelope.dart';
import 'package:test/test.dart';

import 'package:harness_adapter/src/dsh_connection_manager.dart';

class ClosableTestSocket implements DshEventSocket {
  ClosableTestSocket({this.autoOpen = true});

  final bool autoOpen;
  final List<String> paths = <String>[];
  final List<Completer<void>> _closures = <Completer<void>>[];

  int get connectCount => paths.length;

  @override
  Stream<ServerRequest> connect(String path, {void Function()? onOpen}) async* {
    paths.add(path);
    if (autoOpen) onOpen?.call();
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

class FakeDshRpcClient implements DshRpcClient {
  FakeDshRpcClient({required this.failFirstCall});

  final bool failFirstCall;
  int callCount = 0;

  @override
  Future<RpcResult> call(String endpoint, String method, JsonMap payload) async {
    callCount += 1;
    if (failFirstCall && callCount == 1) {
      return RpcResult(
        ok: false,
        error: RpcError(code: 'test-failure', message: 'first attempt fails'),
      );
    }
    return RpcResult(
      ok: true,
      value: <String, Object?>{
        'version': '0.0.0-test',
        'cwd': '/tmp/dsh',
        'attachedSessions': 2,
      },
    );
  }

  @override
  Future<void> respond(String rpcId, RpcResult result) async {}
}

void main() {
  test('connected only after host describe and both streams open', () {
    fakeAsync((async) {
      final socket = ClosableTestSocket();
      final rpc = FakeDshRpcClient(failFirstCall: false);
      final manager = DshConnectionManager(
        rpc,
        socket,
        (_) => 1000,
      );

      manager.start();
      expect(manager.state.value.phase, ConnectionPhase.disconnected);
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 5));

      final state = manager.state.value;
      expect(state.phase, ConnectionPhase.connected);
      expect(state.generation, 1);
      expect(state.hostDescription?.version, '0.0.0-test');
      expect(state.hostDescription?.cwd, '/tmp/dsh');
      expect(rpc.callCount, 1);
      expect(socket.paths, <String>['/api/events.mux', '/api/events.host']);
      manager.stop();
    });
  });

  test('backoff attempt resets after a generation reached connected', () {
    fakeAsync((async) {
      final socket = ClosableTestSocket();
      final rpc = FakeDshRpcClient(failFirstCall: true);
      final backoffAttempts = <int>[];
      final manager = DshConnectionManager(
        rpc,
        socket,
        (attempt) {
          backoffAttempts.add(attempt);
          return backoffAttempts.length == 1 ? 0 : 5000;
        },
      );

      manager.start();
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 1));

      // First describe failed, retry delay 0, second describe succeeded and
      // both streams are still open.
      expect(manager.state.value.phase, ConnectionPhase.connected);
      expect(rpc.callCount, 2);
      expect(socket.connectCount, greaterThanOrEqualTo(2));

      // Lose the healthy generation and process only tasks due now. The 5s
      // delay must not elapse yet, so this isolates the attempt-number reset.
      socket.closeAllStreams();
      async.flushMicrotasks();

      expect(manager.state.value.phase, ConnectionPhase.reconnecting);
      expect(rpc.callCount, 2);
      expect(backoffAttempts, <int>[0, 0]);
      manager.stop();
    });
  });

  test('missing socket open keeps generation from publishing connected', () {
    fakeAsync((async) {
      final socket = ClosableTestSocket(autoOpen: false);
      final rpc = FakeDshRpcClient(failFirstCall: false);
      final manager = DshConnectionManager(
        rpc,
        socket,
        (_) => 5000,
      );
      manager.start();
      async.flushMicrotasks();
      async.elapse(const Duration(milliseconds: 3001));
      async.flushMicrotasks();

      // The exact transient phase depends on when the timed-out generation
      // is swept; the invariant is that CONNECTED is never published.
      expect(rpc.callCount, greaterThanOrEqualTo(1));
      expect(manager.hostDescription.value, isNull);
      expect(manager.state.value.phase, isNot(ConnectionPhase.connected));
      manager.stop();
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
        expect(value, inInclusiveRange(40, 80),
            reason: 'expected capped delay, got $value');
      }
    }
  });
}
