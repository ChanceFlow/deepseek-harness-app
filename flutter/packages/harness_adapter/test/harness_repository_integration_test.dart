import 'dart:async';
import 'dart:typed_data';

import 'package:domain/model/attachment.dart';
import 'package:domain/model/chat_message.dart';
import 'package:domain/model/plan.dart';
import 'package:domain/model/prompt.dart';
import 'package:domain/model/session.dart';
import 'package:domain/model/settings.dart';
import 'package:domain/model/todo.dart';
import 'package:domain/model/goal.dart';
import 'package:domain/model/timeline_item.dart';
import 'package:domain/model/agent_preset.dart';
import 'package:domain/repository/chat_repository.dart' show QuestionEvidence;
import 'package:network/dsh_event_socket.dart';
import 'package:network/dsh_rpc_client.dart';
import 'package:network/dsh_exceptions.dart';
import 'package:network/rpc_envelope.dart';
import 'package:test/test.dart';

import 'package:harness_adapter/src/dsh_connection_manager.dart';
import 'package:harness_adapter/src/dsh_wire_types.dart';
import 'package:harness_adapter/src/harness_repository_impl.dart';
import 'package:harness_adapter/src/rpc_map.dart';

JsonMap _workspaceJson(
  String id,
  String path,
  String title, [
  List<String> sessionIds = const <String>[],
]) => <String, Object?>{
  'workspaceId': id,
  'path': path,
  'title': title,
  'sessionIds': sessionIds,
  'createdAt': '2026-01-01T00:00:00Z',
  'updatedAt': '2026-01-01T00:00:00Z',
};

JsonMap _directoryEntryJson(String name, String path, bool hidden) =>
    <String, Object?>{'name': name, 'path': path, 'hidden': hidden};

ServerRequest _hostFrame(String type, JsonMap payload) =>
    ServerRequest(rpcId: 'rpc-$type', method: type, payload: payload);

ServerRequest _muxFrame(String type, String sessionId, JsonMap event) =>
    ServerRequest(
      rpcId: 'rpc-$type-$sessionId',
      method: type,
      payload: <String, Object?>{
        'type': type,
        'sessionId': sessionId,
        'event': event,
      },
    );

JsonMap _assistantMessageEvent() => <String, Object?>{
  'type': 'assistant/message',
  'seq': 7,
  'time': 7,
  'data': <String, Object?>{
    'turn': 1,
    'step': 1,
    'message': <String, Object?>{
      'id': 'assistant-1',
      'role': 'assistant',
      'content': <Object?>[
        <String, Object?>{'type': 'text', 'text': 'hello from fake host'},
      ],
    },
  },
};

Future<HarnessRepositoryImpl> harnessRepository(
  HarnessFakeRpc rpc,
  ScriptedHarnessSocket socket,
) async {
  final manager = DshConnectionManager(rpc, socket, (_) => 10000);
  final repository = HarnessRepositoryImpl(rpc, manager);
  await pumpEventQueue();
  return repository;
}

class HarnessFakeRpc implements DshRpcClient {
  HarnessFakeRpc([
    this._initialSessions = const <Object?>[],
    this._initialWorkspaces = const <Object?>[],
  ]);

  final List<Object?> _initialSessions;
  final List<Object?> _initialWorkspaces;
  final Map<String, int> _calls = <String, int>{};
  final Map<String, List<JsonMap>> _payloadsByEndpoint =
      <String, List<JsonMap>>{};
  final List<(String, RpcResult)> _receivedResponses = <(String, RpcResult)>[];

  int callCountFor(String endpoint) => _calls[endpoint] ?? 0;

  List<JsonMap> payloads(String endpoint) =>
      List<JsonMap>.of(_payloadsByEndpoint[endpoint] ?? <JsonMap>[]);

  List<(String, RpcResult)> receivedResponses() =>
      List<(String, RpcResult)>.of(_receivedResponses);

  /// One-shot scripted business failure for the next call to [endpoint].
  void failNextCall(String endpoint, String code) {
    _failures[endpoint] = code;
  }

  final Map<String, String> _failures = <String, String>{};

  @override
  Future<RpcResult> call(
    String endpoint,
    String method,
    JsonMap payload,
  ) async {
    _calls[endpoint] = callCountFor(endpoint) + 1;
    _payloadsByEndpoint.putIfAbsent(endpoint, () => <JsonMap>[]).add(payload);
    if (_failures.remove(endpoint) case final code?) {
      return RpcResult(
        ok: false,
        error: RpcError(code: code, message: 'scripted failure: $code'),
      );
    }
    final value = _valueFor(endpoint);
    return RpcResult(ok: true, value: value);
  }

