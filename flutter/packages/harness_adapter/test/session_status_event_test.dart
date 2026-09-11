/// Finished-but-unviewed fold over the pinned contract: `api-session/status`
/// arrives as an ordinary forwarded Remote Event (`{type: 'emit', event,
/// args}`) on the `$events` stream the client opens over `/api/remote.mux`.
///
/// Wire truth (read from the reference submodule at `dsh-v0.1.5-rc.2`,
/// `fb2c4b9e698e30edb738bca4cf0618587db7d203`):
/// - payload shape `'api-session/status'(sessionId: SessionId, running:
///   boolean)` — packages/api/session-controller/src/types.ts:592;
/// - forwarded allowlist entry `{ event: 'api-session/status', mode: 'emit' }`
///   — packages/api/remotes/src/remote-events.ts:23;
/// - the emitted item `{ type: 'emit', event: 'api-session/status',
///   args: [sessionId, running] }` — packages/client/connection/tests/
///   fixture.client.spec.ts:1027.
///
/// The dead `host/session-status` host frame (removed from the host at
/// 0.1.2-alpha.1) is no longer decoded.
library;

import 'dart:async';

import 'package:domain/model/session.dart';
import 'package:harness_adapter/src/dsh_connection_manager.dart';
import 'package:harness_adapter/src/harness_repository_impl.dart';
import 'package:network/dsh_event_socket.dart';
import 'package:network/dsh_rpc_client.dart';
import 'package:network/rpc_envelope.dart';
import 'package:test/test.dart';

/// The `$events` registration answer the gateway sends over `/api/remote.mux`
/// (`reference/deepseek-harness/packages/api/gateway/src/stream-protocol.ts`
/// `RemoteEventReadyFrame`); it is the connection generation handshake.
ServerRequest _readyFrame() => ServerRequest(
  rpcId: 'remote-events',
  method: 'item',
  payload: <String, Object?>{
    'type': 'ready',
    'clientId': 'client-1',
    'host': <String, Object?>{'home': '/home/tester'},
  },
);

/// A downlink socket whose mux stream the test drives frame by frame.
class _MuxSocket implements DshEventSocket {
  final StreamController<ServerRequest> _mux =
      StreamController<ServerRequest>();

  @override
  Stream<ServerRequest> connect(String path, {void Function()? onOpen}) {
    onOpen?.call();
    _mux.add(_readyFrame());
    return _mux.stream;
  }

  /// One `$events` `emit` item carrying `api-session/status`.
  void emitStatus(String sessionId, bool running) {
    _mux.add(
      ServerRequest(
        rpcId: 'remote-events',
        method: 'item',
        payload: <String, Object?>{
          'type': 'emit',
          'event': 'api-session/status',
          'args': <Object?>[sessionId, running],
        },
      ),
    );
  }

  Future<void> close() => _mux.close();
}

class _FakeRpc implements DshRpcClient {
  _FakeRpc(this.sessionsValue);

  List<Object?> sessionsValue;

  @override
  Future<RpcResult> call(
    String endpoint,
    String method,
    JsonMap payload, {
    Duration? timeout,
  }) async {
    switch (endpoint) {
      case 'session/list':
        return RpcResult(
          ok: true,
          value: <String, Object?>{'items': sessionsValue},
        );
      case 'session/page':
      case 'session/history':
        return RpcResult(
          ok: true,
          value: <String, Object?>{'events': <Object?>[], 'hasMore': false},
        );
      default:
        return RpcResult(ok: true, value: <String, Object?>{});
    }
  }

  @override
  Future<void> respond(String rpcId, RpcResult result) async {}
}

JsonMap _sessionRow(String id, {required bool running}) => <String, Object?>{
  'sessionId': id,
  'updatedAt': 1,
  'running': running,
  'blank': false,
};

SessionSummary _byId(List<SessionSummary> sessions, String id) =>
    sessions.firstWhere((session) => session.id == id);

class _Fixture {
  _Fixture(this.repository, this.rpc, this.socket);

  final HarnessRepositoryImpl repository;
  final _FakeRpc rpc;
  final _MuxSocket socket;
}

Future<_Fixture> _fixture(List<Object?> sessions) async {
  final rpc = _FakeRpc(sessions);
  final socket = _MuxSocket();
  final repository = HarnessRepositoryImpl(
    rpc,
    DshConnectionManager(socket, (_) => 10000),
  );
  addTearDown(() async {
    await repository.dispose();
    await socket.close();
  });
  await pumpEventQueue();
  return _Fixture(repository, rpc, socket);
}

void main() {
  test('api-session/status true then false on a non-open session arms the '
      'completion dot, and running again clears it', () async {
    final fixture = await _fixture(<Object?>[
      _sessionRow('session-open', running: false),
      _sessionRow('session-bg', running: false),
    ]);
    await fixture.repository.openSession('session-open');
    await pumpEventQueue();

    fixture.socket.emitStatus('session-bg', true);
    await pumpEventQueue();
    fixture.socket.emitStatus('session-bg', false);
    await pumpEventQueue();

    var sessions = await fixture.repository.observeSessions().first;
    expect(_byId(sessions, 'session-bg').running, isFalse);
    expect(_byId(sessions, 'session-bg').completed, isTrue);
    // Finished while being viewed never arms.
    expect(_byId(sessions, 'session-open').completed, isFalse);

    // The open session finishing is not a reminder: nobody needs to be
    // told about the session already on screen.
    fixture.socket.emitStatus('session-open', true);
    await pumpEventQueue();
    fixture.socket.emitStatus('session-open', false);
    await pumpEventQueue();

    sessions = await fixture.repository.observeSessions().first;
    expect(_byId(sessions, 'session-open').completed, isFalse);

    // Running again clears the completion reminder.
    fixture.socket.emitStatus('session-bg', true);
    await pumpEventQueue();

    sessions = await fixture.repository.observeSessions().first;
    expect(_byId(sessions, 'session-bg').running, isTrue);
    expect(_byId(sessions, 'session-bg').completed, isFalse);
  });

  test(
    'the first api-session/status observation seeds without arming',
    () async {
      // The session is not in the list yet, so the frame is genuinely the first
      // observation: an idle first sight records the baseline and arms nothing.
      final fixture = await _fixture(const <Object?>[]);

      fixture.socket.emitStatus('session-bg', false);
      await pumpEventQueue();
      // A second idle observation with no running sight in between still does
      // not arm.
      fixture.socket.emitStatus('session-bg', false);
      await pumpEventQueue();

      fixture.rpc.sessionsValue = <Object?>[
        _sessionRow('session-bg', running: false),
      ];
      await fixture.repository.refreshSessions();
      await pumpEventQueue();

      var sessions = await fixture.repository.observeSessions().first;
      expect(_byId(sessions, 'session-bg').completed, isFalse);

      // The seeded baseline still drives the edge: running then idle arms.
      fixture.socket.emitStatus('session-bg', true);
      await pumpEventQueue();
      fixture.socket.emitStatus('session-bg', false);
      await pumpEventQueue();

      sessions = await fixture.repository.observeSessions().first;
      expect(_byId(sessions, 'session-bg').completed, isTrue);
    },
  );
}
