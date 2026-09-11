// Integration tests drive [HarnessRepositoryImpl] through
// [HarnessFakeRpc], a fake host whose accepted RPC method set is derived
// from the client registry ([DshRpcEndpoints] in `lib/src/rpc_map.dart`)
// rather than a hand-maintained list: a call to any other wire name throws
// a [StateError] naming the endpoint, so a name change in `rpc_map.dart`
// fails here instead of silently folding.
//
// Wire shapes come from the pinned reference submodule; these tests assert
// external repository state through the real entry paths
// (`docs/testing.md`).
import 'dart:async';
import 'dart:io' show SocketException;
import 'dart:typed_data';

import 'package:domain/model/attachment.dart';
import 'package:domain/model/chat_message.dart';
import 'package:domain/model/command.dart';
import 'package:domain/model/connection_state.dart';
import 'package:domain/model/context_pressure.dart';
import 'package:domain/model/plan.dart';
import 'package:domain/model/prompt.dart';
import 'package:domain/model/session.dart';
import 'package:domain/model/session_window_stats.dart';
import 'package:domain/model/settings.dart';
import 'package:domain/model/subagent.dart';
import 'package:domain/model/todo.dart';
import 'package:domain/model/goal.dart';
import 'package:domain/model/timeline_item.dart';
import 'package:domain/model/timeline_window.dart';
import 'package:domain/model/agent_preset.dart';
import 'package:domain/repository/chat_repository.dart' show QuestionEvidence;
import 'package:network/dsh_event_socket.dart';
import 'package:network/dsh_rpc_client.dart';
import 'package:network/dsh_exceptions.dart';
import 'package:network/rpc_envelope.dart';
import 'package:test/test.dart';

import 'package:harness_adapter/src/adapter_diagnostics.dart';
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

/// One `workspace/follow` baseline item. The pinned 0.1.5 workspace namespace
/// (`reference/deepseek-harness/packages/api/workspace-controller/src/
/// index.ts`) registers no unary list: the roster is pushed by this stream.
ServerRequest _workspaceBaseline(List<JsonMap> workspaces) => ServerRequest(
  rpcId: 'workspace-follow',
  method: 'workspace/follow',
  payload: <String, Object?>{
    'type': 'baseline',
    'value': <String, Object?>{
      'items': workspaces,
      'archivedSessionIds': <Object?>[],
    },
  },
);

/// One `$events` forwarded Remote Event item: the live `emit` shape
/// `{type: 'emit', event, args}` on `/api/remote.mux`
/// (`packages/api/gateway/src/stream-protocol.ts` `RemoteEventEmitFrame`).
/// The retired `host/*` frame vocabulary rode `/api/events.host`, which the
/// pinned 0.1.5 host never serves; these items are the live session
/// lifecycle path.
ServerRequest _remoteEmit(String event, List<Object?> args) => ServerRequest(
  rpcId: 'remote-events',
  method: 'item',
  payload: <String, Object?>{'type': 'emit', 'event': event, 'args': args},
);

ServerRequest _sessionStatusEvent(String sessionId, bool running) =>
    _remoteEmit('api-session/status', <Object?>[sessionId, running]);

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

/// A top-level pending-interaction frame (`approval/requested`,
/// `approval/resolved`, `question/requested`, `question/resolved`) — these
/// carry their fields directly on the frame payload, not inside `event`.
ServerRequest _pendingFrame(String type, JsonMap payload) => ServerRequest(
  rpcId: 'rpc-$type',
  method: type,
  payload: <String, Object?>{'type': type, ...payload},
);

// Mux-open burst frames: the legacy `session/subscribed` baseline boundary
// and the `session/queue` snapshot that follows it on the same stream. The
// 0.1.5 reference replaces the `muxFrameSchema` burst with the Session
// Controller's `SessionControlFrame` (a per-generation `baseline` plus the
// `queue` snapshot) in packages/api/session-controller/src/types.ts; the
// Gateway Remote stream wire messages are in packages/api/gateway/src/
// stream-protocol.ts.
ServerRequest _subscribedFrame(String sessionId, int lastSeq) => ServerRequest(
  rpcId: 'rpc-subscribed-$sessionId',
  method: 'session/subscribed',
  payload: <String, Object?>{
    'type': 'session/subscribed',
    'sessionId': sessionId,
    'lastSeq': lastSeq,
  },
);

ServerRequest _queueFrame(String sessionId, List<Object?> items) =>
    ServerRequest(
      rpcId: 'rpc-queue-$sessionId',
      method: 'session/queue',
      payload: <String, Object?>{
        'type': 'session/queue',
        'sessionId': sessionId,
        'items': items,
      },
    );

JsonMap _queueWireItem(String id, String text, [String placement = 'queued']) =>
    <String, Object?>{
      'id': id,
      'placement': placement,
      'message': <String, Object?>{
        'id': 'msg-$id',
        'role': 'user',
        'content': <Object?>[
          <String, Object?>{'type': 'text', 'text': text},
        ],
        'source': <String, Object?>{'kind': 'user'},
      },
    };

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
  ScriptedHarnessSocket socket, {
  void Function(AdapterDiagnostic)? onDiagnostic,
}) async {
  final manager = DshConnectionManager(socket, (_) => 10000);
  final repository = HarnessRepositoryImpl(
    rpc,
    manager,
    onDiagnostic: onDiagnostic,
  );
  await pumpEventQueue();
  return repository;
}

class HarnessFakeRpc implements DshRpcClient {
  HarnessFakeRpc([List<Object?> initialSessions = const <Object?>[]])
    : sessionsValue = initialSessions;

  final Map<String, int> _calls = <String, int>{};
  final Map<String, List<JsonMap>> _payloadsByEndpoint =
      <String, List<JsonMap>>{};
  final List<(String, RpcResult)> _receivedResponses = <(String, RpcResult)>[];

  /// Every wire name the client's registry declares, built from the
  /// [DshRpcEndpoints] constants themselves rather than a hand-maintained
  /// copy. A `rpc_map.dart` rename moves this set with it; an endpoint the
  /// repository invents outside the registry is rejected by [call].
  ///
  /// The set is closed so a call to a name not declared here fails loudly
  /// naming the offender — the client cannot drift onto 0.1.1-era singular,
  /// dotted, or otherwise vanished names without a red test.
  static const Set<String> acceptedEndpoints = <String>{
    DshRpcEndpoints.sessionList,
    DshRpcEndpoints.sessionCreate,
    DshRpcEndpoints.sessionPrompt,
    DshRpcEndpoints.sessionAttachment,
    DshRpcEndpoints.sessionCancel,
    DshRpcEndpoints.sessionSearch,
    DshRpcEndpoints.sessionRename,
    DshRpcEndpoints.sessionFork,
    DshRpcEndpoints.sessionUpdateQueue,
    DshRpcEndpoints.sessionSelectModel,
    DshRpcEndpoints.sessionModelCatalog,
    DshRpcEndpoints.sessionHistory,
    DshRpcEndpoints.sessionPage,
    DshRpcEndpoints.skillsList,
    DshRpcEndpoints.subagentsList,
    DshRpcEndpoints.subagentsPrompt,
    DshRpcEndpoints.subagentsInterrupt,
    DshRpcEndpoints.subagentsHistory,
    DshRpcEndpoints.goalsCreate,
    DshRpcEndpoints.goalsEdit,
    DshRpcEndpoints.goalsPause,
    DshRpcEndpoints.goalsResume,
    DshRpcEndpoints.goalsComplete,
    DshRpcEndpoints.goalsClear,
    DshRpcEndpoints.agentPresetsList,
    DshRpcEndpoints.agentPresetsSelect,
    DshRpcEndpoints.directoryPickerList,
    DshRpcEndpoints.directoryPickerCreate,
    DshRpcEndpoints.workspaceCreate,
    DshRpcEndpoints.workspaceRename,
    DshRpcEndpoints.workspaceDelete,
    DshRpcEndpoints.workspaceInsertBefore,
    DshRpcEndpoints.workspaceInsertSessionBefore,
    DshRpcEndpoints.workspaceArchiveSession,
    DshRpcEndpoints.workspaceFilesStat,
    DshRpcEndpoints.workspaceFilesRead,
    DshRpcEndpoints.workspaceFilesReadBytes,
    DshRpcEndpoints.workspaceFilesReadAll,
    DshRpcEndpoints.workspaceFilesList,
    DshRpcEndpoints.commandsExecute,
    DshRpcEndpoints.settingsDescribe,
    DshRpcEndpoints.settingsUpdate,
    DshRpcEndpoints.settingsReplace,
    DshRpcEndpoints.settingsMutate,
    DshRpcEndpoints.credentialsDescribe,
    DshRpcEndpoints.credentialsSet,
    DshRpcEndpoints.credentialsUnset,
    DshRpcEndpoints.llmListProviders,
    DshRpcEndpoints.llmListConfigurableProviders,
    DshRpcEndpoints.llmDiscoverModels,
    DshRpcEndpoints.eventsResult,
  };

  /// Asserts the client called a name [DshRpcEndpoints] declares. Throws a
  /// [StateError] naming the endpoint and the registry it is missing from,
  /// so a wire-name drift fails the test that provoked the call.
  void _rejectUndeclared(String endpoint) {
    if (acceptedEndpoints.contains(endpoint)) return;
    throw StateError(
      'fake host received undeclared RPC method "$endpoint"; the accepted '
      'set is derived from DshRpcEndpoints and the client may only call a '
      'name that registry declares',
    );
  }

  int callCountFor(String endpoint) => _calls[endpoint] ?? 0;

  List<JsonMap> payloads(String endpoint) {
    final raw = _payloadsByEndpoint[endpoint];
    if (raw == null || raw.isEmpty) return const <JsonMap>[];
    return raw.map((p) {
      final args = asJsonObject(p['args']) ?? p;
      final request =
          asJsonObject(args['request']) ??
          asJsonObject(args['_request']) ??
          args;
      final mergedArgs = <String, Object?>{
        ...request,
        ...args,
        if (args['agentId'] != null) 'sessionId': args['agentId'],
        if (args['sessionId'] != null) 'agentId': args['sessionId'],
        if (request != args) 'request': request,
      };
      return <String, Object?>{...p, ...mergedArgs, 'args': mergedArgs};
    }).toList();
  }

  List<(String, RpcResult)> receivedResponses() =>
      List<(String, RpcResult)>.of(_receivedResponses);

  /// One-shot scripted business failure for the next call to [endpoint],
  /// which must be the exact name the client sends.
  void failNextCall(String endpoint, String code) {
    _failures[endpoint] = code;
  }

  final Map<String, String> _failures = <String, String>{};

  /// Scripted mid-flight transport drops for the next [count]
  /// `commands/execute` calls: each throws a [DshTransportException]
  /// wrapping [cause] (a socket error by default, exactly as a real
  /// connection abort surfaces through the RPC client before any response
  /// bytes arrive). Scoped to the one retryable endpoint so repository
  /// construction (host.describe, session.list, …) never consumes them.
  int _transportDropsRemaining = 0;
  Object? _transportDropCause;

  void dropNextTransportCalls(int count, {Object? cause}) {
    _transportDropsRemaining = count;
    _transportDropCause = cause;
  }

  /// Scripted commands/execute value slot: a recorded execution shape, or
  /// null for the unmatched miss (the host answers ok with no value).
  JsonMap? commandValue = <String, Object?>{
    'commandId': 'cmd-e487ba23-1',
    'result': <String, Object?>{
      'kind': 'success',
      'text': 'Plan mode on. Use /plan off to leave.',
    },
  };

  /// Scripted subagent.list value slot: the parent's durable child tree
  /// (`reference/deepseek-harness/packages/subagent/subagent/src/`
  /// `control-types.ts` `SubagentCatalog` shape).
  JsonMap subagentListValue = <String, Object?>{
    'entries': <Object?>[],
    'parentAvailable': false,
  };

  /// Scripted child-history value slot for `session/page`
  /// (`subagentHistoryValueSchema`: the session history block shape, events
  /// plus hasMore).
  JsonMap subagentHistoryValue = <String, Object?>{
    'events': <Object?>[],
    'hasMore': false,
  };

  /// Scripted `subagents/prompt` value slot: the settled `messageId`
  /// (`packages/subagent/subagent/src/index.ts` `SubagentPromptReceipt`).
  JsonMap subagentPromptValue = <String, Object?>{
    'messageId': 'subagent-msg-1',
  };

  /// The roster served by `session.list`; a resync test rewrites it between
  /// generations to prove which response the folded state came from.
  List<Object?> sessionsValue;

  /// Scripted `session.history` events keyed by sessionId; a session absent
  /// from the map gets the default empty window.
  final Map<String, List<Object?>> historyEvents = <String, List<Object?>>{};

  /// Scripted projections block for `session.history` keyed by sessionId.
  final Map<String, JsonMap> historyProjections = <String, JsonMap>{};

  /// Scripted `hasMore` for `session.history` keyed by sessionId.
  final Map<String, bool> historyHasMore = <String, bool>{};

  /// One-shot response holds: the next response for the key waits on the
  /// value before answering (each hold releases at most once).
  final Map<String, List<Future<void>>> _responseGates =
      <String, List<Future<void>>>{};

  /// Endpoints whose hold expired (witness never appeared) — an expired hold
  /// means the awaited call overlap never happened.
  final List<String> gateTimeouts = <String>[];

  /// Completers fired (after arming) when an endpoint is called.
  final Map<String, List<Completer<void>>> _callWitnesses =
      <String, List<Completer<void>>>{};

  /// `endpoint:start` / `endpoint:return` entries in arrival order: pins
  /// which calls were simultaneously in flight.
  final List<String> callJournal = <String>[];

  /// Holds every further response of [endpoint] until [witness] is called
  /// (bounded at 5s; expiry records into [gateTimeouts]). Two endpoints
  /// gated on each other deadlock under a serial caller and settle under a
  /// concurrent one — the resync fan-out witness.
  void gateResponsesUntilCalled(String endpoint, String witness) {
    final waiter = Completer<void>();
    _callWitnesses.putIfAbsent(witness, () => <Completer<void>>[]).add(waiter);
    _responseGates
        .putIfAbsent(endpoint, () => <Future<void>>[])
        .add(
          waiter.future.timeout(
            const Duration(seconds: 5),
            onTimeout: () {
              gateTimeouts.add(endpoint);
            },
          ),
        );
  }

  /// Holds the next [count] responses of [endpoint] until [gate] completes.
  void gateResponses(String endpoint, Future<void> gate, {int count = 1}) {
    final gates = _responseGates.putIfAbsent(endpoint, () => <Future<void>>[]);
    for (var i = 0; i < count; i++) {
      gates.add(gate);
    }
  }

  @override
  Future<RpcResult> call(
    String endpoint,
    String method,
    JsonMap payload, {
    Duration? timeout,
  }) async {
    _rejectUndeclared(endpoint);
    _calls[endpoint] = (_calls[endpoint] ?? 0) + 1;
    _payloadsByEndpoint.putIfAbsent(endpoint, () => <JsonMap>[]).add(payload);
    callJournal.add('$endpoint:start');
    final witnesses = _callWitnesses.remove(endpoint);
    if (witnesses != null) {
      for (final waiter in witnesses) {
        if (!waiter.isCompleted) waiter.complete();
      }
    }
    final gates = _responseGates[endpoint];
    if (gates != null && gates.isNotEmpty) {
      await gates.removeAt(0);
    }
    try {
      return await _answer(endpoint, payload);
    } finally {
      callJournal.add('$endpoint:return');
    }
  }

  Future<RpcResult> _answer(String endpoint, JsonMap payload) async {
    if (endpoint == 'commands/execute' && _transportDropsRemaining > 0) {
      _transportDropsRemaining--;
      throw DshTransportException(
        'transport failure for $endpoint',
        _transportDropCause ??
            const SocketException('Software caused connection abort'),
      );
    }
    final failureCode = _failures.remove(endpoint);
    if (failureCode != null) {
      if (failureCode == '404') {
        throw DshTransportException('HTTP 404 for api/$endpoint: not found');
      }
      return RpcResult(
        ok: false,
        error: RpcError(
          code: failureCode,
          message: 'scripted failure: $failureCode',
        ),
      );
    }
    if (endpoint == DshRpcEndpoints.commandsExecute) {
      return RpcResult(ok: true, value: commandValue);
    }
    final value = _valueFor(endpoint, payload);
    return RpcResult(ok: true, value: value);
  }

