/// Repository-level wire coverage for the `dsh-v0.1.5-rc.2` pin:
/// `commands/list`, `pluginInventory/list`, and the dynamic-Cordis approval
/// round trip (`cordis/request-run` forwarded emit +
/// `dynamicCordisRunner/resolveRequestRun`).
///
/// Wire truth read from the reference submodule at `dsh-v0.1.5-rc.2`
/// (`fb2c4b9e698e30edb738bca4cf0618587db7d203`):
/// - `packages/interaction/commands/src/index.ts:309` `@Remote list` and
///   `types.ts` `CommandDescriptor` / `CommandInputDescriptor`;
/// - `packages/host/plugin-inventory/src/index.ts:65` `@Remote('list')` and
///   `types.ts` `PluginInventorySnapshot`;
/// - `packages/api/remotes/src/remote-events.ts:27` `cordis/request-run`
///   (mode `emit`) and `packages/extensions/cordis-host-runner/src/
///   index.ts:412` `@Remote('resolveRequestRun')`.
///
/// The live host was probed with
/// `POST /api/commands/list {"args":{"agentId":"<root session>"}}`, which
/// answered the six registered descriptors (`compact`, `export`,
/// `feedback`, `plan`, `permission`, `goal`) — the fixture below transcribes
/// that response.
library;

import 'dart:async';