  JsonMap _valueFor(String endpoint) {
    switch (endpoint) {
      case 'host.describe':
        return <String, Object?>{
          'version': 'fake-host',
          'cwd': '/tmp/fake-host',
          'attachedSessions': 0,
        };
      case 'session.list':
        return <String, Object?>{'items': _initialSessions};
      case 'workspace.list':
        return <String, Object?>{
          'items': _initialWorkspaces,
          'archivedSessionIds': <Object?>[],
        };
      case 'workspace.insertBefore':
        return <String, Object?>{
          'workspaceIds': <Object?>['ws-b', 'ws-a', 'ws-c'],
        };
      case 'session.history':
        return <String, Object?>{
          'events': <Object?>[],
          'hasMore': false,
          'projections': <String, Object?>{
            'values': <String, Object?>{
              'plan': <String, Object?>{'active': false, 'pending': true},
            },
          },
        };
      case 'session.attachment':
        return <String, Object?>{
          'attachment': <String, Object?>{
            'attachmentId': 'sha256:abc',
            'mediaType': 'image/png',
            'bytes': 2,
            'width': 1,
            'height': 1,
            'name': 'shot.png',
          },
          'data': 'aGk=',
        };
      case 'workspace.insertSessionBefore':
        return <String, Object?>{
          'workspace': _workspaceJson('ws-a', '/a', 'A', <String>[
            's2',
            's3',
            's1',
          ]),
        };
      case 'skill.list':
        return <String, Object?>{
          'skills': <Object?>[
            <String, Object?>{
              'name': 'generate-image',
              'description': 'Generate images from text',
              'whenToUse': 'user asks for pictures',
              'modelInvocable': true,
            },
            <String, Object?>{
              'name': 'firefly3-manager',
              'description': 'Manage Firefly III ledgers',
              'modelInvocable': false,
            },
          ],
        };
      case 'host.listDirectory':
        return <String, Object?>{
          'path': '/tmp/chosen',
          'home': '/home/user',
          'crumbs': <Object?>[
            _directoryEntryJson('chosen', '/tmp/chosen', false),
          ],
          'entries': <Object?>[
            _directoryEntryJson('src', '/tmp/chosen/src', false),
          ],
          'truncated': false,
        };
      case 'host.createDirectory':
        return <String, Object?>{'path': '/tmp/chosen/new-folder'};
      case 'settings.describe':
        return <String, Object?>{
          'writable': true,
          'hasDocument': false,
          'namespaces': <Object?>[
            <String, Object?>{
              'ns': 'llm-deepseek',
              'schema': <String, Object?>{'type': 'object'},
              'value': <String, Object?>{
                'providers': <String, Object?>{
                  'deepseek-official': <String, Object?>{
                    'apiKeyEnv': 'DEEPSEEK_API_KEY',
                  },
                },
              },
              'base': <String, Object?>{},
              'user': <String, Object?>{'touched': true},
              'applies': 'live',
              'secrets': <Object?>[
                <String, Object?>{
                  'path': <Object?>['providers'],
                  'set': true,
                },
              ],
              'revision': 3,
            },
            <String, Object?>{
              'ns': 'shell',
              'value': <String, Object?>{},
              'applies': 'restart',
              'secrets': <Object?>[],
              'revision': 0,
            },
          ],
        };
      case 'credentials.describe':
        return <String, Object?>{
          'credentials': <String, Object?>{
            'DEEPSEEK_API_KEY': <String, Object?>{
              'configured': true,
              'source': 'file',
              'writable': true,
            },
            'MINIMAX_CN_API_KEY': <String, Object?>{
              'configured': false,
              'writable': false,
            },
          },
        };
      case 'settings.update':
      case 'settings.replace':
      case 'settings.mutate':
        return <String, Object?>{
          'ns': 'llm-deepseek',
          'value': <String, Object?>{},
          'user': <String, Object?>{'touched': true},
          'applies': 'live',
          'secrets': <Object?>[],
          'revision': 3,
        };
      case 'goal.edit':
        return <String, Object?>{
          'ref': <String, Object?>{'id': 'goal-1', 'revision': 2},
        };
      case 'agentPreset.list':
        // Fixture transcribed from
        // reference/deepseek-harness/packages/host/apiproxy/src/api/
        // agent-presets.schema.ts agentPresetListValueSchema.
        return <String, Object?>{
          'presets': <Object?>[
            <String, Object?>{
              'id': 'standard',
              'trust': 'system',
              'isDefault': true,
            },
            <String, Object?>{
              'id': 'minimal',
              'trust': 'system',
              'isDefault': false,
              'name': 'Tiny',
              'description': 'Two tools only',
            },
            <String, Object?>{
              'id': 'my-agent',
              'trust': 'user',
              'isDefault': false,
              'broken': 'composition missing',
            },
          ],
          'authorable': true,
          'hasDocument': false,
        };
      case 'agentPreset.select':
        return <String, Object?>{'agentPreset': 'minimal'};
      default:
        return <String, Object?>{};
    }
  }

  @override
  Future<void> respond(String rpcId, RpcResult result) async {
    _receivedResponses.add((rpcId, result));
  }
}

class ScriptedHarnessSocket implements DshEventSocket {
  ScriptedHarnessSocket({
    this.muxFrames = const <ServerRequest>[],
    this.hostFrames = const <ServerRequest>[],
  });

  final List<ServerRequest> muxFrames;
  final List<ServerRequest> hostFrames;
  final Completer<void> _muxRelease = Completer<void>();
  final Completer<void> _hostRelease = Completer<void>();
  final List<String> _paths = <String>[];

  List<String> get connectedPaths => List<String>.of(_paths);

  void releaseMuxFrames() {
    if (!_muxRelease.isCompleted) _muxRelease.complete();
  }

  void releaseHostFrames() {
    if (!_hostRelease.isCompleted) _hostRelease.complete();
  }