  JsonMap _valueFor(String endpoint, JsonMap payload) {
    final args = asJsonObject(payload['args']) ?? payload;
    final request =
        asJsonObject(args['request']) ?? asJsonObject(args['_request']) ?? args;
    switch (endpoint) {
      case DshRpcEndpoints.sessionList:
        return <String, Object?>{'items': sessionsValue};
      case DshRpcEndpoints.subagentsList:
        return subagentListValue;
      case DshRpcEndpoints.subagentsHistory:
        return subagentHistoryValue;
      case DshRpcEndpoints.subagentsPrompt:
        return subagentPromptValue;
      case DshRpcEndpoints.subagentsInterrupt:
        return <String, Object?>{'receipt': true};
      case DshRpcEndpoints.workspaceInsertBefore:
        return <String, Object?>{
          'workspaceIds': <Object?>['ws-b', 'ws-a', 'ws-c'],
        };
      case DshRpcEndpoints.sessionHistory:
      case DshRpcEndpoints.sessionPage:
        final address = asJsonObject(request['address']);
        if (address?['kind'] == 'subagent') {
          return subagentHistoryValue;
        }
        // History entries ride the `historyEntrySchema` envelope: the log
        // event nests under 'event' (sessions.schema.ts).
        final sessionId =
            (address?['sessionId'] ??
                    request['sessionId'] ??
                    args['sessionId'] ??
                    payload['sessionId'])
                as String?;
        final scripted = historyEvents[sessionId];
        final scriptedProjections = historyProjections[sessionId];
        final records = (scripted ?? <Object?>[])
            .map((event) => <String, Object?>{'type': 'event', 'event': event})
            .toList();
        return <String, Object?>{
          'events': records,
          'records': records,
          'hasMore': historyHasMore[sessionId] ?? false,
          if (scriptedProjections != null)
            'projections': scriptedProjections
          else
            'projections': <String, Object?>{
              'values': <String, Object?>{
                'plan': <String, Object?>{'active': false, 'pending': true},
              },
            },
        };
      case DshRpcEndpoints.sessionAttachment:
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
      case DshRpcEndpoints.workspaceInsertSessionBefore:
        return <String, Object?>{
          'workspace': _workspaceJson('ws-a', '/a', 'A', <String>[
            's2',
            's3',
            's1',
          ]),
        };
      case DshRpcEndpoints.skillsList:
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
      case DshRpcEndpoints.directoryPickerList:
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
      case DshRpcEndpoints.directoryPickerCreate:
        return <String, Object?>{'path': '/tmp/chosen/new-folder'};
      case DshRpcEndpoints.settingsDescribe:
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
      case DshRpcEndpoints.credentialsDescribe:
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
      case DshRpcEndpoints.settingsUpdate:
      case DshRpcEndpoints.settingsReplace:
      case DshRpcEndpoints.settingsMutate:
        return <String, Object?>{
          'ns': 'llm-deepseek',
          'value': <String, Object?>{},
          'user': <String, Object?>{'touched': true},
          'applies': 'live',
          'secrets': <Object?>[],
          'revision': 3,
        };
      case DshRpcEndpoints.goalsEdit:
        return <String, Object?>{
          'ref': <String, Object?>{'id': 'goal-1', 'revision': 2},
        };
      case DshRpcEndpoints.agentPresetsList:
        // Fixture transcribed from
        // reference/deepseek-harness/packages/preset/agent-presets/src/
        // types.ts AgentPresetRoster.
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
      case DshRpcEndpoints.agentPresetsSelect:
        return <String, Object?>{'agentPreset': 'minimal'};
      case DshRpcEndpoints.sessionModelCatalog:
        return <String, Object?>{
          'defaultSelection': <String, Object?>{
            'provider': 'deepseek',
            'model': 'glm-x',
          },
          'entries': <Object?>[],
        };
      default:
        return <String, Object?>{};
    }
  }

  @override
  Future<void> respond(String rpcId, RpcResult result) async {
    _receivedResponses.add((rpcId, result));
  }
}

/// The `$events` registration answer the gateway sends over `/api/remote.mux`
/// (`reference/deepseek-harness/packages/api/gateway/src/stream-protocol.ts`
/// `RemoteEventReadyFrame` -> `RemoteEventHostInfo`); it is the connection
/// generation handshake.
ServerRequest _readyFrame([String home = '/home/tester']) => ServerRequest(
  rpcId: 'remote-events',
  method: 'item',
  payload: <String, Object?>{
    'type': 'ready',
    'clientId': 'client-1',
    'host': <String, Object?>{'home': home},
  },
);

class ScriptedHarnessSocket implements DshEventSocket {
  ScriptedHarnessSocket({this.muxFrames = const <ServerRequest>[]});

  final List<ServerRequest> muxFrames;
  final Completer<void> _muxRelease = Completer<void>();
  final List<String> _paths = <String>[];

  List<String> get connectedPaths => List<String>.of(_paths);

  void releaseMuxFrames() {
    if (!_muxRelease.isCompleted) _muxRelease.complete();
  }

  @override
  Stream<ServerRequest> connect(String path, {void Function()? onOpen}) async* {
    _paths.add(path);
    onOpen?.call();
    // The generation handshake settles before the scripted frames land.
    yield _readyFrame();
    await _muxRelease.future;
    for (final frame in muxFrames) {
      yield frame;
    }
    // awaitCancellation: stay open until the subscriber cancels.
    await Completer<void>().future;
  }
}

const String _muxPath = '/api/remote.mux';

/// A socket seam that can end the current generation: closing the downlink
/// stream drives [DshConnectionManager] into its reconnect loop, so the next
/// generation connects and the repository resyncs exactly as on a real
/// resume. Frames flow through the per-generation controller.
class ReconnectableHarnessSocket implements DshEventSocket {
  final Map<String, StreamController<ServerRequest>> _open =
      <String, StreamController<ServerRequest>>{};
  final List<String> _paths = <String>[];

  /// How many times the mux downlink was opened (1 per generation).
  int get downlinksOpened => _paths.length;

  List<String> get connectedPaths => List<String>.of(_paths);

  /// When set, each generation's `ready` frame waits on this gate before it
  /// is delivered, so a test can pin the mux-open burst relative to the
  /// connected publish.
  Completer<void>? readyGate;

  @override
  Stream<ServerRequest> connect(String path, {void Function()? onOpen}) {
    final controller = StreamController<ServerRequest>();
    _paths.add(path);
    _open[path] = controller;
    onOpen?.call();
    // Register the generation before any scripted frame arrives.
    final gate = readyGate;
    if (gate == null) {
      controller.add(_readyFrame());
    } else {
      unawaited(() async {
        await gate.future;
        if (!controller.isClosed) controller.add(_readyFrame());
      }());
    }
    return controller.stream;
  }

  void emitMuxFrame(ServerRequest frame) => _open[_muxPath]?.add(frame);

  /// Ends every current downlink; the manager counts that as generation
  /// loss and reconnects after its backoff.
  void terminate() {
    for (final controller in _open.values.toList()) {
      unawaited(controller.close());
    }
    _open.clear();
  }
}

JsonMap resyncSessionRow(String id) => <String, Object?>{
  'sessionId': id,
  'updatedAt': 3,
  'running': false,
  'blank': false,
};

JsonMap resyncAssistantTextEvent(int seq, String text) => <String, Object?>{
  'type': 'assistant/message',
  'seq': seq,
  'time': seq,
  'data': <String, Object?>{
    'turn': 1,
    'step': 1,
    'message': <String, Object?>{
      'id': 'assistant-$seq',
      'role': 'assistant',
      'content': <Object?>[
        <String, Object?>{'type': 'text', 'text': text},
      ],
    },
  },
};

/// A repository on a reconnect-capable socket with zero backoff: each
/// [ReconnectableHarnessSocket.terminate] drives one fresh connection
/// generation (and with it one repository resync) in tests.
Future<HarnessRepositoryImpl> resyncFixture(
  HarnessFakeRpc rpc,
  ReconnectableHarnessSocket socket, {
  void Function(AdapterDiagnostic)? onDiagnostic,
}) async {
  final manager = DshConnectionManager(socket, (_) => 0);
  final repository = HarnessRepositoryImpl(
    rpc,
    manager,
    onDiagnostic: onDiagnostic,
  );
  await pumpEventQueue();
  await Future<void>.delayed(const Duration(milliseconds: 20));
  await pumpEventQueue();
  return repository;
}

class _DiagnosticTestConnectionManager extends DshConnectionManager {
  _DiagnosticTestConnectionManager(DshEventSocket socket)
    : super(socket, (_) => 10000);

  final StreamController<ServerRequest> testMuxFrames =
      StreamController<ServerRequest>.broadcast();

  @override
  Stream<ServerRequest> get muxFrames => testMuxFrames.stream;

  void dispose() {
    stop();
    unawaited(testMuxFrames.close());
  }
}

