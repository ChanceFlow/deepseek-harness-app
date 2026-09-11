/// `sendSubagentPrompt` calls only the canonical `subagents/prompt` route and
/// propagates a host business refusal verbatim.
///
/// Wire truth (read from the reference submodule at `dsh-v0.1.5-rc.2`,
/// `fb2c4b9e698e30edb738bca4cf0618587db7d203`): the Subagent service registers
/// `@Remote('prompt')` under the `subagents` namespace
/// (`packages/subagent/subagent/src/index.ts`), so the only Remote name is
/// `subagents/prompt`. The dotted `subagent.prompt` string is a control-schema
/// key in `packages/subagent/subagent/src/control.ts`, never a registered
/// route, and the 0.1.5 fixture dispatches only `subagents/prompt`
/// (`packages/client/connection/src/client/fixture.ts`).
///
/// A prior retry loop swallowed any failure and re-called the undeclared
/// `subagent.prompt` name, so an honest host's refusal surfaced as the
/// fallback's `not-found` instead of the host's own code.
library;

import 'dart:async';

import 'package:harness_adapter/src/dsh_connection_manager.dart';
import 'package:harness_adapter/src/harness_repository_impl.dart';
import 'package:harness_adapter/src/rpc_map.dart';
import 'package:network/dsh_event_socket.dart';
import 'package:network/dsh_exceptions.dart';
import 'package:network/dsh_rpc_client.dart';
import 'package:network/rpc_envelope.dart';
import 'package:test/test.dart';

/// A recording host whose readiness reads succeed and whose `subagents/prompt`
/// answers the scripted business refusal. Every endpoint the repository calls
/// is journalled, so a retry can only come from the client.
class _RefusingRpc implements DshRpcClient {
  final List<String> calls = <String>[];

  @override
  Future<RpcResult> call(
    String endpoint,
    String method,
    JsonMap payload, {
    Duration? timeout,
  }) async {
    calls.add(endpoint);
    switch (endpoint) {
      case DshRpcEndpoints.sessionList:
        return RpcResult(
          ok: true,
          value: <String, Object?>{'items': <Object?>[]},
        );
      case DshRpcEndpoints.subagentsPrompt:
        return RpcResult(
          ok: false,
          error: RpcError(
            code: 'subagent/unauthorized',
            message: 'scripted refusal: subagent/unauthorized',
          ),
        );
      default:
        return RpcResult(ok: true, value: <String, Object?>{});
    }
  }

  @override
  Future<void> respond(String rpcId, RpcResult result) async {}
}

/// A downlink socket that answers the handshake and then stays open: the
/// refusal rides the unary path, so no further frame is needed.
class _OpenSocket implements DshEventSocket {
  final StreamController<ServerRequest> _mux =
      StreamController<ServerRequest>();

  @override
  Stream<ServerRequest> connect(String path, {void Function()? onOpen}) {
    onOpen?.call();
    _mux.add(_readyFrame());
    return _mux.stream;
  }

  Future<void> close() => _mux.close();
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

void main() {
  test(
    'a subagents/prompt business refusal is delivered, not retried',
    () async {
      final rpc = _RefusingRpc();
      final socket = _OpenSocket();
      final repository = HarnessRepositoryImpl(
        rpc,
        DshConnectionManager(socket, (_) => 10000),
      );
      addTearDown(() async {
        await repository.dispose();
        await socket.close();
      });
      await pumpEventQueue();

      await expectLater(
        repository.sendSubagentPrompt('parent-1', 'child-1', 'hello'),
        throwsA(
          isA<DshBusinessException>()
              .having((error) => error.code, 'code', 'subagent/unauthorized')
              .having(
                (error) => error.message,
                'message',
                contains('subagent/unauthorized'),
              ),
        ),
      );

      // Exactly one canonical call, and no call to the undeclared legacy name
      // the old catch-all fallback used.
      expect(
        rpc.calls.where((name) => name == DshRpcEndpoints.subagentsPrompt),
        hasLength(1),
      );
      expect(rpc.calls, isNot(contains('subagent.prompt')));
    },
  );
}
