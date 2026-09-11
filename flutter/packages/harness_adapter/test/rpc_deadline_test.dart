/// Verifies the adapter's per-call RPC deadline policy: short/unary calls
/// carry a deadline, the long-running exempt ones pass an explicit none.
library;

import 'dart:async';

import 'package:domain/model/prompt.dart';
import 'package:network/dsh_event_socket.dart';
import 'package:network/dsh_rpc_client.dart';
import 'package:network/rpc_envelope.dart';
import 'package:test/test.dart';

import 'package:harness_adapter/src/dsh_connection_manager.dart';
import 'package:harness_adapter/src/harness_repository_impl.dart';
import 'package:harness_adapter/src/rpc_map.dart';

/// Records the deadline every transport call arrived with.
class RecordingDshRpcClient implements DshRpcClient {
  final List<(String, Duration?)> calls = <(String, Duration?)>[];

  Duration? timeoutFor(String endpoint) => calls
      .firstWhere(
        (call) => call.$1 == endpoint,
        orElse: () => throw StateError('$endpoint was never called'),
      )
      .$2;

  @override
  Future<RpcResult> call(
    String endpoint,
    String method,
    JsonMap payload, {
    Duration? timeout,
  }) async {
    calls.add((endpoint, timeout));
    return switch (endpoint) {
      DshRpcEndpoints.sessionList => RpcResult(
        ok: true,
        value: <String, Object?>{'items': <Object?>[]},
      ),
      DshRpcEndpoints.sessionPrompt => RpcResult(
        ok: true,
        value: <String, Object?>{'accepted': true},
      ),
      _ => RpcResult(ok: true, value: <String, Object?>{}),
    };
  }

  @override
  Future<void> respond(String rpcId, RpcResult result) async {}
}

/// A downlink seam that answers the generation handshake and then stays open.
class SilentHarnessSocket implements DshEventSocket {
  @override
  Stream<ServerRequest> connect(String path, {void Function()? onOpen}) async* {
    onOpen?.call();
    yield ServerRequest(
      rpcId: 'remote-events',
      method: 'item',
      payload: <String, Object?>{
        'type': 'ready',
        'clientId': 'client-1',
        'host': <String, Object?>{'home': '/home/tester'},
      },
    );
    await Completer<void>().future;
  }
}

Future<HarnessRepositoryImpl> _repository(RecordingDshRpcClient rpc) async {
  final repository = HarnessRepositoryImpl(
    rpc,
    DshConnectionManager(SilentHarnessSocket(), (_) => 10000),
  );
  // Lets the generation handshake settle before the test drives the seam.
  await pumpEventQueue();
  return repository;
}

void main() {
  test('a short unary call carries a deadline', () async {
    final rpc = RecordingDshRpcClient();
    final repository = await _repository(rpc);

    await repository.refreshSessions();

    expect(
      rpc.timeoutFor(DshRpcEndpoints.sessionList),
      const Duration(seconds: 30),
    );
    await repository.dispose();
  });

  test('the prompt path passes an explicit no-deadline', () async {
    final rpc = RecordingDshRpcClient();
    final repository = await _repository(rpc);

    await repository.sendMessage(
      const SendMessageRequest(sessionId: 's-1', text: 'hi'),
    );

    expect(
      rpc.timeoutFor(DshRpcEndpoints.sessionPrompt),
      isNull,
      reason:
          'session/prompt hosts agent work (compaction); a deadline would '
          'kill legitimate turns',
    );
    await repository.dispose();
  });
}
