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
import 'dart:convert';
import 'dart:io' show SocketException;
import 'dart:typed_data';

import 'package:domain/model/account.dart';
import 'package:domain/model/agent_team.dart';
import 'package:domain/model/attachment.dart';
import 'package:domain/model/chat_message.dart';
import 'package:domain/model/command.dart';
import 'package:domain/model/connection_state.dart';
import 'package:domain/model/context_pressure.dart';
import 'package:domain/model/file_reference.dart';
import 'package:domain/model/file_upload.dart';
import 'package:domain/model/plan.dart';
import 'package:domain/model/repository_failure.dart';
import 'package:domain/model/plugin_management.dart';
import 'package:domain/model/prompt.dart';
import 'package:domain/model/schedule.dart';
import 'package:domain/model/terminal.dart';
import 'package:domain/model/session.dart';
import 'package:domain/model/session_window_stats.dart';
import 'package:domain/model/settings.dart';
import 'package:domain/model/subagent.dart';
import 'package:domain/model/todo.dart';
import 'package:domain/model/goal.dart';
import 'package:domain/model/jobs.dart';
import 'package:domain/model/message_feedback.dart';
import 'package:domain/model/timeline_item.dart';
import 'package:domain/model/timeline_window.dart';
import 'package:domain/model/user_question.dart';
import 'package:domain/model/model_catalog.dart';
import 'package:domain/model/session_archive.dart';
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

/// One `JobView` row as the host sends it
/// (`packages/jobs/jobs/src/view.ts` `JobView`).
JsonMap _jobRowJson({
  required String id,
  required String status,
  int? total,
  int? earliest,
  String? detail,
  String kind = 'bash',
  String label = 'pnpm test',
  int startedAt = 5,
  int? finishedAt,
}) => <String, Object?>{
  'id': id,
  'kind': kind,
  'label': label,
  'status': status,
  'startedAt': startedAt,
  if (finishedAt != null) 'finishedAt': finishedAt,
  if (detail != null) 'detail': detail,
  if (total != null)
    'output': <String, Object?>{'total': total, 'earliest': earliest ?? 0},
};

/// One `WebTerminalInfo` row
/// (`packages/api/terminal-controller/src/types.ts`).
JsonMap _terminalRowJson({
  required String id,
  String title = 'bash',
  String state = 'running',
  int? exitCode,
  String? controllerId,
}) => <String, Object?>{
  'id': id,
  'title': title,
  'shell': <String, Object?>{
    'path': '/bin/bash',
    'name': 'bash',
    'args': <Object?>['-i'],
  },
  'cwd': '/home/tester/project',
  'cols': 80,
  'rows': 24,
  'state': state,
  'exitCode': exitCode,
  if (controllerId != null) 'controllerId': controllerId,
};

/// One frame on a terminal's `terminal/follow` route.
ServerRequest _terminalFrame(String streamId, JsonMap payload) =>
    ServerRequest(rpcId: streamId, method: 'terminal/follow', payload: payload);

/// One frame on a job's `job/follow` route
/// (`packages/api/job-controller/src/types.ts` `JobFollowFrame`).
ServerRequest _jobFollowFrame(String streamId, JsonMap payload) =>
    ServerRequest(rpcId: streamId, method: 'job/follow', payload: payload);

/// The `request` record inside one captured request-wrapped payload, from
/// either the raw envelope or the fake's merged view of it.
Object? requestPayload(JsonMap payload) {
  final args = asJsonObject(payload['args']) ?? payload;
  return args['request'] ?? args;
}

