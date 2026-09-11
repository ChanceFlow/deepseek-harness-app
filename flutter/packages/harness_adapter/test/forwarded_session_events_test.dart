/// Forwarded Remote Events over the `$events` stream: the 0.1.5 delivery
/// path that replaced the retired `host/*` host-frame vocabulary.
///
/// Wire truth read from the reference submodule at `dsh-v0.1.5-rc.2`
/// (`fb2c4b9e698e30edb738bca4cf0618587db7d203`):
/// - allowlist entries, including `{ event: 'api-session/added', mode: 'emit' }`
///   — `packages/api/remotes/src/remote-events.ts:20`;
/// - the emitted item `{ type: 'emit', event, args }` —
///   `packages/api/gateway/src/stream-protocol.ts` `RemoteEventEmitFrame`;
/// - payload `'api-session/added'(summary: SessionSummary)` and the
///   `SessionSummary` fields (`sessionId`, `updatedAt`, `running`, `blank`,
///   optional `parentSessionId` / `origin` / `cwd` / `projections`) —
///   `packages/api/session-controller/src/types.ts:163,579`.
///
/// The retired `/api/events.host` leg never answers the upgrade on 0.1.5, so
/// these are the live path; the repository is driven through its real entry
/// points and the real `SessionWire` decoder, not a re-encode.
library;

import 'dart:async';

import 'package:domain/model/session.dart';
import 'package:harness_adapter/src/adapter_diagnostics.dart';
import 'package:harness_adapter/src/dsh_connection_manager.dart';
import 'package:harness_adapter/src/harness_repository_impl.dart';
import 'package:harness_adapter/src/rpc_map.dart';
import 'package:network/dsh_event_socket.dart';
import 'package:network/dsh_rpc_client.dart';
import 'package:network/rpc_envelope.dart';
import 'package:test/test.dart';

/// The minimum host the repository needs to reach CONNECTED and settle its
/// list resync; every other endpoint answers an empty value.
class _FakeRpc implements DshRpcClient {
  _FakeRpc({this.sessions = const <Object?>[]});

  List<Object?> sessions;

  /// `session/page` value; a test rewrites it before opening a session.
  JsonMap historyValue = <String, Object?>{
    'events': <Object?>[],
    'hasMore': false,
  };

  int sessionListCalls = 0;

  @override
  Future<RpcResult> call(
    String endpoint,
    String method,
    JsonMap payload, {
    Duration? timeout,
  }) async {
    switch (endpoint) {
      case DshRpcEndpoints.sessionList:
        sessionListCalls += 1;
        return RpcResult(ok: true, value: <String, Object?>{'items': sessions});
      case DshRpcEndpoints.sessionPage:
        return RpcResult(ok: true, value: historyValue);
      default:
        return RpcResult(ok: true, value: <String, Object?>{});
    }
  }

  @override
  Future<void> respond(String rpcId, RpcResult result) async {}
}

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

  /// One `$events` `emit` item carrying [event] with positional [args].
  void emit(String event, List<Object?> args) {
    _mux.add(
      ServerRequest(
        rpcId: 'remote-events',
        method: 'item',
        payload: <String, Object?>{
          'type': 'emit',
          'event': event,
          'args': args,
        },
      ),
    );
  }

  Future<void> close() => _mux.close();
}

JsonMap _sessionRow(String id) => <String, Object?>{
  'sessionId': id,
  'updatedAt': 3,
  'running': false,
  'blank': false,
};