void main() {
  test(
    'fake host rejects an RPC method the registry does not declare',
    () async {
      // Guarding the guard: the accepted set is closed, so a future client
      // drift onto a vanished 0.1.1-era name (singular namespace, dotted
      // separator) fails the test that provoked the call instead of quietly
      // resolving to a canonical endpoint.
      final rpc = HarnessFakeRpc();
      await expectLater(
        rpc.call('skill/list', 'skill/list', <String, Object?>{}),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            allOf(contains('skill/list'), contains('DshRpcEndpoints')),
          ),
        ),
      );
      await expectLater(
        rpc.call('subagent.prompt', 'subagent.prompt', <String, Object?>{}),
        throwsA(isA<StateError>()),
      );
      // A declared name still answers its scripted value.
      final result = await rpc.call(
        DshRpcEndpoints.sessionList,
        DshRpcEndpoints.sessionList,
        <String, Object?>{},
      );
      expect(result.ok, isTrue);
      expect(rpc.callCountFor(DshRpcEndpoints.sessionList), 1);
    },
  );

  test('the connection path reaches CONNECTED without an RPC outside the '
      'registry', () async {
    // The generation handshake is the mux `$events` ready frame, not a
    // unary probe: [HarnessFakeRpc] rejects every wire name
    // [DshRpcEndpoints] does not declare, so a client still reaching for
    // `host/describe` — or any other vanished name — would throw here
    // instead of connecting. The resync that follows exercises the guard
    // through declared names only.
    final rpc = HarnessFakeRpc();
    final socket = ScriptedHarnessSocket();
    final manager = DshConnectionManager(socket, (_) => 10000);
    final repository = HarnessRepositoryImpl(rpc, manager);
    addTearDown(repository.dispose);
    await pumpEventQueue();

    expect(manager.state.value.phase, ConnectionPhase.connected);
    expect(manager.hostDescription.value?.home, '/home/tester');
    expect(manager.hostDescription.value?.version, isNull);
    await pumpEventQueue();
    expect(
      rpc.callCountFor(DshRpcEndpoints.sessionList),
      greaterThanOrEqualTo(1),
    );
  });

  test('primary endpoint 404 fails loud without legacy fallbacks', () async {
    final rpc = HarnessFakeRpc();
    rpc.failNextCall(DshRpcEndpoints.skillsList, '404');
    final repository = await harnessRepository(rpc, ScriptedHarnessSocket());
    await pumpEventQueue();

    expect(
      () => repository.listSkills('session-1'),
      throwsA(isA<DshTransportException>()),
    );
    expect(rpc.callCountFor(DshRpcEndpoints.skillsList), 1);
  });

  test('settings/describe 404 fails loud without legacy fallbacks', () async {
    final rpc = HarnessFakeRpc();
    rpc.failNextCall(DshRpcEndpoints.settingsDescribe, '404');
    final repository = await harnessRepository(rpc, ScriptedHarnessSocket());
    await pumpEventQueue();

    expect(
      () => repository.describeSettings(),
      throwsA(isA<DshTransportException>()),
    );
    expect(rpc.callCountFor(DshRpcEndpoints.settingsDescribe), 1);
  });

  test(
    'loadModels strips arguments for canonical session/modelCatalog',
    () async {
      final rpc = HarnessFakeRpc();
      final repository = await harnessRepository(rpc, ScriptedHarnessSocket());
      await pumpEventQueue();

      final models = await repository.loadModels('session-1');
      expect(models.current.model, 'glm-x');
      expect(rpc.callCountFor(DshRpcEndpoints.sessionModelCatalog), 1);
      final payloads = rpc.payloads(DshRpcEndpoints.sessionModelCatalog);
      expect(payloads, isNotEmpty);
      expect(payloads.first['args'], isEmpty);
    },
  );

  test(
    'session/page with past-cursor error triggers auto-discovery and retries',
    () async {
      final rpc = HarnessFakeRpc(<Object?>[
        <String, Object?>{
          'sessionId': 'session-1',
          'updatedAt': 3,
          'running': false,
          'blank': false,
        },
      ]);
      rpc.historyEvents['session-1'] = <JsonMap>[
        <String, Object?>{
          'type': 'user/message',
          'seq': 42,
          'time': 42,
          'data': <String, Object?>{
            'id': 'msg-1',
            'role': 'user',
            'source': <String, Object?>{'kind': 'user'},
            'content': <Object?>[
              <String, Object?>{'type': 'text', 'text': 'restored text'},
            ],
          },
        },
      ];
      // Simulate DSH 0.1.2 server throwing when throughSeq (999999999) exceeds cursor 42
      rpc.failNextCall(
        DshRpcEndpoints.sessionPage,
        'gateway/bad-request: session page through seq 999999999 is past cursor 42',
      );
      final repository = await harnessRepository(rpc, ScriptedHarnessSocket());
      await pumpEventQueue();

      await repository.openSession('session-1');
      await pumpEventQueue();

      final window = await repository
          .observeTimelineWindow('session-1')
          .firstWhere((w) => !w.isLoading && w.items.isNotEmpty);
      expect(window.items, hasLength(1));
      final msg = window.items.first as TimelineMessage;
      expect(msg.value.text, 'restored text');
      // Verify retry occurred with discovered cursor 42
      final pageCalls = rpc.payloads(DshRpcEndpoints.sessionPage);
      expect(pageCalls, hasLength(2));
      final retryReq = asJsonObject(pageCalls.last['args'])?['request'] as Map?;
      expect(retryReq?['throughSeq'], 42);
    },
  );

  test(r'a 0.1.2 forwarded waterfall opens the decision card and answers through $events/result', () async {
    // DSH 0.1.2 never sends the 0.1.1 `question/requested` /
    // `approval/requested` mux frames: an interactive decision arrives as an
    // Agent-scoped waterfall on the `$events` forwarded-event stream, and
    // the client answers by returning the listener's value through
    // `$events/result`. Without this path a live question had no card at all.
    final rpc = HarnessFakeRpc(<Object?>[resyncSessionRow('session-ask')]);
    rpc.historyEvents['session-ask'] = <JsonMap>[
      resyncAssistantTextEvent(1, 'working'),
    ];
    final socket = ScriptedHarnessSocket(
      muxFrames: <ServerRequest>[
        ServerRequest(
          rpcId: 'remote-events',
          method: 'item',
          payload: <String, Object?>{
            'type': 'ready',
            'clientId': 'client-7',
            'host': <String, Object?>{'home': '/home/user'},
          },
        ),
        ServerRequest(
          rpcId: 'remote-events',
          method: 'item',
          payload: <String, Object?>{
            'type': 'waterfall',
            'event': 'user-questions/request',
            'eventId': 'evt-q1',
            'agentId': 'session-ask',
            'request': <String, Object?>{
              'questions': <Object?>[
                <String, Object?>{
                  'id': 'q1',
                  'header': 'Deploy',
                  'question': 'Which backend?',
                  'options': <Object?>[
                    <String, Object?>{'label': 'local'},
                    <String, Object?>{'label': 'remote'},
                  ],
                },
              ],
            },
          },
        ),
        ServerRequest(
          rpcId: 'remote-events',
          method: 'item',
          payload: <String, Object?>{
            'type': 'waterfall',
            'event': 'approval/request',
            'eventId': 'evt-a1',
            'agentId': 'session-ask',
            'request': <String, Object?>{
              'toolName': 'bash',
              'callId': 'call-9',
              'reason': 'run the migration',
            },
          },
        ),
      ],
    );
    final repository = HarnessRepositoryImpl(
      rpc,
      DshConnectionManager(socket, (_) => 10000),
    );
    addTearDown(repository.dispose);
    await pumpEventQueue();

    socket.releaseMuxFrames();
    await pumpEventQueue();
    await repository.openSession('session-ask');
    await pumpEventQueue();

    final window = await repository
        .observeTimelineWindow('session-ask')
        .firstWhere(
          (w) =>
              w.items.whereType<TimelineQuestionRequest>().isNotEmpty &&
              w.items.whereType<TimelineApprovalRequest>().isNotEmpty,
        );
    final question = window.items.whereType<TimelineQuestionRequest>().single;
    expect(question.requestId, 'evt-q1');
    expect(question.questions.single.question, 'Which backend?');
    final approval = window.items.whereType<TimelineApprovalRequest>().single;
    expect(approval.approvalId, 'evt-a1');
    expect(approval.toolName, 'bash');
    expect(approval.reason, 'run the migration');

    // The answer returns the waterfall's value, binding the stream's client
    // id and the request's own event id.
    await repository.answerQuestions(
      'evt-q1',
      const QuestionEvidence(
        sessionId: 'session-ask',
        answers: <QuestionAnswer>[
          QuestionAnswer(questionId: 'q1', selectedOptions: <String>['remote']),
        ],
      ),
    );
    await pumpEventQueue();
    final answerCall = rpc
        .payloads(DshRpcEndpoints.eventsResult)
        .map((payload) => asJsonObject(payload['args']) ?? payload)
        .single;
    expect(answerCall['clientId'], 'client-7');
    expect(answerCall['eventId'], 'evt-q1');
    expect(answerCall['outcome'], <String, Object?>{
      'kind': 'result',
      'value': <String, Object?>{
        'answers': <Object?>[
          <String, Object?>{
            'id': 'q1',
            'selected': <Object?>['remote'],
          },
        ],
      },
    });

    await repository.respondToApproval(
      const ApprovalAnswer(
        requestId: 'evt-a1',
        sessionId: 'session-ask',
        approvalId: 'evt-a1',
        allowed: false,
      ),
    );
    await pumpEventQueue();
    final approvalCall = rpc
        .payloads(DshRpcEndpoints.eventsResult)
        .map((payload) => asJsonObject(payload['args']) ?? payload)
        .last;
    expect(approvalCall['eventId'], 'evt-a1');
    expect(approvalCall['outcome'], <String, Object?>{
      'kind': 'result',
      'value': 'rejected',
    });

    // Answering settles the card locally too: the host's own resolution
    // frame is not guaranteed to follow an answered waterfall.
    final settled = repository.observeTimelineWindow('session-ask').first;
    await pumpEventQueue();
    expect((await settled).items.whereType<TimelineApprovalRequest>(), isEmpty);
  });

  test('a cancelled forwarded waterfall withdraws its card', () async {
    // The host ends an unanswered request's lifetime (the turn was cancelled,
    // the Agent scope went away): a `cancel` item names the event, and the
    // card leaves the transcript with the pending projection.
    final rpc = HarnessFakeRpc(<Object?>[resyncSessionRow('session-cancel')]);
    rpc.historyEvents['session-cancel'] = <JsonMap>[];
    final socket = ReconnectableHarnessSocket();
    final repository = await resyncFixture(rpc, socket);
    addTearDown(repository.dispose);
    await repository.openSession('session-cancel');
    await pumpEventQueue();

    socket
      ..emitMuxFrame(
        ServerRequest(
          rpcId: 'remote-events',
          method: 'item',
          payload: <String, Object?>{
            'type': 'ready',
            'clientId': 'client-7',
            'host': <String, Object?>{'home': '/home/user'},
          },
        ),
      )
      ..emitMuxFrame(
        ServerRequest(
          rpcId: 'remote-events',
          method: 'item',
          payload: <String, Object?>{
            'type': 'waterfall',
            'event': 'user-questions/request',
            'eventId': 'evt-q2',
            'agentId': 'session-cancel',
            'request': <String, Object?>{
              'questions': <Object?>[
                <String, Object?>{'id': 'q1', 'question': 'Continue?'},
              ],
            },
          },
        ),
      );
    await pumpEventQueue();

    expect(
      (await repository.observeTimelineWindow('session-cancel').first).items
          .whereType<TimelineQuestionRequest>(),
      hasLength(1),
    );

    socket.emitMuxFrame(
      ServerRequest(
        rpcId: 'remote-events',
        method: 'item',
        payload: <String, Object?>{'type': 'cancel', 'eventId': 'evt-q2'},
      ),
    );
    await pumpEventQueue();

    expect(
      (await repository.observeTimelineWindow('session-cancel').first).items
          .whereType<TimelineQuestionRequest>(),
      isEmpty,
    );
  });

  test(
    'a forked session keeps its root window: lineage is not a subagent mark',
    () async {
      // `session/fork` gives the child its source's parentSessionId lineage
      // while the session stays one the reader chats in; only the host's
      // `origin: 'subagent'` marks a child transcript. Treating lineage as a
      // subagent mark left a forked session with no history, no follow stream
      // and therefore no question/approval card.
      final rpc = HarnessFakeRpc(<Object?>[
        <String, Object?>{
          'sessionId': 'session-fork',
          'parentSessionId': 'session-source',
          'updatedAt': 1,
          'running': false,
          'blank': false,
        },
      ]);
      rpc.historyEvents['session-fork'] = <JsonMap>[
        resyncAssistantTextEvent(1, 'forked transcript'),
      ];
      final diagnostics = <AdapterDiagnostic>[];
      final repository = HarnessRepositoryImpl(
        rpc,
        DshConnectionManager(ScriptedHarnessSocket(), (_) => 10000),
        onDiagnostic: diagnostics.add,
      );
      addTearDown(repository.dispose);
      await pumpEventQueue();

      await repository.openSession('session-fork');
      await pumpEventQueue();

      final window = await repository
          .observeTimelineWindow('session-fork')
          .firstWhere((w) => w.items.isNotEmpty);
      expect(window.items, hasLength(1));
      expect(rpc.payloads(DshRpcEndpoints.sessionPage), isNotEmpty);
      expect(
        diagnostics.where((d) => d.context == 'session.open'),
        isEmpty,
        reason: 'a forked session is not a subagent child',
      );
    },
  );

  test(
    'session/page with empty session past-cursor -1 recovers empty page',
    () async {
      final rpc = HarnessFakeRpc(<Object?>[
        <String, Object?>{
          'sessionId': 'session-empty',
          'updatedAt': 1,
          'running': false,
          'blank': true,
        },
      ]);
      rpc.historyEvents['session-empty'] = <JsonMap>[];
      rpc.failNextCall(
        DshRpcEndpoints.sessionPage,
        'gateway/bad-request: session page through seq 999999999 is past cursor -1',
      );
      final repository = await harnessRepository(rpc, ScriptedHarnessSocket());
      await pumpEventQueue();

      await repository.openSession('session-empty');
      await pumpEventQueue();

      final window = await repository
          .observeTimelineWindow('session-empty')
          .first;
      expect(window.items, isEmpty);
      final pageCalls = rpc.payloads(DshRpcEndpoints.sessionPage);
      expect(pageCalls, hasLength(2));
      final retryReq = asJsonObject(pageCalls.last['args'])?['request'] as Map?;
      expect(retryReq?['throughSeq'], -1);
    },
  );

  test('session.list seeds initial contextPressure and breakdown into session state', () async {
    final rpc = HarnessFakeRpc(<Object?>[
      <String, Object?>{
        'sessionId': 'session-seed',
        'updatedAt': 3,
        'running': false,
        'blank': false,
        'projections': <String, Object?>{
          'asOfSeq': 10,
          'values': <String, Object?>{
            'contextPressure': <String, Object?>{
              'pressureTokens': 1500,
              'projectedTokens': 1600,
              'contextWindow': 128000,
            },
            'contextBreakdown': <String, Object?>{
              'systemTokens': 500,
              'toolsTokens': 800,
              'messageTokens': 200,
            },
          },
        },
      },
    ]);
    final repository = await harnessRepository(rpc, ScriptedHarnessSocket());
    await pumpEventQueue();

    final pressure = await repository
        .observeContextPressure('session-seed')
        .first;
    expect(pressure, isNotNull);
    expect(pressure?.pressureTokens, 1500);
    expect(pressure?.projectedTokens, 1600);
    expect(pressure?.contextWindow, 128000);

    final breakdown = await repository
        .observeContextBreakdown('session-seed')
        .first;
    expect(breakdown, isNotNull);
    expect(breakdown?.systemTokens, 500);
    expect(breakdown?.toolsTokens, 800);
    expect(breakdown?.messageTokens, 200);
  });

  test(
    'session-control baseline and live projection frame update contextPressure',
    () async {
      final rpc = HarnessFakeRpc(<Object?>[
        <String, Object?>{
          'sessionId': 'session-ctrl',
          'updatedAt': 1,
          'running': false,
          'blank': false,
        },
      ]);
      final socket = ScriptedHarnessSocket(
        muxFrames: <ServerRequest>[
          ServerRequest(
            rpcId: 'session-control',
            method: 'session/control',
            payload: <String, Object?>{
              'type': 'baseline',
              'value': <String, Object?>{
                'projections': <String, Object?>{
                  'session-ctrl': <String, Object?>{
                    'asOfSeq': 5,
                    'values': <String, Object?>{
                      'contextPressure': <String, Object?>{
                        'pressureTokens': 2000,
                        'projectedTokens': 2200,
                        'contextWindow': 64000,
                      },
                    },
                  },
                },
              },
            },
          ),
          ServerRequest(
            rpcId: 'session-control',
            method: 'session/control',
            payload: <String, Object?>{
              'type': 'projection',
              'sessionId': 'session-ctrl',
              'key': 'contextPressure',
              'seq': 6,
              'value': <String, Object?>{
                'pressureTokens': 3000,
                'projectedTokens': 3200,
                'contextWindow': 64000,
              },
            },
          ),
        ],
      );
      final repository = await harnessRepository(rpc, socket);
      await pumpEventQueue();

      socket.releaseMuxFrames();
      await pumpEventQueue();

      final pressure = await repository
          .observeContextPressure('session-ctrl')
          .firstWhere((p) => p?.pressureTokens == 3000);
      expect(pressure?.pressureTokens, 3000);
      expect(pressure?.projectedTokens, 3200);
    },
  );

  test(
    'diagnostic callback receives error on malformed projection decode',
    () async {
      final diagnostics = <AdapterDiagnostic>[];
      final rpc = HarnessFakeRpc(<Object?>[
        <String, Object?>{
          'sessionId': 'session-bad',
          'updatedAt': 1,
          'running': false,
          'blank': false,
        },
      ]);
      final socket = ScriptedHarnessSocket(
        muxFrames: <ServerRequest>[
          ServerRequest(
            rpcId: 'session-control',
            method: 'session/control',
            payload: <String, Object?>{
              'type': 'projection',
              'sessionId': 'session-bad',
              'key': 'contextPressure',
              'seq': 1,
              'value': 'not-a-map',
            },
          ),
        ],
      );
      HarnessRepositoryImpl(
        rpc,
        DshConnectionManager(socket, exponentialDshBackoffDelay),
        onDiagnostic: diagnostics.add,
      );
      await pumpEventQueue();

      socket.releaseMuxFrames();
      await pumpEventQueue();

      expect(diagnostics, isNotEmpty);
      expect(
        diagnostics.any((d) => d.message.contains('contextPressure')),
        isTrue,
      );
    },
  );

  test('_collectMuxFrames stream error emits diagnostic', () async {
    final diagnostics = <AdapterDiagnostic>[];
    final rpc = HarnessFakeRpc();
    final socket = ScriptedHarnessSocket();
    final manager = _DiagnosticTestConnectionManager(socket);
    final repository = HarnessRepositoryImpl(
      rpc,
      manager,
      onDiagnostic: diagnostics.add,
    );
    addTearDown(repository.dispose);
    addTearDown(manager.dispose);
    await pumpEventQueue();

    final testError = Exception('simulated mux stream failure');
    manager.testMuxFrames.addError(testError);
    await pumpEventQueue();

    expect(diagnostics, isNotEmpty);
    final diag = diagnostics.firstWhere((d) => d.context == 'mux.stream');
    expect(diag.level, AdapterDiagnosticLevel.error);
    expect(diag.message, 'mux stream error: $testError');
    expect(diag.error, equals(testError));
    expect(diag.stackTrace, isNotNull);
  });

  test('handleFrame error emits diagnostic', () async {
    final diagnostics = <AdapterDiagnostic>[];
    final rpc = HarnessFakeRpc(<Object?>[
      resyncSessionRow('session-test-frame'),
    ]);
    final socket = ScriptedHarnessSocket();
    final manager = _DiagnosticTestConnectionManager(socket);
    final repository = HarnessRepositoryImpl(
      rpc,
      manager,
      onDiagnostic: diagnostics.add,
    );
    addTearDown(repository.dispose);
    addTearDown(manager.dispose);
    await pumpEventQueue();

    await repository.openSession('session-test-frame');
    await pumpEventQueue();

    manager.testMuxFrames.add(
      ServerRequest(
        rpcId: 'rpc-bad-frame',
        method: 'session/queue',
        payload: <String, Object?>{
          'type': 'session/queue',
          'sessionId': 'session-test-frame',
        },
      ),
    );
    await pumpEventQueue();

    expect(diagnostics, isNotEmpty);
    final diag = diagnostics.firstWhere((d) => d.context == 'session.frame');
    expect(diag.level, AdapterDiagnosticLevel.error);
    expect(
      diag.message,
      contains('handleFrame failed for session-test-frame:'),
    );
    expect(diag.error, isA<FormatException>());
    expect(diag.stackTrace, isNotNull);
  });

  test('refreshSessions failure emits diagnostic', () async {
    final diagnostics = <AdapterDiagnostic>[];
    final rpc = HarnessFakeRpc(<Object?>[
      resyncSessionRow('session-refresh-test'),
    ]);
    final socket = ScriptedHarnessSocket();
    final manager = _DiagnosticTestConnectionManager(socket);
    final repository = HarnessRepositoryImpl(
      rpc,
      manager,
      onDiagnostic: diagnostics.add,
    );
    addTearDown(repository.dispose);
    addTearDown(manager.dispose);
    await pumpEventQueue();

    // 1. turn/end triggers refreshSessions
    rpc.failNextCall(DshRpcEndpoints.sessionList, 'turn-end-fail');
    manager.testMuxFrames.add(
      ServerRequest(
        rpcId: 'session-follow-session-refresh-test',
        method: 'session/event',
        payload: <String, Object?>{
          'type': 'session/event',
          'event': <String, Object?>{'type': 'turn/end'},
        },
      ),
    );
    await pumpEventQueue();

    expect(
      diagnostics.any(
        (d) =>
            d.context == 'session.refresh' &&
            d.level == AdapterDiagnosticLevel.warning &&
            d.message.contains('refreshSessions failed after turn end:'),
      ),
      isTrue,
    );

    // 3. workspace upsert triggers refreshSessions
    rpc.failNextCall(DshRpcEndpoints.sessionList, 'workspace-fail');
    manager.testMuxFrames.add(
      ServerRequest(
        rpcId: 'workspace-follow',
        method: 'workspace/follow',
        payload: <String, Object?>{
          'type': 'upsert',
          'workspace': _workspaceJson('ws-test', '/path', 'Test Workspace'),
        },
      ),
    );
    await pumpEventQueue();

    expect(
      diagnostics.any(
        (d) =>
            d.context == 'workspace.refresh' &&
            d.level == AdapterDiagnosticLevel.warning &&
            d.message.contains('refreshSessions failed on workspace upsert:'),
      ),
      isTrue,
    );
  });

  test('resync failures emit diagnostic for list and ensureLoaded', () async {
    final diagnostics = <AdapterDiagnostic>[];
    final rpc = HarnessFakeRpc(<Object?>[
      resyncSessionRow('session-resync-diag'),
    ]);
    final socket = ReconnectableHarnessSocket();
    final manager = DshConnectionManager(socket, (_) => 0);
    final repository = HarnessRepositoryImpl(
      rpc,
      manager,
      onDiagnostic: diagnostics.add,
    );
    addTearDown(repository.dispose);
    await pumpEventQueue();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await pumpEventQueue();

    await repository.openSession('session-resync-diag');
    await pumpEventQueue();

    // Cause list refresh and history page to fail on reconnect resync
    rpc.failNextCall(DshRpcEndpoints.sessionList, 'resync-list-fail');
    rpc.failNextCall(DshRpcEndpoints.sessionPage, 'resync-page-fail');

    socket.terminate();
    await pumpEventQueue();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await pumpEventQueue();

    expect(
      diagnostics.any(
        (d) =>
            d.context == 'resync.list' &&
            d.level == AdapterDiagnosticLevel.warning &&
            d.message.contains('resync list refresh failed:'),
      ),
      isTrue,
    );
    expect(
      diagnostics.any(
        (d) =>
            d.context == 'resync.session' &&
            d.level == AdapterDiagnosticLevel.warning &&
            d.message.contains(
              'resync ensureLoaded failed for session-resync-diag:',
            ),
      ),
      isTrue,
    );
  });

  test('loadOlderHistory error emits diagnostic', () async {
    final diagnostics = <AdapterDiagnostic>[];
    final rpc = HarnessFakeRpc(<Object?>[
      resyncSessionRow('session-older-test'),
    ]);
    rpc.historyEvents['session-older-test'] = <Object?>[
      resyncAssistantTextEvent(10, 'first batch message'),
    ];
    rpc.historyHasMore['session-older-test'] = true;

    final socket = ScriptedHarnessSocket();
    final repository = HarnessRepositoryImpl(
      rpc,
      DshConnectionManager(socket, (_) => 10000),
      onDiagnostic: diagnostics.add,
    );
    addTearDown(repository.dispose);
    await pumpEventQueue();

    await repository.openSession('session-older-test');
    await pumpEventQueue();

    rpc.failNextCall(DshRpcEndpoints.sessionPage, 'history-page-error');
    final success = await repository.loadOlderHistory('session-older-test');

    expect(success, isFalse);
    expect(diagnostics, isNotEmpty);
    final diag = diagnostics.firstWhere((d) => d.context == 'session.history');
    expect(diag.level, AdapterDiagnosticLevel.error);
    expect(
      diag.message,
      contains('loadOlderHistory failed for session-older-test:'),
    );
    expect(diag.error, isA<DshBusinessException>());
    expect(diag.stackTrace, isNotNull);
  });

  test(
    'the workspace roster arrives on workspace/follow with no unary pull',
    () async {
      final rpc = HarnessFakeRpc();
      final socket = ScriptedHarnessSocket(
        muxFrames: <ServerRequest>[
          ServerRequest(
            rpcId: 'workspace-follow',
            method: 'workspace/follow',
            payload: <String, Object?>{
              'type': 'baseline',
              'value': <String, Object?>{
                'items': <Object?>[_workspaceJson('ws-a', '/a', 'A')],
                'archivedSessionIds': <Object?>['s-archived'],
              },
            },
          ),
        ],
      );
      final repository = await harnessRepository(rpc, socket);
      await pumpEventQueue();
      socket.releaseMuxFrames();
      await pumpEventQueue();

      expect(
        (await repository.observeWorkspaces().first)
            .map((workspace) => workspace.workspaceId)
            .toList(),
        <String>['ws-a'],
      );
      expect(await repository.observeArchivedSessionIds().first, <String>{
        's-archived',
      });
      // The pinned 0.1.5 workspace namespace registers no unary list; a
      // refresh has no pull to perform and must not invent one.
      await expectLater(repository.refreshWorkspaces(), completes);
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

  test(
    'streaming chunks coalesce into one window publish per window',
    () async {
      // Web markFrameDirty parity: N assistant token chunks inside one
      // window collapse into ONE timeline-window publish carrying the
      // fully accumulated partial — never one publish per chunk.
      JsonMap chunkEvent(int seq, String text) => <String, Object?>{
        'type': 'assistant/chunk',
        'seq': seq,
        'time': seq,
        'data': <String, Object?>{
          'turn': 1,
          'step': 1,
          'chunk': <String, Object?>{
            'type': 'text-delta',
            'index': 0,
            'text': text,
          },
        },
      };
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
          for (var i = 0; i < 5; i++)
            _muxFrame('session/event', 'session-1', chunkEvent(i + 1, 'x')),
        ],
      );
      final repository = await harnessRepository(rpc, socket);
      await pumpEventQueue();

      await repository.openSession('session-1');
      await pumpEventQueue();

      final windows = <TimelineWindow>[];
      final sub = repository
          .observeTimelineWindow('session-1')
          .listen(windows.add);
      addTearDown(() => sub.cancel());

      socket.releaseMuxFrames();
      await pumpEventQueue();
      // Every chunk is deferred to the window timer; on a loaded or fast runner
      // the 16ms coalescing timer may already have fired.
      expect(windows.length, inInclusiveRange(1, 2));

      // The coalescing timer is wall-clock; under CI load it can lag any
      // fixed bet. Wait (bounded) for the coalesced publish to land.
      for (var i = 0; i < 100 && windows.length < 2; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      // One coalesced publish carried all five chunks at once.
      expect(windows, hasLength(2));
      final published = windows.last.items;
      expect(published, hasLength(1));
      final partial = published.single as TimelineMessage;
      expect(partial.value.text, 'xxxxx');
      expect(partial.value.streaming, isTrue);
    },
  );

  test(
    'a non-streaming frame publishes immediately and carries pending chunks',
    () async {
      // Structural events keep microtask latency (web markDirty); the
      // immediate publish also flushes chunks still waiting on the window
      // timer, so nothing the stream already delivered is delayed behind
      // it.
      JsonMap chunkEvent(int seq) => <String, Object?>{
        'type': 'assistant/chunk',
        'seq': seq,
        'time': seq,
        'data': <String, Object?>{
          'turn': 1,
          'step': 1,
          'chunk': <String, Object?>{
            'type': 'text-delta',
            'index': 0,
            'text': 'abc',
          },
        },
      };
      JsonMap userMessageEvent(int seq) => <String, Object?>{
        'type': 'user/message',
        'seq': seq,
        'time': seq,
        'data': <String, Object?>{
          'id': 'user-1',
          'role': 'user',
          'source': <String, Object?>{'kind': 'user'},
          'content': <Object?>[
            <String, Object?>{'type': 'text', 'text': 'next turn'},
          ],
        },
      };
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
          _muxFrame('session/event', 'session-1', chunkEvent(1)),
          _muxFrame('session/event', 'session-1', chunkEvent(2)),
          _muxFrame('session/event', 'session-1', userMessageEvent(3)),
        ],
      );
      final repository = await harnessRepository(rpc, socket);
      await pumpEventQueue();

      await repository.openSession('session-1');
      await pumpEventQueue();

      final windows = <TimelineWindow>[];
      final sub = repository
          .observeTimelineWindow('session-1')
          .listen(windows.add);
      addTearDown(() => sub.cancel());

      socket.releaseMuxFrames();
      await pumpEventQueue();

      // The user message's immediate publish already carries both the
      // finalized partial (its two chunks) and itself — no timer wait.
      expect(windows, hasLength(2));
      final items = windows.last.items;
      expect(items, hasLength(2));
      final settled = items.first as TimelineMessage;
      expect(settled.value.text, 'abcabc');
      expect(settled.value.streaming, isFalse);
      final user = items.last as TimelineMessage;
      expect(user.value.role, MessageRole.user);
    },
  );

  test('question/requested that arrives before the session is opened still '
      'renders after openSession (web pendingBuffers parity)', () async {
    // Regression: the host can emit a pending question for a session the
    // client has not opened yet (agent asked mid-turn, user opens the
    // session afterwards). `question/requested` is a live frame that never
    // lands in session.history, so the open's history backfill shows only
    // the still-running ask_user_question tool call — without buffering the
    // frame would be dropped and the card never render (spinner forever).
    final rpc = HarnessFakeRpc(<Object?>[
      <String, Object?>{
        'sessionId': 'session-q',
        'updatedAt': 3,
        'running': false,
        'blank': false,
      },
    ]);
    final socket = ScriptedHarnessSocket(
      muxFrames: <ServerRequest>[
        _pendingFrame('question/requested', <String, Object?>{
          'sessionId': 'session-q',
          'questions': <Object?>[
            <String, Object?>{
              'id': 'q1',
              'question': 'Continue?',
              'options': <Object?>[
                <String, Object?>{'label': 'yes'},
                <String, Object?>{'label': 'no'},
              ],
            },
          ],
        }),
      ],
    );
    final repository = await harnessRepository(rpc, socket);
    await pumpEventQueue();

    // The frame arrives before openSession instantiates the session state.
    socket.releaseMuxFrames();
    await pumpEventQueue();

    await repository.openSession('session-q');
    await pumpEventQueue();

    final timeline = await repository.observeTimeline('session-q').first;
    final question = timeline.whereType<TimelineQuestionRequest>();
    expect(question, hasLength(1), reason: 'buffered question must render');
    expect(question.single.questions.single.id, 'q1');
  });

  test('question/resolved before openSession drops the buffered question '
      '(no replay of an answered request)', () async {
    final rpc = HarnessFakeRpc(<Object?>[
      <String, Object?>{
        'sessionId': 'session-q',
        'updatedAt': 3,
        'running': false,
        'blank': false,
      },
    ]);
    final socket = ScriptedHarnessSocket(
      muxFrames: <ServerRequest>[
        _pendingFrame('question/requested', <String, Object?>{
          'sessionId': 'session-q',
          'rpcId': 'rpc-question/requested',
          'questions': <Object?>[
            <String, Object?>{'id': 'q1', 'question': 'Continue?'},
          ],
        }),
        _pendingFrame('question/resolved', <String, Object?>{
          'sessionId': 'session-q',
          'questionRpcId': 'rpc-question/requested',
          'outcome': 'answered',
        }),
      ],
    );
    final repository = await harnessRepository(rpc, socket);
    await pumpEventQueue();

    socket.releaseMuxFrames();
    await pumpEventQueue();

    await repository.openSession('session-q');
    await pumpEventQueue();

    final timeline = await repository.observeTimeline('session-q').first;
    expect(
      timeline.whereType<TimelineQuestionRequest>(),
      isEmpty,
      reason: 'resolved question must not replay into the timeline',
    );
  });

  test(
    'initial timeline load publishes a loading window then settles',
    () async {
      final rpc = HarnessFakeRpc(<Object?>[
        <String, Object?>{
          'sessionId': 'session-1',
          'updatedAt': 3,
          'running': false,
          'blank': false,
        },
      ]);
      final repository = await harnessRepository(rpc, ScriptedHarnessSocket());
      await pumpEventQueue();

      final windows = <TimelineWindow>[];
      final sub = repository
          .observeTimelineWindow('session-1')
          .listen(windows.add);
      addTearDown(() => sub.cancel());

      await repository.openSession('session-1');
      // Broadcast StateStream delivery is microtask-scheduled; flush so the
      // window stream has observed the in-flight and settled emissions.
      await pumpEventQueue();

      // Seed (empty, idle) → in-flight first load → settled empty window.
      // The in-flight flag is what lets the UI render a loader instead of
      // the empty hero while the conversation's history is fetched.
      expect(windows.map((window) => window.isLoading).toList(), <bool>[
        false,
        true,
        false,
      ]);
    },
  );

  test('failed initial timeline load clears the loading window', () async {
    final rpc = HarnessFakeRpc(<Object?>[
      <String, Object?>{
        'sessionId': 'session-1',
        'updatedAt': 3,
        'running': false,
        'blank': false,
      },
    ]);
    rpc.failNextCall(DshRpcEndpoints.sessionHistory, 'bad-response');
    final repository = await harnessRepository(rpc, ScriptedHarnessSocket());
    await pumpEventQueue();

    final windows = <TimelineWindow>[];
    final sub = repository
        .observeTimelineWindow('session-1')
        .listen(windows.add);
    addTearDown(() => sub.cancel());

    // The failure is swallowed by openSession; the window must still drop
    // its in-flight flag so the UI never hangs on a perpetual spinner.
    await repository.openSession('session-1');
    await pumpEventQueue();

    expect(windows.map((window) => window.isLoading).toList(), <bool>[
      false,
      true,
      false,
    ]);
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

    final payload = rpc.payloads(DshRpcEndpoints.sessionUpdateQueue).single;
    final payloadArgs = asJsonObject(payload['args']) ?? payload;
    final action = asJsonObject(payloadArgs['action']);
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
      rpc.failNextCall(DshRpcEndpoints.sessionUpdateQueue, 'steer-unavailable');
      await repository.updateQueue(
        const QueueUpdateRequest(
          sessionId: 'session-1',
          itemId: 'queued-1',
          kind: QueueUpdateKind.steer,
        ),
      );
      rpc.failNextCall(
        DshRpcEndpoints.sessionUpdateQueue,
        'queue-item-not-found',
      );
      await repository.updateQueue(
        const QueueUpdateRequest(
          sessionId: 'session-1',
          itemId: 'queued-1',
          kind: QueueUpdateKind.remove,
        ),
      );

      rpc.failNextCall(DshRpcEndpoints.sessionUpdateQueue, 'agent-busy');
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

  test(
    'cancelled question responds with the cancelled error envelope',
    () async {
      final rpc = HarnessFakeRpc();
      final repository = await harnessRepository(rpc, ScriptedHarnessSocket());
      await pumpEventQueue();

      await repository.cancelQuestions('rpc-question', 'session-1');

      final received = rpc.receivedResponses().single;
      expect(received.$1, 'rpc-question');
      final result = received.$2;
      expect(result.ok, isFalse);
      expect(result.error?.code, 'cancelled');
      expect(result.value?['sessionId'], 'session-1');
    },
  );

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
    final payload = rpc.payloads(DshRpcEndpoints.goalsEdit).single;
    final payloadArgs = asJsonObject(payload['args']) ?? payload;
    expect(payloadArgs['sessionId'], 'session-1');
    expect(payloadArgs['objective'], 'ship it v2');
    final ref = asJsonObject(payloadArgs['ref']);
    expect(ref, isNotNull, reason: 'missing goal ref');
    expect(ref!['id'], 'goal-1');
    expect(ref['revision'], 1);
  });

  test('executeCommand decodes the settled execution', () async {
    // Recorded from the reference host (commands/execute over the typert
    // remote bridge; reference packages/interaction/commands/src/index.ts
    // CommandRuntime.execute -> CommandExecution).
    final rpc = HarnessFakeRpc();
    final repository = await harnessRepository(rpc, ScriptedHarnessSocket());
    await pumpEventQueue();

    final execution = await repository.executeCommand(
      'session-1',
      '/plan',
      const <PendingImage>[],
    );

    expect(execution, isNotNull);
    expect(execution!.commandId, 'cmd-e487ba23-1');
    expect(execution.kind, CommandOutcomeKind.success);
    expect(execution.text, 'Plan mode on. Use /plan off to leave.');
    // The typert remote envelope: the args carry the addressed agent
    // (session id), the complete line, and the images slot.
    final payload = rpc.payloads(DshRpcEndpoints.commandsExecute).single;
    final args = asJsonObject(payload['args']);
    expect(args, isNotNull, reason: 'missing args envelope');
    expect(args!['agentId'], 'session-1');
    expect(args['line'], '/plan');
    expect(args['images'], <Object?>[]);
  });

  test('executeCommand encodes composer images in submission order', () async {
    // Reference admission (dsh-attachment admitEncodedImages): each
    // image is {mediaType, data (canonical base64), name?} in caller
    // order; the host enforces the command's image-acceptance flag.
    final rpc = HarnessFakeRpc();
    final repository = await harnessRepository(rpc, ScriptedHarnessSocket());
    await pumpEventQueue();

    await repository.executeCommand('session-1', '/goal Ship it', const [
      PendingImage(
        id: 'img-1',
        mediaType: 'image/png',
        base64Data: 'aGVsbG8=',
        name: 'mockup.png',
      ),
      PendingImage(id: 'img-2', mediaType: 'image/jpeg', base64Data: 'dw=='),
    ]);

    final payload = rpc.payloads(DshRpcEndpoints.commandsExecute).single;
    final args = asJsonObject(payload['args'])!;
    final images = args['images'];
    expect(images, isA<List<Object?>>());
    expect(images, <Object?>[
      <String, Object?>{
        'mediaType': 'image/png',
        'data': 'aGVsbG8=',
        'name': 'mockup.png',
      },
      <String, Object?>{'mediaType': 'image/jpeg', 'data': 'dw=='},
    ]);
  });

  test('executeCommand unmatched answers ok with no value slot', () async {
    final rpc = HarnessFakeRpc()..commandValue = null;
    final repository = await harnessRepository(rpc, ScriptedHarnessSocket());
    await pumpEventQueue();

    // Reference: CommandRuntime.execute returns undefined on a syntax or
    // name miss — the wire serializes that as ok without a value.
    final execution = await repository.executeCommand(
      'session-1',
      '/nope',
      const <PendingImage>[],
    );
    expect(execution, isNull);
  });

  test('executeCommand error kind carries the command text', () async {
    final rpc = HarnessFakeRpc()
      ..commandValue = <String, Object?>{
        'commandId': 'cmd-e487ba23-4',
        'result': <String, Object?>{
          'kind': 'error',
          'text':
              'unknown preset "bogus-preset" (available: read-only, '
              'workspace-write, danger-full-access)',
        },
      };
    final repository = await harnessRepository(rpc, ScriptedHarnessSocket());
    await pumpEventQueue();

    final execution = await repository.executeCommand(
      'session-1',
      '/permission bogus',
      const <PendingImage>[],
    );
    expect(execution!.kind, CommandOutcomeKind.error);
    expect(execution.text, startsWith('unknown preset "bogus-preset"'));
  });

  test('executeCommand fails loud on a malformed execution', () async {
    final rpc = HarnessFakeRpc()
      ..commandValue = <String, Object?>{
        'result': <String, Object?>{'kind': 'success'},
      };
    final repository = await harnessRepository(rpc, ScriptedHarnessSocket());
    await pumpEventQueue();

    await expectLater(
      repository.executeCommand('session-1', '/plan', const <PendingImage>[]),
      throwsFormatException,
    );
  });

  test('executeCommand fails loud on an unknown result kind', () async {
    final rpc = HarnessFakeRpc()
      ..commandValue = <String, Object?>{
        'commandId': 'cmd-x',
        'result': <String, Object?>{'kind': 'explosion'},
      };
    final repository = await harnessRepository(rpc, ScriptedHarnessSocket());
    await pumpEventQueue();

    await expectLater(
      repository.executeCommand('session-1', '/plan', const <PendingImage>[]),
      throwsFormatException,
    );
  });

  test('executeCommand retries once on a mid-flight transport drop', () async {
    final rpc = HarnessFakeRpc()..dropNextTransportCalls(1);
    final repository = await harnessRepository(rpc, ScriptedHarnessSocket());
    await pumpEventQueue();

    final execution = await repository.executeCommand(
      'session-1',
      '/compact',
      const <PendingImage>[],
      retryOnTransportAbort: true,
    );

    expect(execution, isNotNull);
    expect(execution!.commandId, 'cmd-e487ba23-1');
    // The dropped first attempt plus the fresh-connection retry.
    expect(rpc.callCountFor(DshRpcEndpoints.commandsExecute), 2);
  });

  test('executeCommand does not retry without the opt-in flag', () async {
    final rpc = HarnessFakeRpc()..dropNextTransportCalls(1);
    final repository = await harnessRepository(rpc, ScriptedHarnessSocket());
    await pumpEventQueue();

    await expectLater(
      repository.executeCommand(
        'session-1',
        '/compact',
        const <PendingImage>[],
      ),
      throwsA(
        isA<DshTransportException>().having(
          (error) => error.cause,
          'cause',
          isA<SocketException>(),
        ),
      ),
    );
    expect(rpc.callCountFor(DshRpcEndpoints.commandsExecute), 1);
  });

  test('executeCommand does not retry a business failure', () async {
    final rpc = HarnessFakeRpc()
      ..failNextCall(DshRpcEndpoints.commandsExecute, 'admission');
    final repository = await harnessRepository(rpc, ScriptedHarnessSocket());
    await pumpEventQueue();

    await expectLater(
      repository.executeCommand(
        'session-1',
        '/compact',
        const <PendingImage>[],
        retryOnTransportAbort: true,
      ),
      throwsA(isA<DshBusinessException>()),
    );
    expect(rpc.callCountFor(DshRpcEndpoints.commandsExecute), 1);
  });

  test('executeCommand does not retry a non-socket transport error', () async {
    // A transport failure whose cause is not a socket drop (HTTP status,
    // envelope decode) is a completed exchange: the line is never
    // re-dispatched, even with the opt-in flag set.
    final rpc = HarnessFakeRpc()
      ..dropNextTransportCalls(1, cause: const FormatException('bad envelope'));
    final repository = await harnessRepository(rpc, ScriptedHarnessSocket());
    await pumpEventQueue();

    await expectLater(
      repository.executeCommand(
        'session-1',
        '/compact',
        const <PendingImage>[],
        retryOnTransportAbort: true,
      ),
      throwsA(isA<DshTransportException>()),
    );
    expect(rpc.callCountFor(DshRpcEndpoints.commandsExecute), 1);
  });

  test('executeCommand rethrows after exhausting the retry budget', () async {
    final rpc = HarnessFakeRpc()..dropNextTransportCalls(2);
    final repository = await harnessRepository(rpc, ScriptedHarnessSocket());
    await pumpEventQueue();

    await expectLater(
      repository.executeCommand(
        'session-1',
        '/compact',
        const <PendingImage>[],
        retryOnTransportAbort: true,
      ),
      throwsA(isA<DshTransportException>()),
    );
    // Both attempts dropped: the original plus its single retry.
    expect(rpc.callCountFor(DshRpcEndpoints.commandsExecute), 2);
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
    final payload = rpc.payloads(DshRpcEndpoints.directoryPickerList).single;
    final payloadArgs = asJsonObject(payload['args']) ?? payload;
    expect(payloadArgs['path'], '/tmp/chosen');
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
    final payload = rpc.payloads(DshRpcEndpoints.directoryPickerCreate).single;
    final payloadArgs = asJsonObject(payload['args']) ?? payload;
    expect(payloadArgs['path'], '/tmp/chosen');
    expect(payloadArgs['name'], 'new-folder');
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
    final settingsPayload = rpc
        .payloads(DshRpcEndpoints.settingsDescribe)
        .single;
    final settingsArgs =
        asJsonObject(settingsPayload['args']) ?? settingsPayload;
    expect(settingsArgs.length, 0);
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
    final credPayload = rpc
        .payloads(DshRpcEndpoints.credentialsDescribe)
        .single;
    final credArgs = asJsonObject(credPayload['args']) ?? credPayload;
    final refs = asJsonArray(credArgs['refs']);
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
    expect(rpc.payloads(DshRpcEndpoints.credentialsDescribe), isEmpty);
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

  test(
    'history tail page seeds contextPressure and contextBreakdown projections',
    () async {
      final rpc = HarnessFakeRpc();
      rpc.historyProjections['session-1'] = <String, Object?>{
        'asOfSeq': 90132,
        'values': <String, Object?>{
          'contextPressure': <String, Object?>{
            'pressureTokens': 390103,
            'projectedTokens': 390450,
            'contextWindow': 1000000,
          },
          'contextBreakdown': <String, Object?>{
            'systemTokens': 1582,
            'toolsTokens': 6475,
            'messageTokens': 269949,
          },
        },
      };

      final repository = await harnessRepository(rpc, ScriptedHarnessSocket());
      await pumpEventQueue();

      await repository.openSession('session-1');
      await pumpEventQueue();

      final pressure = await repository
          .observeContextPressure('session-1')
          .first;
      expect(pressure, isNotNull);
      expect(pressure!.pressureTokens, 390103);
      expect(pressure.projectedTokens, 390450);
      expect(pressure.contextWindow, 1000000);

      final breakdown = await repository
          .observeContextBreakdown('session-1')
          .first;
      expect(breakdown, isNotNull);
      expect(breakdown!.systemTokens, 1582);
      expect(breakdown.toolsTokens, 6475);
      expect(breakdown.messageTokens, 269949);
    },
  );

  test(
    'contextPressure projection frames update live and drop stale seq frames',
    () async {
      final rpc = HarnessFakeRpc();
      rpc.historyProjections['session-1'] = <String, Object?>{
        'asOfSeq': 100,
        'values': <String, Object?>{
          'contextPressure': <String, Object?>{
            'pressureTokens': 10000,
            'projectedTokens': 12000,
            'contextWindow': 50000,
          },
        },
      };

      final socket = ScriptedHarnessSocket(
        muxFrames: <ServerRequest>[
          // Frame 1: Newer seq (110) -> updates
          ServerRequest(
            rpcId: 'rpc-press-1',
            method: 'session/projection',
            payload: <String, Object?>{
              'type': 'session/projection',
              'sessionId': 'session-1',
              'key': 'contextPressure',
              'seq': 110,
              'value': <String, Object?>{
                'pressureTokens': 20000,
                'projectedTokens': 22000,
                'contextWindow': 50000,
              },
            },
          ),
          // Frame 2: Older seq (95) -> dropped (higher seq wins)
          ServerRequest(
            rpcId: 'rpc-press-2',
            method: 'session/projection',
            payload: <String, Object?>{
              'type': 'session/projection',
              'sessionId': 'session-1',
              'key': 'contextPressure',
              'seq': 95,
              'value': <String, Object?>{
                'pressureTokens': 5000,
                'projectedTokens': 5000,
                'contextWindow': 50000,
              },
            },
          ),
          // Frame 3: Equal or newer seq (120) -> updates
          ServerRequest(
            rpcId: 'rpc-press-3',
            method: 'session/projection',
            payload: <String, Object?>{
              'type': 'session/projection',
              'sessionId': 'session-1',
              'key': 'contextPressure',
              'seq': 120,
              'value': <String, Object?>{
                'pressureTokens': 30000,
                'projectedTokens': 35000,
                'contextWindow': 50000,
              },
            },
          ),
        ],
      );

      final repository = await harnessRepository(rpc, socket);
      await pumpEventQueue();

      await repository.openSession('session-1');
      await pumpEventQueue();

      // Baseline from history
      expect(
        (await repository.observeContextPressure('session-1').first)
            ?.pressureTokens,
        10000,
      );

      // Release push frames
      socket.releaseMuxFrames();
      await pumpEventQueue();

      // Final value should be from frame 3 (seq 120), frame 2 (seq 95) was dropped
      final current = await repository
          .observeContextPressure('session-1')
          .first;
      expect(current, isNotNull);
      expect(current!.pressureTokens, 30000);
      expect(current.projectedTokens, 35000);
      expect(current.contextWindow, 50000);
    },
  );

  test(
    'contextBreakdown projection frames update live and drop stale seq frames',
    () async {
      final rpc = HarnessFakeRpc();
      rpc.historyProjections['session-1'] = <String, Object?>{
        'asOfSeq': 50,
        'values': <String, Object?>{
          'contextBreakdown': <String, Object?>{
            'systemTokens': 100,
            'toolsTokens': 200,
            'messageTokens': 300,
          },
        },
      };

      final socket = ScriptedHarnessSocket(
        muxFrames: <ServerRequest>[
          // Frame 1: Newer seq (60) -> updates
          ServerRequest(
            rpcId: 'rpc-bd-1',
            method: 'session/projection',
            payload: <String, Object?>{
              'type': 'session/projection',
              'sessionId': 'session-1',
              'key': 'contextBreakdown',
              'seq': 60,
              'value': <String, Object?>{
                'systemTokens': 150,
                'toolsTokens': 250,
                'messageTokens': 350,
              },
            },
          ),
          // Frame 2: Older seq (40) -> dropped
          ServerRequest(
            rpcId: 'rpc-bd-2',
            method: 'session/projection',
            payload: <String, Object?>{
              'type': 'session/projection',
              'sessionId': 'session-1',
              'key': 'contextBreakdown',
              'seq': 40,
              'value': <String, Object?>{
                'systemTokens': 10,
                'toolsTokens': 20,
                'messageTokens': 30,
              },
            },
          ),
        ],
      );

      final repository = await harnessRepository(rpc, socket);
      await pumpEventQueue();

      await repository.openSession('session-1');
      await pumpEventQueue();

      expect(
        (await repository.observeContextBreakdown('session-1').first)
            ?.systemTokens,
        100,
      );

      socket.releaseMuxFrames();
      await pumpEventQueue();

      final current = await repository
          .observeContextBreakdown('session-1')
          .first;
      expect(current, isNotNull);
      expect(current!.systemTokens, 150);
      expect(current.toolsTokens, 250);
      expect(current.messageTokens, 350);
    },
  );

  test(
    'context projections tolerate missing and malformed shapes safely',
    () async {
      final rpc = HarnessFakeRpc();
      rpc.historyProjections['session-1'] = <String, Object?>{
        'asOfSeq': 10,
        'values': <String, Object?>{
          // Missing contextPressure and contextBreakdown keys
        },
      };

      final socket = ScriptedHarnessSocket(
        muxFrames: <ServerRequest>[
          // Malformed non-object value
          ServerRequest(
            rpcId: 'rpc-malformed',
            method: 'session/projection',
            payload: <String, Object?>{
              'type': 'session/projection',
              'sessionId': 'session-1',
              'key': 'contextPressure',
              'seq': 20,
              'value': 'not-an-object',
            },
          ),
        ],
      );

      final repository = await harnessRepository(rpc, socket);
      await pumpEventQueue();

      await repository.openSession('session-1');
      await pumpEventQueue();

      expect(
        await repository.observeContextPressure('session-1').first,
        isNull,
      );
      expect(
        await repository.observeContextBreakdown('session-1').first,
        isNull,
      );

      socket.releaseMuxFrames();
      await pumpEventQueue();

      // Still safe and null
      expect(
        await repository.observeContextPressure('session-1').first,
        isNull,
      );
    },
  );

  test('skill list sends session scope and maps catalog', () async {
    final rpc = HarnessFakeRpc();
    final repository = await harnessRepository(rpc, ScriptedHarnessSocket());
    await pumpEventQueue();

    final catalog = await repository.listSkills('session-1');

    final skillPayload = rpc.payloads(DshRpcEndpoints.skillsList).single;
    final skillArgs = asJsonObject(skillPayload['args']) ?? skillPayload;
    expect(skillArgs['sessionId'], 'session-1');
    expect(catalog, hasLength(2));
    final first = catalog.first;
    expect(first.name, 'generate-image');
    expect(first.description, 'Generate images from text');
    expect(first.whenToUse, 'user asks for pictures');
    expect(first.modelInvocable, isTrue);
    expect(catalog[1].whenToUse, isNull);
  });

  test('move workspace sends anchor and applies response order', () async {
    final rpc = HarnessFakeRpc();
    final socket = ScriptedHarnessSocket(
      muxFrames: <ServerRequest>[
        _workspaceBaseline(<JsonMap>[
          _workspaceJson('ws-a', '/a', 'A'),
          _workspaceJson('ws-b', '/b', 'B'),
          _workspaceJson('ws-c', '/c', 'C'),
        ]),
      ],
    );
    final repository = await harnessRepository(rpc, socket);
    await pumpEventQueue();
    socket.releaseMuxFrames();
    await pumpEventQueue();

    final orderedIds = await repository.moveWorkspace('ws-a', 'ws-c');

    expect(orderedIds, <String>['ws-b', 'ws-a', 'ws-c']);
    final payload = rpc.payloads(DshRpcEndpoints.workspaceInsertBefore).single;
    final payloadArgs = asJsonObject(payload['args']) ?? payload;
    expect(payloadArgs['workspaceId'], 'ws-a');
    expect(payloadArgs['beforeWorkspaceId'], 'ws-c');
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

    final payload = rpc.payloads(DshRpcEndpoints.workspaceInsertBefore).single;
    final payloadArgs = asJsonObject(payload['args']) ?? payload;
    expect(payloadArgs['workspaceId'], 'ws-a');
    expect(payloadArgs.containsKey('beforeWorkspaceId'), isFalse);
  });

  test('credential set sends ref and value', () async {
    final rpc = HarnessFakeRpc();
    final repository = await harnessRepository(rpc, ScriptedHarnessSocket());
    await pumpEventQueue();

    await repository.setCredential('DEEPSEEK_API_KEY', 'sk-typed');

    final payload = rpc.payloads(DshRpcEndpoints.credentialsSet).single;
    final payloadArgs = asJsonObject(payload['args']) ?? payload;
    expect(payloadArgs['ref'], 'DEEPSEEK_API_KEY');
    expect(payloadArgs['value'], 'sk-typed');
  });

  test('credential unset sends ref only', () async {
    final rpc = HarnessFakeRpc();
    final repository = await harnessRepository(rpc, ScriptedHarnessSocket());
    await pumpEventQueue();

    await repository.unsetCredential('DEEPSEEK_API_KEY');

    final payload = rpc.payloads(DshRpcEndpoints.credentialsUnset).single;
    final payloadArgs = asJsonObject(payload['args']) ?? payload;
    expect(payloadArgs['ref'], 'DEEPSEEK_API_KEY');
    expect(payloadArgs.length, 1);
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

    final payload = rpc.payloads(DshRpcEndpoints.settingsUpdate).single;
    final payloadArgs = asJsonObject(payload['args']) ?? payload;
    expect(payloadArgs['ns'], 'llm-deepseek');
    expect(payloadArgs['expectedRevision'], 3);
    final patch = asJsonObject(payloadArgs['patch']);
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

    final payload = rpc.payloads(DshRpcEndpoints.settingsReplace).single;
    final payloadArgs = asJsonObject(payload['args']) ?? payload;
    expect(payloadArgs['ns'], 'shell');
    expect(payloadArgs['expectedRevision'], 2);
    final section = asJsonObject(payloadArgs['section']);
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

    final payload = rpc.payloads(DshRpcEndpoints.settingsMutate).single;
    final payloadArgs = asJsonObject(payload['args']) ?? payload;
    expect(payloadArgs['ns'], 'llm-deepseek');
    expect(payloadArgs.containsKey('expectedRevision'), isFalse);
    final ops = asJsonArray(payloadArgs['ops']);
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
      final rpc = HarnessFakeRpc();
      final socket = ScriptedHarnessSocket(
        muxFrames: <ServerRequest>[
          _workspaceBaseline(<JsonMap>[
            _workspaceJson('ws-a', '/a', 'A', <String>['s1', 's2', 's3']),
          ]),
        ],
      );
      final repository = await harnessRepository(rpc, socket);
      await pumpEventQueue();
      socket.releaseMuxFrames();
      await pumpEventQueue();

      final updated = await repository.moveSession('ws-a', 's1', 's3');

      final payload = rpc
          .payloads(DshRpcEndpoints.workspaceInsertSessionBefore)
          .single;
      final payloadArgs = asJsonObject(payload['args']) ?? payload;
      expect(payloadArgs['workspaceId'], 'ws-a');
      expect(payloadArgs['sessionId'], 's1');
      expect(payloadArgs['beforeSessionId'], 's3');
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

    final payload = rpc.payloads(DshRpcEndpoints.sessionPrompt).single;
    final payloadArgs = asJsonObject(payload['args']) ?? payload;
    final content = asJsonArray(payloadArgs['content']) ?? const <Object?>[];
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

    final payload = rpc.payloads(DshRpcEndpoints.sessionAttachment).single;
    final payloadArgs = asJsonObject(payload['args']) ?? payload;
    expect(payloadArgs['sessionId'], 'session-1');
    expect(payloadArgs['attachmentId'], 'sha256:abc');
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
    // (`origin?: 'subagent'`) — reference/deepseek-harness/packages/
    // api/session-controller/src/types.ts (built by list.ts `listFields`).
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

  test('session list carries the subagent lineage into the domain', () async {
    // Wire: `SessionSummary.parentSessionId` is the optional
    // spawning-parent key on a subagent child row —
    // reference/deepseek-harness/packages/api/session-controller/src/
    // types.ts. The Subagents screen diffs this key on the
    // sessions stream to spot child spawns and detachments.
    final rpc = HarnessFakeRpc(<Object?>[
      <String, Object?>{
        'sessionId': 'session-child',
        'updatedAt': 4,
        'running': true,
        'blank': false,
        'parentSessionId': 'session-root',
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

    final sessions = await repository.observeSessions().first;
    final child = sessions.firstWhere(
      (session) => session.id == 'session-child',
    );
    expect(child.parentSessionId, 'session-root');
    expect(child.origin, 'subagent');
    final root = sessions.firstWhere((session) => session.id == 'session-root');
    expect(root.parentSessionId, isNull);
  });

  test(
    'api-session/added upserts the roster so a spawn reaches the stream',
    () async {
      // Wire: the forwarded Remote Event `api-session/added`
      // (packages/api/session-controller/src/types.ts
      // `'api-session/added'(summary: SessionSummary)`) carries sessionId +
      // blank + parentSessionId + origin for a subagent spawn. The adapter
      // upserts the summary in place; the summary is the lineage carrier
      // into the domain, with no session.list repull.
      final rows = <Object?>[
        <String, Object?>{
          'sessionId': 'session-root',
          'updatedAt': 3,
          'running': false,
          'blank': false,
        },
      ];
      final rpc = HarnessFakeRpc(rows);
      final socket = ScriptedHarnessSocket(
        muxFrames: <ServerRequest>[
          _remoteEmit('api-session/added', <Object?>[
            <String, Object?>{
              'sessionId': 'session-child',
              'updatedAt': 5,
              'running': true,
              'blank': false,
              'parentSessionId': 'session-root',
              'origin': 'subagent',
            },
          ]),
        ],
      );
      final repository = await harnessRepository(rpc, socket);
      await pumpEventQueue();
      final before = rpc.callCountFor(DshRpcEndpoints.sessionList);

      final sessions = <List<SessionSummary>>[];
      final sub = repository.observeSessions().listen(sessions.add);
      addTearDown(() => sub.cancel());

      // The spawn event lands; the summary upserts the roster row in place,
      // so the child reaches the stream without a session.list round-trip.
      socket.releaseMuxFrames();
      await pumpEventQueue();

      expect(rpc.callCountFor(DshRpcEndpoints.sessionList), before);
      final last = sessions.last;
      final child = last.firstWhere((session) => session.id == 'session-child');
      expect(child.parentSessionId, 'session-root');
      expect(child.origin, 'subagent');
    },
  );

  // The subagent catalog is the tree's fact source: `subagent.list` reads
  // durable session state, so a cold host answers the parent's complete
  // child tree — the fact the Subagents screen cold-seeds from.
  test('subagent.list decodes the host-reported child tree', () async {
    // Fixture transcribed from
    // reference/deepseek-harness/packages/subagent/subagent/src/
    // control-types.ts SubagentCatalog: continuable and
    // one-shot child rows (label required/optional per mode) plus a
    // diagnostic row.
    final rpc = HarnessFakeRpc()
      ..subagentListValue = <String, Object?>{
        'entries': <Object?>[
          <String, Object?>{
            'kind': 'child',
            'id': 'child-1',
            'mode': 'continuable',
            'activity': 'running',
            'hasChildren': true,
            'label': 'Worker',
          },
          <String, Object?>{
            'kind': 'child',
            'id': 'child-2',
            'mode': 'one-shot',
            'activity': 'inactive',
            'hasChildren': false,
          },
          <String, Object?>{
            'kind': 'diagnostic',
            'id': 'child-3',
            'reason': 'corrupt',
          },
        ],
        'parentAvailable': true,
      };
    final repository = await harnessRepository(rpc, ScriptedHarnessSocket());
    await pumpEventQueue();

    final catalog = await repository.loadSubagents('session-root');

    final subagentPayload = rpc.payloads(DshRpcEndpoints.subagentsList).first;
    final subagentArgs =
        asJsonObject(subagentPayload['args']) ?? subagentPayload;
    expect(subagentArgs, <String, Object?>{'parentSessionId': 'session-root'});
    expect(catalog.parentSessionId, 'session-root');
    expect(catalog.parentAvailable, isTrue);
    expect(catalog.entries, const <SubagentEntry>[
      SubagentEntry(
        id: 'child-1',
        kind: 'child',
        mode: SubagentMode.continuable,
        activity: 'running',
        hasChildren: true,
        label: 'Worker',
      ),
      SubagentEntry(
        id: 'child-2',
        kind: 'child',
        mode: SubagentMode.oneShot,
        activity: 'inactive',
      ),
      SubagentEntry(id: 'child-3', kind: 'diagnostic', reason: 'corrupt'),
    ]);
  });

  test(
    'subagent.list answers a parent without children as an empty catalog',
    () async {
      final rpc = HarnessFakeRpc()
        ..subagentListValue = <String, Object?>{
          'entries': <Object?>[],
          'parentAvailable': false,
        };
      final repository = await harnessRepository(rpc, ScriptedHarnessSocket());
      await pumpEventQueue();

      final catalog = await repository.loadSubagents('session-root');

      expect(catalog.parentSessionId, 'session-root');
      expect(catalog.entries, isEmpty);
      expect(catalog.parentAvailable, isFalse);
    },
  );

  test(
    'subagent.list child row without id fails loud with the field name',
    () async {
      // Negative fixture: the contract requires `id` on every row; a row
      // missing it must throw naming the field, never decode to a default.
      final rpc = HarnessFakeRpc()
        ..subagentListValue = <String, Object?>{
          'entries': <Object?>[
            <String, Object?>{
              'kind': 'child',
              'mode': 'continuable',
              'activity': 'running',
              'hasChildren': false,
              'label': 'Worker',
            },
          ],
          'parentAvailable': true,
        };
      final repository = await harnessRepository(rpc, ScriptedHarnessSocket());
      await pumpEventQueue();

      await expectLater(
        repository.loadSubagents('session-root'),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('"id"'),
          ),
        ),
      );
    },
  );

  test(
    'subagent.list child row without a mode fails loud naming the field',
    () async {
      // Negative fixture: `subagentListEntrySchema` requires `mode` on
      // every child row ('one-shot' | 'continuable'); a child row
      // without it must throw naming the field, never decode modeless.
      final rpc = HarnessFakeRpc()
        ..subagentListValue = <String, Object?>{
          'entries': <Object?>[
            <String, Object?>{
              'kind': 'child',
              'id': 'child-1',
              'activity': 'running',
              'hasChildren': false,
              'label': 'Worker',
            },
          ],
          'parentAvailable': true,
        };
      final repository = await harnessRepository(rpc, ScriptedHarnessSocket());
      await pumpEventQueue();

      await expectLater(
        repository.loadSubagents('session-root'),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('"mode"'),
          ),
        ),
      );
    },
  );

  test(
    'session/page addresses each subagent row with its own catalog mode',
    () async {
      // Wire: the subagent address carries mode
      // ('one-shot' | 'continuable'), and the host rejects a mismatch
      // (surfaced as `subagent/unauthorized`) —
      // reference/deepseek-harness/packages/subagent/subagent/src/control-types.ts
      // `SubagentAddress` + packages/api/session-controller/src/history.ts.
      // A one-shot row must go out
      // as one-shot; the transcript folds through the reducer.
      final rpc = HarnessFakeRpc()
        ..subagentHistoryValue = <String, Object?>{
          'events': <Object?>[
            <String, Object?>{'event': _assistantMessageEvent()},
          ],
          'hasMore': false,
        };
      final repository = await harnessRepository(rpc, ScriptedHarnessSocket());
      await pumpEventQueue();

      final items = await repository.loadSubagentHistory(
        'session-root',
        'child-2',
        SubagentMode.oneShot,
      );

      final subHistoryPayload = rpc
          .payloads(DshRpcEndpoints.sessionPage)
          .single;
      final subHistoryArgs =
          asJsonObject(subHistoryPayload['args']) ?? subHistoryPayload;
      expect(subHistoryArgs['address'], <String, Object?>{
        'kind': 'subagent',
        'parentSessionId': 'session-root',
        'childSessionId': 'child-2',
        'mode': 'one-shot',
      });
      expect(items, isNotEmpty);

      await repository.loadSubagentHistory(
        'session-root',
        'child-1',
        SubagentMode.continuable,
      );
      final lastSubHistory = rpc.payloads(DshRpcEndpoints.sessionPage).last;
      final lastSubHistoryArgs =
          asJsonObject(lastSubHistory['args']) ?? lastSubHistory;
      expect(
        asJsonObject(lastSubHistoryArgs['address'])?['mode'],
        'continuable',
      );
    },
  );

  test('a child-history host failure surfaces to the caller', () async {
    // Fail-loud: a `subagent/unauthorized` answer (the host's mode-guard
    // rejection) never decays into an empty transcript — the
    // exception reaches the caller, which surfaces it on the error
    // banner.
    final rpc = HarnessFakeRpc()
      ..failNextCall(DshRpcEndpoints.sessionPage, 'subagent/unauthorized');
    final repository = await harnessRepository(rpc, ScriptedHarnessSocket());
    await pumpEventQueue();

    await expectLater(
      repository.loadSubagentHistory(
        'session-root',
        'child-2',
        SubagentMode.oneShot,
      ),
      throwsA(
        isA<DshBusinessException>().having(
          (error) => error.code,
          'code',
          'subagent/unauthorized',
        ),
      ),
    );
  });

  test(
    'subagent.interrupt and subagent.prompt pin the continuable mode',
    () async {
      // Wire: `subagentInterruptRequestSchema` and
      // `subagentPromptRequestSchema` carry the literal 'continuable' —
      // the verbs exist only for continuable rows (subagents.schema.ts).
      final rpc = HarnessFakeRpc();
      final repository = await harnessRepository(rpc, ScriptedHarnessSocket());
      await pumpEventQueue();

      await repository.interruptSubagent('session-root', 'child-1');
      final messageId = await repository.sendSubagentPrompt(
        'session-root',
        'child-1',
        'keep going',
      );

      final interruptPayload = rpc
          .payloads(DshRpcEndpoints.subagentsInterrupt)
          .single;
      final interruptArgs =
          asJsonObject(interruptPayload['args']) ?? interruptPayload;
      expect(interruptArgs, <String, Object?>{
        'parentSessionId': 'session-root',
        'childSessionId': 'child-1',
        'mode': 'continuable',
      });
      final prompt = rpc.payloads(DshRpcEndpoints.subagentsPrompt).single;
      final promptArgs = asJsonObject(prompt['args']) ?? prompt;
      expect(promptArgs['mode'], 'continuable');
      expect(promptArgs['childSessionId'], 'child-1');
      expect(messageId, 'subagent-msg-1');
    },
  );

  // Pending-interaction fold: the sidebar's amber dot comes from
  // approval/question frames tracked for every session, opened or not
  // (web SessionManager list-level parity). Wire shapes:
  // reference/deepseek-harness/packages/api/remotes/src/remote-events.ts
  // (`approval/request`, `user-questions/request`).
  test('approval requested lights pending and resolved clears it', () async {
    final rpc = HarnessFakeRpc(<Object?>[
      <String, Object?>{
        'sessionId': 'session-a',
        'updatedAt': 3,
        'running': false,
        'blank': false,
      },
    ]);
    final socket = ScriptedHarnessSocket(
      muxFrames: <ServerRequest>[
        _pendingFrame('approval/requested', <String, Object?>{
          'sessionId': 'session-a',
          'approvalId': 'ap-1',
          'toolName': 'bash',
          'reason': 'run destructive command',
        }),
      ],
    );
    final repository = await harnessRepository(rpc, socket);
    await pumpEventQueue();
    // The session was never opened — the fold must still light the row.
    socket.releaseMuxFrames();
    await pumpEventQueue();

    final pending = await repository.observeSessions().first;
    final session = pending.firstWhere((item) => item.id == 'session-a');
    expect(session.pendingInteraction, SessionPendingInteraction.approval);
  });

  test('approval resolution drops the pending status', () async {
    final rpc = HarnessFakeRpc(<Object?>[
      <String, Object?>{
        'sessionId': 'session-a',
        'updatedAt': 3,
        'running': false,
        'blank': false,
      },
    ]);
    final socket = ScriptedHarnessSocket(
      muxFrames: <ServerRequest>[
        _pendingFrame('approval/requested', <String, Object?>{
          'sessionId': 'session-a',
          'approvalId': 'ap-1',
          'toolName': 'bash',
        }),
        _pendingFrame('approval/resolved', <String, Object?>{
          'sessionId': 'session-a',
          'approvalId': 'ap-1',
          'outcome': 'allowed',
        }),
      ],
    );
    final repository = await harnessRepository(rpc, socket);
    await pumpEventQueue();
    socket.releaseMuxFrames();
    await pumpEventQueue();

    final pending = await repository.observeSessions().first;
    final session = pending.firstWhere((item) => item.id == 'session-a');
    expect(session.pendingInteraction, isNull);
  });

  test('plan-review question routes to planReview; a plain question stays question', () async {
    final rpc = HarnessFakeRpc(<Object?>[
      <String, Object?>{
        'sessionId': 'session-p',
        'updatedAt': 3,
        'running': false,
        'blank': false,
      },
      <String, Object?>{
        'sessionId': 'session-q',
        'updatedAt': 3,
        'running': false,
        'blank': false,
      },
    ]);
    // Wire question intent: `plan-review` with a single binary approve/
    // deny option set (web manager `questionInteractionStatus`).
    final socket = ScriptedHarnessSocket(
      muxFrames: <ServerRequest>[
        _pendingFrame('question/requested', <String, Object?>{
          'sessionId': 'session-p',
          'questions': <Object?>[
            <String, Object?>{
              'id': 'q1',
              'question': 'Approve plan?',
              'detail': 'Apply the plan steps?',
              'options': <Object?>[
                <String, Object?>{'label': 'Approve', 'description': 'yes'},
                <String, Object?>{'label': 'Deny', 'description': 'no'},
              ],
              'intent': <String, Object?>{
                'kind': 'plan-review',
                'approve': 'Approve',
              },
            },
          ],
        }),
        _pendingFrame('question/requested', <String, Object?>{
          'sessionId': 'session-q',
          'questions': <Object?>[
            <String, Object?>{
              'id': 'q2',
              'question': 'Pick a color',
              'options': <Object?>[
                <String, Object?>{'label': 'Red'},
                <String, Object?>{'label': 'Blue'},
              ],
            },
          ],
        }),
      ],
    );
    final repository = await harnessRepository(rpc, socket);
    await pumpEventQueue();
    socket.releaseMuxFrames();
    await pumpEventQueue();

    final pending = await repository.observeSessions().first;
    final plan = pending.firstWhere((item) => item.id == 'session-p');
    expect(plan.pendingInteraction, SessionPendingInteraction.planReview);
    final plain = pending.firstWhere((item) => item.id == 'session-q');
    expect(plain.pendingInteraction, SessionPendingInteraction.question);
  });

  test('a question pending beside an approval projects the question', () async {
    // Web SessionManager buildListSnapshot (sessions/manager.ts:1033-1039):
    // the dot names the interaction the composer can act on, so a question
    // outranks an approval regardless of arrival order.
    final rpc = HarnessFakeRpc(<Object?>[
      <String, Object?>{
        'sessionId': 'session-x',
        'updatedAt': 3,
        'running': false,
        'blank': false,
      },
    ]);
    final socket = ScriptedHarnessSocket(
      muxFrames: <ServerRequest>[
        _pendingFrame('approval/requested', <String, Object?>{
          'sessionId': 'session-x',
          'approvalId': 'ap-1',
          'toolName': 'bash',
        }),
        _pendingFrame('question/requested', <String, Object?>{
          'sessionId': 'session-x',
          'questions': <Object?>[
            <String, Object?>{
              'id': 'q1',
              'question': 'Pick a color',
              'options': <Object?>[
                <String, Object?>{'label': 'Red'},
                <String, Object?>{'label': 'Blue'},
              ],
            },
          ],
        }),
      ],
    );
    final repository = await harnessRepository(rpc, socket);
    await pumpEventQueue();
    socket.releaseMuxFrames();
    await pumpEventQueue();

    final sessions = await repository.observeSessions().first;
    final session = sessions.firstWhere((item) => item.id == 'session-x');
    expect(session.pendingInteraction, SessionPendingInteraction.question);
  });

  test('the question still projects when the approval arrives last', () async {
    // The discriminating order: arrival-last would project the approval
    // (the old `values.last` fold), while the reference priority keeps the
    // question the user can act on.
    final rpc = HarnessFakeRpc(<Object?>[
      <String, Object?>{
        'sessionId': 'session-x',
        'updatedAt': 3,
        'running': false,
        'blank': false,
      },
    ]);
    final socket = ScriptedHarnessSocket(
      muxFrames: <ServerRequest>[
        _pendingFrame('question/requested', <String, Object?>{
          'sessionId': 'session-x',
          'questions': <Object?>[
            <String, Object?>{
              'id': 'q1',
              'question': 'Pick a color',
              'options': <Object?>[
                <String, Object?>{'label': 'Red'},
                <String, Object?>{'label': 'Blue'},
              ],
            },
          ],
        }),
        _pendingFrame('approval/requested', <String, Object?>{
          'sessionId': 'session-x',
          'approvalId': 'ap-1',
          'toolName': 'bash',
        }),
      ],
    );
    final repository = await harnessRepository(rpc, socket);
    await pumpEventQueue();
    socket.releaseMuxFrames();
    await pumpEventQueue();

    final sessions = await repository.observeSessions().first;
    final session = sessions.firstWhere((item) => item.id == 'session-x');
    expect(session.pendingInteraction, SessionPendingInteraction.question);
    // Resolving the question leaves the still-pending approval projected.
    final resolved = ScriptedHarnessSocket(
      muxFrames: <ServerRequest>[
        _pendingFrame('question/requested', <String, Object?>{
          'sessionId': 'session-x',
          'questions': <Object?>[
            <String, Object?>{
              'id': 'q1',
              'question': 'Pick a color',
              'options': <Object?>[
                <String, Object?>{'label': 'Red'},
                <String, Object?>{'label': 'Blue'},
              ],
            },
          ],
        }),
        _pendingFrame('approval/requested', <String, Object?>{
          'sessionId': 'session-x',
          'approvalId': 'ap-1',
          'toolName': 'bash',
        }),
        _pendingFrame('question/resolved', <String, Object?>{
          'sessionId': 'session-x',
          'questionRpcId': 'rpc-question/requested',
          'outcome': 'answered',
        }),
      ],
    );
    final resolvedRepository = await harnessRepository(rpc, resolved);
    await pumpEventQueue();
    resolved.releaseMuxFrames();
    await pumpEventQueue();

    final afterResolve = await resolvedRepository.observeSessions().first;
    final stillPending = afterResolve.firstWhere(
      (item) => item.id == 'session-x',
    );
    expect(
      stillPending.pendingInteraction,
      SessionPendingInteraction.approval,
      reason: 'with the question gone, the lone approval is the projection',
    );
  });

  test('question resolution drops the pending status by rpcId', () async {
    final rpc = HarnessFakeRpc(<Object?>[
      <String, Object?>{
        'sessionId': 'session-q',
        'updatedAt': 3,
        'running': false,
        'blank': false,
      },
    ]);
    final socket = ScriptedHarnessSocket(
      muxFrames: <ServerRequest>[
        _pendingFrame('question/requested', <String, Object?>{
          'sessionId': 'session-q',
          'questions': <Object?>[
            <String, Object?>{'id': 'q1', 'question': 'Continue?'},
          ],
        }),
        _pendingFrame('question/resolved', <String, Object?>{
          'sessionId': 'session-q',
          'questionRpcId': 'rpc-question/requested',
          'outcome': 'answered',
        }),
      ],
    );
    final repository = await harnessRepository(rpc, socket);
    await pumpEventQueue();
    socket.releaseMuxFrames();
    await pumpEventQueue();

    final pending = await repository.observeSessions().first;
    final session = pending.firstWhere((item) => item.id == 'session-q');
    expect(session.pendingInteraction, isNull);
  });

  // Finished-but-unviewed fold: the running true→false edge while the
  // session is not the one being viewed arms the green dot (web
  // SessionManager `syncCompletedNotifications`); opening it or it
  // running again clears it.
  test(
    'a session finishing while not viewed is completed; running clears it',
    () async {
      final rpc = HarnessFakeRpc(<Object?>[
        <String, Object?>{
          'sessionId': 'session-a',
          'updatedAt': 3,
          'running': false,
          'blank': false,
        },
        <String, Object?>{
          'sessionId': 'session-b',
          'updatedAt': 3,
          'running': false,
          'blank': false,
        },
      ]);
      final socket = ScriptedHarnessSocket(
        muxFrames: <ServerRequest>[
          _sessionStatusEvent('session-a', true),
          _sessionStatusEvent('session-a', false),
        ],
      );
      final repository = await harnessRepository(rpc, socket);
      await pumpEventQueue();
      // Not viewing session-a; it then stops running → completed arms.
      await repository.openSession('session-b');
      await pumpEventQueue();
      socket.releaseMuxFrames();
      await pumpEventQueue();

      var sessions = await repository.observeSessions().first;
      expect(
        sessions.firstWhere((item) => item.id == 'session-a').completed,
        isTrue,
      );
      expect(
        sessions.firstWhere((item) => item.id == 'session-b').completed,
        isFalse,
      );

      // Opening the completed session clears the reminder.
      await repository.openSession('session-a');
      await pumpEventQueue();
      sessions = await repository.observeSessions().first;
      expect(
        sessions.firstWhere((item) => item.id == 'session-a').completed,
        isFalse,
      );

      // Running again also clears it.
      socket.releaseMuxFrames();
      await repository.refreshSessions();
      await pumpEventQueue();
    },
  );

  test('a session finishing while being viewed never arms completed', () async {
    final rpc = HarnessFakeRpc(<Object?>[
      <String, Object?>{
        'sessionId': 'session-a',
        'updatedAt': 3,
        'running': false,
        'blank': false,
      },
    ]);
    final socket = ScriptedHarnessSocket(
      muxFrames: <ServerRequest>[
        _sessionStatusEvent('session-a', true),
        _sessionStatusEvent('session-a', false),
      ],
    );
    final repository = await harnessRepository(rpc, socket);
    await pumpEventQueue();
    // View session-a before it finishes: no reminder arms.
    await repository.openSession('session-a');
    await pumpEventQueue();
    socket.releaseMuxFrames();
    await pumpEventQueue();

    final sessions = await repository.observeSessions().first;
    expect(
      sessions.firstWhere((item) => item.id == 'session-a').completed,
      isFalse,
    );
  });

  // Web SessionManager parity (runtime/tests/manager.client.spec.ts
  // "a list refresh carrying the running→idle transition arms the
  // reminder"): the edge fold runs on every observation source, not only
  // on api-session/status forwarded events — a pull that arrives after the
  // turn finished (WS gap, app process death) must arm the reminder too.
  test(
    'a list pull carrying the running→idle transition arms the reminder',
    () async {
      JsonMap sessionRow(String id, int updatedAt, bool running) =>
          <String, Object?>{
            'sessionId': id,
            'updatedAt': updatedAt,
            'running': running,
            'blank': false,
          };
      final rpc = HarnessFakeRpc(<Object?>[
        sessionRow('session-a', 3, true),
        sessionRow('session-b', 3, false),
      ]);
      final repository = await harnessRepository(rpc, ScriptedHarnessSocket());
      await pumpEventQueue();
      await repository.openSession('session-b');
      await pumpEventQueue();

      // The turn finished on the host while the client saw no frame; the
      // next pull is the first observation of the idle state.
      rpc.sessionsValue = <Object?>[
        sessionRow('session-a', 4, false),
        sessionRow('session-b', 3, false),
      ];
      await repository.refreshSessions();
      await pumpEventQueue();

      final sessions = await repository.observeSessions().first;
      expect(
        sessions.firstWhere((item) => item.id == 'session-a').completed,
        isTrue,
      );
    },
  );

  // Web SessionManager parity ("arms a completion that happened during an
  // in-flight first pull"): a session already running at the client's
  // first observation must arm when its completion event arrives — the
  // pull records the running baseline even though no running:true event
  // was ever seen.
  test(
    'a completion event after a running first pull arms the reminder',
    () async {
      JsonMap sessionRow(String id, int updatedAt, bool running) =>
          <String, Object?>{
            'sessionId': id,
            'updatedAt': updatedAt,
            'running': running,
            'blank': false,
          };
      final rpc = HarnessFakeRpc(<Object?>[
        sessionRow('session-a', 3, true),
        sessionRow('session-b', 3, false),
      ]);
      final socket = ScriptedHarnessSocket(
        muxFrames: <ServerRequest>[_sessionStatusEvent('session-a', false)],
      );
      final repository = await harnessRepository(rpc, socket);
      await pumpEventQueue();
      await repository.openSession('session-b');
      await pumpEventQueue();
      socket.releaseMuxFrames();
      await pumpEventQueue();

      final sessions = await repository.observeSessions().first;
      expect(
        sessions.firstWhere((item) => item.id == 'session-a').completed,
        isTrue,
      );
    },
  );

  // Wire shape: agentPreset.list roster
  // (reference/deepseek-harness/packages/preset/agent-presets/src/
  // types.ts).
  test('agentPreset.list decodes the roster and deployment facts', () async {
    final rpc = HarnessFakeRpc();
    final repository = await harnessRepository(rpc, ScriptedHarnessSocket());
    await pumpEventQueue();

    final roster = await repository.listAgentPresets();

    final presetPayload = rpc.payloads(DshRpcEndpoints.agentPresetsList).single;
    final presetArgs = asJsonObject(presetPayload['args']) ?? presetPayload;
    expect(presetArgs, isEmpty);
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
    final selectPayload = rpc
        .payloads(DshRpcEndpoints.agentPresetsSelect)
        .single;
    final selectArgs = asJsonObject(selectPayload['args']) ?? selectPayload;
    expect(selectArgs['agentPreset'], 'minimal');
    expect(selectArgs['agentId'] ?? selectArgs['sessionId'], 'session-1');
  });

  test('agentPreset.select surfaces the host refusal', () async {
    final rpc = HarnessFakeRpc();
    rpc.failNextCall(DshRpcEndpoints.agentPresetsSelect, 'agent-preset-locked');
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
    expect(select.options.last.description, 'Edit files inside the workspace');
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

  // Wire shape: `agent-preset/selected` arrives as a forwarded Remote Event
  // `{type: 'emit', event, args}` with args [sessionId, agentPreset] on the
  // mux `$events` stream (allowlist in
  // packages/api/remotes/src/remote-events.ts).
  test(
    'agent-preset/selected remote event folds the session summary',
    () async {
      final rpc = HarnessFakeRpc(<Object?>[
        <String, Object?>{
          'sessionId': 'session-1',
          'updatedAt': 3,
          'running': false,
          'blank': true,
        },
      ]);
      final socket = ScriptedHarnessSocket(
        muxFrames: <ServerRequest>[
          _remoteEmit('agent-preset/selected', <Object?>[
            'session-1',
            'minimal',
          ]),
        ],
      );
      final repository = await harnessRepository(rpc, socket);
      await pumpEventQueue();
      await repository.refreshSessions();

      socket.releaseMuxFrames();
      await pumpEventQueue();

      final sessions = await repository.observeSessions().first;
      final switched = sessions.firstWhere(
        (session) => session.id == 'session-1',
      );
      expect(switched.agentPreset, 'minimal');
    },
  );

  // ---- Connection resync fan-out ------------------------------------------

  test(
    'resync fires the list pull and the window rebuilds concurrently',
    () async {
      // Web SessionManager `handleConnected` parity: `void refreshList()`
      // and `void session.resync()` fire side by side, so one slow history
      // load never holds back the roster or the release of buffered frames.
      // Cross-gated RPCs deadlock a serial implementation: each response
      // waits for the other endpoint's call to be observed.
      final rpc = HarnessFakeRpc(<Object?>[resyncSessionRow('a')]);
      final socket = ReconnectableHarnessSocket();
      final repository = await resyncFixture(rpc, socket);
      await repository.openSession('a');

      rpc.sessionsValue = <Object?>[
        resyncSessionRow('a'),
        resyncSessionRow('b'),
      ];
      await repository.openSession('b');
      await pumpEventQueue();
      expect(rpc.callCountFor(DshRpcEndpoints.sessionList), 1);
      expect(rpc.callCountFor(DshRpcEndpoints.sessionPage), 2);

      rpc.historyEvents['a'] = <Object?>[
        resyncAssistantTextEvent(7, 'after resync'),
      ];
      rpc.gateResponsesUntilCalled(
        DshRpcEndpoints.sessionList,
        DshRpcEndpoints.sessionPage,
      );
      rpc.gateResponsesUntilCalled(
        DshRpcEndpoints.sessionPage,
        DshRpcEndpoints.sessionList,
      );
      final mark = rpc.callJournal.length;

      socket.terminate();
      await pumpEventQueue();
      await Future<void>.delayed(const Duration(milliseconds: 80));
      await pumpEventQueue();

      // Neither hold expired: the list response was still gated when the
      // history call landed, and vice versa.
      expect(rpc.gateTimeouts, isEmpty);
      final journal = rpc.callJournal.sublist(mark);
      expect(
        journal.indexOf('${DshRpcEndpoints.sessionList}:start'),
        lessThan(journal.indexOf('${DshRpcEndpoints.sessionPage}:start')),
      );
      expect(
        journal.indexOf('${DshRpcEndpoints.sessionPage}:start'),
        lessThan(journal.indexOf('${DshRpcEndpoints.sessionList}:return')),
      );
      expect(rpc.callCountFor(DshRpcEndpoints.sessionList), 2);
      expect(rpc.callCountFor(DshRpcEndpoints.sessionPage), 4);

      final timeline = await repository.observeTimeline('a').first;
      final message = timeline.whereType<TimelineMessage>().single;
      expect(message.value.text, 'after resync');
      final sessions = await repository.observeSessions().first;
      expect(
        sessions.map((session) => session.id),
        containsAll(<String>['a', 'b']),
      );
    },
  );

  test(
    'consecutive resync generations serialize; the newest baseline wins',
    () async {
      final rpc = HarnessFakeRpc(<Object?>[resyncSessionRow('a')]);
      final socket = ReconnectableHarnessSocket();
      final repository = await resyncFixture(rpc, socket);
      await repository.openSession('a');

      rpc.historyEvents['a'] = <Object?>[
        resyncAssistantTextEvent(7, 'baseline v1'),
      ];
      final holdList = Completer<void>();
      rpc.gateResponses(DshRpcEndpoints.sessionList, holdList.future);
      socket.terminate();
      await pumpEventQueue();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await pumpEventQueue();

      // Generation 2's window rebuild settled while its list pull is still
      // in flight.
      expect(rpc.callCountFor(DshRpcEndpoints.sessionList), 2);
      expect(rpc.callCountFor(DshRpcEndpoints.sessionPage), 2);
      final first = await repository.observeTimeline('a').first;
      expect(
        first.whereType<TimelineMessage>().single.value.text,
        'baseline v1',
      );

      // Connection loss while generation 2's resync is still in flight:
      // the resync mutex keeps generation 3 from firing any RPC until
      // generation 2 settles.
      rpc.historyEvents['a'] = <Object?>[
        resyncAssistantTextEvent(9, 'baseline v2'),
      ];
      socket.terminate();
      await pumpEventQueue();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await pumpEventQueue();
      expect(rpc.callCountFor(DshRpcEndpoints.sessionList), 2);

      holdList.complete();
      await pumpEventQueue();
      await Future<void>.delayed(const Duration(milliseconds: 80));
      await pumpEventQueue();
      expect(rpc.callCountFor(DshRpcEndpoints.sessionList), 3);
      expect(rpc.callCountFor(DshRpcEndpoints.sessionPage), 3);
      final second = await repository.observeTimeline('a').first;
      expect(
        second.whereType<TimelineMessage>().single.value.text,
        'baseline v2',
      );
    },
  );

  test(
    'a folded event that changes no value republishes only the window',
    () async {
      // The stats/pressure/breakdown folds mint a fresh equal value per
      // handled event; the StateStream equality gate keeps those no-change
      // writes off the streams, so the controller never rebuilds on them.
      final rpc = HarnessFakeRpc(<Object?>[resyncSessionRow('a')]);
      final socket = ReconnectableHarnessSocket();
      final repository = await resyncFixture(rpc, socket);
      await repository.openSession('a');

      final windows = <TimelineWindow>[];
      final stats = <SessionWindowStats>[];
      final pressures = <ContextPressure?>[];
      final breakdowns = <ContextBreakdown?>[];
      final subs = <StreamSubscription<void>>[
        repository.observeTimelineWindow('a').listen(windows.add),
        repository.observeSessionStats('a').listen(stats.add),
        repository.observeContextPressure('a').listen(pressures.add),
        repository.observeContextBreakdown('a').listen(breakdowns.add),
      ];
      for (final sub in subs) {
        addTearDown(sub.cancel);
      }
      await pumpEventQueue();
      expect(windows, hasLength(1));
      expect(stats, hasLength(1));
      expect(pressures, hasLength(1));
      expect(breakdowns, hasLength(1));

      JsonMap turnEnd(int seq) => <String, Object?>{
        'type': 'turn/end',
        'seq': seq,
        'time': seq,
        'data': <String, Object?>{
          'turn': 1,
          'reason': <String, Object?>{'kind': 'completed'},
        },
      };
      socket.emitMuxFrame(_muxFrame('session/event', 'a', turnEnd(11)));
      socket.emitMuxFrame(_muxFrame('session/event', 'a', turnEnd(12)));
      await pumpEventQueue();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await pumpEventQueue();

      // Structural frames publish the window immediately, one per frame…
      expect(windows, hasLength(3));
      // …while the unchanged folded values stayed silent past their seeds.
      expect(stats, hasLength(1));
      expect(pressures, hasLength(1));
      expect(breakdowns, hasLength(1));
    },
  );

  // ---- In-band queue re-baseline across a reconnect burst -----------------
  // `session/queue` is a live authoritative snapshot with no durable history:
  // the mux-open burst pushes each session's `session/subscribed` and the
  // queue baseline that follows it, and the host never resends the baseline
  // in that generation. `DshConnectionManager` forwards burst frames from
  // stream open — before the `$events` ready frame publishes CONNECTED — so
  // every re-baseline rides the stream, never the connected publish
  // (reference session.ts:419-426 author comment; web queueMirror design).
  // Each test holds the generation's readiness frame (or the
  // `session.history` response) to pin the burst relative to the resync prep.

  test('a queue baseline whose burst outruns the connected publish survives '
      'the window rebuild', () async {
    final rpc = HarnessFakeRpc(<Object?>[resyncSessionRow('a')]);
    final socket = ReconnectableHarnessSocket();
    final repository = await resyncFixture(rpc, socket);
    rpc.historyEvents['a'] = <Object?>[
      resyncAssistantTextEvent(5, 'durable history'),
    ];
    await repository.openSession('a');

    // A live queue snapshot lands on the ready window (host change push).
    socket.emitMuxFrame(
      _queueFrame('a', <Object?>[
        _queueWireItem('q-old', 'stale steer', 'steering'),
      ]),
    );
    await pumpEventQueue();
    expect(
      (await repository.observeTimeline('a').first)
          .whereType<TimelineQueue>()
          .single
          .items
          .single
          .text,
      'stale steer',
    );

    // Generation 2: hold the readiness frame so the mux-open burst
    // flows while the previous window is still ready — the race the old
    // connected-time truncation lost to.
    final readyHeld = Completer<void>();
    socket.readyGate = readyHeld;
    socket.terminate();
    await pumpEventQueue();
    await Future<void>.delayed(const Duration(milliseconds: 30));
    await pumpEventQueue();

    socket.emitMuxFrame(_subscribedFrame('a', 5));
    socket.emitMuxFrame(
      _queueFrame('a', <Object?>[_queueWireItem('q-new', 'fresh steer')]),
    );
    socket.emitMuxFrame(
      _pendingFrame('question/requested', <String, Object?>{
        'sessionId': 'a',
        'questions': <Object?>[
          <String, Object?>{'id': 'q1', 'question': 'Continue?'},
        ],
      }),
    );
    await pumpEventQueue();
    socket.readyGate = null;
    readyHeld.complete();
    await pumpEventQueue();
    await Future<void>.delayed(const Duration(milliseconds: 80));
    await pumpEventQueue();

    // The rebuild re-folded durable history and carried the fresh baseline
    // over: no stale row, dock alive while the host queue is.
    final timeline = await repository.observeTimeline('a').first;
    expect(
      timeline.whereType<TimelineMessage>().single.value.text,
      'durable history',
    );
    final dock = timeline.whereType<TimelineQueue>().single;
    expect(dock.items, <SessionQueueItem>[
      const SessionQueueItem(
        itemId: 'q-new',
        placement: QueuePlacement.queued,
        text: 'fresh steer',
      ),
    ]);
    // The pending-interaction mirror likewise re-baselined in-band: the
    // replayed request re-lit the dot after its session's subscribed
    // frame, and the resync prep no longer wipes it.
    final sessions = await repository.observeSessions().first;
    expect(
      sessions.firstWhere((session) => session.id == 'a').pendingInteraction,
      SessionPendingInteraction.question,
    );
  });

  test('a queue baseline arriving after the resync prep replays in order '
      'past the history reset', () async {
    final rpc = HarnessFakeRpc(<Object?>[resyncSessionRow('a')]);
    final socket = ReconnectableHarnessSocket();
    final repository = await resyncFixture(rpc, socket);
    rpc.historyEvents['a'] = <Object?>[
      resyncAssistantTextEvent(5, 'durable history'),
    ];
    await repository.openSession('a');

    // Generation 2: connected publishes, the prep runs, and the history
    // reload is held — the burst now arrives against a not-ready window
    // and parks for the after-reset replay.
    final historyHeld = Completer<void>();
    rpc.gateResponses(DshRpcEndpoints.sessionPage, historyHeld.future);
    socket.terminate();
    await pumpEventQueue();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await pumpEventQueue();

    socket.emitMuxFrame(_subscribedFrame('a', 5));
    socket.emitMuxFrame(
      _queueFrame('a', <Object?>[_queueWireItem('q-new', 'parked baseline')]),
    );
    await pumpEventQueue();
    historyHeld.complete();
    await pumpEventQueue();
    await Future<void>.delayed(const Duration(milliseconds: 80));
    await pumpEventQueue();

    final timeline = await repository.observeTimeline('a').first;
    expect(
      timeline.whereType<TimelineMessage>().single.value.text,
      'durable history',
    );
    final dock = timeline.whereType<TimelineQueue>().single;
    expect(dock.items.single.itemId, 'q-new');
    expect(dock.items.single.text, 'parked baseline');
  });

  test('an unopened session keeps its burst baseline and question card '
      'for a later open', () async {
    final rpc = HarnessFakeRpc(<Object?>[
      resyncSessionRow('b'),
      resyncSessionRow('c'),
    ]);
    final socket = ReconnectableHarnessSocket();
    final repository = await resyncFixture(rpc, socket);

    // Live queue snapshots buffer for the never-instantiated sessions.
    // Session 'c' has a stale baseline whose new generation sends no
    // queue frame at all (the host omits the baseline for an empty
    // queue), so opening it must show no dock rows, never the stale.
    socket.emitMuxFrame(
      _queueFrame('b', <Object?>[_queueWireItem('q-old', 'stale work')]),
    );
    socket.emitMuxFrame(
      _queueFrame('c', <Object?>[_queueWireItem('q-old-c', 'phantom work')]),
    );
    await pumpEventQueue();

    // Generation 2: the burst (subscribed → replayed request → queue
    // baseline) arrives before the connected publish drives the prep; the
    // old connected-time truncation wiped exactly these fresh buffers.
    final readyHeld = Completer<void>();
    socket.readyGate = readyHeld;
    socket.terminate();
    await pumpEventQueue();
    await Future<void>.delayed(const Duration(milliseconds: 30));
    await pumpEventQueue();

    socket.emitMuxFrame(_subscribedFrame('b', 2));
    socket.emitMuxFrame(
      _pendingFrame('question/requested', <String, Object?>{
        'sessionId': 'b',
        'questions': <Object?>[
          <String, Object?>{'id': 'q1', 'question': 'Continue?'},
        ],
      }),
    );
    socket.emitMuxFrame(
      _queueFrame('b', <Object?>[_queueWireItem('q-new', 'fresh work')]),
    );
    // 'c''s generation: subscribed only — an emptied queue resends nothing.
    socket.emitMuxFrame(_subscribedFrame('c', 1));
    await pumpEventQueue();
    socket.readyGate = null;
    readyHeld.complete();
    await pumpEventQueue();
    await Future<void>.delayed(const Duration(milliseconds: 80));
    await pumpEventQueue();

    // Opening the session replays the buffer through the real frame path:
    // the dock rows are the fresh baseline, not the stale one, and the
    // question card renders (the 08-22 buffering contract intact).
    await repository.openSession('b');
    final timeline = await repository.observeTimeline('b').first;
    final dock = timeline.whereType<TimelineQueue>().single;
    expect(dock.items, <SessionQueueItem>[
      const SessionQueueItem(
        itemId: 'q-new',
        placement: QueuePlacement.queued,
        text: 'fresh work',
      ),
    ]);
    expect(timeline.whereType<TimelineQuestionRequest>(), hasLength(1));

    // The stale snapshot was truncated by 'c''s own subscribed frame, so
    // its open shows no dock row (web manager.ts:714-732 phantom guard).
    await repository.openSession('c');
    expect(
      (await repository.observeTimeline('c').first).whereType<TimelineQueue>(),
      isEmpty,
    );
  });

  test('resync ignores subagent sessions and unopened sessions during window rebuild', () async {
    // Dsh wire parity: session.list carries both root and subagent sessions
    // (with origin: 'subagent' and parentSessionId). Subagents cannot be
    // loaded via session/page with address.kind: 'session' (the host throws
    // session/agent-busy: subagent Sessions require their durable parent address).
    // Resync must rebuild only opened, non-subagent session windows.
    final rpc = HarnessFakeRpc(<Object?>[
      resyncSessionRow('root-1'),
      <String, Object?>{
        'sessionId': 'subagent-1',
        'parentSessionId': 'root-1',
        'origin': 'subagent',
        'updatedAt': 1,
        'running': false,
        'blank': false,
        'projections': <String, Object?>{
          'asOfSeq': 10,
          'values': <String, Object?>{
            'contextPressure': <String, Object?>{
              'pressureTokens': 1500,
              'projectedTokens': 1600,
              'contextWindow': 128000,
            },
            'contextBreakdown': <String, Object?>{
              'systemTokens': 500,
              'toolsTokens': 800,
              'messageTokens': 200,
            },
          },
        },
      },
      resyncSessionRow('unopened-root'),
    ]);
    final diagnostics = <AdapterDiagnostic>[];
    final socket = ReconnectableHarnessSocket();
    final repository = await resyncFixture(
      rpc,
      socket,
      onDiagnostic: diagnostics.add,
    );

    // Verify that subagent-1 projections are accessible without creating
    // an opened session window.
    final pressure = await repository
        .observeContextPressure('subagent-1')
        .first;
    expect(pressure?.pressureTokens, 1500);

    // Even if observeTimeline is called on unopened-root, it has not been opened.
    final unopenedTimelineStream = repository.observeTimeline('unopened-root');
    expect(unopenedTimelineStream, isNotNull);

    // Only root-1 is explicitly opened.
    await repository.openSession('root-1');
    await pumpEventQueue();

    // Disconnect and drive resync.
    socket.terminate();
    await pumpEventQueue();
    await Future<void>.delayed(const Duration(milliseconds: 80));
    await pumpEventQueue();

    // Ensure no resync.session diagnostic warnings occurred.
    final resyncWarnings = diagnostics.where(
      (d) => d.context == 'resync.session',
    );
    expect(resyncWarnings, isEmpty);

    // Verify that session/history (or session/page) was reloaded for root-1 only,
    // never for subagent-1 or unopened-root.
    final historyPayloads = rpc
        .payloads(DshRpcEndpoints.sessionPage)
        .followedBy(rpc.payloads(DshRpcEndpoints.sessionPage));
    for (final payload in historyPayloads) {
      final args = asJsonObject(payload['args']) ?? payload;
      final request = asJsonObject(args['request']) ?? args;
      final address = asJsonObject(request['address']);
      final sid =
          address?['sessionId'] ?? request['sessionId'] ?? payload['sessionId'];
      expect(sid, isNot('subagent-1'));
      expect(sid, isNot('unopened-root'));
    }
  });

  test('openSession on subagent session emits warning and does not call session.page', () async {
    final rpc = HarnessFakeRpc(<Object?>[
      <String, Object?>{
        'sessionId': 'subagent-child',
        'parentSessionId': 'parent-root',
        'origin': 'subagent',
        'updatedAt': 1,
        'running': false,
        'blank': false,
      },
    ]);
    final diagnostics = <AdapterDiagnostic>[];
    final socket = ScriptedHarnessSocket();
    final repository = await harnessRepository(
      rpc,
      socket,
      onDiagnostic: diagnostics.add,
    );
    await pumpEventQueue();

    await repository.openSession('subagent-child');
    await pumpEventQueue();

    // Diagnostic emitted naming subagent and loadSubagentHistory
    final warning = diagnostics.firstWhere((d) => d.context == 'session.open');
    expect(warning.message, contains('subagent-child'));
    expect(warning.message, contains('loadSubagentHistory'));

    // No history/page calls made for subagent-child with address.kind: 'session'
    final historyPayloads = rpc
        .payloads(DshRpcEndpoints.sessionPage)
        .followedBy(rpc.payloads(DshRpcEndpoints.sessionPage));
    for (final payload in historyPayloads) {
      final args = asJsonObject(payload['args']) ?? payload;
      final request = asJsonObject(args['request']) ?? args;
      final address = asJsonObject(request['address']);
      final sid =
          address?['sessionId'] ?? request['sessionId'] ?? payload['sessionId'];
      expect(sid, isNot('subagent-child'));
    }
  });

  test(
    'switching back to an already-opened session reloads latest history',
    () async {
      final rpc = HarnessFakeRpc(<Object?>[
        resyncSessionRow('s1'),
        resyncSessionRow('s2'),
      ]);
      final socket = ScriptedHarnessSocket();
      final repository = await harnessRepository(rpc, socket);
      await pumpEventQueue();

      // Open s1 first time with initial history
      rpc.historyEvents['s1'] = <Object?>[
        resyncAssistantTextEvent(1, 'initial s1 message'),
      ];
      await repository.openSession('s1');
      await pumpEventQueue();

      final firstTimeline = await repository.observeTimeline('s1').first;
      expect(
        firstTimeline.whereType<TimelineMessage>().single.value.text,
        'initial s1 message',
      );

      // Switch to s2
      rpc.historyEvents['s2'] = <Object?>[
        resyncAssistantTextEvent(2, 'initial s2 message'),
      ];
      await repository.openSession('s2');
      await pumpEventQueue();

      // While on s2, new events landed in s1 on the server (e.g. from desktop client)
      rpc.historyEvents['s1'] = <Object?>[
        resyncAssistantTextEvent(1, 'initial s1 message'),
        resyncAssistantTextEvent(3, 'new message from desktop'),
      ];

      // Switch back to s1: openSession must reload and reflect the new message
      await repository.openSession('s1');
      await pumpEventQueue();

      final updatedTimeline = await repository.observeTimeline('s1').first;
      final messages = updatedTimeline.whereType<TimelineMessage>().toList();
      expect(messages, hasLength(2));
      expect(messages.last.value.text, 'new message from desktop');
    },
  );

  test(
    'session follow snapshot frame updates timeline with latest history',
    () async {
      final rpc = HarnessFakeRpc(<Object?>[resyncSessionRow('s1')]);
      final socket = ReconnectableHarnessSocket();
      final repository = await resyncFixture(rpc, socket);
      await pumpEventQueue();

      rpc.historyEvents['s1'] = <Object?>[
        resyncAssistantTextEvent(1, 'old message'),
      ];
      await repository.openSession('s1');
      await pumpEventQueue();

      // Emit follow snapshot frame carrying updated history records
      socket.emitMuxFrame(
        ServerRequest(
          rpcId: 'session-follow-s1',
          method: 'session/follow',
          payload: <String, Object?>{
            'type': 'snapshot',
            'cursor': 5,
            'records': <Object?>[
              <String, Object?>{
                'type': 'event',
                'event': resyncAssistantTextEvent(
                  5,
                  'updated from follow snapshot',
                ),
              },
            ],
            'hasMore': false,
          },
        ),
      );
      await pumpEventQueue();

      final timeline = await repository.observeTimeline('s1').first;
      expect(
        timeline.whereType<TimelineMessage>().single.value.text,
        'updated from follow snapshot',
      );
    },
  );
}