  @override
  Stream<ServerRequest> connect(String path, {void Function()? onOpen}) async* {
    _paths.add(path);
    onOpen?.call();
    if (path.endsWith('events.host')) {
      await _hostRelease.future;
      for (final frame in hostFrames) {
        yield frame;
      }
    } else {
      await _muxRelease.future;
      for (final frame in muxFrames) {
        yield frame;
      }
    }
    // awaitCancellation: stay open until the subscriber cancels.
    await Completer<void>().future;
  }
}

void main() {
  test(
    'host workspace frames fold locally without extra workspace list calls',
    () async {
      final rpc = HarnessFakeRpc(<Object?>[], <Object?>[
        _workspaceJson('ws-a', '/a', 'A'),
        _workspaceJson('ws-b', '/b', 'B'),
      ]);
      final socket = ScriptedHarnessSocket(
        hostFrames: <ServerRequest>[
          _hostFrame('host/workspace-changed', <String, Object?>{
            'type': 'host/workspace-changed',
            'workspace': _workspaceJson('ws-a', '/a', 'A renamed', <String>[
              's1',
            ]),
          }),
          _hostFrame('host/workspace-order-changed', <String, Object?>{
            'type': 'host/workspace-order-changed',
            'workspaceIds': <Object?>['ws-b', 'ws-a'],
          }),
          _hostFrame('host/workspace-removed', <String, Object?>{
            'type': 'host/workspace-removed',
            'workspaceId': 'ws-b',
          }),
        ],
      );
      final repository = await harnessRepository(rpc, socket);
      await pumpEventQueue();

      socket.releaseHostFrames();
      await pumpEventQueue();

      final workspaces = await repository.observeWorkspaces().first;
      expect(workspaces.map((workspace) => workspace.title), <String>[
        'A renamed',
      ]);
      expect(workspaces.map((workspace) => workspace.workspaceId), <String>[
        'ws-a',
      ]);
      expect(rpc.callCountFor('workspace.list'), 1);
    },
  );

  test('mux session event reaches an opened session timeline', () async {
    final rpc = HarnessFakeRpc(<Object?>[
      <String, Object?>{
        'sessionId': 'session-1',
        'updatedAt': 3,
        'running': false,
        'blank': false,
      },
    ]);
    final socket = ScriptedHarnessSocket(
      muxFrames: <ServerRequest>[
        _muxFrame('session/event', 'session-1', _assistantMessageEvent()),
      ],
    );
    final repository = await harnessRepository(rpc, socket);
    await pumpEventQueue();

    await repository.openSession('session-1');
    await pumpEventQueue();

    socket.releaseMuxFrames();
    await pumpEventQueue();

    final timeline = await repository.observeTimeline('session-1').first;
    expect(timeline, hasLength(1));
    final message = timeline.single as TimelineMessage;
    expect(message.value.role, MessageRole.assistant);
    expect(message.value.text, 'hello from fake host');
    expect(message.value.streaming, isFalse);
  });

  test('queue edit serializes text content block', () async {
    final rpc = HarnessFakeRpc();
    final repository = await harnessRepository(rpc, ScriptedHarnessSocket());
    await pumpEventQueue();

    await repository.updateQueue(
      const QueueUpdateRequest(
        sessionId: 'session-1',
        itemId: 'queued-1',
        kind: QueueUpdateKind.edit,
        text: 'revised prompt',
      ),
    );

    final payload = rpc.payloads('session.updateQueue').single;
    final action = asJsonObject(payload['action']);
    expect(action, isNotNull, reason: 'missing action');
    final content = asJsonObject(asJsonArray(action!['content'])?.single);
    expect(content, isNotNull, reason: 'missing content block');
    expect(action['kind'], 'edit');
    expect(content!['type'], 'text');
    expect(content['text'], 'revised prompt');
  });

  test(
    'steer racing a closing turn is swallowed, other errors surface',
    () async {
      final rpc = HarnessFakeRpc();
      final repository = await harnessRepository(rpc, ScriptedHarnessSocket());
      await pumpEventQueue();

      // Web parity: steer-unavailable / queue-item-not-found are benign races
      // (the queue projection refreshes the dock) — no exception escapes.
      rpc.failNextCall('session.updateQueue', 'steer-unavailable');
      await repository.updateQueue(
        const QueueUpdateRequest(
          sessionId: 'session-1',
          itemId: 'queued-1',
          kind: QueueUpdateKind.steer,
        ),
      );
      rpc.failNextCall('session.updateQueue', 'queue-item-not-found');
      await repository.updateQueue(
        const QueueUpdateRequest(
          sessionId: 'session-1',
          itemId: 'queued-1',
          kind: QueueUpdateKind.remove,
        ),
      );

      rpc.failNextCall('session.updateQueue', 'agent-busy');
      await expectLater(
        repository.updateQueue(
          const QueueUpdateRequest(
            sessionId: 'session-1',
            itemId: 'queued-1',
            kind: QueueUpdateKind.steer,
          ),
        ),
        throwsA(isA<DshBusinessException>()),
      );
    },
  );

  test('skipped question response uses empty selected array', () async {
    final rpc = HarnessFakeRpc();
    final repository = await harnessRepository(rpc, ScriptedHarnessSocket());
    await pumpEventQueue();

    await repository.answerQuestions(
      'rpc-question',
      const QuestionEvidence(
        sessionId: 'session-1',
        answers: <QuestionAnswer>[QuestionAnswer(questionId: 'question-1')],
      ),
    );

    final received = rpc.receivedResponses().single;
    expect(received.$1, 'rpc-question');
    final value = received.$2.value;
    expect(value, isNotNull, reason: 'missing responded value');
    final answer = asJsonObject(value!['answer']);
    expect(answer, isNotNull, reason: 'missing answer');
    final firstAnswer = asJsonObject(asJsonArray(answer!['answers'])?.single);
    expect(firstAnswer, isNotNull, reason: 'missing question answer');
    expect(firstAnswer!['id'], 'question-1');
    expect((firstAnswer['selected'] as List).length, 0);
  });

  test('goal edit sends objective with cas ref', () async {
    final rpc = HarnessFakeRpc();
    final repository = await harnessRepository(rpc, ScriptedHarnessSocket());
    await pumpEventQueue();

    final edited = await repository.editGoal(
      'session-1',
      const GoalRef(id: 'goal-1', revision: 1),
      'ship it v2',
    );

    expect(edited.id, 'goal-1');
    expect(edited.revision, 2);
    final payload = rpc.payloads('goal.edit').single;
    expect(payload['sessionId'], 'session-1');
    expect(payload['objective'], 'ship it v2');
    final ref = asJsonObject(payload['ref']);
    expect(ref, isNotNull, reason: 'missing goal ref');
    expect(ref!['id'], 'goal-1');
    expect(ref['revision'], 1);
  });

  test('directory listing maps host wire shape', () async {
    final rpc = HarnessFakeRpc();
    final repository = await harnessRepository(rpc, ScriptedHarnessSocket());
    await pumpEventQueue();

    final listing = await repository.listDirectory('/tmp/chosen');

    expect(listing.path, '/tmp/chosen');
    expect(listing.home, '/home/user');
    expect(listing.entries.single.name, 'src');
    expect(listing.entries.single.hidden, isFalse);
    expect(rpc.payloads('host.listDirectory').single['path'], '/tmp/chosen');
  });

  test('directory creation sends host payload', () async {
    final rpc = HarnessFakeRpc();
    final repository = await harnessRepository(rpc, ScriptedHarnessSocket());
    await pumpEventQueue();

    final created = await repository.createDirectory(
      '/tmp/chosen',
      'new-folder',
    );

    expect(created, '/tmp/chosen/new-folder');
    final payload = rpc.payloads('host.createDirectory').single;
    expect(payload['path'], '/tmp/chosen');
    expect(payload['name'], 'new-folder');
  });

  test('settings describe maps namespace wire shape', () async {
    final rpc = HarnessFakeRpc();
    final repository = await harnessRepository(rpc, ScriptedHarnessSocket());
    await pumpEventQueue();

    final snapshot = await repository.describeSettings();

    expect(snapshot.writable, isTrue);
    expect(snapshot.hasDocument, isFalse);
    final deepseek = snapshot.namespaces.firstWhere(
      (namespace) => namespace.ns == 'llm-deepseek',
    );
    expect(deepseek.applies, SettingsApplies.live);
    expect(deepseek.revision, 3);
    expect(deepseek.hasUserLayer, isTrue);
    expect(deepseek.secretCount, 1);
    final shell = snapshot.namespaces.firstWhere(
      (namespace) => namespace.ns == 'shell',
    );
    expect(shell.applies, SettingsApplies.restart);
    expect(shell.hasUserLayer, isFalse);
    expect(snapshot.credentialRefs, <String>['DEEPSEEK_API_KEY']);
    expect(rpc.payloads('settings.describe').single.length, 0);
  });

  test('credentials describe sends refs and maps views', () async {
    final rpc = HarnessFakeRpc();
    final repository = await harnessRepository(rpc, ScriptedHarnessSocket());
    await pumpEventQueue();

    final described = await repository.describeCredentials(<String>[
      'MINIMAX_CN_API_KEY',
      'DEEPSEEK_API_KEY',
    ]);

    expect(described.map((status) => status.ref).toList(), <String>[
      'DEEPSEEK_API_KEY',
      'MINIMAX_CN_API_KEY',
    ]);
    final configured = described.firstWhere(
      (status) => status.ref == 'DEEPSEEK_API_KEY',
    );
    expect(configured.configured, isTrue);
    expect(configured.source, 'file');
    expect(configured.writable, isTrue);
    final missing = described.firstWhere(
      (status) => status.ref == 'MINIMAX_CN_API_KEY',
    );
    expect(missing.configured, isFalse);
    expect(missing.source, isNull);
    expect(missing.writable, isFalse);
    final refs = asJsonArray(
      rpc.payloads('credentials.describe').single['refs'],
    );
    expect(refs?.cast<String>(), <String>[
      'MINIMAX_CN_API_KEY',
      'DEEPSEEK_API_KEY',
    ]);
  });

  test('credentials describe skips the wire for empty refs', () async {
    final rpc = HarnessFakeRpc();
    final repository = await harnessRepository(rpc, ScriptedHarnessSocket());
    await pumpEventQueue();

    expect(await repository.describeCredentials(<String>[]), isEmpty);
    expect(rpc.payloads('credentials.describe'), isEmpty);
  });

  test('history projections seed plan state', () async {
    final rpc = HarnessFakeRpc();
    final repository = await harnessRepository(rpc, ScriptedHarnessSocket());
    await pumpEventQueue();

    await repository.openSession('session-1');
    await pumpEventQueue();

    expect(
      await repository.observePlan('session-1').first,
      const PlanState(active: false, pending: true),
    );
  });

  test('plan projection frame updates plan state live', () async {
    final rpc = HarnessFakeRpc();
    final socket = ScriptedHarnessSocket(
      muxFrames: <ServerRequest>[
        ServerRequest(
          rpcId: 'rpc-plan-1',
          method: 'session/projection',
          payload: <String, Object?>{
            'type': 'session/projection',
            'sessionId': 'session-1',
            'key': 'plan',
            'value': <String, Object?>{'active': true, 'pending': false},
          },
        ),
      ],
    );
    final repository = await harnessRepository(rpc, socket);
    await pumpEventQueue();

    socket.releaseMuxFrames();
    await pumpEventQueue();

    expect(
      await repository.observePlan('session-1').first,
      const PlanState(active: true, pending: false),
    );
  });

  // Wire shape: the `todos` projection value is the whole TodoItem list or
  // null (dsh-tool-todo projection schema).
  test('todos projection frames update the standing list live', () async {
    final rpc = HarnessFakeRpc();
    final socket = ScriptedHarnessSocket(
      muxFrames: <ServerRequest>[
        ServerRequest(
          rpcId: 'rpc-todos-1',
          method: 'session/projection',
          payload: <String, Object?>{
            'type': 'session/projection',
            'sessionId': 'session-1',
            'key': 'todos',
            'value': <Object?>[
              <String, Object?>{
                'content': 'ship the fix',
                'status': 'in_progress',
              },
              <String, Object?>{
                'content': 'write tests',
                'status': 'completed',
              },
            ],
          },
        ),
      ],
    );
    final repository = await harnessRepository(rpc, socket);
    await pumpEventQueue();

    // Seeded null before any frame.
    expect(await repository.observeTodos('session-1').first, isNull);

    socket.releaseMuxFrames();
    await pumpEventQueue();

    final emitted = await repository.observeTodos('session-1').first;
    expect(emitted, hasLength(2));
    expect(emitted!.first.content, 'ship the fix');
    expect(emitted.first.status, TodoStatus.inProgress);
    expect(emitted.last.status, TodoStatus.completed);
  });

  test('skill list sends session scope and maps catalog', () async {
    final rpc = HarnessFakeRpc();
    final repository = await harnessRepository(rpc, ScriptedHarnessSocket());
    await pumpEventQueue();

    final catalog = await repository.listSkills('session-1');

    expect(rpc.payloads('skill.list').single['sessionId'], 'session-1');
    expect(catalog, hasLength(2));
    final first = catalog.first;
    expect(first.name, 'generate-image');
    expect(first.description, 'Generate images from text');
    expect(first.whenToUse, 'user asks for pictures');
    expect(first.modelInvocable, isTrue);
    expect(catalog[1].whenToUse, isNull);
  });

  test('move workspace sends anchor and applies response order', () async {
    final rpc = HarnessFakeRpc(<Object?>[], <Object?>[
      _workspaceJson('ws-a', '/a', 'A'),
      _workspaceJson('ws-b', '/b', 'B'),
      _workspaceJson('ws-c', '/c', 'C'),
    ]);
    final repository = await harnessRepository(rpc, ScriptedHarnessSocket());
    await pumpEventQueue();
    await repository.refreshWorkspaces();

    final orderedIds = await repository.moveWorkspace('ws-a', 'ws-c');

    expect(orderedIds, <String>['ws-b', 'ws-a', 'ws-c']);
    final payload = rpc.payloads('workspace.insertBefore').single;
    expect(payload['workspaceId'], 'ws-a');
    expect(payload['beforeWorkspaceId'], 'ws-c');
    expect(
      (await repository.observeWorkspaces().first)
          .map((workspace) => workspace.workspaceId)
          .toList(),
      <String>['ws-b', 'ws-a', 'ws-c'],
    );
  });

  test('move workspace without anchor omits the field', () async {
    final rpc = HarnessFakeRpc();
    final repository = await harnessRepository(rpc, ScriptedHarnessSocket());
    await pumpEventQueue();

    await repository.moveWorkspace('ws-a', null);

    final payload = rpc.payloads('workspace.insertBefore').single;
    expect(payload['workspaceId'], 'ws-a');
    expect(payload.containsKey('beforeWorkspaceId'), isFalse);
  });

  test('credential set sends ref and value', () async {
    final rpc = HarnessFakeRpc();
    final repository = await harnessRepository(rpc, ScriptedHarnessSocket());
    await pumpEventQueue();

    await repository.setCredential('DEEPSEEK_API_KEY', 'sk-typed');

    final payload = rpc.payloads('credentials.set').single;
    expect(payload['ref'], 'DEEPSEEK_API_KEY');
    expect(payload['value'], 'sk-typed');
  });

  test('credential unset sends ref only', () async {
    final rpc = HarnessFakeRpc();
    final repository = await harnessRepository(rpc, ScriptedHarnessSocket());
    await pumpEventQueue();

    await repository.unsetCredential('DEEPSEEK_API_KEY');

    final payload = rpc.payloads('credentials.unset').single;
    expect(payload['ref'], 'DEEPSEEK_API_KEY');
    expect(payload.length, 1);
  });

  test('setting update sends patch with cas revision and maps view', () async {
    final rpc = HarnessFakeRpc();
    final repository = await harnessRepository(rpc, ScriptedHarnessSocket());
    await pumpEventQueue();

    final updated = await repository.updateSetting(
      'llm-deepseek',
      'retry',
      '{"attempts": 5}',
      expectedRevision: 3,
    );

    final payload = rpc.payloads('settings.update').single;
    expect(payload['ns'], 'llm-deepseek');
    expect(payload['expectedRevision'], 3);
    final patch = asJsonObject(payload['patch']);
    expect(patch, isNotNull, reason: 'missing patch');
    expect(asJsonObject(patch!['retry'])?['attempts'], 5);
    // The response arm reuses the settings.describe namespace fixture.
    expect(updated.ns, 'llm-deepseek');
    expect(updated.revision, 3);
    expect(updated.hasUserLayer, isTrue);
  });

  test('setting replace sends whole section object', () async {
    final rpc = HarnessFakeRpc();
    final repository = await harnessRepository(rpc, ScriptedHarnessSocket());
    await pumpEventQueue();

    await repository.replaceSetting(
      'shell',
      '{"bash":{"enabled":false}}',
      expectedRevision: 2,
    );

    final payload = rpc.payloads('settings.replace').single;
    expect(payload['ns'], 'shell');
    expect(payload['expectedRevision'], 2);
    final section = asJsonObject(payload['section']);
    expect(section, isNotNull, reason: 'missing section');
    expect(asJsonObject(section!['bash'])?['enabled'], isFalse);
  });

  test('setting mutate serializes set and unset path ops', () async {
    final rpc = HarnessFakeRpc();
    final repository = await harnessRepository(rpc, ScriptedHarnessSocket());
    await pumpEventQueue();

    await repository.mutateSetting('llm-deepseek', <SettingPathOp>[
      SettingPathOp(
        op: 'set',
        path: <String>['providers', 'x'],
        jsonValue: '5',
      ),
      SettingPathOp(op: 'unset', path: <String>['retry']),
    ]);

    final payload = rpc.payloads('settings.mutate').single;
    expect(payload['ns'], 'llm-deepseek');
    expect(payload.containsKey('expectedRevision'), isFalse);
    final ops = asJsonArray(payload['ops']);
    expect(ops, isNotNull, reason: 'missing ops');
    expect(ops!.length, 2);
    final setOp = asJsonObject(ops[0])!;
    expect(setOp['op'], 'set');
    expect(setOp['path'], <String>['providers', 'x']);
    expect(setOp['value'], 5);
    final unsetOp = asJsonObject(ops[1])!;
    expect(unsetOp['op'], 'unset');
    expect(unsetOp.containsKey('value'), isFalse);
  });

  test(
    'move session sends anchors and applies the updated workspace',
    () async {
      final rpc = HarnessFakeRpc(<Object?>[], <Object?>[
        _workspaceJson('ws-a', '/a', 'A', <String>['s1', 's2', 's3']),
      ]);
      final repository = await harnessRepository(rpc, ScriptedHarnessSocket());
      await pumpEventQueue();
      await repository.refreshWorkspaces();

      final updated = await repository.moveSession('ws-a', 's1', 's3');

      final payload = rpc.payloads('workspace.insertSessionBefore').single;
      expect(payload['workspaceId'], 'ws-a');
      expect(payload['sessionId'], 's1');
      expect(payload['beforeSessionId'], 's3');
      expect(updated.workspaceId, 'ws-a');
      expect(
        (await repository.observeWorkspaces().first)
            .map((workspace) => workspace.workspaceId)
            .toList(),
        <String>['ws-a'],
      );
    },
  );

  test('prompt with images appends image content parts', () async {
    final rpc = HarnessFakeRpc();
    final repository = await harnessRepository(rpc, ScriptedHarnessSocket());
    await pumpEventQueue();

    await repository.sendMessage(
      const SendMessageRequest(
        sessionId: 'session-1',
        text: 'see this',
        images: <PendingImage>[
          PendingImage(
            id: 'u1',
            mediaType: 'image/png',
            base64Data: 'aGk=',
            name: 'shot.png',
          ),
        ],
      ),
    );

    final payload = rpc.payloads('session.prompt').single;
    final content = asJsonArray(payload['content']) ?? const <Object?>[];
    expect(content, hasLength(2));
    final textPart = asJsonObject(content[0])!;
    expect(textPart['type'], 'text');
    expect(textPart['text'], 'see this');
    final image = asJsonObject(content[1])!;
    expect(image['type'], 'image');
    expect(image['mediaType'], 'image/png');
    expect(image['data'], 'aGk=');
    expect(image['name'], 'shot.png');
  });

  test('read attachment sends ids and decodes base64 payload', () async {
    final rpc = HarnessFakeRpc();
    final repository = await harnessRepository(rpc, ScriptedHarnessSocket());
    await pumpEventQueue();

    final downloaded = await repository.readAttachment(
      'session-1',
      'sha256:abc',
    );

    final payload = rpc.payloads('session.attachment').single;
    expect(payload['sessionId'], 'session-1');
    expect(payload['attachmentId'], 'sha256:abc');
    expect(downloaded.ref.attachmentId, 'sha256:abc');
    expect(downloaded.ref.mediaType, 'image/png');
    expect(downloaded.ref.bytes, 2);
    expect(downloaded.data, Uint8List.fromList(<int>[0x68, 0x69]));
  });

  test('image limits projection flows from session list', () async {
    final session = <String, Object?>{
      'sessionId': 'session-1',
      'projections': <String, Object?>{
        'values': <String, Object?>{
          'title': 'titled',
          'imageLimits': <String, Object?>{
            'maxImageBytes': 1048576,
            'maxImagesPerMessage': 4,
            'maxMessageImageBytes': 2097152,
            'maxImagePixels': 1000000,
            'mediaTypes': <Object?>['image/png', 'image/jpeg'],
          },
        },
      },
    };
    final rpc = HarnessFakeRpc(<Object?>[session]);
    final repository = await harnessRepository(rpc, ScriptedHarnessSocket());
    await pumpEventQueue();

    await repository.refreshSessions();

    final limits = await repository.observeImageLimits().first;
    expect(limits?.maxImageBytes, 1048576);
    expect(limits?.maxImagesPerMessage, 4);
    expect(limits?.maxMessageImageBytes, 2097152);
    expect(limits?.maxImagePixels, 1000000);
    expect(limits?.mediaTypes, <String>['image/png', 'image/jpeg']);
  });

  test('session list maps subagent origin and root absence', () async {
    // Wire: SessionSummary.origin is the optional coarse origin
    // (`origin?: 'subagent'`) — reference/deepseek-harness/
    // packages/host/apiproxy/src/api/sessions.ts.
    final rpc = HarnessFakeRpc(<Object?>[
      <String, Object?>{
        'sessionId': 'session-child',
        'updatedAt': 4,
        'running': false,
        'blank': false,
        'origin': 'subagent',
      },
      <String, Object?>{
        'sessionId': 'session-root',
        'updatedAt': 3,
        'running': false,
        'blank': false,
      },
    ]);
    final repository = await harnessRepository(rpc, ScriptedHarnessSocket());
    await pumpEventQueue();

    await repository.refreshSessions();

    final sessions = await repository.observeSessions().first;
    final child = sessions.firstWhere(
      (session) => session.id == 'session-child',
    );
    expect(child.origin, 'subagent');
    final root = sessions.firstWhere((session) => session.id == 'session-root');
    expect(root.origin, isNull);
  });

  // Wire shape: agentPreset.list roster
  // (reference/deepseek-harness/packages/host/apiproxy/src/api/
  // agent-presets.schema.ts).
  test('agentPreset.list decodes the roster and deployment facts', () async {
    final rpc = HarnessFakeRpc();
    final repository = await harnessRepository(rpc, ScriptedHarnessSocket());
    await pumpEventQueue();

    final roster = await repository.listAgentPresets();

    expect(rpc.payloads('agentPreset.list').single, isEmpty);
    expect(roster.authorable, isTrue);
    expect(roster.hasDocument, isFalse);
    expect(roster.entries, hasLength(3));
    final standard = roster.entries[0];
    expect(standard.id, 'standard');
    expect(standard.trust, AgentPresetTrust.system);
    expect(standard.isDefault, isTrue);
    expect(standard.name, isNull);
    expect(roster.defaultEntry?.id, 'standard');
    final minimal = roster.entries[1];
    expect(minimal.name, 'Tiny');
    expect(minimal.description, 'Two tools only');
    final custom = roster.entries[2];
    expect(custom.trust, AgentPresetTrust.user);
    expect(custom.broken, 'composition missing');
  });

  test('agentPreset.select sends the switch and echoes the preset', () async {
    final rpc = HarnessFakeRpc();
    final repository = await harnessRepository(rpc, ScriptedHarnessSocket());
    await pumpEventQueue();

    final echoed = await repository.selectAgentPreset('session-1', 'minimal');

    expect(echoed, 'minimal');
    expect(rpc.payloads('agentPreset.select').single, <String, Object?>{
      'sessionId': 'session-1',
      'agentPreset': 'minimal',
    });
  });

  test('agentPreset.select surfaces the host refusal', () async {
    final rpc = HarnessFakeRpc();
    rpc.failNextCall('agentPreset.select', 'agent-preset-locked');
    final repository = await harnessRepository(rpc, ScriptedHarnessSocket());
    await pumpEventQueue();

    await expectLater(
      repository.selectAgentPreset('session-1', 'minimal'),
      throwsA(
        isA<DshBusinessException>().having(
          (error) => error.code,
          'code',
          'agent-preset-locked',
        ),
      ),
    );
  });

  // Negative fixture: a required roster field absent must fail loud.
  test('agentPreset.list value without authorable throws', () {
    expect(
      () => AgentPresetListValueWire.fromJson(<String, Object?>{
        'presets': <Object?>[],
        'hasDocument': false,
      }),
      throwsFormatException,
    );
  });

  // Wire shape: the `permissions` projection value is the
  // interaction/permission-presets select (options + currentValue).
  test('permissions projection frames update the select live', () async {
    final rpc = HarnessFakeRpc();
    final socket = ScriptedHarnessSocket(
      muxFrames: <ServerRequest>[
        ServerRequest(
          rpcId: 'rpc-permissions-1',
          method: 'session/projection',
          payload: <String, Object?>{
            'type': 'session/projection',
            'sessionId': 'session-1',
            'key': 'permissions',
            'value': <String, Object?>{
              'options': <Object?>[
                <String, Object?>{
                  'value': 'read-only',
                  'name': 'Read Only',
                },
                <String, Object?>{
                  'value': 'workspace-write',
                  'name': 'Workspace Write',
                  'description': 'Edit files inside the workspace',
                },
              ],
              'currentValue': 'workspace-write',
            },
          },
        ),
        ServerRequest(
          rpcId: 'rpc-permissions-2',
          method: 'session/projection',
          payload: <String, Object?>{
            'type': 'session/projection',
            'sessionId': 'session-1',
            'key': 'permissions',
            'value': <String, Object?>{
              'options': <Object?>[
                <String, Object?>{'value': 'read-only', 'name': 'Read Only'},
              ],
              'currentValue': 'read-only',
            },
          },
        ),
      ],
    );
    final repository = await harnessRepository(rpc, socket);
    await pumpEventQueue();

    // Seeded null before any frame — a host that composes no permission
    // service keeps the chip hidden.
    expect(await repository.observePermissions('session-1').first, isNull);

    socket.releaseMuxFrames();
    await pumpEventQueue();

    // Both frames landed; the projection is last-wins, so the second
    // frame's select is current.
    final select = await repository.observePermissions('session-1').first;
    expect(select, isNotNull);
    expect(select!.currentValue, 'read-only');
    expect(select.options, hasLength(1));
    expect(select.options.first.name, 'Read Only');
    expect(select.currentOption?.name, 'Read Only');
  });

  // A single `permissions` frame decodes the full option table.
  test('permissions projection frame carries the option table', () async {
    final rpc = HarnessFakeRpc();
    final socket = ScriptedHarnessSocket(
      muxFrames: <ServerRequest>[
        ServerRequest(
          rpcId: 'rpc-permissions-table',
          method: 'session/projection',
          payload: <String, Object?>{
            'type': 'session/projection',
            'sessionId': 'session-1',
            'key': 'permissions',
            'value': <String, Object?>{
              'options': <Object?>[
                <String, Object?>{'value': 'read-only', 'name': 'Read Only'},
                <String, Object?>{
                  'value': 'workspace-write',
                  'name': 'Workspace Write',
                  'description': 'Edit files inside the workspace',
                },
              ],
              'currentValue': 'workspace-write',
            },
          },
        ),
      ],
    );
    final repository = await harnessRepository(rpc, socket);
    await pumpEventQueue();

    socket.releaseMuxFrames();
    await pumpEventQueue();

    final select = await repository.observePermissions('session-1').first;
    expect(select, isNotNull);
    expect(select!.currentValue, 'workspace-write');
    expect(select.currentOption?.name, 'Workspace Write');
    expect(select.options, hasLength(2));
    expect(select.options.first.description, isNull);
    expect(
      select.options.last.description,
      'Edit files inside the workspace',
    );
  });

  // A `null`-valued frame clears the select back to the hidden state.
  test('permissions projection null frame clears the select', () async {
    final rpc = HarnessFakeRpc();
    final socket = ScriptedHarnessSocket(
      muxFrames: <ServerRequest>[
        ServerRequest(
          rpcId: 'rpc-permissions-null',
          method: 'session/projection',
          payload: <String, Object?>{
            'type': 'session/projection',
            'sessionId': 'session-1',
            'key': 'permissions',
            'value': 'null',
          },
        ),
      ],
    );
    final repository = await harnessRepository(rpc, socket);
    await pumpEventQueue();

    socket.releaseMuxFrames();
    await pumpEventQueue();

    expect(await repository.observePermissions('session-1').first, isNull);
  });

  // Unknown projection keys are ignored: the key set is open and owned by
  // the host's composed units.
  test('unknown projection keys change nothing', () async {
    final rpc = HarnessFakeRpc();
    final socket = ScriptedHarnessSocket(
      muxFrames: <ServerRequest>[
        ServerRequest(
          rpcId: 'rpc-unknown-1',
          method: 'session/projection',
          payload: <String, Object?>{
            'type': 'session/projection',
            'sessionId': 'session-1',
            'key': 'trajectory',
            'value': <String, Object?>{'unexpected': true},
          },
        ),
      ],
    );
    final repository = await harnessRepository(rpc, socket);
    await pumpEventQueue();

    socket.releaseMuxFrames();
    await pumpEventQueue();

    expect(await repository.observePermissions('session-1').first, isNull);
  });

  // Wire shape: `agent-preset/selected` arrives as a forwarded
  // host/remote-event frame with args [sessionId, agentPreset]
  // (events.ts HostFrame; allowlist in dsh-api-remotes remote-events.ts).
  test('agent-preset/selected remote event folds the session summary', () async {
    final rpc = HarnessFakeRpc(<Object?>[
      <String, Object?>{
        'sessionId': 'session-1',
        'updatedAt': 3,
        'running': false,
        'blank': true,
      },
    ]);
    final socket = ScriptedHarnessSocket(
      hostFrames: <ServerRequest>[
        _hostFrame('host/remote-event', <String, Object?>{
          'type': 'host/remote-event',
          'event': 'agent-preset/selected',
          'args': <Object?>['session-1', 'minimal'],
        }),
      ],
    );
    final repository = await harnessRepository(rpc, socket);
    await pumpEventQueue();
    await repository.refreshSessions();

    socket.releaseHostFrames();
    await pumpEventQueue();

    final sessions = await repository.observeSessions().first;
    final switched = sessions.firstWhere(
      (session) => session.id == 'session-1',
    );
    expect(switched.agentPreset, 'minimal');
  });
}