void main() {
  test(
    'a forwarded api-session/added summary upserts the roster in place',
    () async {
      final rpc = _FakeRpc();
      final socket = _MuxSocket();
      final repository = HarnessRepositoryImpl(
        rpc,
        DshConnectionManager(socket, (_) => 10000),
      );
      addTearDown(repository.dispose);
      await pumpEventQueue();

      // Capture every roster publication: with the fold missing the second
      // expectation fails on the still-empty list instead of hanging.
      final emissions = <List<SessionSummary>>[];
      final subscription = repository.observeSessions().listen(emissions.add);
      addTearDown(subscription.cancel);
      await pumpEventQueue();

      // The connect resync pulled the list once; the roster is empty.
      expect(emissions.last, isEmpty);
      expect(rpc.sessionListCalls, 1);

      // A 0.1.5 host pushes a session created elsewhere as a forwarded event.
      socket.emit('api-session/added', <Object?>[
        <String, Object?>{
          'sessionId': 'session-remote-9',
          'updatedAt': 42,
          'running': false,
          'blank': true,
          'cwd': '/tmp/project',
          'origin': 'subagent',
          'parentSessionId': 'session-parent',
          'projections': <String, Object?>{
            'asOfSeq': 7,
            'values': <String, Object?>{'title': 'created elsewhere'},
          },
        },
      ]);
      await pumpEventQueue();

      final added = emissions.last.single;
      expect(added.id, 'session-remote-9');
      // `title` rides the summary's projection hints through the real
      // `SessionWire` decoder and `_toDomainSession`.
      expect(added.title, 'created elsewhere');
      expect(added.running, isFalse);
      expect(added.blank, isTrue);
      expect(added.updatedAtEpochMs, 42);
      expect(added.cwd, '/tmp/project');
      expect(added.origin, 'subagent');
      expect(added.parentSessionId, 'session-parent');
      // The summary is authoritative: no extra `session.list` round-trip.
      expect(rpc.sessionListCalls, 1);

      await socket.close();
    },
  );

  test(
    'a later api-session/added for a known session replaces its row',
    () async {
      final rpc = _FakeRpc(sessions: <Object?>[_sessionRow('session-known')]);
      final socket = _MuxSocket();
      final repository = HarnessRepositoryImpl(
        rpc,
        DshConnectionManager(socket, (_) => 10000),
      );
      addTearDown(repository.dispose);
      await pumpEventQueue();

      final emissions = <List<SessionSummary>>[];
      final subscription = repository.observeSessions().listen(emissions.add);
      addTearDown(subscription.cancel);
      await pumpEventQueue();

      expect(emissions.last.single.id, 'session-known');

      socket.emit('api-session/added', <Object?>[
        <String, Object?>{
          'sessionId': 'session-known',
          'updatedAt': 99,
          'running': true,
          'blank': false,
          'cwd': '/tmp/project',
          'projections': <String, Object?>{
            'asOfSeq': 11,
            'values': <String, Object?>{'title': 'retitled elsewhere'},
          },
        },
      ]);
      await pumpEventQueue();

      final updated = emissions.last.single;
      expect(updated.id, 'session-known');
      expect(updated.title, 'retitled elsewhere');
      expect(updated.running, isTrue);
      expect(updated.updatedAtEpochMs, 99);
      expect(rpc.sessionListCalls, 1);

      await socket.close();
    },
  );

  test('the repository reports an unrecognised session event type', () async {
    final diagnostics = <AdapterDiagnostic>[];
    final rpc = _FakeRpc(sessions: <Object?>[_sessionRow('session-x')]);
    // A history page whose one event has no fold. `sandbox/mode`, `hook/*`
    // and `tool-workflow/*` are covered folds now, so this uses a
    // merge-extensible name the adapter does not know.
    rpc.historyValue = <String, Object?>{
      'events': <Object?>[
        <String, Object?>{
          'type': 'event',
          'event': <String, Object?>{
            'type': 'team/created',
            'seq': 5,
            'time': 5,
            'data': <String, Object?>{'teamId': 'team-1'},
          },
        },
      ],
      'hasMore': false,
    };
    final socket = _MuxSocket();
    final repository = HarnessRepositoryImpl(
      rpc,
      DshConnectionManager(socket, (_) => 10000),
      onDiagnostic: diagnostics.add,
    );
    addTearDown(repository.dispose);
    await pumpEventQueue();

    await repository.openSession('session-x');
    await pumpEventQueue();

    final diagnostic = diagnostics.singleWhere(
      (entry) => entry.context == 'timeline.event',
    );
    expect(diagnostic.level, AdapterDiagnosticLevel.debug);
    expect(diagnostic.message, contains('team/created'));
    expect(diagnostic.message, contains('seq 5'));
    expect(diagnostic.metadata['type'], 'team/created');
    expect(diagnostic.metadata['seq'], 5);
    expect(diagnostic.metadata['sessionId'], 'session-x');

    await socket.close();
  });
}