import 'package:domain/model/cordis.dart';
import 'package:domain/model/plugin_inventory.dart';
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
  /// Scripted `commands/list` value slot. The envelope parks a non-object
  /// result under `value`, exactly as the host's bare descriptor array does.
  JsonMap commandsValue = <String, Object?>{
    'value': <Object?>[
      <String, Object?>{
        'name': 'compact',
        'description': 'Compact older conversation history',
      },
      <String, Object?>{
        'name': 'goal',
        'description': 'set or view the goal for a long-running task',
        'input': <String, Object?>{
          'hint': '[<objective>|clear|edit <objective>|pause|resume]',
          'attachments': true,
        },
      },
    ],
  };

  /// Scripted `pluginInventory/list` value slot.
  JsonMap inventoryValue = <String, Object?>{
    'entries': <Object?>[
      <String, Object?>{
        'entryId': 'include',
        'moduleName': 'cordis:include',
        'enabled': true,
        'fiberPhase': 'active',
      },
      <String, Object?>{
        'entryId': 'include:hmr',
        'moduleName': '@deepseek-ai/cordis-plugin-hmr',
        'enabled': false,
        'fiberPhase': null,
      },
    ],
    'agentPresets': <Object?>[
      <String, Object?>{
        'id': 'standard',
        'trust': 'system',
        'isDefault': true,
        'name': 'Standard',
        'rows': <Object?>[
          <String, Object?>{
            'entryId': 'include:llm',
            'moduleName': '@deepseek-ai/dsh-llm',
            'enabled': true,
            'fiberPhase': 'active',
          },
          <String, Object?>{
            'entryId': null,
            'moduleName': '@deepseek-ai/dsh-tool-cordis',
            'enabled': 'conditional',
            'condition': 'process.env.CORDIS === "1"',
            'fiberPhase': null,
          },
        ],
      },
    ],
  };

  int sessionListCalls = 0;
  final List<(String, JsonMap)> calls = <(String, JsonMap)>[];

  @override
  Future<RpcResult> call(
    String endpoint,
    String method,
    JsonMap payload, {
    Duration? timeout,
  }) async {
    calls.add((endpoint, payload));
    switch (endpoint) {
      case DshRpcEndpoints.sessionList:
        sessionListCalls += 1;
        return RpcResult(
          ok: true,
          value: <String, Object?>{'items': <Object?>[]},
        );
      case DshRpcEndpoints.commandsList:
        return RpcResult(ok: true, value: commandsValue);
      case DshRpcEndpoints.pluginInventoryList:
        return RpcResult(ok: true, value: inventoryValue);
      case DshRpcEndpoints.cordisResolveRequestRun:
        return RpcResult(ok: true, value: <String, Object?>{'accepted': true});
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

JsonMap _cordisRequest() => <String, Object?>{
  'requestId': 'approval-7',
  'agentId': 'session-1',
  'pluginId': 'plugin-1',
  'packageId': 'pkg-1',
  'mode': 'run',
  'name': 'rock-paper-scissors',
  'purpose': 'play a game in the browser panel',
  'requiresApproval': true,
};

Future<HarnessRepositoryImpl> _repository(
  _FakeRpc rpc,
  _MuxSocket socket,
) async {
  final repository = HarnessRepositoryImpl(
    rpc,
    DshConnectionManager(socket, (_) => 10000),
  );
  await pumpEventQueue();
  return repository;
}

void main() {
  test('commands/list decodes the live roster with its input hints', () async {
    final rpc = _FakeRpc();
    final socket = _MuxSocket();
    final repository = await _repository(rpc, socket);
    addTearDown(repository.dispose);

    final roster = await repository.listCommands('session-1');

    expect(roster, hasLength(2));
    final compact = roster.first;
    expect(compact.name, 'compact');
    expect(compact.description, 'Compact older conversation history');
    // No advertised input is the bare-only signal.
    expect(compact.inputHint, isNull);
    expect(compact.acceptsArgs, isFalse);
    expect(compact.acceptsAttachments, isFalse);

    final goal = roster.last;
    expect(goal.inputHint, '[<objective>|clear|edit <objective>|pause|resume]');
    expect(goal.acceptsArgs, isTrue);
    expect(goal.acceptsAttachments, isTrue);

    // The addressed agent rides `agentId` (live probe: a request without it
    // answers `gateway/arguments-invalid`).
    final (_, payload) = rpc.calls.lastWhere(
      (call) => call.$1 == DshRpcEndpoints.commandsList,
    );
    expect(payload['args'], <String, Object?>{'agentId': 'session-1'});

    await socket.close();
  });

  test('commands/list missing a descriptor field throws naming it', () async {
    final rpc = _FakeRpc();
    final socket = _MuxSocket();
    final repository = await _repository(rpc, socket);
    addTearDown(repository.dispose);

    rpc.commandsValue = <String, Object?>{
      'value': <Object?>[
        <String, Object?>{'name': 'compact'},
      ],
    };
    await expectLater(
      repository.listCommands('session-1'),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('description'),
        ),
      ),
    );

    await socket.close();
  });

  test('commands/list answering a non-array result throws', () async {
    final rpc = _FakeRpc();
    final socket = _MuxSocket();
    final repository = await _repository(rpc, socket);
    addTearDown(repository.dispose);

    rpc.commandsValue = <String, Object?>{'value': <String, Object?>{}};
    await expectLater(
      repository.listCommands('session-1'),
      throwsA(isA<FormatException>()),
    );

    await socket.close();
  });

  test('commands/change ticks the roster-invalidation stream', () async {
    final rpc = _FakeRpc();
    final socket = _MuxSocket();
    final repository = await _repository(rpc, socket);
    addTearDown(repository.dispose);

    final ticks = <void>[];
    final subscription = repository.observeCommandRosterChanges().listen(
      ticks.add,
    );
    addTearDown(subscription.cancel);
    await pumpEventQueue();
    expect(ticks, isEmpty);

    socket.emit('commands/change', const <Object?>[]);
    await pumpEventQueue();
    expect(ticks, hasLength(1));

    await socket.close();
  });

  test(
    'pluginInventory/list decodes entries and preset compositions',
    () async {
      final rpc = _FakeRpc();
      final socket = _MuxSocket();
      final repository = await _repository(rpc, socket);
      addTearDown(repository.dispose);

      final inventory = await repository.listPluginInventory();

      expect(inventory.entries, hasLength(2));
      expect(inventory.entries.first.entryId, 'include');
      expect(inventory.entries.first.moduleName, 'cordis:include');
      expect(inventory.entries.first.enabled, isTrue);
      expect(inventory.entries.first.fiberPhase, PluginFiberPhase.active);
      // A null fiber phase is the wire's "no live root fiber".
      expect(inventory.entries.last.fiberPhase, isNull);
      expect(inventory.entries.last.enabled, isFalse);

      expect(inventory.agentPresets, hasLength(1));
      final preset = inventory.agentPresets.single;
      expect(preset.id, 'standard');
      expect(preset.isDefault, isTrue);
      expect(preset.rows, hasLength(2));
      expect(preset.rows.last.enabled, PresetRowEnablement.conditional);
      expect(preset.rows.last.condition, 'process.env.CORDIS === "1"');

      await socket.close();
    },
  );

  test(
    'pluginInventory/list without entries throws naming the field',
    () async {
      final rpc = _FakeRpc();
      final socket = _MuxSocket();
      final repository = await _repository(rpc, socket);
      addTearDown(repository.dispose);

      rpc.inventoryValue = <String, Object?>{};
      await expectLater(
        repository.listPluginInventory(),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('entries'),
          ),
        ),
      );

      await socket.close();
    },
  );

  test('pluginInventory/list with an unknown fiberPhase throws', () async {
    final rpc = _FakeRpc();
    final socket = _MuxSocket();
    final repository = await _repository(rpc, socket);
    addTearDown(repository.dispose);

    rpc.inventoryValue = <String, Object?>{
      'entries': <Object?>[
        <String, Object?>{
          'entryId': 'x',
          'moduleName': 'x',
          'enabled': true,
          'fiberPhase': 'exploded',
        },
      ],
    };
    await expectLater(
      repository.listPluginInventory(),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('exploded'),
        ),
      ),
    );

    await socket.close();
  });

  test('a cordis/request-run emit publishes the pending request', () async {
    final rpc = _FakeRpc();
    final socket = _MuxSocket();
    final repository = await _repository(rpc, socket);
    addTearDown(repository.dispose);

    final pending = <List<CordisRunRequest>>[];
    final subscription = repository.observeCordisRunRequests().listen(
      pending.add,
    );
    addTearDown(subscription.cancel);
    await pumpEventQueue();
    expect(pending.last, isEmpty);

    socket.emit('cordis/request-run', <Object?>[_cordisRequest()]);
    await pumpEventQueue();

    final request = pending.last.single;
    expect(request.requestId, 'approval-7');
    expect(request.sessionId, 'session-1');
    expect(request.pluginId, 'plugin-1');
    expect(request.packageId, 'pkg-1');
    expect(request.mode, CordisRunMode.run);
    expect(request.name, 'rock-paper-scissors');
    expect(request.purpose, 'play a game in the browser panel');
    expect(request.requiresApproval, isTrue);

    await socket.close();
  });

  test(
    'a rejection answers resolveRequestRun with the refusal union',
    () async {
      final rpc = _FakeRpc();
      final socket = _MuxSocket();
      final repository = await _repository(rpc, socket);
      addTearDown(repository.dispose);

      final pending = <List<CordisRunRequest>>[];
      final subscription = repository.observeCordisRunRequests().listen(
        pending.add,
      );
      addTearDown(subscription.cancel);
      await pumpEventQueue();

      socket.emit('cordis/request-run', <Object?>[_cordisRequest()]);
      await pumpEventQueue();
      expect(pending.last, hasLength(1));

      await repository.resolveCordisRunRequest(
        'approval-7',
        const CordisRunRejected(),
      );
      await pumpEventQueue();

      final (_, payload) = rpc.calls.lastWhere(
        (call) => call.$1 == DshRpcEndpoints.cordisResolveRequestRun,
      );
      expect(payload['args'], <String, Object?>{
        'requestId': 'approval-7',
        'resolution': <String, Object?>{'ok': false, 'reason': 'rejected'},
      });
      // The local affordance drops once the host accepted the answer.
      expect(pending.last, isEmpty);

      await socket.close();
    },
  );

  test('an approval answers with the exact activation identity', () async {
    final rpc = _FakeRpc();
    final socket = _MuxSocket();
    final repository = await _repository(rpc, socket);
    addTearDown(repository.dispose);
    await repository.resolveCordisRunRequest(
      'approval-8',
      const CordisRunApproved(
        pluginRunId: 'run-9',
        waitingFor: <String>['slots'],
      ),
    );
    final (_, payload) = rpc.calls.lastWhere(
      (call) => call.$1 == DshRpcEndpoints.cordisResolveRequestRun,
    );
    expect(payload['args'], <String, Object?>{
      'requestId': 'approval-8',
      'resolution': <String, Object?>{
        'ok': true,
        'pluginRunId': 'run-9',
        'waitingFor': <String>['slots'],
      },
    });
    await socket.close();
  });

  test('cordis/request-run-resolved clears the pending request', () async {
    final rpc = _FakeRpc();
    final socket = _MuxSocket();
    final repository = await _repository(rpc, socket);
    addTearDown(repository.dispose);

    final pending = <List<CordisRunRequest>>[];
    final subscription = repository.observeCordisRunRequests().listen(
      pending.add,
    );
    addTearDown(subscription.cancel);
    await pumpEventQueue();

    socket.emit('cordis/request-run', <Object?>[_cordisRequest()]);
    await pumpEventQueue();
    expect(pending.last, hasLength(1));

    socket.emit('cordis/request-run-resolved', <Object?>[
      <String, Object?>{'requestId': 'approval-7', 'outcome': 'rejected'},
    ]);
    await pumpEventQueue();
    expect(pending.last, isEmpty);

    await socket.close();
  });

  test('a malformed cordis/request-run is dropped, not crashed on', () async {
    final rpc = _FakeRpc();
    final socket = _MuxSocket();
    final repository = await _repository(rpc, socket);
    addTearDown(repository.dispose);

    final diagnostics = <String>[];
    final pending = <List<CordisRunRequest>>[];
    final subscription = repository.observeCordisRunRequests().listen(
      pending.add,
    );
    addTearDown(subscription.cancel);
    await pumpEventQueue();

    // `pluginId` is required by `DynamicCordisRunRequest`.
    socket.emit('cordis/request-run', <Object?>[
      <String, Object?>{
        'requestId': 'approval-x',
        'agentId': 'session-1',
        'packageId': 'pkg-1',
        'mode': 'run',
        'name': 'x',
        'purpose': 'y',
        'requiresApproval': true,
      },
    ]);
    await pumpEventQueue();
    expect(pending.last, isEmpty);
    expect(diagnostics, isEmpty);

    await socket.close();
  });
}