/// One single-key control-stream projection frame
/// (`packages/api/session-controller/src/types.ts`
/// `{type: 'projection', sessionId, key, value, seq}`).
ServerRequest _controlProjection(
  String sessionId,
  String key,
  int seq,
  Object? value,
) => ServerRequest(
  rpcId: 'session-control',
  method: 'session/control',
  payload: <String, Object?>{
    'type': 'projection',
    'sessionId': sessionId,
    'key': key,
    'seq': seq,
    'value': value,
  },
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
    DshRpcEndpoints.sessionProjections,
    DshRpcEndpoints.userQuestionsAnswer,
    DshRpcEndpoints.skillsList,
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
    DshRpcEndpoints.agentPresetsRead,
    DshRpcEndpoints.agentPresetsSelect,
    DshRpcEndpoints.directoryPickerList,
    DshRpcEndpoints.directoryPickerCreate,
    DshRpcEndpoints.workspaceCreate,
    DshRpcEndpoints.workspaceRename,
    DshRpcEndpoints.workspaceDelete,
    DshRpcEndpoints.workspaceInsertBefore,
    DshRpcEndpoints.workspaceInsertSessionBefore,
    DshRpcEndpoints.workspaceArchiveSession,
    DshRpcEndpoints.workspaceUnarchiveSession,
    DshRpcEndpoints.workspacePinSession,
    DshRpcEndpoints.workspaceUnpinSession,
    DshRpcEndpoints.workspaceFilesStat,
    DshRpcEndpoints.workspaceFilesRead,
    DshRpcEndpoints.workspaceFilesList,
    DshRpcEndpoints.commandsExecute,
    DshRpcEndpoints.fileReferencesList,
    DshRpcEndpoints.fileUploadsUpload,
    DshRpcEndpoints.settingsDescribe,
    DshRpcEndpoints.settingsUpdate,
    DshRpcEndpoints.settingsReplace,
    DshRpcEndpoints.settingsMutate,
    DshRpcEndpoints.permissionPresetsCatalog,
    DshRpcEndpoints.credentialsDescribe,
    DshRpcEndpoints.credentialsSet,
    DshRpcEndpoints.credentialsUnset,
    DshRpcEndpoints.accountGetState,
    DshRpcEndpoints.accountGetProfile,
    DshRpcEndpoints.accountGetBalance,
    DshRpcEndpoints.accountGetUnnotifiedBonuses,
    DshRpcEndpoints.accountAckBonusNotified,
    DshRpcEndpoints.llmListProviders,
    DshRpcEndpoints.llmListConfigurableProviders,
    DshRpcEndpoints.llmDiscoverModels,
    DshRpcEndpoints.pluginInventoryList,
    DshRpcEndpoints.pluginManagerListBundles,
    DshRpcEndpoints.pluginManagerListPlugins,
    DshRpcEndpoints.pluginManagerRegistries,
    DshRpcEndpoints.pluginManagerInspect,
    DshRpcEndpoints.pluginManagerInstallBundle,
    DshRpcEndpoints.pluginManagerWaitForInstall,
    DshRpcEndpoints.pluginManagerCancelInstall,
    DshRpcEndpoints.pluginManagerSetBundleEnabled,
    DshRpcEndpoints.pluginManagerSetPluginEnabled,
    DshRpcEndpoints.pluginManagerRemoveBundle,
    DshRpcEndpoints.pluginManagerListVersionExemptions,
    DshRpcEndpoints.pluginManagerSetVersionExemption,
    DshRpcEndpoints.pluginRegistryProbeFastest,
    DshRpcEndpoints.scheduleList,
    DshRpcEndpoints.scheduleCatalog,
    DshRpcEndpoints.scheduleHistory,
    DshRpcEndpoints.scheduleUpdate,
    DshRpcEndpoints.scheduleDelete,
    DshRpcEndpoints.terminalEnvironment,
    DshRpcEndpoints.terminalShells,
    DshRpcEndpoints.terminalList,
    DshRpcEndpoints.terminalCreate,
    DshRpcEndpoints.terminalWrite,
    DshRpcEndpoints.terminalResize,
    DshRpcEndpoints.terminalRename,
    DshRpcEndpoints.terminalClose,
    DshRpcEndpoints.jobKill,
    DshRpcEndpoints.messageFeedbackList,
    DshRpcEndpoints.messageFeedbackPut,
    DshRpcEndpoints.messageFeedbackDelete,
    DshRpcEndpoints.sessionFeedbackRecord,
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

  /// The arguments exactly as the client sent them, before [payloads] mirrors
  /// the Agent lookup's `agentId` onto `sessionId`. Assertions about which
  /// field name crossed the wire must read this one.
  List<JsonMap> rawPayloads(String endpoint) =>
      (_payloadsByEndpoint[endpoint] ?? const <JsonMap>[])
          .map((JsonMap p) => asJsonObject(p['args']) ?? p)
          .toList();

  List<(String, RpcResult)> receivedResponses() =>
      List<(String, RpcResult)>.of(_receivedResponses);

  /// One-shot scripted business failure for the next call to [endpoint],
  /// which must be the exact name the client sends.
  void failNextCall(String endpoint, String code) {
    _failures[endpoint] = code;
  }

  /// One-shot scripted business failure carrying structured details — the
  /// shape a refusal answers with (`workspace/session-active` names the
  /// activity it refused over).
  void failNextCallWithDetails(String endpoint, String code, JsonMap details) {
    _failureDetails[endpoint] = (code, details);
  }

  final Map<String, String> _failures = <String, String>{};
  final Map<String, (String, JsonMap)> _failureDetails =
      <String, (String, JsonMap)>{};

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
  /// Scripted `terminal/list` rows.
  List<Object?> terminalRowsValue = <Object?>[];

  /// Scripted `schedule/list` and `schedule/catalog` rows.
  List<Object?> scheduleRowsValue = <Object?>[];

  /// Scripted `schedule/history` result.
  JsonMap scheduleHistoryValue = <String, Object?>{
    'id': 'schedule-1',
    'records': <Object?>[],
    'earlierRecordsUnavailable': false,
    'earlierRecordsPruned': false,
    'retention': <String, Object?>{'days': 30, 'records': 200},
  };

  /// Scripted `schedule/update` result.
  JsonMap scheduleUpdateValue = <String, Object?>{
    'id': 'schedule-1',
    'updated': false,
    'code': 'schedule_conflict',
  };

  /// Scripted `agentPresets/read` value.
  JsonMap agentPresetDocumentValue = <String, Object?>{
    'agentPreset': 'standard',
    'name': 'Standard',
    'description': 'The default toolchain.',
    'content': '- id: tool-bash\n  name: "@deepseek-ai/dsh-tool-bash"\n',
  };

  /// Scripted `permissionPresets/catalog` value.
  JsonMap permissionCatalogValue = <String, Object?>{
    'options': <Object?>[
      <String, Object?>{
        'value': 'workspace-write',
        'name': 'Workspace write',
        'description': 'Write inside the workspace.',
      },
      <String, Object?>{
        'value': 'danger-full-access',
        'name': 'Full access',
        'description': 'Full file access without approval prompts.',
      },
    ],
    'defaultOptions': <Object?>[
      <String, Object?>{'value': 'workspace-write', 'name': 'Workspace write'},
      <String, Object?>{'value': 'danger-full-access', 'name': 'Full access'},
    ],
    'defaultPreset': 'workspace-write',
  };

  /// Scripted `account/getState` value (`AccountView` —
  /// reference/deepseek-harness/packages/credentials/deepseek-account/src/
  /// types.ts).
  JsonMap accountStateValue = <String, Object?>{
    'status': 'credential-stored',
    'links': <String, Object?>{
      'usageUrl': 'https://platform.example/usage',
      'topUpUrl': 'https://platform.example/top_up',
    },
    'attempt': <String, Object?>{'id': 'attempt-1', 'phase': 'succeeded'},
  };

  /// Scripted `account/getProfile` outcome; null answers the endpoint's null
  /// result, which is the host holding no account grant.
  JsonMap? accountProfileValue = <String, Object?>{
    'status': 'ready',
    'value': <String, Object?>{
      'id': 'user-7',
      'name': 'Ada',
      'contact': 'a***@example.com',
      'avatarUrl': null,
    },
  };

  /// Scripted `account/getBalance` outcome; null answers the endpoint's null
  /// result.
  JsonMap? accountBalanceValue = <String, Object?>{
    'status': 'ready',
    'value': <Object?>[
      <String, Object?>{'currency': 'CNY', 'balance': '12.34'},
    ],
    'bonusWallets': <Object?>[
      <String, Object?>{'currency': 'USD', 'balance': '0.50'},
    ],
  };

  /// Scripted `account/getUnnotifiedBonuses` batch; null answers the
  /// endpoint's null result.
  JsonMap? accountBonusesValue = <String, Object?>{
    'accountId': 'user-7',
    'bonuses': <Object?>[
      <String, Object?>{
        'orderId': 'order-1',
        'campaign': 'welcome',
        'amount': '5.00',
        'currency': 'CNY',
        'grantedAt': '2026-10-01T00:00:00Z',
        'expiresAt': '2026-11-01T00:00:00Z',
        'message': 'A 5.00 CNY bonus was credited.',
      },
    ],
  };

  /// Scripted `account/ackBonusNotified` answer: a bare boolean, so
  /// [_valueFor] parks it under the envelope's `value` key.
  bool accountAckValue = true;

  /// Scripted `workspace/pinSession` and `workspace/unpinSession` reply: the
  /// complete resulting pin set, most recently pinned first.
  JsonMap pinValue = <String, Object?>{'pinnedSessionIds': <String>[]};

  /// Scripted `pluginManager/listBundles` rows.
  List<Object?> pluginBundlesValue = <Object?>[];

  /// Scripted `pluginManager/listPlugins` rows.
  List<Object?> pluginRowsValue = <Object?>[];

  /// Scripted `pluginManager/inspect` result.
  JsonMap inspectionValue = <String, Object?>{
    'status': 'accepted',
    'kind': 'registry',
    'name': '@deepseek-ai/dsh-schedule',
    'version': '0.1.7-rc.2',
    'bundle': true,
    'registry': 'https://registry.npmmirror.com/',
  };

  /// Scripted `ChangeResult` for every mutating manager method.
  JsonMap changeResultValue = <String, Object?>{
    'changed': true,
    'application': 'applied',
    'stage': 'enable',
    'target': 'dsh-schedule',
  };

  /// Scripted `pluginManager/waitForInstall` value; null answers a null
  /// result, the host's "no record of that request".
  JsonMap? waitForInstallValue;

  /// Scripted `agentTeam` projection value served by `session/projections`;
  /// null means the host publishes no Team for the Session.
  JsonMap? agentTeamValue;

  JsonMap? commandValue = <String, Object?>{
    'commandId': 'cmd-e487ba23-1',
    'result': <String, Object?>{
      'kind': 'success',
      'text': 'Plan mode on. Use /plan off to leave.',
    },
  };

  /// Scripted `fileReferences/list` rows. The result is a bare JSON array, so
  /// [_valueFor] hands it over under the envelope's `value` key, exactly as
  /// `RpcResult.fromJson` parks a non-object result. Shapes transcribe
  /// `reference/deepseek-harness/packages/context/file-reference/src/types.ts`
  /// `FileReferenceCandidate` (`path`, `kind`), ranked by the host.
  List<Object?> fileReferenceRowsValue = <Object?>[
    <String, Object?>{'path': 'src', 'kind': 'directory'},
    <String, Object?>{'path': 'src/main.dart', 'kind': 'file'},
  ];

  /// Scripted `fileUploads/upload` receipt. Shapes transcribe
  /// `reference/deepseek-harness/packages/client/file-upload/src/types.ts`
  /// (`FileUploadValue` = `{receiptId, file: FileAttachmentRef}`) over
  /// `packages/attachment/attachment/src/types.ts` (`FileAttachmentRef` =
  /// `{attachmentId, name, bytes}`).
  JsonMap fileUploadValue = <String, Object?>{
    'receiptId': 'receipt-7',
    'file': <String, Object?>{
      'attachmentId': 'sha256:file-a',
      'name': 'notes.pdf',
      'bytes': 2,
    },
  };

  /// Scripted `messageFeedback/list` items. Shapes transcribe
  /// `reference/deepseek-harness/packages/feedback/message-feedback/src/
  /// types.ts` `MessageFeedbackItem` (`messageId`, `rating`, optional `note`
  /// and `category`, `version`, `createdAt`, `updatedAt`).
  List<Object?> messageFeedbackItemsValue = <Object?>[];

  /// Scripted `messageFeedback/list` result envelope; null answers the items
  /// above. Set it to a `{ok: false, error}` envelope for a read refusal.
  JsonMap? messageFeedbackListValue;

  /// Scripted `messageFeedback/{put,delete}` result; null answers the
  /// success branch (the committed item for `put`, `{absent: true}` for
  /// `delete`). Set it to a `{ok: false, error}` envelope to exercise a
  /// refusal.
  JsonMap? messageFeedbackMutationValue;

  /// Scripted `sessionFeedback/record` result; null answers
  /// `{ok: true, value: {recorded: true}}`.
  JsonMap? sessionFeedbackRecordValue;

  /// Scripted `session/projections` roster slot: the parent Session's
  /// `subagentCatalog` projection value
  /// (`reference/deepseek-harness/packages/subagent/subagent/src/catalog.ts`
  /// `viewSchema`, rows shaped by `projection-types.ts`
  /// `SubagentCatalogEntry`). 0.1.7 deleted `subagents/list`, so this
  /// projection is the tree's fact source.
  List<Object?> subagentCatalogValue = <Object?>[];

  /// Models the `session/projections` contract's null answer: the Session does
  /// not exist, so no baseline can be read for it.
  bool projectionsSessionMissing = false;

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
    final failureDetails = _failureDetails.remove(endpoint);
    if (failureDetails != null) {
      return RpcResult(
        ok: false,
        error: RpcError(
          code: failureDetails.$1,
          message: 'scripted failure: ${failureDetails.$1}',
          details: failureDetails.$2,
        ),
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
    if (endpoint == DshRpcEndpoints.fileReferencesList) {
      // A bare-array result rides the envelope's `value` slot
      // (`packages/network/lib/rpc_envelope.dart` `RpcResult.fromJson`).
      return RpcResult(
        ok: true,
        value: <String, Object?>{'value': fileReferenceRowsValue},
      );
    }
    if (endpoint == DshRpcEndpoints.pluginManagerWaitForInstall &&
        waitForInstallValue == null) {
      // The host's "no record of that request" is a null result, not an
      // error and not an empty object.
      return RpcResult(ok: true, value: null);
    }
    if (endpoint == DshRpcEndpoints.sessionProjections &&
        projectionsSessionMissing) {
      return RpcResult(ok: true, value: null);
    }
    // The three account detail reads answer `T | null`, where null is "this
    // host holds no account grant": a null result is a value, not an error.
    if (endpoint == DshRpcEndpoints.accountGetProfile &&
        accountProfileValue == null) {
      return RpcResult(ok: true, value: null);
    }
    if (endpoint == DshRpcEndpoints.accountGetBalance &&
        accountBalanceValue == null) {
      return RpcResult(ok: true, value: null);
    }
    if (endpoint == DshRpcEndpoints.accountGetUnnotifiedBonuses &&
        accountBonusesValue == null) {
      return RpcResult(ok: true, value: null);
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
      case DshRpcEndpoints.fileUploadsUpload:
        return fileUploadValue;
      case DshRpcEndpoints.sessionProjections:
        return <String, Object?>{
          'asOfSeq': 7,
          'values': <String, Object?>{
            'subagentCatalog': subagentCatalogValue,
            if (agentTeamValue != null) 'agentTeam': agentTeamValue,
          },
        };
      case DshRpcEndpoints.subagentsHistory:
        return subagentHistoryValue;
      case DshRpcEndpoints.subagentsPrompt:
        return subagentPromptValue;
      case DshRpcEndpoints.subagentsInterrupt:
        return <String, Object?>{'receipt': true};
      case DshRpcEndpoints.terminalEnvironment:
        return <String, Object?>{
          'cwd': '/home/tester/project',
          'maxInputBytes': 65536,
          'maxCols': 500,
          'maxRows': 200,
          'scrollback': 1000,
        };
      case DshRpcEndpoints.terminalShells:
        return <String, Object?>{
          'shells': <Object?>[
            <String, Object?>{
              'path': '/bin/bash',
              'name': 'bash',
              'args': <Object?>['-i'],
            },
          ],
        };
      case DshRpcEndpoints.terminalList:
        return <String, Object?>{'terminals': terminalRowsValue};
      case DshRpcEndpoints.terminalCreate:
        return _terminalRowJson(
          id: (request['id'] as String?) ?? 'term-1',
          controllerId: 'att-1',
        );
      case DshRpcEndpoints.terminalWrite:
      case DshRpcEndpoints.terminalResize:
      case DshRpcEndpoints.terminalRename:
      case DshRpcEndpoints.terminalClose:
        return <String, Object?>{};
      case DshRpcEndpoints.scheduleList:
      case DshRpcEndpoints.scheduleCatalog:
        return <String, Object?>{'schedules': scheduleRowsValue};
      case DshRpcEndpoints.scheduleHistory:
        return scheduleHistoryValue;
      case DshRpcEndpoints.scheduleUpdate:
        return scheduleUpdateValue;
      case DshRpcEndpoints.scheduleDelete:
        return <String, Object?>{'id': request['id'], 'deleted': true};
      case DshRpcEndpoints.pluginManagerListBundles:
        return <String, Object?>{'bundles': pluginBundlesValue};
      case DshRpcEndpoints.pluginManagerListPlugins:
        return <String, Object?>{'plugins': pluginRowsValue};
      case DshRpcEndpoints.pluginManagerRegistries:
        return <String, Object?>{
          'registry': 'https://registry.npmmirror.com/',
          'fallbackRegistries': <Object?>['https://registry.npmjs.org/'],
          'resolved': 'https://registry.npmmirror.com/',
        };
      case DshRpcEndpoints.pluginManagerInspect:
        return inspectionValue;
      case DshRpcEndpoints.pluginManagerInstallBundle:
      case DshRpcEndpoints.pluginManagerSetBundleEnabled:
      case DshRpcEndpoints.pluginManagerSetPluginEnabled:
      case DshRpcEndpoints.pluginManagerRemoveBundle:
      case DshRpcEndpoints.pluginManagerSetVersionExemption:
        return changeResultValue;
      case DshRpcEndpoints.pluginManagerWaitForInstall:
        return waitForInstallValue!;
      case DshRpcEndpoints.pluginManagerCancelInstall:
        return <String, Object?>{'status': 'cancelled'};
      case DshRpcEndpoints.pluginManagerListVersionExemptions:
        return <String, Object?>{
          'exemptions': <String, Object?>{
            'some-plugin@1.0.0': <Object?>['0.1.7-rc.2'],
          },
          'warnings': <Object?>['compatibility.json is not writable'],
        };
      case DshRpcEndpoints.pluginRegistryProbeFastest:
        // A non-object result rides the transport's `{value, path}` carrier.
        return <String, Object?>{
          'value': 'https://registry.npmmirror.com/',
          'path': 'https://registry.npmmirror.com/',
        };
      case DshRpcEndpoints.jobKill:
        // `JobKillValue` (`packages/api/job-controller/src/types.ts`): an
        // already-finished job is a success, not an error.
        return <String, Object?>{'outcome': 'requested'};
      case DshRpcEndpoints.workspacePinSession:
      case DshRpcEndpoints.workspaceUnpinSession:
        return pinValue;
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
      case DshRpcEndpoints.agentPresetsRead:
        return agentPresetDocumentValue;
      case DshRpcEndpoints.permissionPresetsCatalog:
        return permissionCatalogValue;
      case DshRpcEndpoints.accountGetState:
        return accountStateValue;
      // The three nullable reads never reach here with a null script (that
      // path is answered in [_answer]); the fallback keeps the switch total.
      case DshRpcEndpoints.accountGetProfile:
        return accountProfileValue ?? const <String, Object?>{};
      case DshRpcEndpoints.accountGetBalance:
        return accountBalanceValue ?? const <String, Object?>{};
      case DshRpcEndpoints.accountGetUnnotifiedBonuses:
        return accountBonusesValue ?? const <String, Object?>{};
      case DshRpcEndpoints.accountAckBonusNotified:
        // `Promise<boolean>` is not a JSON object, so the envelope parks the
        // raw answer under `value` (`RpcResult.fromJson`).
        return <String, Object?>{'value': accountAckValue};
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
        // reference/deepseek-harness/packages/preset/agent-preset-registry/
        // src/types.ts AgentPresetRoster: the row carries no trust signal and
        // the roster carries no authoring capability, because 0.1.7 moved
        // preset authoring off the Remote surface.
        return <String, Object?>{
          'presets': <Object?>[
            <String, Object?>{'id': 'standard', 'isDefault': true, 'order': 1},
            <String, Object?>{
              'id': 'minimal',
              'isDefault': false,
              'order': 2,
              'name': 'Tiny',
              'description': 'Two tools only',
            },
            <String, Object?>{
              'id': 'my-agent',
              'isDefault': false,
              'order': 3,
              'broken': 'composition missing',
            },
          ],
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
      case DshRpcEndpoints.messageFeedbackList:
        return messageFeedbackListValue ??
            <String, Object?>{
              'ok': true,
              'value': <String, Object?>{'items': messageFeedbackItemsValue},
            };
      case DshRpcEndpoints.messageFeedbackPut:
        // A scripted envelope is a refusal or a hand-built item; otherwise the
        // fake commits what the client asked for, the way the Host's `put`
        // answers the durable item it just wrote.
        final scriptedMutation = messageFeedbackMutationValue;
        if (scriptedMutation != null) return scriptedMutation;
        return <String, Object?>{
          'ok': true,
          'value': <String, Object?>{
            'messageId': request['messageId'],
            'rating': request['rating'],
            if (request['note'] != null) 'note': request['note'],
            if (request['category'] != null) 'category': request['category'],
            'version': 'v-put-1',
            'createdAt': 100,
            'updatedAt': 100,
          },
        };
      case DshRpcEndpoints.messageFeedbackDelete:
        return messageFeedbackMutationValue ??
            <String, Object?>{
              'ok': true,
              'value': <String, Object?>{'absent': true},
            };
      case DshRpcEndpoints.sessionFeedbackRecord:
        return sessionFeedbackRecordValue ??
            <String, Object?>{
              'ok': true,
              'value': <String, Object?>{'recorded': true},
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

class ScriptedHarnessSocket implements DshWritableEventSocket {
  ScriptedHarnessSocket({this.muxFrames = const <ServerRequest>[]});

  final List<ServerRequest> muxFrames;
  final Completer<void> _muxRelease = Completer<void>();
  final List<String> _paths = <String>[];

  /// Upstream mux control messages this double received, decoded: the follow
  /// opens the repository sends carry the session address under test.
  final List<JsonMap> sentMuxMessages = <JsonMap>[];

  List<String> get connectedPaths => List<String>.of(_paths);

  @override
  void send(String path, String message) {
    sentMuxMessages.add((jsonDecode(message) as Map).cast<String, Object?>());
  }

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

/// One `inbox` projection entry: a user-role message in the shape
/// `packages/core/agent-loop/src/inbox.ts` publishes
/// (`inboxProjectionSchema` carries whole `UserMessage` values).
JsonMap _inboxUserMessage(String id, String text) => <String, Object?>{
  'id': id,
  'role': 'user',
  'source': <String, Object?>{'kind': 'user'},
  'content': <Object?>[
    <String, Object?>{'type': 'text', 'text': text},
  ],
};

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
    'loadModels and observeSessionModels reflect modelSelection projection',
    () async {
      final rpc = HarnessFakeRpc();
      final socket = ReconnectableHarnessSocket();
      final repository = await resyncFixture(rpc, socket);
      await pumpEventQueue();

      // Initially loads host default
      final initial = await repository.loadModels('session-1');
      expect(initial.current.model, 'glm-x');

      // Observe session models
      final observed = <SessionModels>[];
      final sub = repository.observeSessionModels('session-1').listen((m) {
        if (m != null) observed.add(m);
      });
      await pumpEventQueue();

      // Push a modelSelection projection frame over session-control
      socket.emitMuxFrame(
        ServerRequest(
          rpcId: 'session-control',
          method: 'item',
          payload: <String, Object?>{
            'type': 'projection',
            'sessionId': 'session-1',
            'key': 'modelSelection',
            'value': <String, Object?>{
              'lastUsed': null,
              'next': <String, Object?>{
                'provider': 'anthropic',
                'model': 'claude-3-7-sonnet',
              },
            },
            'seq': 5,
          },
        ),
      );
      await pumpEventQueue();

      expect(observed, isNotEmpty);
      expect(observed.last.current.provider, 'anthropic');
      expect(observed.last.current.model, 'claude-3-7-sonnet');

      // A subsequent loadModels returns the session selection, not host default
      final refreshed = await repository.loadModels('session-1');
      expect(refreshed.current.provider, 'anthropic');
      expect(refreshed.current.model, 'claude-3-7-sonnet');

      await sub.cancel();
    },
  );

  test(
    'forwarded llm/adapters-updated invalidates model catalog cache',
    () async {
      final rpc = HarnessFakeRpc();
      final socket = ReconnectableHarnessSocket();
      final repository = await resyncFixture(rpc, socket);
      await pumpEventQueue();

      await repository.loadModels('session-1');
      expect(rpc.callCountFor(DshRpcEndpoints.sessionModelCatalog), 1);

      // Subsequent call reuses cached catalog
      await repository.loadModels('session-1');
      expect(rpc.callCountFor(DshRpcEndpoints.sessionModelCatalog), 1);

      // Remote event arrives on $events
      socket.emitMuxFrame(
        ServerRequest(
          rpcId: 'remote-events',
          method: 'item',
          payload: <String, Object?>{
            'type': 'emit',
            'event': 'llm/adapters-updated',
            'args': <Object?>[],
          },
        ),
      );
      await pumpEventQueue();

      // Cache is invalidated; next load fetches fresh catalog from backend
      await repository.loadModels('session-1');
      expect(rpc.callCountFor(DshRpcEndpoints.sessionModelCatalog), 2);
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
    'whole-log sessionStats and tokenUsage projections govern the line',
    () async {
      // The host computes these across the complete durable log, so the figures
      // must not move when history is paged — the window fold is only the
      // fallback for an assembly that publishes neither key
      // (`session-stats/src/types.ts`; `ui-chat/StatsPills.tsx:319`).
      final rpc = HarnessFakeRpc(<Object?>[
        <String, Object?>{
          'sessionId': 'session-stats',
          'updatedAt': 1,
          'running': false,
          'blank': false,
        },
      ]);
      final socket = ScriptedHarnessSocket(
        muxFrames: <ServerRequest>[
          ServerRequest(
            rpcId: 'projection-stats',
            method: 'session/projection',
            payload: <String, Object?>{
              'type': 'projection',
              'sessionId': 'session-stats',
              'key': 'sessionStats',
              'seq': 30,
              'value': <String, Object?>{
                'turns': 7,
                'steps': 21,
                'llmMs': 1000,
                'toolMs': 2000,
                'ttftMs': 300,
                'ttftSteps': 7,
                'decodeMs': 400,
                'decodeTokens': 500,
              },
            },
          ),
          ServerRequest(
            rpcId: 'projection-usage',
            method: 'session/projection',
            payload: <String, Object?>{
              'type': 'projection',
              'sessionId': 'session-stats',
              'key': 'tokenUsage',
              'seq': 31,
              'value': <String, Object?>{
                'uncachedInputTokens': 100,
                'cacheReadTokens': 900,
                'cacheWriteTokens': 0,
                'outputTokens': 50,
              },
            },
          ),
        ],
      );
      final repository = await harnessRepository(rpc, socket);
      await pumpEventQueue();
      socket.releaseMuxFrames();
      await pumpEventQueue();

      final stats = await repository.observeSessionStats('session-stats').first;
      expect(stats.turns, 7);
      expect(stats.steps, 21);
      expect(stats.llmMs, 1000);
      expect(stats.toolMs, 2000);
      expect(stats.ttftMs, 300);
      expect(stats.decodeTokens, 500);
      // Billed input is the three prompt-side buckets summed, the reference's
      // own denominator for the cache-hit share.
      expect(stats.billedInputTokens, 1000);
      expect(stats.cacheReadTokens, 900);
      expect(stats.outputTokens, 50);
      expect(stats.cacheHitPercent, 90);
    },
  );

  test(
    'a session the host reports no whole-log figures for keeps the fold',
    () async {
      final rpc = HarnessFakeRpc(<Object?>[
        <String, Object?>{
          'sessionId': 'session-fold',
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
                  'session-fold': <String, Object?>{
                    'asOfSeq': 4,
                    'values': <String, Object?>{},
                  },
                },
              },
            },
          ),
        ],
      );
      final repository = await harnessRepository(rpc, socket);
      await pumpEventQueue();
      socket.releaseMuxFrames();
      await pumpEventQueue();

      final stats = await repository.observeSessionStats('session-fold').first;
      expect(stats, const SessionWindowStats());
    },
  );

  test('a projection frame older than the value held is dropped', () async {
    // The reference's projection store has one ordering rule: a value whose
    // `seq` is not newer than the row's is dropped
    // (`projection-store.ts` `apply`). Without it a `session/list` pull that
    // raced a live frame lands afterwards and flips the title back.
    final rpc = HarnessFakeRpc(<Object?>[
      <String, Object?>{
        'sessionId': 'session-wm',
        'updatedAt': 1,
        'running': false,
        'blank': false,
        // The list row's own projection block sits at an older cut than the
        // live frame below, which is exactly the race the watermark settles.
        'projections': <String, Object?>{
          'asOfSeq': 5,
          'values': <String, Object?>{'title': 'list title'},
        },
      },
    ]);
    final socket = ScriptedHarnessSocket(
      muxFrames: <ServerRequest>[
        ServerRequest(
          rpcId: 'projection-1',
          method: 'session/projection',
          payload: <String, Object?>{
            'type': 'projection',
            'sessionId': 'session-wm',
            'key': 'title',
            'value': 'newer title',
            'seq': 40,
          },
        ),
        ServerRequest(
          rpcId: 'projection-2',
          method: 'session/projection',
          payload: <String, Object?>{
            'type': 'projection',
            'sessionId': 'session-wm',
            'key': 'title',
            'value': 'older title',
            'seq': 12,
          },
        ),
      ],
    );
    final repository = await harnessRepository(rpc, socket);
    await pumpEventQueue();
    socket.releaseMuxFrames();
    await pumpEventQueue();
    // A later list pull must not reset the row either: the pull's own block
    // sits at an older `asOfSeq`, so its title loses to the value held.
    await repository.refreshSessions();
    await pumpEventQueue();

    final session = (await repository.observeSessions().first).single;
    expect(session.title, 'newer title');
  });

  test('a complete baseline clears a projection key it omits', () async {
    // A control baseline is the host's whole store for the session, so a key
    // absent from it means the host no longer computes that value (the
    // reference `ProjectionValueStore.seed` deletes rows the baseline omits) —
    // a restarted host must not keep showing the previous goal.
    final rpc = HarnessFakeRpc(<Object?>[
      <String, Object?>{
        'sessionId': 'session-clear',
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
                'session-clear': <String, Object?>{
                  'asOfSeq': 9,
                  'values': <String, Object?>{
                    'todos': <Object?>[
                      <String, Object?>{
                        'content': 'first item',
                        'status': 'pending',
                      },
                    ],
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
            'type': 'baseline',
            'value': <String, Object?>{
              'projections': <String, Object?>{
                'session-clear': <String, Object?>{
                  'asOfSeq': 20,
                  'values': <String, Object?>{},
                },
              },
            },
          },
        ),
      ],
    );
    final repository = await harnessRepository(rpc, socket);
    await pumpEventQueue();
    socket.releaseMuxFrames();
    await pumpEventQueue();

    final todos = await repository.observeTodos('session-clear').first;
    expect(todos, isEmpty);
  });

  test('a baseline inbox seeds a session opened later', () async {
    // The baseline is retained per session, not replayed once: a session this
    // client had not instantiated when the generation's control frame landed
    // still shows the messages that were already queued for it.
    //
    // Fixture: 0.1.7's control baseline carries each session's whole projection
    // block (there is no separate `queues` block any more), and the pending
    // input lives in the `inbox` value
    // (`packages/core/agent-loop/src/inbox.ts` `inboxProjectionSchema`).
    final rpc = HarnessFakeRpc(<Object?>[
      <String, Object?>{
        'sessionId': 'session-late',
        'updatedAt': 1,
        'running': true,
        'blank': false,
      },
    ])..historyEvents['session-late'] = <Object?>[_assistantMessageEvent()];
    final socket = ScriptedHarnessSocket(
      muxFrames: <ServerRequest>[
        ServerRequest(
          rpcId: 'session-control',
          method: 'session/control',
          payload: <String, Object?>{
            'type': 'baseline',
            'value': <String, Object?>{
              'projections': <String, Object?>{
                'session-late': <String, Object?>{
                  'asOfSeq': 4,
                  'values': <String, Object?>{
                    'inbox': <String, Object?>{
                      'next-turn': <Object?>[
                        <String, Object?>{
                          'id': 'queued-1',
                          'role': 'user',
                          'source': <String, Object?>{'kind': 'user'},
                          'content': <Object?>[
                            <String, Object?>{'type': 'text', 'text': 'held'},
                          ],
                        },
                      ],
                      'next-step': <Object?>[],
                    },
                  },
                },
              },
            },
          },
        ),
      ],
    );
    final repository = await harnessRepository(rpc, socket);
    await pumpEventQueue();
    socket.releaseMuxFrames();
    await pumpEventQueue();

    // Opening the session after the baseline still seeds its queue dock.
    await repository.openSession('session-late');
    await pumpEventQueue();
    final window = await repository
        .observeTimelineWindow('session-late')
        .firstWhere(
          (value) => value.items.any((item) => item is TimelineQueue),
        );
    final queue = window.items.whereType<TimelineQueue>().single;
    expect(queue.items, hasLength(1));
    expect(queue.items.single.itemId, 'queued-1');
  });

  test('inbox projection values reach the dock with the host placements', () async {
    // 0.1.7 publishes pending input as the `inbox` projection, whose two
    // targets are the whole placement vocabulary left on the wire: `next-turn`
    // is a queued turn, and `next-step` is `steering` for a human-authored
    // message and `context` otherwise — the mapping the deleted control-stream
    // host function `queueItemsFromInbox` used.
    final rpc = HarnessFakeRpc(<Object?>[
      <String, Object?>{
        'sessionId': 'session-a',
        'updatedAt': 1,
        'blank': false,
      },
    ])..historyEvents['session-a'] = <Object?>[_assistantMessageEvent()];
    final socket = ScriptedHarnessSocket(
      muxFrames: <ServerRequest>[
        ServerRequest(
          rpcId: 'session-control',
          method: 'session/control',
          payload: <String, Object?>{
            'type': 'baseline',
            'value': <String, Object?>{
              'projections': <String, Object?>{
                'session-a': <String, Object?>{
                  'asOfSeq': 9,
                  'values': <String, Object?>{
                    'inbox': <String, Object?>{
                      'next-turn': <Object?>[
                        <String, Object?>{
                          'id': 'turn-1',
                          'role': 'user',
                          'source': <String, Object?>{
                            'kind': 'user',
                            'rpcId': 'rpc-local-1',
                          },
                          'content': <Object?>[
                            <String, Object?>{'type': 'text', 'text': 'queued'},
                          ],
                        },
                      ],
                      'next-step': <Object?>[
                        <String, Object?>{
                          'id': 'step-1',
                          'role': 'user',
                          'source': <String, Object?>{'kind': 'user'},
                          'content': <Object?>[
                            <String, Object?>{'type': 'text', 'text': 'steer'},
                          ],
                        },
                        <String, Object?>{
                          'id': 'step-2',
                          'role': 'user',
                          'source': <String, Object?>{
                            'kind': 'skill-invocation',
                          },
                          'content': <Object?>[
                            <String, Object?>{
                              'type': 'text',
                              'text': 'context',
                            },
                          ],
                        },
                      ],
                    },
                  },
                },
              },
            },
          },
        ),
      ],
    );
    final repository = await harnessRepository(rpc, socket);
    await pumpEventQueue();
    await repository.openSession('session-a');
    socket.releaseMuxFrames();
    await pumpEventQueue();

    final window = await repository
        .observeTimelineWindow('session-a')
        .firstWhere(
          (value) => value.items.any((item) => item is TimelineQueue),
        );
    final queue = window.items.whereType<TimelineQueue>().single;
    // Queued turns first, then next-step in its own order (the deleted host
    // function's array order).
    expect(queue.items.map((item) => item.itemId).toList(), <String>[
      'turn-1',
      'step-1',
      'step-2',
    ]);
    expect(queue.items.map((item) => item.placement).toList(), <QueuePlacement>[
      QueuePlacement.queued,
      QueuePlacement.steering,
      QueuePlacement.context,
    ]);
    expect(queue.items.first.text, 'queued');
  });

  test('a live inbox projection frame replaces the dock in place', () async {
    // A live `inbox` update is a whole-value replacement: the generation's
    // baseline seeds one queued turn, and the frame that follows carries a
    // different one, so the dock must show exactly the later state.
    final rpc = HarnessFakeRpc(<Object?>[
      <String, Object?>{
        'sessionId': 'session-a',
        'updatedAt': 1,
        'blank': false,
      },
    ])..historyEvents['session-a'] = <Object?>[_assistantMessageEvent()];
    final socket = ScriptedHarnessSocket(
      muxFrames: <ServerRequest>[
        ServerRequest(
          rpcId: 'session-control',
          method: 'session/control',
          payload: <String, Object?>{
            'type': 'baseline',
            'value': <String, Object?>{
              'projections': <String, Object?>{
                'session-a': <String, Object?>{
                  'asOfSeq': 9,
                  'values': <String, Object?>{
                    'inbox': <String, Object?>{
                      'next-turn': <Object?>[
                        _inboxUserMessage('turn-1', 'baseline'),
                      ],
                      'next-step': <Object?>[],
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
            'sessionId': 'session-a',
            'key': 'inbox',
            'seq': 12,
            'value': <String, Object?>{
              'next-turn': <Object?>[_inboxUserMessage('turn-2', 'later')],
              'next-step': <Object?>[],
            },
          },
        ),
      ],
    );
    final repository = await harnessRepository(rpc, socket);
    await pumpEventQueue();
    await repository.openSession('session-a');
    await pumpEventQueue();
    socket.releaseMuxFrames();
    await pumpEventQueue();

    final window = await repository
        .observeTimelineWindow('session-a')
        .firstWhere(
          (value) => value.items.whereType<TimelineQueue>().any(
            (queue) => queue.items.isNotEmpty,
          ),
        );
    final queue = window.items.whereType<TimelineQueue>().single;
    expect(queue.items.map((item) => item.itemId).toList(), <String>['turn-2']);
    expect(queue.items.single.text, 'later');
  });

  test('an emptied inbox projection clears the dock', () async {
    final rpc = HarnessFakeRpc(<Object?>[
      <String, Object?>{
        'sessionId': 'session-a',
        'updatedAt': 1,
        'blank': false,
      },
    ])..historyEvents['session-a'] = <Object?>[_assistantMessageEvent()];
    final socket = ScriptedHarnessSocket(
      muxFrames: <ServerRequest>[
        ServerRequest(
          rpcId: 'session-control',
          method: 'session/control',
          payload: <String, Object?>{
            'type': 'projection',
            'sessionId': 'session-a',
            'key': 'inbox',
            'seq': 13,
            'value': <String, Object?>{
              'next-turn': <Object?>[],
              'next-step': <Object?>[],
            },
          },
        ),
      ],
    );
    final repository = await harnessRepository(rpc, socket);
    await pumpEventQueue();
    await repository.openSession('session-a');
    await pumpEventQueue();
    socket.releaseMuxFrames();
    await pumpEventQueue();

    final window = await repository
        .observeTimelineWindow('session-a')
        .firstWhere(
          (value) => value.items.any((item) => item is TimelineQueue),
        );
    expect(window.items.whereType<TimelineQueue>().single.items, isEmpty);
  });

  test(
    'each followed session opens one job/list stream and folds its rows',
    () async {
      // 0.1.7 moved the job roster off the control baseline onto a per-session
      // stream (`packages/api/job-controller/src/index.ts`
      // `@Remote({ mode: 'stream' }) list`), whose frames are whole-set `rows`.
      final rpc = HarnessFakeRpc(<Object?>[
        <String, Object?>{
          'sessionId': 'session-j',
          'updatedAt': 1,
          'blank': false,
        },
      ])..historyEvents['session-j'] = <Object?>[_assistantMessageEvent()];
      final socket = ScriptedHarnessSocket(
        muxFrames: <ServerRequest>[
          ServerRequest(
            rpcId: 'job-list-session-j',
            method: 'job/list',
            payload: <String, Object?>{
              'type': 'rows',
              'jobs': <Object?>[
                <String, Object?>{
                  'id': 'bash-1',
                  'kind': 'bash',
                  'label': 'pnpm test',
                  'progress': '3/10',
                  'owner': 'session-j',
                  'outputLimitBytes': 4096,
                  'status': 'running',
                  'startedAt': 5,
                },
                <String, Object?>{
                  'id': 'bash-2',
                  'kind': 'bash',
                  'label': 'build apk',
                  'status': 'completed',
                  'startedAt': 1,
                  'finishedAt': 4,
                  'detail': 'exit code: 0',
                },
              ],
            },
          ),
        ],
      );
      final repository = await harnessRepository(rpc, socket);
      await pumpEventQueue();
      await repository.openSession('session-j');
      await pumpEventQueue();

      final open = socket.sentMuxMessages.firstWhere(
        (message) => message['streamId'] == 'job-list-session-j',
      );
      expect(open['type'], 'open');
      expect(open['endpoint'], 'job/list');
      expect(open['payload'], <String, Object?>{
        'args': <String, Object?>{
          'request': <String, Object?>{'sessionId': 'session-j'},
        },
      });

      socket.releaseMuxFrames();
      await pumpEventQueue();

      final window = await repository
          .observeTimelineWindow('session-j')
          .firstWhere(
            (value) => value.items.whereType<TimelineJobs>().any(
              (item) => item.jobs.isNotEmpty,
            ),
          );
      final jobs = window.items.whereType<TimelineJobs>().single.jobs;
      expect(jobs.map((job) => job.id).toList(), <String>['bash-1', 'bash-2']);
      expect(jobs.first.status, JobStatus.running);
      expect(jobs.first.label, 'pnpm test');
      // `owner` and `progress` are decoded from 0.1.7's `JobView`
      // (`packages/jobs/jobs/src/view.ts`); `outputLimitBytes` stays unread
      // because nothing on this surface consumes it.
      expect(jobs.first.owner, 'session-j');
      expect(jobs.first.progress, '3/10');
      expect(jobs.last.status, JobStatus.completed);
      expect(jobs.last.detail, 'exit code: 0');
    },
  );

  test(
    'a followed session with no jobs still carries the roster mirror',
    () async {
      // `job/list` yields one whole-set `rows` frame on open
      // (`packages/api/job-controller/src/rows.ts` yields it
      // unconditionally), so a session with no jobs answers `jobs: []` and
      // the fold still mints its `TimelineJobs` item. The window of an
      // otherwise message-free conversation is therefore never empty: the UI
      // cannot read an empty `timeline` as "nothing has happened here yet".
      final rpc = HarnessFakeRpc(<Object?>[
        <String, Object?>{
          'sessionId': 'session-k',
          'updatedAt': 1,
          'blank': true,
        },
      ])..historyEvents['session-k'] = <Object?>[];
      final socket = ScriptedHarnessSocket(
        muxFrames: <ServerRequest>[
          ServerRequest(
            rpcId: 'job-list-session-k',
            method: 'job/list',
            payload: <String, Object?>{'type': 'rows', 'jobs': <Object?>[]},
          ),
        ],
      );
      final repository = await harnessRepository(rpc, socket);
      await pumpEventQueue();
      await repository.openSession('session-k');
      await pumpEventQueue();
      socket.releaseMuxFrames();
      await pumpEventQueue();

      final window = await repository
          .observeTimelineWindow('session-k')
          .firstWhere(
            (value) => value.items.any((item) => item is TimelineJobs),
          );
      expect(window.items.whereType<TimelineJobs>().single.jobs, isEmpty);
      expect(window.items, isNotEmpty);
    },
  );

  test(
    'job/kill posts the request-wrapped args and reports admission',
    () async {
      // `kill(request: JobKillRequest)` is the only unary in the `job`
      // namespace, and the request carries the session fence
      // (`packages/api/job-controller/src/index.ts` `@Remote('kill')`).
      final rpc = HarnessFakeRpc(<Object?>[
        <String, Object?>{
          'sessionId': 'session-j',
          'updatedAt': 1,
          'blank': false,
        },
      ]);
      final socket = ScriptedHarnessSocket();
      final repository = await harnessRepository(rpc, socket);
      await pumpEventQueue();

      await repository.killJob('session-j', 'bash-1');
      await pumpEventQueue();

      final payload = rpc.payloads(DshRpcEndpoints.jobKill).single;
      expect(payload['request'], <String, Object?>{
        'sessionId': 'session-j',
        'jobId': 'bash-1',
      });
    },
  );

  test('a refused job/kill surfaces the host business code', () async {
    final rpc = HarnessFakeRpc(<Object?>[
      <String, Object?>{
        'sessionId': 'session-j',
        'updatedAt': 1,
        'blank': false,
      },
    ]);
    final socket = ScriptedHarnessSocket();
    final repository = await harnessRepository(rpc, socket);
    await pumpEventQueue();

    // The session's list no longer carries a killable row under that id
    // (`packages/api/job-controller/src/types.ts` `RemoteErrorDetailsMap`).
    rpc.failNextCall(DshRpcEndpoints.jobKill, 'job/not-found');

    await expectLater(
      repository.killJob('session-j', 'bash-1'),
      throwsA(
        isA<DshBusinessException>().having(
          (DshBusinessException error) => error.code,
          'code',
          'job/not-found',
        ),
      ),
    );
  });

  test(
    'a job/follow observation decodes its three frame kinds and ends',
    () async {
      // `job/follow` is a logical stream opened by literal; its frames are the
      // `opened`/`output`/`status` union (`packages/api/job-controller/src/
      // types.ts` `JobFollowFrame`). `next` is the resume offset, and the
      // terminal `status` closes the generation.
      final rpc = HarnessFakeRpc(<Object?>[
        <String, Object?>{
          'sessionId': 'session-j',
          'updatedAt': 1,
          'blank': false,
        },
      ]);
      final socket = ScriptedHarnessSocket(
        muxFrames: <ServerRequest>[
          _jobFollowFrame('job-follow-0', <String, Object?>{
            'type': 'opened',
            'from': 0,
            'job': _jobRowJson(
              id: 'bash-1',
              status: 'running',
              total: 12,
              earliest: 0,
            ),
          }),
          _jobFollowFrame('job-follow-0', <String, Object?>{
            'type': 'output',
            'next': 12,
            'chunks': <Object?>[
              <String, Object?>{
                'at': 0,
                'text': 'building\n',
                'channel': 'stdout',
              },
              <String, Object?>{
                'at': 9,
                'text': 'warning\n',
                'channel': 'stderr',
                'gapBefore': true,
              },
            ],
          }),
          _jobFollowFrame('job-follow-0', <String, Object?>{
            'type': 'status',
            'job': _jobRowJson(
              id: 'bash-1',
              status: 'completed',
              total: 18,
              earliest: 0,
              detail: 'exit code: 0',
            ),
          }),
        ],
      );
      final repository = await harnessRepository(rpc, socket);
      await pumpEventQueue();

      final frames = <JobOutputFrame>[];
      final subscription = repository
          .observeJobOutput('session-j', 'bash-1')
          .listen(frames.add);
      addTearDown(subscription.cancel);
      await pumpEventQueue();

      final open = socket.sentMuxMessages.firstWhere(
        (message) => message['endpoint'] == 'job/follow',
      );
      expect(open['type'], 'open');
      expect(open['payload'], <String, Object?>{
        'args': <String, Object?>{
          'request': <String, Object?>{
            'sessionId': 'session-j',
            'jobId': 'bash-1',
          },
        },
      });

      socket.releaseMuxFrames();
      await pumpEventQueue();

      expect(frames, hasLength(3));
      final opened = frames[0] as JobOutputOpened;
      expect(opened.from, 0);
      expect(opened.job.status, JobStatus.running);
      expect(opened.job.output?.total, 12);
      final chunks = frames[1] as JobOutputChunks;
      expect(chunks.next, 12);
      expect(chunks.lossy, isFalse);
      expect(chunks.chunks, hasLength(2));
      expect(chunks.chunks.first.channel, JobChannel.stdout);
      expect(chunks.chunks.first.gapBefore, isFalse);
      expect(chunks.chunks.last.channel, JobChannel.stderr);
      expect(chunks.chunks.last.gapBefore, isTrue);
      final status = frames[2] as JobOutputStatus;
      expect(status.job.status, JobStatus.completed);
      expect(status.job.detail, 'exit code: 0');
    },
  );

  test(
    'collapsing a job observation cancels its route, and a re-expand resumes',
    () async {
      final rpc = HarnessFakeRpc(<Object?>[
        <String, Object?>{
          'sessionId': 'session-j',
          'updatedAt': 1,
          'blank': false,
        },
      ]);
      final socket = ScriptedHarnessSocket(
        muxFrames: <ServerRequest>[
          _jobFollowFrame('job-follow-0', <String, Object?>{
            'type': 'opened',
            'from': 0,
            'job': _jobRowJson(
              id: 'bash-1',
              status: 'running',
              total: 0,
              earliest: 0,
            ),
          }),
          _jobFollowFrame('job-follow-0', <String, Object?>{
            'type': 'output',
            'next': 7,
            'chunks': <Object?>[
              <String, Object?>{'at': 0, 'text': 'seven!!'},
            ],
          }),
        ],
      );
      final repository = await harnessRepository(rpc, socket);
      await pumpEventQueue();

      final frames = <JobOutputFrame>[];
      final subscription = repository
          .observeJobOutput('session-j', 'bash-1')
          .listen(frames.add);
      await pumpEventQueue();
      socket.releaseMuxFrames();
      await pumpEventQueue();
      expect((frames.last as JobOutputChunks).next, 7);

      await subscription.cancel();
      await pumpEventQueue();

      final cancel = socket.sentMuxMessages.firstWhere(
        (message) =>
            message['type'] == 'cancel' &&
            message['streamId'] == 'job-follow-0',
      );
      expect(cancel['streamId'], 'job-follow-0');

      // A re-expansion resumes from the last published offset instead of
      // replaying the retained head.
      final resumed = repository
          .observeJobOutput('session-j', 'bash-1', resumeFrom: 7)
          .listen((_) {});
      addTearDown(resumed.cancel);
      await pumpEventQueue();

      final reopened = socket.sentMuxMessages
          .where((message) => message['endpoint'] == 'job/follow')
          .last;
      expect(reopened['payload'], <String, Object?>{
        'args': <String, Object?>{
          'request': <String, Object?>{
            'sessionId': 'session-j',
            'jobId': 'bash-1',
            'from': 7,
          },
        },
      });
    },
  );

  test(
    'the plugin manager roster decodes bundles, rows, and registries',
    () async {
      final rpc = HarnessFakeRpc(<Object?>[])
        ..pluginBundlesValue = <Object?>[
          <String, Object?>{
            'name': 'dsh-schedule',
            'version': '0.1.7-rc.2',
            'meta': <String, Object?>{
              'title': <String, Object?>{'en': 'Scheduled tasks', 'zh': '定时任务'},
              'description': <String, Object?>{'en': 'Reminders'},
            },
            'description': 'Reminders on the host',
            'enabled': false,
            'installed': true,
            'optional': true,
            'removable': true,
            'overrides': <Object?>['@deepseek-ai/dsh-old'],
            'rows': <Object?>[
              <String, Object?>{
                'rowId': 'schedule-core',
                'moduleName': '@deepseek-ai/dsh-schedule',
                'entryId': 'entry-1',
              },
              <String, Object?>{'rowId': 'legacy', 'moduleName': 'legacy-pkg'},
            ],
          },
        ]
        ..pluginRowsValue = <Object?>[
          <String, Object?>{
            'entryId': 'entry-1',
            'moduleName': '@deepseek-ai/dsh-schedule',
            'enabled': true,
            'patchId': 'patch-1',
          },
          <String, Object?>{
            'entryId': 'entry-2',
            'moduleName': '@deepseek-ai/dsh-base',
            'enabled': true,
            'readOnlyReason': 'management-required',
          },
        ];
      final socket = ScriptedHarnessSocket();
      final repository = await harnessRepository(rpc, socket);
      await pumpEventQueue();

      final bundles = await repository.listPluginBundles();
      final bundle = bundles.single;
      expect(bundle.name, 'dsh-schedule');
      expect(bundle.installed, isTrue);
      expect(bundle.removable, isTrue);
      expect(bundle.title?.resolve('zh'), '定时任务');
      expect(bundle.title?.resolve('en'), 'Scheduled tasks');
      // A locale the host did not send falls back to English.
      expect(bundle.title?.resolve('fr'), 'Scheduled tasks');
      expect(bundle.description, 'Reminders on the host');
      expect(bundle.metaDescription?.resolve('en'), 'Reminders');
      expect(bundle.overrides, <String>['@deepseek-ai/dsh-old']);
      expect(bundle.rows, hasLength(2));
      expect(bundle.rows.first.entryId, 'entry-1');
      // A row with no loaded entry carries no addressable id.
      expect(bundle.rows.last.entryId, isNull);

      final plugins = await repository.listPlugins();
      expect(plugins.first.patchId, 'patch-1');
      expect(plugins.first.readOnlyReason, isNull);
      expect(
        plugins.last.readOnlyReason,
        PluginReadOnlyReason.managementRequired,
      );

      final registries = await repository.pluginRegistries();
      expect(registries.resolved, 'https://registry.npmmirror.com/');
      expect(registries.offered, <String>[
        'https://registry.npmmirror.com/',
        'https://registry.npmjs.org/',
      ]);

      expect(
        await repository.fastestPluginRegistry(),
        'https://registry.npmmirror.com/',
      );
    },
  );

  test('inspect decodes a refused spec as a value, not an error', () async {
    final rpc = HarnessFakeRpc(<Object?>[])
      ..inspectionValue = <String, Object?>{
        'status': 'refused',
        'problem': 'network',
        'reason': 'the registry did not answer',
        'registries': <Object?>['https://registry.npmjs.org/'],
      };
    final socket = ScriptedHarnessSocket();
    final repository = await harnessRepository(rpc, socket);
    await pumpEventQueue();

    final inspection = await repository.inspectPluginSpec('some-plugin');
    final refused = inspection as PluginSpecRefused;
    expect(refused.problem, PluginInspectProblem.network);
    expect(refused.registries, <String>['https://registry.npmjs.org/']);
    // The spec travels in its wire field, with the registry under `options`.
    final payload = rpc.payloads(DshRpcEndpoints.pluginManagerInspect).single;
    expect(payload['spec'], 'some-plugin');
  });

  test('an install gates activation and settles on its ChangeResult', () async {
    final rpc = HarnessFakeRpc(<Object?>[])
      ..changeResultValue = <String, Object?>{
        'changed': true,
        'application': 'restart-required',
        'stage': 'install',
        'target': 'some-plugin@1.0.0',
        'bundle': 'some-plugin',
        'pendingBuilds': <Object?>[],
      };
    final socket = ScriptedHarnessSocket();
    final repository = await harnessRepository(rpc, socket);
    await pumpEventQueue();

    final result = await repository.installPluginBundle(
      'some-plugin@1.0.0',
      requestId: 'req-1',
      registry: 'https://registry.npmmirror.com/',
    );
    expect(result.needsRestart, isTrue);
    expect(result.bundle, 'some-plugin');

    // Activation is deferred: the request always asks for `enabled: false`,
    // and the client-minted request id is what makes the host emit progress.
    final payload = rpc
        .payloads(DshRpcEndpoints.pluginManagerInstallBundle)
        .single;
    expect(payload['spec'], 'some-plugin@1.0.0');
    final options = asJsonObject(payload['options'])!;
    expect(options['enabled'], isFalse);
    expect(options['requestId'], 'req-1');
    expect(options['registry'], 'https://registry.npmmirror.com/');
  });

  test('a lost install reply reconciles through waitForInstall', () async {
    final rpc = HarnessFakeRpc(<Object?>[])
      ..waitForInstallValue = <String, Object?>{
        'changed': true,
        'application': 'applied',
        'stage': 'install',
        'target': 'some-plugin',
        'bundle': 'some-plugin',
      };
    final socket = ScriptedHarnessSocket();
    final repository = await harnessRepository(rpc, socket);
    await pumpEventQueue();

    final reconciled = await repository.waitForPluginInstall('req-9');
    expect(reconciled?.bundle, 'some-plugin');

    // A host with no record answers a null result, which is a miss rather
    // than a failure.
    rpc.waitForInstallValue = null;
    expect(await repository.waitForPluginInstall('req-10'), isNull);
  });

  test('plugin version exemptions decode with their warnings', () async {
    final rpc = HarnessFakeRpc(<Object?>[]);
    final socket = ScriptedHarnessSocket();
    final repository = await harnessRepository(rpc, socket);
    await pumpEventQueue();

    final exemptions = await repository.listPluginVersionExemptions();
    expect(exemptions.exemptions['some-plugin@1.0.0'], <String>['0.1.7-rc.2']);
    expect(exemptions.warnings, hasLength(1));

    await repository.setPluginVersionExemption(
      packageVersion: 'some-plugin@1.0.0',
      runtimeVersion: '0.1.7-rc.2',
      enabled: true,
      acceptRisk: true,
    );
    final payload = rpc
        .payloads(DshRpcEndpoints.pluginManagerSetVersionExemption)
        .single;
    expect(payload['packageVersion'], 'some-plugin@1.0.0');
    expect(payload['runtimeVersion'], '0.1.7-rc.2');
    expect(payload['enabled'], isTrue);
    expect(payload['acceptRisk'], isTrue);
  });

  test(
    'plugin-manager forwarded events feed progress, log, and change',
    () async {
      final rpc = HarnessFakeRpc(<Object?>[]);
      final socket = ScriptedHarnessSocket(
        muxFrames: <ServerRequest>[
          _remoteEmit('plugin-manager/install-state', <Object?>[
            <String, Object?>{
              'requestId': 'req-1',
              'phase': 'installing',
              'attempt': <String, Object?>{
                'registry': 'https://registry.npmmirror.com/',
                'index': 1,
                'total': 2,
              },
            },
          ]),
          _remoteEmit('plugin-manager/install-log', <Object?>[
            <String, Object?>{
              'requestId': 'req-1',
              'jobId': 'bash-1',
              'argv': <Object?>['pnpm', 'add', 'some-plugin'],
              'cwd': '/home/tester/.dsh',
              'stream': 'stdout',
              'text': 'Progress: resolved 1\n',
            },
          ]),
          _remoteEmit('plugin-manager/changed', <Object?>[
            <String, Object?>{'reason': 'install'},
          ]),
        ],
      );
      final repository = await harnessRepository(rpc, socket);
      await pumpEventQueue();

      final progress = <PluginInstallProgress>[];
      final log = <PluginInstallLogChunk>[];
      var changes = 0;
      final progressSub = repository.observePluginInstallProgress().listen(
        progress.add,
      );
      final logSub = repository.observePluginInstallLog().listen(log.add);
      final changeSub = repository.observePluginChanges().listen((_) {
        changes += 1;
      });
      addTearDown(progressSub.cancel);
      addTearDown(logSub.cancel);
      addTearDown(changeSub.cancel);
      await pumpEventQueue();

      socket.releaseMuxFrames();
      await pumpEventQueue();

      expect(progress.single.requestId, 'req-1');
      expect(progress.single.phase, PluginInstallPhase.installing);
      expect(progress.single.registry, 'https://registry.npmmirror.com/');
      expect(progress.single.attemptIndex, 1);
      expect(progress.single.attemptTotal, 2);
      expect(log.single.jobId, 'bash-1');
      expect(log.single.argv.first, 'pnpm');
      expect(log.single.isStderr, isFalse);
      expect(log.single.text, contains('resolved'));
      expect(changes, 1);
    },
  );

  test(
    'schedule/catalog reads every task without activating a session',
    () async {
      final rpc = HarnessFakeRpc(<Object?>[])
        ..scheduleRowsValue = <Object?>[
          <String, Object?>{
            'id': 'schedule-1',
            'kind': 'weekly',
            'title': 'Weekly review',
            'prompt': 'review the diff',
            'scheduledAt': '2026-09-30T09:00:00.000Z',
            'time': '09:00:00.000',
            'timeZone': 'Asia/Shanghai',
            'weekdays': <Object?>[1, 3, 5],
            'sessionId': 'session-s',
            'status': 'active',
            'lastDelivery': <String, Object?>{
              'scheduledAt': '2026-09-23T09:00:00.000Z',
              'deliveredAt': '2026-09-23T09:00:01.000Z',
              'messageId': 'msg-1',
            },
          },
          <String, Object?>{
            'id': 'schedule-2',
            'kind': 'cron',
            'title': 'Nightly',
            'prompt': 'run the smoke suite',
            'scheduledAt': '2026-09-30T18:00:00.000Z',
            'expression': '0 2 * * *',
            'timeZone': 'UTC',
            'sessionId': 'session-s',
            'status': 'inactive',
          },
        ];
      final socket = ScriptedHarnessSocket();
      final repository = await harnessRepository(rpc, socket);
      await pumpEventQueue();

      final catalog = await repository.scheduleCatalog();
      expect(catalog, hasLength(2));
      final weekly = catalog.first;
      expect(weekly.record.kind, ScheduleKind.weekly);
      expect(weekly.record.weekdays, <int>[1, 3, 5]);
      expect(weekly.record.timeZone, 'Asia/Shanghai');
      expect(weekly.status, ScheduleStatus.active);
      expect(weekly.lastDelivery?.messageId, 'msg-1');
      expect(catalog.last.record.isRecurring, isTrue);
      expect(catalog.last.status, ScheduleStatus.inactive);
      // A one-shot stores no zone; a recurring one always does.
      expect(catalog.last.record.expression, '0 2 * * *');

      // `catalog` takes no arguments, unlike the four request-shaped methods.
      final payload = rpc.payloads(DshRpcEndpoints.scheduleCatalog).single;
      expect(asJsonObject(payload['args']) ?? payload, isEmpty);
    },
  );

  test('schedule reads and writes carry their request record', () async {
    final rpc = HarnessFakeRpc(<Object?>[])
      ..scheduleRowsValue = <Object?>[
        <String, Object?>{
          'id': 'schedule-1',
          'kind': 'every',
          'title': 'Poll',
          'prompt': 'check the build',
          'scheduledAt': '2026-09-30T09:00:00.000Z',
          'everySeconds': 900,
        },
      ]
      ..scheduleUpdateValue = <String, Object?>{
        'id': 'schedule-1',
        'updated': true,
        'record': <String, Object?>{
          'id': 'schedule-1',
          'kind': 'daily',
          'title': 'Poll',
          'prompt': 'check the build',
          'scheduledAt': '2026-10-01T01:00:00.000Z',
          'time': '09:00:00.000',
          'timeZone': 'Asia/Shanghai',
        },
      };
    final socket = ScriptedHarnessSocket();
    final repository = await harnessRepository(rpc, socket);
    await pumpEventQueue();

    final active = await repository.listSchedules('session-s');
    expect(active.single.everySeconds, 900);
    final listPayload = rpc.payloads(DshRpcEndpoints.scheduleList).single;
    expect(asJsonObject(listPayload['request']), <String, Object?>{
      'sessionId': 'session-s',
    });

    // A compare-and-update carries the observed record as `expected` and only
    // the fields that changed.
    final updated = await repository.updateSchedule(
      sessionId: 'session-s',
      id: 'schedule-1',
      expected: active.single,
      change: const ScheduleDailyChange(
        time: '09:00:00.000',
        timeZone: 'Asia/Shanghai',
      ),
    );
    final committed = updated as ScheduleUpdateCommitted;
    expect(committed.record.kind, ScheduleKind.daily);
    expect(committed.record.timeZone, 'Asia/Shanghai');

    final updatePayload = rpc.payloads(DshRpcEndpoints.scheduleUpdate).single;
    final request = asJsonObject(requestPayload(updatePayload))!;
    expect(request['id'], 'schedule-1');
    expect(request['title'], isNull);
    final expected = asJsonObject(request['expected'])!;
    expect(expected['kind'], 'every');
    expect(expected['everySeconds'], 900);
    expect(expected['scheduledAt'], '2026-09-30T09:00:00.000Z');
    expect(asJsonObject(request['change']), <String, Object?>{
      'kind': 'daily',
      'daily': <String, Object?>{
        'time': '09:00:00.000',
        'time_zone': 'Asia/Shanghai',
      },
    });

    final deleted = await repository.deleteSchedule(
      sessionId: 'session-s',
      id: 'schedule-1',
    );
    expect(deleted.deleted, isTrue);
    final deletePayload = rpc.payloads(DshRpcEndpoints.scheduleDelete).single;
    expect(asJsonObject(requestPayload(deletePayload)), <String, Object?>{
      'sessionId': 'session-s',
      'id': 'schedule-1',
    });
  });

  test('a stale schedule update answers a conflict, not a write', () async {
    final rpc = HarnessFakeRpc(<Object?>[]);
    final socket = ScriptedHarnessSocket();
    final repository = await harnessRepository(rpc, socket);
    await pumpEventQueue();

    final result = await repository.updateSchedule(
      sessionId: 'session-s',
      id: 'schedule-1',
      expected: const ScheduleRecord(
        id: 'schedule-1',
        kind: ScheduleKind.daily,
        title: 'Daily',
        prompt: 'go',
        scheduledAt: '2026-09-30T09:00:00.000Z',
        time: '09:00:00.000',
        timeZone: 'UTC',
      ),
      title: 'Renamed',
    );
    final miss = result as ScheduleUpdateMiss;
    expect(miss.isConflict, isTrue);
    expect(miss.code, 'schedule_conflict');
  });

  test(
    'schedule history answers its page and its miss inside the value',
    () async {
      final rpc = HarnessFakeRpc(<Object?>[])
        ..scheduleHistoryValue = <String, Object?>{
          'id': 'schedule-1',
          'records': <Object?>[
            <String, Object?>{
              'scheduledAt': '2026-09-23T09:00:00.000Z',
              'deliveredAt': '2026-09-23T09:00:01.000Z',
              'messageId': 'msg-2',
              'prompt': 'review the diff',
            },
          ],
          'earlierRecordsUnavailable': true,
          'earlierRecordsPruned': false,
          'retention': <String, Object?>{'days': 30, 'records': 200},
          'nextBefore': 'msg-2',
        };
      final socket = ScriptedHarnessSocket();
      final repository = await harnessRepository(rpc, socket);
      await pumpEventQueue();

      final page = await repository.scheduleHistory(
        sessionId: 'session-s',
        id: 'schedule-1',
        limit: 20,
      ) as ScheduleHistoryPage;
      expect(page.records.single.prompt, 'review the diff');
      expect(page.earlierRecordsUnavailable, isTrue);
      expect(page.retention.days, 30);
      expect(page.nextBefore, 'msg-2');

      final payload = rpc.payloads(DshRpcEndpoints.scheduleHistory).single;
      expect(asJsonObject(requestPayload(payload)), <String, Object?>{
        'sessionId': 'session-s',
        'id': 'schedule-1',
        'limit': 20,
      });

      // A task the session no longer owns answers a code, not a throw.
      rpc.scheduleHistoryValue = <String, Object?>{
        'id': 'schedule-1',
        'code': 'schedule_not_found',
      };
      final miss = await repository.scheduleHistory(
        sessionId: 'session-s',
        id: 'schedule-1',
        limit: 20,
      ) as ScheduleHistoryMiss;
      expect(miss.code, 'schedule_not_found');
    },
  );

  test('terminal reads carry the Agent lookup, not a session id', () async {
    // Every method but `list` takes `agent: Agent`, whose wire field is
    // `agentId` (`TypertLookupMap.agent`); `list` takes a bare `sessionId`.
    final rpc = HarnessFakeRpc(<Object?>[])
      ..terminalRowsValue = <Object?>[
        _terminalRowJson(id: 'term-1', controllerId: 'att-9'),
        _terminalRowJson(id: 'term-2', state: 'exited', exitCode: 3),
      ];
    final socket = ScriptedHarnessSocket();
    final repository = await harnessRepository(rpc, socket);
    await pumpEventQueue();

    final environment = await repository.terminalEnvironment('session-t');
    expect(environment.cwd, '/home/tester/project');
    expect(environment.maxInputBytes, 65536);
    expect(environment.maxCols, 500);
    expect(
      rpc.rawPayloads(DshRpcEndpoints.terminalEnvironment).single,
      <String, Object?>{'agentId': 'session-t'},
    );

    final shells = await repository.terminalShells('session-t');
    expect(shells.single.name, 'bash');
    expect(shells.single.args, <String>['-i']);

    final terminals = await repository.listTerminals('session-t');
    expect(terminals, hasLength(2));
    expect(terminals.first.state, TerminalState.running);
    expect(terminals.first.controllerId, 'att-9');
    // An exited process keeps its exit code and never restarts itself.
    expect(terminals.last.state, TerminalState.exited);
    expect(terminals.last.exitCode, 3);
    // `list` is the one terminal method that takes the bare session id.
    expect(
      rpc.rawPayloads(DshRpcEndpoints.terminalList).single,
      <String, Object?>{'sessionId': 'session-t'},
    );

    final created = await repository.createTerminal(
      'session-t',
      id: 'term-3',
      cols: 100,
      rows: 30,
      shellPath: '/bin/bash',
    );
    expect(created.id, 'term-3');
    final createArgs = rpc.rawPayloads(DshRpcEndpoints.terminalCreate).single;
    expect(createArgs['agentId'], 'session-t');
    expect(asJsonObject(createArgs['request']), <String, Object?>{
      'id': 'term-3',
      'cols': 100,
      'rows': 30,
      'shellPath': '/bin/bash',
    });

    await repository.writeTerminal('session-t', 'term-1', 'att-1', 'ls\r');
    await repository.resizeTerminal('session-t', 'term-1', 'att-1', 120, 40);
    await repository.renameTerminal('session-t', 'term-1', 'build');
    await repository.closeTerminal('session-t', 'term-1');
    expect(
      rpc.rawPayloads(DshRpcEndpoints.terminalWrite).single,
      <String, Object?>{
        'agentId': 'session-t',
        'id': 'term-1',
        'attachmentId': 'att-1',
        'data': 'ls\r',
      },
    );
    expect(
      rpc.rawPayloads(DshRpcEndpoints.terminalResize).single,
      <String, Object?>{
        'agentId': 'session-t',
        'id': 'term-1',
        'attachmentId': 'att-1',
        'cols': 120,
        'rows': 40,
      },
    );
    expect(
      rpc.rawPayloads(DshRpcEndpoints.terminalRename).single,
      <String, Object?>{
        'agentId': 'session-t',
        'id': 'term-1',
        'title': 'build',
      },
    );
    expect(
      rpc.rawPayloads(DshRpcEndpoints.terminalClose).single,
      <String, Object?>{'agentId': 'session-t', 'id': 'term-1'},
    );
  });

  test(
    'a terminal attachment opens with a snapshot and streams output',
    () async {
      final rpc = HarnessFakeRpc(<Object?>[]);
      final socket = ScriptedHarnessSocket(
        muxFrames: <ServerRequest>[
          _terminalFrame('terminal-follow-0', <String, Object?>{
            'type': 'snapshot',
            'sequence': 7,
            'screen': 'ready',
            'info': _terminalRowJson(id: 'term-1', controllerId: 'att-1'),
          }),
          _terminalFrame('terminal-follow-0', <String, Object?>{
            'type': 'output',
            'sequence': 8,
            'data': 'build ok\r\n',
          }),
          _terminalFrame('terminal-follow-0', <String, Object?>{
            'type': 'state',
            'info': _terminalRowJson(
              id: 'term-1',
              state: 'exited',
              exitCode: 0,
            ),
          }),
        ],
      );
      final repository = await harnessRepository(rpc, socket);
      await pumpEventQueue();

      final frames = <TerminalFrame>[];
      final subscription = repository
          .observeTerminal('session-t', 'term-1', 'att-1')
          .listen(frames.add);
      addTearDown(subscription.cancel);
      await pumpEventQueue();

      final open = socket.sentMuxMessages.firstWhere(
        (message) => message['endpoint'] == 'terminal/follow',
      );
      expect(open['payload'], <String, Object?>{
        'args': <String, Object?>{
          'agentId': 'session-t',
          'id': 'term-1',
          'attachmentId': 'att-1',
        },
      });

      socket.releaseMuxFrames();
      await pumpEventQueue();

      expect(frames, hasLength(3));
      final snapshot = frames.first as TerminalSnapshot;
      expect(snapshot.sequence, 7);
      expect(snapshot.screen, 'ready');
      expect(snapshot.info.controllerId, 'att-1');
      expect((frames[1] as TerminalOutput).sequence, 8);
      final state = frames.last as TerminalStateChange;
      expect(state.info.state, TerminalState.exited);
      expect(state.info.exitCode, 0);

      // A cancelled attachment cancels its route.
      await subscription.cancel();
      await pumpEventQueue();
      expect(
        socket.sentMuxMessages.any(
          (message) =>
              message['type'] == 'cancel' &&
              message['streamId'] == 'terminal-follow-0',
        ),
        isTrue,
      );
    },
  );

  test('a terminal hold takes the bare session id and acknowledges', () async {
    // `retain` and `list` are the two calls a dormant session can make: they
    // take a plain `sessionId`, not the Agent lookup.
    final rpc = HarnessFakeRpc(<Object?>[]);
    final socket = ScriptedHarnessSocket(
      muxFrames: <ServerRequest>[
        ServerRequest(
          rpcId: 'terminal-retain-0',
          method: 'terminal/retain',
          payload: <String, Object?>{'type': 'retained'},
        ),
      ],
    );
    final repository = await harnessRepository(rpc, socket);
    await pumpEventQueue();

    final holds = <void>[];
    final subscription = repository
        .retainTerminal('session-t', 'term-1')
        .listen(holds.add);
    addTearDown(subscription.cancel);
    await pumpEventQueue();

    final open = socket.sentMuxMessages.firstWhere(
      (message) => message['endpoint'] == 'terminal/retain',
    );
    expect(open['payload'], <String, Object?>{
      'args': <String, Object?>{'sessionId': 'session-t', 'id': 'term-1'},
    });

    socket.releaseMuxFrames();
    await pumpEventQueue();
    expect(holds, hasLength(1));

    await subscription.cancel();
    await pumpEventQueue();
    expect(
      socket.sentMuxMessages.any(
        (message) =>
            message['type'] == 'cancel' &&
            message['streamId'] == 'terminal-retain-0',
      ),
      isTrue,
    );
  });

  test('a terminal refusal surfaces the host code', () async {
    final rpc = HarnessFakeRpc(<Object?>[]);
    final socket = ScriptedHarnessSocket();
    final repository = await harnessRepository(rpc, socket);
    await pumpEventQueue();

    rpc.failNextCall(DshRpcEndpoints.terminalCreate, 'terminal/limit-reached');
    await expectLater(
      repository.createTerminal('session-t', id: 'term-9', cols: 80, rows: 24),
      throwsA(
        isA<DshBusinessException>().having(
          (DshBusinessException error) => error.code,
          'code',
          'terminal/limit-reached',
        ),
      ),
    );
  });

  test('an agentTeam control frame reaches the team stream', () async {
    // `agentTeam` is a Session projection, not an RPC namespace: the host
    // publishes it on the control stream and the reference panel reads it from
    // the shared Session store
    // (`packages/experimental/agent-team/src/projection.ts` `key: 'agentTeam'`).
    final rpc = HarnessFakeRpc(<Object?>[
      <String, Object?>{
        'sessionId': 'session-t',
        'updatedAt': 1,
        'blank': false,
      },
    ]);
    final socket = ScriptedHarnessSocket(
      muxFrames: <ServerRequest>[
        _controlProjection('session-t', 'agentTeam', 4, <String, Object?>{
          'members': <Object?>[
            <String, Object?>{
              'id': 'session-t',
              'name': 'lead',
              'role': 'lead',
              'phase': 'active',
            },
          ],
          'tasks': <Object?>[
            <String, Object?>{
              'id': 'task-1',
              'revision': 1,
              'subject': 'Split the audit',
              'description': 'Two halves',
              'status': 'pending',
              'blockedBy': <Object?>[],
              'writeScopes': <Object?>[],
              'ready': true,
              'writeScopeWarnings': <Object?>[],
            },
          ],
        }),
        // An older frame for the same key must lose to the value already held.
        _controlProjection('session-t', 'agentTeam', 3, <String, Object?>{
          'members': <Object?>[],
          'tasks': <Object?>[],
        }),
      ],
    );
    final repository = await harnessRepository(rpc, socket);
    await pumpEventQueue();

    final teams = <AgentTeam?>[];
    final subscription = repository
        .observeAgentTeam('session-t')
        .listen(teams.add);
    addTearDown(subscription.cancel);
    await pumpEventQueue();
    // Nothing published yet: absence is null rather than an empty roster.
    expect(teams.last, isNull);

    socket.releaseMuxFrames();
    await pumpEventQueue();

    final team = teams.last;
    expect(team, isNotNull);
    expect(team!.members.single.isLead, isTrue);
    expect(team.tasks.single.isReady, isTrue);
  });

  test(
    'loadAgentTeam reads the projection without activating the session',
    () async {
      final rpc = HarnessFakeRpc(<Object?>[
        <String, Object?>{
          'sessionId': 'session-t',
          'updatedAt': 1,
          'blank': false,
        },
      ]);
      rpc.agentTeamValue = <String, Object?>{
        'members': <Object?>[
          <String, Object?>{
            'id': 'session-t',
            'name': 'lead',
            'role': 'lead',
            'phase': 'active',
          },
        ],
        'tasks': <Object?>[],
      };
      final socket = ScriptedHarnessSocket();
      final repository = await harnessRepository(rpc, socket);
      await pumpEventQueue();

      final team = await repository.loadAgentTeam('session-t');
      expect(team, isNotNull);
      expect(team!.members.single.name, 'lead');
      // The cold read seeds the live stream, so a panel that opened first
      // renders the same value.
      expect(await repository.observeAgentTeam('session-t').first, isNotNull);
    },
  );

  test('a developer/message folds as a context row, not a user bubble', () async {
    // 0.1.7 added `developer/message` (an incremental agent session change on
    // the model-visible surface). The upstream chat client presents it through
    // the same context-row lifecycle as an injected `user/message`
    // (`ui-chat/src/client/conversation-nodes/message.ts`
    // `developerMessageDefinition`).
    final rpc = HarnessFakeRpc(<Object?>[
      <String, Object?>{
        'sessionId': 'session-d',
        'updatedAt': 1,
        'blank': false,
      },
    ])..historyEvents['session-d'] = <Object?>[_assistantMessageEvent()];
    final socket = ScriptedHarnessSocket(
      muxFrames: <ServerRequest>[
        _muxFrame('session/event', 'session-d', <String, Object?>{
          'type': 'developer/message',
          'seq': 90,
          'time': 20,
          'data': <String, Object?>{
            'turn': 1,
            'step': 1,
            'message': <String, Object?>{
              'id': 'developer-1',
              'role': 'developer',
              'source': <String, Object?>{'kind': 'developer'},
              'content': <Object?>[
                <String, Object?>{'type': 'text', 'text': 'Added tool: read'},
              ],
            },
          },
        }),
      ],
    );
    final repository = await harnessRepository(rpc, socket);
    await pumpEventQueue();
    await repository.openSession('session-d');
    await pumpEventQueue();
    socket.releaseMuxFrames();
    await pumpEventQueue();

    final timeline = await repository
        .observeTimeline('session-d')
        .firstWhere(
          (items) => items.whereType<TimelineContextInjection>().any(
            (item) => item.text.contains('Added tool'),
          ),
        );
    final injection = timeline.whereType<TimelineContextInjection>().firstWhere(
      (item) => item.text.contains('Added tool'),
    );
    expect(injection.producerLabel, 'developer');
    // No user bubble: the message is model-visible state, not a human turn.
    expect(
      timeline.whereType<TimelineMessage>().where(
        (item) => item.value.role == MessageRole.user,
      ),
      isEmpty,
    );
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

  test('the userQuestions projection folds a continued call, and a late answer '
      'rides userQuestions/answer', () async {
    // Wire truth: `packages/interaction/user-questions/src/types.ts`
    // (`UserQuestionProjectionView = {active, settled}`,
    // `PendingUserQuestion = {callId, questions, state}`) and
    // `.../src/index.ts` `@Remote answer(agent, callId, answer)`.
    final rpc = HarnessFakeRpc(<Object?>[
      <String, Object?>{
        'sessionId': 'session-timed',
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
            'sessionId': 'session-timed',
            'key': 'userQuestions',
            'seq': 1,
            'value': <String, Object?>{
              'active': <Object?>[
                <String, Object?>{
                  'callId': 'call-1',
                  'state': 'continued',
                  'questions': <Object?>[
                    <String, Object?>{
                      'id': 'q1',
                      'question': 'Which registry?',
                      'options': <Object?>[
                        <String, Object?>{'label': 'internal'},
                        <String, Object?>{'label': 'public'},
                      ],
                      'multiSelect': false,
                    },
                  ],
                },
              ],
              'settled': const <Object?>[],
            },
          },
        ),
      ],
    );
    final repository = await harnessRepository(rpc, socket);
    await pumpEventQueue();

    socket.releaseMuxFrames();
    await pumpEventQueue();

    final rows = await repository
        .observePendingUserQuestions('session-timed')
        .firstWhere((list) => list.isNotEmpty);
    expect(rows, hasLength(1));
    expect(rows.single.callId, 'call-1');
    expect(rows.single.state, UserQuestionState.continued);
    expect(rows.single.questions.single.id, 'q1');
    expect(rows.single.questions.single.options, <String>[
      'internal',
      'public',
    ]);
    expect(rows.single.questions.single.multiSelect, isFalse);

    await repository.answerContinuedQuestion(
      'session-timed',
      'call-1',
      const QuestionEvidence(
        sessionId: 'session-timed',
        answers: <QuestionAnswer>[
          QuestionAnswer(
            questionId: 'q1',
            selectedOptions: <String>['internal'],
          ),
        ],
      ),
    );

    expect(rpc.callCountFor(DshRpcEndpoints.userQuestionsAnswer), 1);
    final payload = rpc.payloads(DshRpcEndpoints.userQuestionsAnswer).single;
    expect(payload['agentId'], 'session-timed');
    expect(payload['callId'], 'call-1');
    expect(payload['answer'], <String, Object?>{
      'answers': <Object?>[
        <String, Object?>{
          'id': 'q1',
          'selected': <String>['internal'],
        },
      ],
    });
  });

  test(
    'a userQuestions row without a callId is dropped loudly, not defaulted',
    () async {
      final diagnostics = <AdapterDiagnostic>[];
      final rpc = HarnessFakeRpc(<Object?>[
        <String, Object?>{
          'sessionId': 'session-bad-timed',
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
              'sessionId': 'session-bad-timed',
              'key': 'userQuestions',
              'seq': 1,
              'value': <String, Object?>{
                'active': <Object?>[
                  <String, Object?>{
                    'state': 'continued',
                    'questions': <Object?>[
                      <String, Object?>{'id': 'q1', 'question': 'no call id'},
                    ],
                  },
                ],
                'settled': const <Object?>[],
              },
            },
          ),
        ],
      );
      final repository = HarnessRepositoryImpl(
        rpc,
        DshConnectionManager(socket, exponentialDshBackoffDelay),
        onDiagnostic: diagnostics.add,
      );
      await pumpEventQueue();
      socket.releaseMuxFrames();
      await pumpEventQueue();

      final rows = await repository
          .observePendingUserQuestions('session-bad-timed')
          .first;
      expect(rows, isEmpty);
      expect(
        diagnostics.any(
          (d) => d.message.contains('userQuestions: callId is absent'),
        ),
        isTrue,
      );
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

  test(
    'archiving stamps stopActivity only when the caller asked for it',
    () async {
      final rpc = HarnessFakeRpc();
      final socket = ScriptedHarnessSocket();
      final repository = await harnessRepository(rpc, socket);
      addTearDown(repository.dispose);

      await repository.archiveSession('s-quiet');
      expect(
        rpc
            .payloads(DshRpcEndpoints.workspaceArchiveSession)
            .single['stopActivity'],
        isNull,
        reason: 'a quiet archive never asks the Host to stop anything',
      );

      await repository.archiveSession('s-busy', stopActivity: true);
      expect(
        rpc
            .payloads(DshRpcEndpoints.workspaceArchiveSession)
            .last['stopActivity'],
        isTrue,
      );
    },
  );

  test('a running-work refusal surfaces the activity the Host named', () async {
    final rpc = HarnessFakeRpc();
    final socket = ScriptedHarnessSocket();
    final repository = await harnessRepository(rpc, socket);
    addTearDown(repository.dispose);

    rpc.failNextCallWithDetails(
      DshRpcEndpoints.workspaceArchiveSession,
      'workspace/session-active',
      <String, Object?>{
        'sessionId': 's-busy',
        'activity': <Object?>[
          <String, Object?>{'kind': 'turn'},
          <String, Object?>{
            'kind': 'job',
            'items': <Object?>[
              <String, Object?>{'id': 'job-1', 'label': 'build'},
            ],
          },
          <String, Object?>{
            'kind': 'workflow',
            'items': <Object?>[
              <String, Object?>{'id': 'wf-1'},
            ],
          },
        ],
      },
    );

    await expectLater(
      repository.archiveSession('s-busy'),
      throwsA(
        isA<SessionArchiveRefused>()
            .having((refusal) => refusal.sessionId, 'sessionId', 's-busy')
            .having(
              (refusal) => refusal.activity.map((entry) => entry.kind).toList(),
              'kinds',
              <SessionActivityKind>[
                SessionActivityKind.turn,
                SessionActivityKind.job,
                SessionActivityKind.other,
              ],
            )
            .having(
              (refusal) => refusal.activity.last.rawKind,
              'unknown family keeps its wire spelling',
              'workflow',
            )
            .having(
              (refusal) => refusal.activity[1].items.single.displayName,
              'item label',
              'build',
            )
            .having(
              (refusal) => refusal.activity.last.items.single.displayName,
              'item without a label falls back to its id',
              'wf-1',
            ),
      ),
    );
  });

  test('unarchive calls workspace/unarchiveSession for that session', () async {
    final rpc = HarnessFakeRpc();
    final socket = ScriptedHarnessSocket();
    final repository = await harnessRepository(rpc, socket);
    addTearDown(repository.dispose);

    await repository.unarchiveSession('s-archived');

    expect(rpc.callCountFor(DshRpcEndpoints.workspaceUnarchiveSession), 1);
    expect(
      rpc
          .rawPayloads(DshRpcEndpoints.workspaceUnarchiveSession)
          .single['sessionId'],
      's-archived',
    );
  });

  test('agent preset read sends the id and decodes the declaration', () async {
    final rpc = HarnessFakeRpc();
    final socket = ScriptedHarnessSocket();
    final repository = await harnessRepository(rpc, socket);
    addTearDown(repository.dispose);

    final document = await repository.readAgentPreset('standard');

    expect(rpc.callCountFor(DshRpcEndpoints.agentPresetsRead), 1);
    expect(
      rpc.rawPayloads(DshRpcEndpoints.agentPresetsRead).single['agentPreset'],
      'standard',
    );
    expect(document.agentPreset, 'standard');
    expect(document.name, 'Standard');
    expect(document.content, contains('dsh-tool-bash'));
  });

  test('permission catalog decodes both tables and the default', () async {
    final rpc = HarnessFakeRpc();
    final socket = ScriptedHarnessSocket();
    final repository = await harnessRepository(rpc, socket);
    addTearDown(repository.dispose);

    final catalog = await repository.loadPermissionPresetCatalog();

    expect(rpc.callCountFor(DshRpcEndpoints.permissionPresetsCatalog), 1);
    expect(catalog.defaultPreset, 'workspace-write');
    expect(catalog.options.map((option) => option.value).toList(), <String>[
      'workspace-write',
      'danger-full-access',
    ]);
    expect(
      catalog.defaultOptions.map((option) => option.value).toList(),
      <String>['workspace-write', 'danger-full-access'],
    );
    expect(catalog.options.first.description, 'Write inside the workspace.');
    expect(catalog.defaultOptions.first.description, isNull);
  });

  test(
    'fileReferences/list carries the Agent lookup and the path query',
    () async {
      final rpc = HarnessFakeRpc();
      final socket = ScriptedHarnessSocket();
      final repository = await harnessRepository(rpc, socket);
      addTearDown(repository.dispose);

      final candidates = await repository.listFileReferences('s-1', 'src/');

      expect(rpc.callCountFor(DshRpcEndpoints.fileReferencesList), 1);
      // The addressed agent rides `agentId`; the path text after `@` rides
      // `query` (reference
      // packages/api/session-controller/src/file-references.ts `list(agent,
      // query, signal)`).
      final payload = rpc
          .rawPayloads(DshRpcEndpoints.fileReferencesList)
          .single;
      expect(payload, <String, Object?>{'agentId': 's-1', 'query': 'src/'});
      expect(candidates, <FileReferenceCandidate>[
        const FileReferenceCandidate(
          path: 'src',
          kind: FileReferenceKind.directory,
        ),
        const FileReferenceCandidate(
          path: 'src/main.dart',
          kind: FileReferenceKind.file,
        ),
      ]);
    },
  );

  test(
    'fileReferences/list missing a candidate field throws naming it',
    () async {
      final rpc = HarnessFakeRpc();
      final socket = ScriptedHarnessSocket();
      final repository = await harnessRepository(rpc, socket);
      addTearDown(repository.dispose);
      rpc.fileReferenceRowsValue = <Object?>[
        <String, Object?>{'kind': 'file'},
      ];

      await expectLater(
        repository.listFileReferences('s-1', ''),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('path'),
          ),
        ),
      );
    },
  );

  test(
    'fileReferences/list with an unknown kind throws naming the field',
    () async {
      final rpc = HarnessFakeRpc();
      final socket = ScriptedHarnessSocket();
      final repository = await harnessRepository(rpc, socket);
      addTearDown(repository.dispose);
      rpc.fileReferenceRowsValue = <Object?>[
        <String, Object?>{'path': 'src', 'kind': 'symlink'},
      ];

      await expectLater(
        repository.listFileReferences('s-1', ''),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('kind'),
          ),
        ),
      );
    },
  );

  test('fileReferences/list answering a non-array result throws', () {
    // The endpoint answered an object where its contract says an array
    // (`FileReferenceCandidate[]`).
    expect(
      () => decodeFileReferenceCandidateList(<String, Object?>{
        'value': <String, Object?>{},
      }),
      throwsA(isA<FormatException>()),
    );
  });

  test('fileUploads/upload carries the Agent lookup and base64 request', () async {
    final rpc = HarnessFakeRpc();
    final socket = ScriptedHarnessSocket();
    final repository = await harnessRepository(rpc, socket);
    addTearDown(repository.dispose);

    final uploaded = await repository.uploadFile(
      sessionId: 's-1',
      name: 'notes.pdf',
      bytes: Uint8List.fromList(<int>[0x68, 0x69]),
    );

    expect(rpc.callCountFor(DshRpcEndpoints.fileUploadsUpload), 1);
    // `upload(agent: Agent, request: EncodedFileUploadRequest, signal)`:
    // the Agent lookup rides `agentId`, the request object rides `request`
    // (reference packages/client/file-upload/src/index.ts `@Remote('upload')`;
    // the `(agentId, request, signal)` wire form is the one
    // packages/typert/generator emits for `goals/create` and
    // `terminal/create`). `data` is the canonical base64 of the bytes.
    expect(
      rpc.rawPayloads(DshRpcEndpoints.fileUploadsUpload).single,
      <String, Object?>{
        'agentId': 's-1',
        'request': <String, Object?>{'data': 'aGk=', 'name': 'notes.pdf'},
      },
    );
    expect(uploaded.receiptId, 'receipt-7');
    expect(uploaded.attachmentId, 'sha256:file-a');
    expect(uploaded.name, 'notes.pdf');
    expect(uploaded.byteSize, 2);
  });

  test('fileUploads/upload omits an empty display name', () async {
    final rpc = HarnessFakeRpc();
    final socket = ScriptedHarnessSocket();
    final repository = await harnessRepository(rpc, socket);
    addTearDown(repository.dispose);

    await repository.uploadFile(
      sessionId: 's-1',
      name: '',
      bytes: Uint8List.fromList(<int>[0x68, 0x69]),
    );

    expect(
      (rpc.rawPayloads(DshRpcEndpoints.fileUploadsUpload).single['request']
          as Map<String, Object?>),
      <String, Object?>{'data': 'aGk='},
    );
  });

  test('fileUploads/upload refuses a file above the phone cap', () async {
    final rpc = HarnessFakeRpc();
    final socket = ScriptedHarnessSocket();
    final repository = await harnessRepository(rpc, socket);
    addTearDown(repository.dispose);

    await expectLater(
      repository.uploadFile(
        sessionId: 's-1',
        name: 'huge.bin',
        bytes: Uint8List(FileUploadLimits.maxFileBytes + 1),
      ),
      throwsA(
        isA<RepositoryFailure>().having(
          (failure) => failure.code,
          'code',
          'session/attachment-invalid',
        ),
      ),
    );
    // The guard runs before the call, so no oversized body crosses the wire.
    expect(rpc.callCountFor(DshRpcEndpoints.fileUploadsUpload), 0);
  });

  test(
    'fileUploads/upload surfaces a host refusal as RepositoryFailure',
    () async {
      final rpc = HarnessFakeRpc();
      final socket = ScriptedHarnessSocket();
      final repository = await harnessRepository(rpc, socket);
      addTearDown(repository.dispose);
      rpc.failNextCall(
        DshRpcEndpoints.fileUploadsUpload,
        'session/attachment-invalid',
      );

      await expectLater(
        repository.uploadFile(
          sessionId: 's-1',
          name: 'notes.pdf',
          bytes: Uint8List.fromList(<int>[0x68, 0x69]),
        ),
        throwsA(
          isA<RepositoryFailure>()
              .having(
                (failure) => failure.code,
                'code',
                'session/attachment-invalid',
              )
              .having(
                (failure) => failure.message,
                'message',
                contains('session/attachment-invalid'),
              ),
        ),
      );
    },
  );

  test('fileUploads/upload missing a receipt field throws naming it', () async {
    final rpc = HarnessFakeRpc();
    final socket = ScriptedHarnessSocket();
    final repository = await harnessRepository(rpc, socket);
    addTearDown(repository.dispose);
    rpc.fileUploadValue = <String, Object?>{
      'file': <String, Object?>{
        'attachmentId': 'sha256:file-a',
        'name': 'notes.pdf',
        'bytes': 2,
      },
    };

    await expectLater(
      repository.uploadFile(
        sessionId: 's-1',
        name: 'notes.pdf',
        bytes: Uint8List.fromList(<int>[0x68, 0x69]),
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('receiptId'),
        ),
      ),
    );
  });

  test(
    'account/getState decodes the projection and sends no arguments',
    () async {
      final rpc = HarnessFakeRpc();
      final socket = ScriptedHarnessSocket();
      final repository = await harnessRepository(rpc, socket);
      addTearDown(repository.dispose);

      final state = await repository.loadAccountState();

      expect(rpc.callCountFor(DshRpcEndpoints.accountGetState), 1);
      expect(rpc.rawPayloads(DshRpcEndpoints.accountGetState).single, isEmpty);
      expect(state.status, AccountSignInStatus.credentialStored);
      expect(state.links.usageUrl, 'https://platform.example/usage');
      expect(state.links.topUpUrl, 'https://platform.example/top_up');
      expect(state.attempt?.id, 'attempt-1');
      expect(state.attempt?.phase, AccountSignInPhase.succeeded);
    },
  );

  test(
    'account/getProfile carries the client identity and decodes it',
    () async {
      final rpc = HarnessFakeRpc();
      final socket = ScriptedHarnessSocket();
      final repository = await harnessRepository(rpc, socket);
      addTearDown(repository.dispose);

      final profile = await repository.loadAccountProfile(
        const AccountClientIdentity(
          version: '1.2.3',
          locale: 'zh-CN',
          timezoneOffsetSeconds: 28800,
        ),
      );

      // The host derives the Platform request headers from this identity, so
      // the three fields are the whole request.
      expect(
        rpc.rawPayloads(DshRpcEndpoints.accountGetProfile).single,
        <String, Object?>{
          'client': <String, Object?>{
            'version': '1.2.3',
            'locale': 'zh-CN',
            'timezoneOffsetSeconds': 28800,
          },
        },
      );
      expect(profile, isA<AccountProfileReady>());
      final ready = profile! as AccountProfileReady;
      expect(ready.profile.id, 'user-7');
      expect(ready.profile.name, 'Ada');
      expect(ready.profile.contact, 'a***@example.com');
      expect(ready.profile.avatarUrl, isNull);
    },
  );

  test('account/getProfile keeps failed and absent apart', () async {
    final rpc = HarnessFakeRpc();
    final socket = ScriptedHarnessSocket();
    final repository = await harnessRepository(rpc, socket);
    addTearDown(repository.dispose);
    const client = AccountClientIdentity(
      version: '1.2.3',
      locale: 'en-US',
      timezoneOffsetSeconds: 0,
    );

    rpc.accountProfileValue = <String, Object?>{'status': 'failed'};
    expect(
      await repository.loadAccountProfile(client),
      isA<AccountProfileFailed>(),
    );

    // A null result is the host holding no grant: not a failure, not an
    // empty profile.
    rpc.accountProfileValue = null;
    expect(await repository.loadAccountProfile(client), isNull);
  });

  test('account/getBalance decodes both wallet lists', () async {
    final rpc = HarnessFakeRpc();
    final socket = ScriptedHarnessSocket();
    final repository = await harnessRepository(rpc, socket);
    addTearDown(repository.dispose);
    const client = AccountClientIdentity(
      version: '1.2.3',
      locale: 'en-US',
      timezoneOffsetSeconds: 0,
    );

    final balance = await repository.loadAccountBalance(client);

    final ready = balance! as AccountBalanceReady;
    expect(ready.wallets, <AccountWallet>[
      const AccountWallet(currency: AccountCurrency.cny, balance: '12.34'),
    ]);
    expect(ready.bonusWallets, <AccountWallet>[
      const AccountWallet(currency: AccountCurrency.usd, balance: '0.50'),
    ]);

    // A failed read is its own outcome, never a zero balance.
    rpc.accountBalanceValue = <String, Object?>{'status': 'failed'};
    expect(
      await repository.loadAccountBalance(client),
      isA<AccountBalanceFailed>(),
    );
  });

  test(
    'account/getUnnotifiedBonuses decodes the batch and its absence',
    () async {
      final rpc = HarnessFakeRpc();
      final socket = ScriptedHarnessSocket();
      final repository = await harnessRepository(rpc, socket);
      addTearDown(repository.dispose);
      const client = AccountClientIdentity(
        version: '1.2.3',
        locale: 'en-US',
        timezoneOffsetSeconds: 0,
      );

      final batch = await repository.loadUnnotifiedBonuses(client);

      expect(batch?.accountId, 'user-7');
      expect(batch?.bonuses, <AccountBonusGrant>[
        const AccountBonusGrant(
          orderId: 'order-1',
          campaign: 'welcome',
          amount: '5.00',
          currency: AccountCurrency.cny,
          grantedAt: '2026-10-01T00:00:00Z',
          expiresAt: '2026-11-01T00:00:00Z',
          message: 'A 5.00 CNY bonus was credited.',
        ),
      ]);

      rpc.accountBonusesValue = null;
      expect(await repository.loadUnnotifiedBonuses(client), isNull);
    },
  );

  test('account/ackBonusNotified names the account and order and reads the boolean', () async {
    final rpc = HarnessFakeRpc();
    final socket = ScriptedHarnessSocket();
    final repository = await harnessRepository(rpc, socket);
    addTearDown(repository.dispose);
    const client = AccountClientIdentity(
      version: '1.2.3',
      locale: 'en-US',
      timezoneOffsetSeconds: -18000,
    );

    expect(
      await repository.ackBonusNotified(
        client,
        accountId: 'user-7',
        orderId: 'order-1',
      ),
      isTrue,
    );
    expect(
      rpc.rawPayloads(DshRpcEndpoints.accountAckBonusNotified).single,
      <String, Object?>{
        'accountId': 'user-7',
        'orderId': 'order-1',
        'client': <String, Object?>{
          'version': '1.2.3',
          'locale': 'en-US',
          'timezoneOffsetSeconds': -18000,
        },
      },
    );

    // The host's own false means it could not settle the order; it is an
    // answer, not an error.
    rpc.accountAckValue = false;
    expect(
      await repository.ackBonusNotified(
        client,
        accountId: 'user-7',
        orderId: 'order-1',
      ),
      isFalse,
    );
  });

  test('account decoders fail loud naming the field that moved', () async {
    final rpc = HarnessFakeRpc();
    final socket = ScriptedHarnessSocket();
    final repository = await harnessRepository(rpc, socket);
    addTearDown(repository.dispose);
    const client = AccountClientIdentity(
      version: '1.2.3',
      locale: 'en-US',
      timezoneOffsetSeconds: 0,
    );

    rpc.accountBonusesValue = <String, Object?>{
      'accountId': 'user-7',
      'bonuses': <Object?>[
        <String, Object?>{
          'orderId': 'order-1',
          'campaign': 'welcome',
          'amount': '5.00',
          'currency': 'CNY',
          'grantedAt': '2026-10-01T00:00:00Z',
          'expiresAt': '2026-11-01T00:00:00Z',
        },
      ],
    };
    await expectLater(
      repository.loadUnnotifiedBonuses(client),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('message'),
        ),
      ),
    );

    // A closed currency union decodes to neither member.
    rpc.accountBonusesValue = <String, Object?>{
      'accountId': 'user-7',
      'bonuses': <Object?>[
        <String, Object?>{
          'orderId': 'order-1',
          'campaign': 'welcome',
          'amount': '5.00',
          'currency': 'EUR',
          'grantedAt': '2026-10-01T00:00:00Z',
          'expiresAt': '2026-11-01T00:00:00Z',
          'message': 'x',
        },
      ],
    };
    await expectLater(
      repository.loadUnnotifiedBonuses(client),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('currency'),
        ),
      ),
    );

    // `attempt` is a required key that may be null; its absence is host
    // breakage, not "no attempt".
    expect(
      () => decodeAccountState(<String, Object?>{
        'status': 'signed-out',
        'links': <String, Object?>{
          'usageUrl': 'https://platform.example/usage',
          'topUpUrl': 'https://platform.example/top_up',
        },
      }),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('attempt'),
        ),
      ),
    );
  });

  test('pin mirrors the pin set the Host returns, most recent first', () async {
    final rpc = HarnessFakeRpc();
    final socket = ScriptedHarnessSocket();
    final repository = await harnessRepository(rpc, socket);
    addTearDown(repository.dispose);
    rpc.pinValue = <String, Object?>{
      'pinnedSessionIds': <String>['s-pinned', 's-older'],
    };

    final seen = <List<String>>[];
    final sub = repository.observePinnedSessionIds().listen(seen.add);
    addTearDown(sub.cancel);

    await repository.pinSession('s-pinned');

    expect(rpc.callCountFor(DshRpcEndpoints.workspacePinSession), 1);
    expect(
      rpc.rawPayloads(DshRpcEndpoints.workspacePinSession).single['sessionId'],
      's-pinned',
    );
    await pumpEventQueue();
    expect(seen.last, <String>['s-pinned', 's-older']);
  });

  test('unpin is a wire call even when the session was never pinned', () async {
    final rpc = HarnessFakeRpc();
    final socket = ScriptedHarnessSocket();
    final repository = await harnessRepository(rpc, socket);
    addTearDown(repository.dispose);
    rpc.pinValue = <String, Object?>{'pinnedSessionIds': <String>[]};

    await repository.unpinSession('s-not-pinned');

    expect(rpc.callCountFor(DshRpcEndpoints.workspaceUnpinSession), 1);
    expect(
      rpc
          .rawPayloads(DshRpcEndpoints.workspaceUnpinSession)
          .single['sessionId'],
      's-not-pinned',
    );
  });

  test(
    'a refused pin surfaces the Host code as a repository failure',
    () async {
      final rpc = HarnessFakeRpc();
      final socket = ScriptedHarnessSocket();
      final repository = await harnessRepository(rpc, socket);
      addTearDown(repository.dispose);

      rpc.failNextCall(
        DshRpcEndpoints.workspacePinSession,
        'gateway/bad-request',
      );

      await expectLater(
        repository.pinSession('s-archived'),
        throwsA(
          isA<RepositoryFailure>().having(
            (failure) => failure.code,
            'code',
            'gateway/bad-request',
          ),
        ),
      );
    },
  );

  test('archived sessions stay in the roster, marked archived', () async {
    final rpc = HarnessFakeRpc(<Object?>[
      <String, Object?>{
        'sessionId': 's-quiet',
        'updatedAt': 1,
        'running': false,
        'blank': false,
      },
      <String, Object?>{
        'sessionId': 's-archived',
        'updatedAt': 2,
        'running': false,
        'blank': false,
      },
    ]);
    final socket = ScriptedHarnessSocket(
      muxFrames: <ServerRequest>[
        ServerRequest(
          rpcId: 'workspace-follow',
          method: 'workspace/follow',
          payload: <String, Object?>{
            'type': 'baseline',
            'value': <String, Object?>{
              'items': <Object?>[],
              'archivedSessionIds': <Object?>['s-archived'],
            },
          },
        ),
      ],
    );
    final repository = await harnessRepository(rpc, socket);
    addTearDown(repository.dispose);
    await pumpEventQueue();
    socket.releaseMuxFrames();
    await pumpEventQueue();

    final sessions = await repository.observeSessions().first;
    expect(
      sessions.map((session) => session.id),
      containsAll(<String>['s-quiet', 's-archived']),
      reason: 'the roster carries archived rows; visibility is the view\'s',
    );
    expect(
      sessions.firstWhere((session) => session.id == 's-archived').archived,
      isTrue,
    );
    expect(
      sessions.firstWhere((session) => session.id == 's-quiet').archived,
      isFalse,
    );
  });

  test('a pinned frame replaces the pin mirror in the Host order', () async {
    final rpc = HarnessFakeRpc();
    final socket = ScriptedHarnessSocket(
      muxFrames: <ServerRequest>[
        ServerRequest(
          rpcId: 'workspace-follow',
          method: 'workspace/follow',
          payload: <String, Object?>{
            'type': 'pinned',
            'pinnedSessionIds': <Object?>['s-b', 's-a'],
          },
        ),
      ],
    );
    final repository = await harnessRepository(rpc, socket);
    addTearDown(repository.dispose);
    await pumpEventQueue();
    socket.releaseMuxFrames();
    await pumpEventQueue();

    expect(await repository.observePinnedSessionIds().first, <String>[
      's-b',
      's-a',
    ], reason: 'the pin order is the user\'s, not the session list\'s');
  });

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
    // (session id), the complete line, and `submittedAttachments` — the
    // descriptor's third parameter name, strict in both directions.
    final payload = rpc.payloads(DshRpcEndpoints.commandsExecute).single;
    final args = asJsonObject(payload['args']);
    expect(args, isNotNull, reason: 'missing args envelope');
    expect(args!['agentId'], 'session-1');
    expect(args['line'], '/plan');
    expect(args['submittedAttachments'], <Object?>[]);
  });

  test('executeCommand encodes composer images in submission order', () async {
    // Reference `CommandSubmitAttachment` (commands/src/types.ts): an
    // image entry is `{type: 'image'}` intersected with
    // `EncodedImageAttachment` `{mediaType, data (canonical base64),
    // name?}`; the tag is required and carries no other variant here.
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
    final attachments = args['submittedAttachments'];
    expect(attachments, isA<List<Object?>>());
    expect(attachments, <Object?>[
      <String, Object?>{
        'type': 'image',
        'mediaType': 'image/png',
        'data': 'aGVsbG8=',
        'name': 'mockup.png',
      },
      <String, Object?>{
        'type': 'image',
        'mediaType': 'image/jpeg',
        'data': 'dw==',
      },
    ]);
  });

  test('executeCommand encodes staged file receipts after images', () async {
    // Reference `CommandSubmitAttachment` (commands/src/types.ts): a file
    // entry is `{type: 'file', receiptId}` — the staged receipt the host
    // resolves inside this agent's scope, never the bytes again.
    final rpc = HarnessFakeRpc();
    final repository = await harnessRepository(rpc, ScriptedHarnessSocket());
    await pumpEventQueue();

    await repository.executeCommand(
      'session-1',
      '/goal Ship it',
      const <PendingImage>[
        PendingImage(id: 'img-1', mediaType: 'image/png', base64Data: 'dw=='),
      ],
      files: const <UploadedFile>[
        UploadedFile(
          receiptId: 'receipt-7',
          attachmentId: 'sha256:file-a',
          name: 'notes.pdf',
          byteSize: 2,
        ),
      ],
    );

    final payload = rpc.payloads(DshRpcEndpoints.commandsExecute).single;
    final args = asJsonObject(payload['args'])!;
    expect(args['submittedAttachments'], <Object?>[
      <String, Object?>{
        'type': 'image',
        'mediaType': 'image/png',
        'data': 'dw==',
      },
      <String, Object?>{'type': 'file', 'receiptId': 'receipt-7'},
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

  test('prompt with files appends file receipt parts after images', () async {
    // Reference `PromptContentPart` (session-controller client contract): the
    // staged file crosses as `{type: 'file', receiptId}` — the host resolves
    // it inside the addressed agent's scope and never re-reads the bytes.
    final rpc = HarnessFakeRpc();
    final repository = await harnessRepository(rpc, ScriptedHarnessSocket());
    await pumpEventQueue();

    await repository.sendMessage(
      const SendMessageRequest(
        sessionId: 'session-1',
        text: 'read this',
        images: <PendingImage>[
          PendingImage(
            id: 'u1',
            mediaType: 'image/png',
            base64Data: 'aGk=',
            name: 'shot.png',
          ),
        ],
        files: <UploadedFile>[
          UploadedFile(
            receiptId: 'receipt-7',
            attachmentId: 'sha256:file-a',
            name: 'notes.pdf',
            byteSize: 2,
          ),
        ],
      ),
    );

    final payload = rpc.payloads(DshRpcEndpoints.sessionPrompt).single;
    final payloadArgs = asJsonObject(payload['args']) ?? payload;
    final content = asJsonArray(payloadArgs['content']) ?? const <Object?>[];
    expect(content, hasLength(3));
    expect(asJsonObject(content[0])!['type'], 'text');
    expect(asJsonObject(content[1])!['type'], 'image');
    expect(asJsonObject(content[2]), <String, Object?>{
      'type': 'file',
      'receiptId': 'receipt-7',
    });
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

  // The subagent roster is the tree's fact source: 0.1.7 deleted
  // `subagents/list`, so the parent Session's `subagentCatalog` projection —
  // read through the non-activating `session/projections` method — is what the
  // Subagents screen cold-seeds from.
  test('session/projections decodes the parent subagent catalog', () async {
    // Fixture transcribed from
    // reference/deepseek-harness/packages/subagent/subagent/src/catalog.ts
    // `subagentCatalogEntries` / `projection-types.ts` SubagentCatalogEntry:
    // continuable and one-shot rows (label required/optional per mode) plus
    // the 0.1.7 `unknown` arm.
    final rpc = HarnessFakeRpc()
      ..subagentCatalogValue = <Object?>[
        <String, Object?>{
          'id': 'child-1',
          'createdAt': 1,
          'mode': 'continuable',
          'label': 'Worker',
        },
        <String, Object?>{'id': 'child-2', 'createdAt': 2, 'mode': 'one-shot'},
        <String, Object?>{'id': 'child-3', 'createdAt': 3, 'mode': 'unknown'},
      ];
    final repository = await harnessRepository(rpc, ScriptedHarnessSocket());
    await pumpEventQueue();

    final catalog = await repository.loadSubagents('session-root');

    final subagentPayload = rpc
        .payloads(DshRpcEndpoints.sessionProjections)
        .first;
    final subagentArgs =
        asJsonObject(subagentPayload['args']) ?? subagentPayload;
    // `payloads` flattens the request envelope for assertions; the wire
    // argument is the one `request` object the descriptor names.
    expect(subagentArgs['request'], <String, Object?>{
      'sessionId': 'session-root',
    });
    expect(catalog.parentSessionId, 'session-root');
    // `activity` comes from the session roster's own running bit (the deleted
    // RPC re-sampled each child's Agent driver); an unlisted child reads
    // inactive. `hasChildren` is derived from the mode, the only descendant
    // signal the projection carries.
    expect(catalog.entries, const <SubagentEntry>[
      SubagentEntry(
        id: 'child-1',
        mode: SubagentMode.continuable,
        activity: 'inactive',
        hasChildren: true,
        label: 'Worker',
      ),
      SubagentEntry(
        id: 'child-2',
        mode: SubagentMode.oneShot,
        activity: 'inactive',
      ),
      SubagentEntry(
        id: 'child-3',
        mode: SubagentMode.unknown,
        activity: 'inactive',
      ),
    ]);
  });

  test(
    'a parent with no catalogued children answers an empty roster',
    () async {
      final rpc = HarnessFakeRpc();
      final repository = await harnessRepository(rpc, ScriptedHarnessSocket());
      await pumpEventQueue();

      final catalog = await repository.loadSubagents('session-root');

      expect(catalog.parentSessionId, 'session-root');
      expect(catalog.entries, isEmpty);
    },
  );

  test(
    'session/projections answering null fails loud instead of an empty roster',
    () async {
      // `SessionProjectionsValue` is nullable: null means the Session does not
      // exist. An empty roster and an unreadable parent must not look the same
      // to the caller.
      final rpc = HarnessFakeRpc()..projectionsSessionMissing = true;
      final repository = await harnessRepository(rpc, ScriptedHarnessSocket());
      await pumpEventQueue();

      await expectLater(
        repository.loadSubagents('session-root'),
        throwsA(
          isA<DshBusinessException>().having(
            (error) => error.code,
            'code',
            'subagent/parent-unavailable',
          ),
        ),
      );
    },
  );

  test('a catalog row without id fails loud with the field name', () async {
    // Negative fixture: the projection schema requires `id` on every row; a
    // row missing it must throw naming the field, never decode to a default.
    final rpc = HarnessFakeRpc()
      ..subagentCatalogValue = <Object?>[
        <String, Object?>{'createdAt': 1, 'mode': 'continuable'},
      ];
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
  });

  test('a catalog row without a mode fails loud naming the field', () async {
    // Negative fixture: `projection-types.ts` SubagentCatalogEntry requires
    // `mode` on every row ('one-shot' | 'continuable' | 'unknown'); a row
    // without it must throw naming the field, never decode modeless.
    final rpc = HarnessFakeRpc()
      ..subagentCatalogValue = <Object?>[
        <String, Object?>{'id': 'child-1', 'createdAt': 1},
      ];
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
  });

  test(
    'a catalog row with an unrecorded mode fails loud naming the value',
    () async {
      final rpc = HarnessFakeRpc()
        ..subagentCatalogValue = <Object?>[
          <String, Object?>{'id': 'child-1', 'createdAt': 1, 'mode': 'future'},
        ];
      final repository = await harnessRepository(rpc, ScriptedHarnessSocket());
      await pumpEventQueue();

      await expectLater(
        repository.loadSubagents('session-root'),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('"future"'),
          ),
        ),
      );
    },
  );

  test(
    'a child opens as a followed window addressed by its own catalog mode',
    () async {
      // Wire: the subagent address carries mode
      // ('one-shot' | 'continuable'), and the host rejects a mismatch
      // (surfaced as `subagent/unauthorized`) —
      // reference/deepseek-harness/packages/subagent/subagent/src/control-types.ts
      // `SubagentAddress` + packages/api/session-controller/src/history.ts.
      // A one-shot row must go out as one-shot, and the same address serves
      // the page read and the live follow.
      final rpc = HarnessFakeRpc()
        ..subagentHistoryValue = <String, Object?>{
          'events': <Object?>[
            <String, Object?>{'event': _assistantMessageEvent()},
          ],
          'hasMore': false,
        };
      final socket = ScriptedHarnessSocket();
      final repository = await harnessRepository(rpc, socket);
      await pumpEventQueue();

      await repository.openSubagentSession(
        'session-root',
        'child-2',
        SubagentMode.oneShot,
      );
      await pumpEventQueue();

      final subHistoryArgs =
          asJsonObject(
            rpc.payloads(DshRpcEndpoints.sessionPage).single['args'],
          ) ??
          const <String, Object?>{};
      expect(subHistoryArgs['address'], <String, Object?>{
        'kind': 'subagent',
        'parentSessionId': 'session-root',
        'childSessionId': 'child-2',
        'mode': 'one-shot',
      });
      final window = await repository
          .observeTimelineWindow('child-2')
          .firstWhere((value) => value.items.isNotEmpty);
      expect(window.items, isNotEmpty);

      // The follow request carries the same address, so the child keeps
      // updating instead of freezing at the first page.
      final follow = socket.sentMuxMessages.firstWhere(
        (message) => message['streamId'] == 'session-follow-child-2',
      );
      final followAddress = asJsonObject(
        asJsonObject(
          asJsonObject(asJsonObject(follow['payload'])?['args'])?['request'],
        )?['address'],
      );
      expect(followAddress, <String, Object?>{
        'kind': 'subagent',
        'parentSessionId': 'session-root',
        'childSessionId': 'child-2',
        'mode': 'one-shot',
      });
    },
  );

  test('an ordinary open still addresses a session as itself', () async {
    final rpc = HarnessFakeRpc();
    final repository = await harnessRepository(rpc, ScriptedHarnessSocket());
    await pumpEventQueue();

    await repository.openSession('session-plain');
    await pumpEventQueue();

    final args =
        asJsonObject(rpc.payloads(DshRpcEndpoints.sessionPage).first['args']) ??
        const <String, Object?>{};
    expect(args['address'], <String, Object?>{
      'kind': 'session',
      'sessionId': 'session-plain',
    });
  });

  test('a child-history host failure reaches the opener', () async {
    // Fail-loud: a `subagent/unauthorized` answer (the host's mode-guard
    // rejection) never decays into a transcript that reads as "this child
    // said nothing" — the subagent view has a catalog to fall back to, so the
    // failure belongs on its banner rather than in an empty record.
    final rpc = HarnessFakeRpc()
      ..failNextCall(DshRpcEndpoints.sessionPage, 'subagent/unauthorized');
    final repository = await harnessRepository(rpc, ScriptedHarnessSocket());
    await pumpEventQueue();

    await expectLater(
      repository.openSubagentSession(
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

  // Wire shape: agentPresets/list roster
  // (reference/deepseek-harness/packages/preset/agent-preset-registry/src/
  // types.ts).
  test('agentPresets/list decodes the roster', () async {
    final rpc = HarnessFakeRpc();
    final repository = await harnessRepository(rpc, ScriptedHarnessSocket());
    await pumpEventQueue();

    final roster = await repository.listAgentPresets();

    final presetPayload = rpc.payloads(DshRpcEndpoints.agentPresetsList).single;
    final presetArgs = asJsonObject(presetPayload['args']) ?? presetPayload;
    expect(presetArgs, isEmpty);
    expect(roster.entries, hasLength(3));
    final standard = roster.entries[0];
    expect(standard.id, 'standard');
    expect(standard.isDefault, isTrue);
    expect(standard.name, isNull);
    expect(roster.defaultEntry?.id, 'standard');
    final minimal = roster.entries[1];
    expect(minimal.name, 'Tiny');
    expect(minimal.description, 'Two tools only');
    final custom = roster.entries[2];
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

  // Negative fixture: a required roster-row field absent must fail loud.
  test('agentPresets/list row without isDefault throws', () {
    expect(
      () => AgentPresetListValueWire.fromJson(<String, Object?>{
        'presets': <Object?>[
          <String, Object?>{'id': 'standard'},
        ],
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

    // Diagnostic emitted: an unaddressed child cannot be opened as an
    // ordinary session, and the message names the verb that can.
    final warning = diagnostics.firstWhere((d) => d.context == 'session.open');
    expect(warning.message, contains('subagent-child'));
    expect(warning.message, contains('openSubagentSession'));

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

  test('openSession is idempotent on multiple calls and preserves paginated history', () async {
    final rpc = HarnessFakeRpc(<Object?>[resyncSessionRow('s1')]);
    final socket = ReconnectableHarnessSocket();
    final repository = await resyncFixture(rpc, socket);
    await pumpEventQueue();

    rpc.historyEvents['s1'] = <Object?>[
      resyncAssistantTextEvent(10, 'tail message'),
    ];

    // Concurrent openSession calls coalesce onto a single RPC
    await Future.wait(<Future<void>>[
      repository.openSession('s1'),
      repository.openSession('s1'),
      repository.openSession('s1'),
    ]);
    await pumpEventQueue();

    expect(rpc.callCountFor(DshRpcEndpoints.sessionPage), 1);

    // Repeated openSession on already opened active session does not re-fetch
    await repository.openSession('s1');
    await pumpEventQueue();
    expect(rpc.callCountFor(DshRpcEndpoints.sessionPage), 1);
  });

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

  test('message feedback reads the Session log and writes its item', () async {
    final rpc = HarnessFakeRpc(<Object?>[])
      ..messageFeedbackItemsValue = <Object?>[
        <String, Object?>{
          'messageId': 'm-1',
          'rating': 'positive',
          'note': 'clear answer',
          'category': 'task-result',
          'version': 'v-1',
          'createdAt': 100,
          'updatedAt': 200,
        },
        <String, Object?>{
          'messageId': 'm-2',
          'rating': 'negative',
          'version': 'v-2',
          'createdAt': 300,
          'updatedAt': 300,
        },
      ];
    final socket = ScriptedHarnessSocket();
    final repository = await harnessRepository(rpc, socket);
    await pumpEventQueue();

    final items = await repository.listMessageFeedback('session-s');
    expect(items, hasLength(2));
    expect(items.first.messageId, 'm-1');
    expect(items.first.rating, MessageFeedbackRating.positive);
    expect(items.first.note, 'clear answer');
    expect(items.first.category, MessageFeedbackCategory.taskResult);
    expect(items.first.version, 'v-1');
    expect(items.first.createdAtEpochMs, 100);
    expect(items.first.updatedAtEpochMs, 200);
    // An absent note or category stays absent; nothing defaults it.
    expect(items.last.note, isNull);
    expect(items.last.category, isNull);
    expect(
      asJsonObject(
        requestPayload(
          rpc.payloads(DshRpcEndpoints.messageFeedbackList).single,
        ),
      ),
      <String, Object?>{'sessionId': 'session-s'},
    );

    final committed = await repository.putMessageFeedback(
      'session-s',
      messageId: 'm-1',
      rating: MessageFeedbackRating.negative,
      ifVersion: 'v-1',
    );
    final item = (committed as MessageFeedbackCommitted).item!;
    expect(item.messageId, 'm-1');
    expect(item.rating, MessageFeedbackRating.negative);
    expect(item.version, 'v-put-1');

    // The optional entry members stay off the wire when the caller omits them,
    // and the compare-and-set version travels as the caller observed it.
    final putRequest = asJsonObject(
      requestPayload(rpc.payloads(DshRpcEndpoints.messageFeedbackPut).single),
    )!;
    expect(putRequest['sessionId'], 'session-s');
    expect(putRequest['messageId'], 'm-1');
    expect(putRequest['rating'], 'negative');
    expect(putRequest['ifVersion'], 'v-1');
    expect(putRequest.containsKey('note'), isFalse);
    expect(putRequest.containsKey('category'), isFalse);

    final deleted = await repository.deleteMessageFeedback(
      'session-s',
      messageId: 'm-1',
      ifVersion: 'v-put-1',
    );
    expect((deleted as MessageFeedbackCommitted).item, isNull);
    expect(
      asJsonObject(
        requestPayload(
          rpc.payloads(DshRpcEndpoints.messageFeedbackDelete).single,
        ),
      ),
      <String, Object?>{
        'sessionId': 'session-s',
        'messageId': 'm-1',
        'ifVersion': 'v-put-1',
      },
    );
  });

  test('a null ifVersion still travels as an explicit wire field', () async {
    final rpc = HarnessFakeRpc(<Object?>[]);
    final socket = ScriptedHarnessSocket();
    final repository = await harnessRepository(rpc, socket);
    await pumpEventQueue();

    await repository.putMessageFeedback(
      'session-s',
      messageId: 'm-1',
      rating: MessageFeedbackRating.positive,
      ifVersion: null,
      note: 'please keep the recap',
      category: MessageFeedbackCategory.instructionFollowing,
    );

    final request = asJsonObject(
      requestPayload(rpc.payloads(DshRpcEndpoints.messageFeedbackPut).single),
    )!;
    // Null demands that no item exists yet, so the key is present and null
    // rather than omitted — the Host reads it for its compare-and-set.
    expect(request.containsKey('ifVersion'), isTrue);
    expect(request['ifVersion'], isNull);
    expect(request['note'], 'please keep the recap');
    expect(request['category'], 'instruction-following');
  });

  test('a version conflict answers the authoritative item', () async {
    final rpc = HarnessFakeRpc(<Object?>[])
      ..messageFeedbackMutationValue = <String, Object?>{
        'ok': false,
        'error': <String, Object?>{
          'code': 'version-conflict',
          'current': <String, Object?>{
            'messageId': 'm-1',
            'rating': 'negative',
            'version': 'v-9',
            'createdAt': 100,
            'updatedAt': 400,
          },
        },
      };
    final socket = ScriptedHarnessSocket();
    final repository = await harnessRepository(rpc, socket);
    await pumpEventQueue();

    final result = await repository.putMessageFeedback(
      'session-s',
      messageId: 'm-1',
      rating: MessageFeedbackRating.positive,
      ifVersion: null,
    );
    final refused = result as MessageFeedbackRefused;
    expect(refused.code, 'version-conflict');
    expect(refused.current?.messageId, 'm-1');
    expect(refused.current?.rating, MessageFeedbackRating.negative);
    expect(refused.current?.version, 'v-9');
  });

  test('a refusal without an authoritative item decodes as absent', () async {
    final rpc = HarnessFakeRpc(<Object?>[])
      ..messageFeedbackMutationValue = <String, Object?>{
        'ok': false,
        'error': <String, Object?>{
          'code': 'session-not-found',
          'sessionId': 'session-s',
        },
      };
    final socket = ScriptedHarnessSocket();
    final repository = await harnessRepository(rpc, socket);
    await pumpEventQueue();

    final result = await repository.deleteMessageFeedback(
      'session-s',
      messageId: 'm-1',
      ifVersion: 'v-1',
    );
    final refused = result as MessageFeedbackRefused;
    expect(refused.code, 'session-not-found');
    expect(refused.current, isNull);
  });

  test('a message feedback list refusal is a RepositoryFailure', () async {
    final rpc = HarnessFakeRpc(<Object?>[])
      ..messageFeedbackListValue = <String, Object?>{
        'ok': false,
        'error': <String, Object?>{
          'code': 'session-not-found',
          'sessionId': 'session-s',
        },
      };
    final socket = ScriptedHarnessSocket();
    final repository = await harnessRepository(rpc, socket);
    await pumpEventQueue();

    await expectLater(
      repository.listMessageFeedback('session-s'),
      throwsA(
        isA<RepositoryFailure>().having(
          (RepositoryFailure failure) => failure.code,
          'code',
          'session-not-found',
        ),
      ),
    );
  });

  test('sessionFeedback/record writes its remark and reports a departed '
      'session', () async {
    final rpc = HarnessFakeRpc(<Object?>[]);
    final socket = ScriptedHarnessSocket();
    final repository = await harnessRepository(rpc, socket);
    await pumpEventQueue();

    await repository.recordSessionFeedback(
      'session-s',
      text: 'the plan missed a step',
      category: MessageFeedbackCategory.productInteraction,
    );
    expect(
      asJsonObject(
        requestPayload(
          rpc.payloads(DshRpcEndpoints.sessionFeedbackRecord).single,
        ),
      ),
      <String, Object?>{
        'sessionId': 'session-s',
        'text': 'the plan missed a step',
        'category': 'product-interaction',
      },
    );

    rpc.sessionFeedbackRecordValue = <String, Object?>{
      'ok': false,
      'error': <String, Object?>{
        'code': 'session-not-found',
        'sessionId': 'session-s',
      },
    };
    await expectLater(
      repository.recordSessionFeedback('session-s', text: 'again'),
      throwsA(
        isA<RepositoryFailure>().having(
          (RepositoryFailure failure) => failure.code,
          'code',
          'session-not-found',
        ),
      ),
    );
  });

  test(
    'a feedback envelope without a boolean ok fails loud naming it',
    () async {
      final rpc = HarnessFakeRpc(<Object?>[])
        ..messageFeedbackMutationValue = <String, Object?>{
          'value': <String, Object?>{
            'messageId': 'm-1',
            'rating': 'positive',
            'version': 'v-1',
            'createdAt': 1,
            'updatedAt': 1,
          },
        };
      final socket = ScriptedHarnessSocket();
      final repository = await harnessRepository(rpc, socket);
      await pumpEventQueue();

      await expectLater(
        repository.putMessageFeedback(
          'session-s',
          messageId: 'm-1',
          rating: MessageFeedbackRating.positive,
          ifVersion: null,
        ),
        throwsA(
          isA<FormatException>().having(
            (FormatException error) => error.message,
            'message',
            contains('ok'),
          ),
        ),
      );
    },
  );

  test(
    'a feedback item missing a required field fails loud naming it',
    () async {
      final rpc = HarnessFakeRpc(<Object?>[])
        ..messageFeedbackItemsValue = <Object?>[
          <String, Object?>{
            'messageId': 'm-1',
            'rating': 'positive',
            'createdAt': 1,
            'updatedAt': 1,
          },
        ];
      final socket = ScriptedHarnessSocket();
      final repository = await harnessRepository(rpc, socket);
      await pumpEventQueue();

      await expectLater(
        repository.listMessageFeedback('session-s'),
        throwsA(
          isA<FormatException>().having(
            (FormatException error) => error.message,
            'message',
            contains('version'),
          ),
        ),
      );
    },
  );
}
