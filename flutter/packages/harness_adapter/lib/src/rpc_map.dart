/// JSON container helpers shared inside the adapter.
///
/// The [JsonMap] type itself comes from the network package so the two
/// packages never disagree about the decoded-wire representation.
library;

import 'package:network/rpc_envelope.dart' show JsonMap;

export 'package:network/rpc_envelope.dart' show JsonMap;

/// A decoded JSON array.
typedef JsonList = List<Object?>;

/// Centralized DSH RPC endpoint registry.
///
/// In DSH 0.1.2+, all RPCs follow Typert Remote conventions (slash-separated
/// namespaces and methods). Plural namespaces (skills, subagents, goals,
/// agentPresets) and separated services (directoryPicker) represent the
/// canonical upstream contract.
abstract final class DshRpcEndpoints {
  // Session
  static const String sessionList = 'session/list';
  static const String sessionCreate = 'session/create';
  static const String sessionPrompt = 'session/prompt';
  static const String sessionAttachment = 'session/attachment';
  static const String sessionCancel = 'session/cancel';
  static const String sessionSearch = 'session/search';
  static const String sessionRename = 'session/rename';
  static const String sessionFork = 'session/fork';
  static const String sessionUpdateQueue = 'session/updateQueue';
  static const String sessionSelectModel = 'session/selectModel';
  static const String sessionModelCatalog = 'session/modelCatalog';
  static const String sessionHistory = 'session/history';
  static const String sessionPage = 'session/page';

  /// Non-activating read of every registered projection for one Session
  /// (`packages/api/session-controller/src/index.ts` `@Remote('projections')`).
  /// It replaced `subagents/list`: the subagent roster is the parent's
  /// `subagentCatalog` projection value, not a dedicated method.
  static const String sessionProjections = 'session/projections';

  // User questions. The blocking answer rides the `$events` waterfall
  // (`$events/result`); a timed ask the host has already continued is answered
  // here instead (`packages/interaction/user-questions/src/index.ts`
  // `@Remote answer`).
  static const String userQuestionsAnswer = 'userQuestions/answer';

  // Skills (DSH 0.1.2 plural namespace)
  static const String skillsList = 'skills/list';

  // Subagents (DSH 0.1.2 plural namespace and renamed verbs). 0.1.7 deleted
  // `subagents/list`; the roster moved to the `subagentCatalog` projection
  // (see [sessionProjections]).
  static const String subagentsPrompt = 'subagents/prompt';
  static const String subagentsInterrupt = 'subagents/interruptByParent';
  static const String subagentsHistory = 'subagent/history';

  // Goals (DSH 0.1.2 plural namespace)
  static const String goalsCreate = 'goals/create';
  static const String goalsEdit = 'goals/edit';
  static const String goalsPause = 'goals/pause';
  static const String goalsResume = 'goals/resume';
  static const String goalsComplete = 'goals/complete';
  static const String goalsClear = 'goals/clear';

  // Agent Presets (DSH 0.1.2 plural namespace)
  static const String agentPresetsList = 'agentPresets/list';
  static const String agentPresetsRead = 'agentPresets/read';
  static const String agentPresetsSelect = 'agentPresets/select';

  // Directory Picker (DSH 0.1.2 directoryPickerController)
  static const String directoryPickerList = 'directoryPicker/list';
  static const String directoryPickerCreate = 'directoryPicker/createDirectory';

  // Workspace
  static const String workspaceCreate = 'workspace/create';
  static const String workspaceRename = 'workspace/rename';
  static const String workspaceDelete = 'workspace/delete';
  static const String workspaceInsertBefore = 'workspace/insertBefore';
  static const String workspaceInsertSessionBefore =
      'workspace/insertSessionBefore';
  static const String workspaceArchiveSession = 'workspace/archiveSession';
  static const String workspaceUnarchiveSession = 'workspace/unarchiveSession';
  static const String workspacePinSession = 'workspace/pinSession';
  static const String workspaceUnpinSession = 'workspace/unpinSession';

  // Workspace Files. `read` pages decoded UTF-8 text; `readBytes` returns
  // native bytes — the whole file when `options.range` is absent, one window
  // otherwise. Both scope the file through the `workspaceFileScope` lookup.
  //
  // `readBytes` answers a `WorkspaceFileBytes` whose `data` is a `Uint8Array`
  // (reference/deepseek-harness/packages/api/workspace-files/src/index.ts:256
  // `@Remote`, :262 return type, :270 ranged return, :279 whole-file return;
  // types.ts:84). The Typert result codec projects a `Uint8Array` field out of
  // the JSON body as a `null` placeholder and records it at its result-relative
  // path (packages/typert/protocol/src/types.ts:283-288 `encode`/`writeBytes`;
  // packages/typert/generator/src/emitter.ts:1059 roots that path at the result
  // value, :575-576 writes the placeholder for the leaf;
  // packages/api/gateway/src/index.ts:991-1001 collects `{path, bytes}`).
  // A reply carrying attachments is therefore `multipart/form-data` — a
  // `metadata` JSON field plus one `bytes-<i>` binary part per attachment
  // (packages/client/connection/src/rpc-host.ts:300-311) — and the reference
  // client splices each part back over its placeholder
  // (packages/client/connection/src/client/rpc.ts:83-139).
  // `decodeRpcAttachmentResponse` in package:network performs that splice, so
  // the byte carrier reaches this package as an ordinary result value.
  static const String workspaceFilesStat = 'workspaceFiles/stat';
  static const String workspaceFilesRead = 'workspaceFiles/read';

  /// Whole-file or byte-window read —
  /// `readBytes(workspaceFileScope, path, options, signal)`; the file preview's
  /// byte path.
  static const String workspaceFilesReadBytes = 'workspaceFiles/readBytes';
  static const String workspaceFilesList = 'workspaceFiles/list';

  // Settings & Commands
  static const String commandsList = 'commands/list';
  static const String commandsExecute = 'commands/execute';

  // File-reference discovery (DSH 0.2.0 `fileReferences` namespace —
  // reference/deepseek-harness/packages/api/session-controller/src/
  // file-references.ts, `super(ctx, 'sessionFileReferences', { namespace:
  // 'fileReferences' })`). Its one method takes the Agent lookup, whose wire
  // field is `agentId`, plus the `@` path query.
  static const String fileReferencesList = 'fileReferences/list';

  // File uploads (DSH 0.2.0 `fileUploads` service —
  // reference/deepseek-harness/packages/client/file-upload/src/index.ts,
  // `super(ctx, 'fileUploads')`, `@Remote('upload')`). The unary method takes
  // the Agent lookup (wire field `agentId`) plus the `EncodedFileUploadRequest`
  // fields flattened by Typert (`data` base64, optional `name`) and answers a
  // `FileUploadValue` — the staged `receiptId` a prompt cites plus the durable
  // `file` reference. The same package registers a raw-byte route
  // (`/api/session/uploadFileBinary`, http-route.ts) for streamed bodies;
  // this client sends one picked file through the base64 method instead (see
  // the file-upload decision note).
  static const String fileUploadsUpload = 'fileUploads/upload';

  // Human feedback (DSH 0.2.0; two Host services — `messageFeedback`
  // (reference/deepseek-harness/packages/feedback/message-feedback/src/
  // index.ts, `@Remote('list')` / `'put'` / `'delete'`) and `sessionFeedback`
  // (packages/feedback/command-feedback/src/index.ts, `@Remote('record')`).
  // All four take one `MessageFeedback*Request` /
  // `SessionFeedbackRecordRequest` object. The message trio works off the
  // canonical Session log rather than a live Agent, and answers the Host's own
  // `{ok, value|error}` business result inside the transport's success branch.
  // `/feedback <text>` additionally rides the ordinary command roster through
  // `commands/execute`.
  static const String messageFeedbackList = 'messageFeedback/list';
  static const String messageFeedbackPut = 'messageFeedback/put';
  static const String messageFeedbackDelete = 'messageFeedback/delete';
  static const String sessionFeedbackRecord = 'sessionFeedback/record';

  static const String settingsDescribe = 'settings/describe';
  static const String settingsUpdate = 'settings/update';
  static const String settingsReplace = 'settings/replace';
  static const String settingsMutate = 'settings/mutate';
  static const String permissionPresetsCatalog = 'permissionPresets/catalog';
  static const String credentialsDescribe = 'credentials/describe';
  static const String credentialsSet = 'credentials/set';
  static const String credentialsUnset = 'credentials/unset';

  // Account (DSH 0.2.0 `accountController` service —
  // reference/deepseek-harness/packages/api/account-controller/src/index.ts,
  // `super(ctx, 'accountController', { namespace: 'account' })`). The four
  // verbs that remain unwired are deliberate: `startSignIn`/`cancelSignIn`/
  // `signOut` need a browser OAuth flow or a Platform callback origin a phone
  // surface cannot supply, and `hasRunningAccountTasks` only gates that flow.
  // `account/watch` and `account/watchExpiry` are streams and stay literals
  // (docs/spec.md §4.6).
  static const String accountGetState = 'account/getState';
  static const String accountGetProfile = 'account/getProfile';
  static const String accountGetBalance = 'account/getBalance';
  static const String accountGetUnnotifiedBonuses =
      'account/getUnnotifiedBonuses';
  static const String accountAckBonusNotified = 'account/ackBonusNotified';

  // LLM provider/model administration (DSH 0.1.5 `llm` service —
  // reference/deepseek-harness/packages/llm/llm/src/index.ts `LlmRuntime`,
  // which binds the bare service key `llm` as its Remote namespace).
  static const String llmListProviders = 'llm/listProviders';
  static const String llmListConfigurableProviders =
      'llm/listConfigurableProviders';
  static const String llmDiscoverModels = 'llm/discoverModels';

  // Dynamic Cordis plugin runner (DSH 0.1.5 `dynamicCordisRunner` service —
  // reference/deepseek-harness/packages/extensions/cordis-host-runner/src/
  // index.ts, `@Remote('resolveRequestRun')`).
  static const String cordisResolveRequestRun =
      'dynamicCordisRunner/resolveRequestRun';

  // Plugin inventory (DSH 0.1.5 `pluginInventory` service —
  // reference/deepseek-harness/packages/host/plugin-inventory/src/index.ts,
  // `@Remote('list')`).
  static const String pluginInventoryList = 'pluginInventory/list';

  // Background jobs (DSH 0.1.2 `job` namespace —
  // reference/deepseek-harness/packages/api/job-controller/src/index.ts,
  // `super(ctx, 'jobController', { namespace: 'job' })`). `job/list` and
  // `job/follow` are streams and are opened by literal: the wire-pin gate
  // compares unary registrations only, so a stream constant would read as a
  // client-only name (docs/spec.md §4.6).
  static const String jobKill = 'job/kill';

  // Plugin manager (DSH 0.1.2 `pluginManager` service —
  // reference/deepseek-harness/packages/boot/plugin-manager/src/index.ts,
  // `super(ctx, 'pluginManager')`). Every method is unary; installation
  // progress travels as the forwarded `plugin-manager/*` events, never as a
  // stream. `pluginInventory/list`'s `managementAvailable` is the gate.
  static const String pluginManagerListBundles = 'pluginManager/listBundles';
  static const String pluginManagerListPlugins = 'pluginManager/listPlugins';
  static const String pluginManagerRegistries = 'pluginManager/registries';
  static const String pluginManagerInspect = 'pluginManager/inspect';
  static const String pluginManagerInstallBundle =
      'pluginManager/installBundle';
  static const String pluginManagerWaitForInstall =
      'pluginManager/waitForInstall';
  static const String pluginManagerCancelInstall =
      'pluginManager/cancelInstall';
  static const String pluginManagerSetBundleEnabled =
      'pluginManager/setBundleEnabled';
  static const String pluginManagerSetPluginEnabled =
      'pluginManager/setPluginEnabled';
  static const String pluginManagerRemoveBundle = 'pluginManager/removeBundle';
  static const String pluginManagerListVersionExemptions =
      'pluginManager/listVersionExemptions';
  static const String pluginManagerSetVersionExemption =
      'pluginManager/setVersionExemption';

  /// Registry speed probe, registered by the Web client package
  /// (`packages/client/ui-plugin-manager/src/index.ts`,
  /// `super(ctx, 'pluginRegistryProbe')`).
  static const String pluginRegistryProbeFastest =
      'pluginRegistryProbe/fastest';

  // Scheduled tasks (DSH 0.1.2 `schedule` service —
  // reference/deepseek-harness/packages/schedule/schedule/src/index.ts,
  // `super(ctx, 'schedule')`). `create` is not a Remote: a reminder is
  // created by the model's own tool, and the shipped Web bundle mounts this
  // service disabled, so a surface must probe `schedule/catalog` rather than
  // assume it.
  static const String scheduleList = 'schedule/list';
  static const String scheduleCatalog = 'schedule/catalog';
  static const String scheduleHistory = 'schedule/history';
  static const String scheduleUpdate = 'schedule/update';
  static const String scheduleDelete = 'schedule/delete';

  // Terminals (DSH 0.1.2 `terminal` namespace —
  // reference/deepseek-harness/packages/api/terminal-controller/src/index.ts,
  // `super(ctx, 'terminalController', { namespace: 'terminal' })`). Every
  // method but `list` takes the Agent lookup, whose wire field is `agentId`;
  // `follow` and `retain` are streams and stay literals (docs/spec.md §4.6).
  static const String terminalEnvironment = 'terminal/environment';
  static const String terminalShells = 'terminal/shells';
  static const String terminalList = 'terminal/list';
  static const String terminalCreate = 'terminal/create';
  static const String terminalWrite = 'terminal/write';
  static const String terminalResize = 'terminal/resize';
  static const String terminalRename = 'terminal/rename';
  static const String terminalClose = 'terminal/close';

  // Remote Events (DSH 0.1.2)
  static const String eventsResult = r'$events/result';
}

/// Fallback mapping from canonical DSH 0.1.2 endpoints to legacy 0.1.1 endpoints.
///
/// Kept empty since all communication is strictly locked to DSH 0.1.2.
const Map<String, List<String>> kDshEndpointFallbacks =
    <String, List<String>>{};

/// HTTP routes the client GETs directly instead of wrapping in a typert RPC
/// envelope.
///
/// These are not Typert Remote methods: the host registers them on the
/// connection carrier's own route table (`connection.fetch.register`), and
/// they answer with a non-JSON body — the session-log route streams a ZIP.
/// They therefore stay out of [DshRpcEndpoints], whose members the wire-pin
/// gate compares against the pinned Typert Remote surface.
abstract final class DshHttpRoutes {
  /// The session-log archive download; methods `GET` and `HEAD` at 0.1.5
  /// (`reference/deepseek-harness/packages/session-query/session-log-export/src/index.ts`
  /// `SESSION_LOG_EXPORT_PATH`).
  static const String sessionLogExport = '/api/session.export';
}

/// Returns [value] as a [JsonMap], or null when it is not an object.
JsonMap? asJsonObject(Object? value) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) return value.cast<String, Object?>();
  return null;
}

/// Returns [value] as a [JsonList], or null when it is not an array.
JsonList? asJsonArray(Object? value) {
  if (value is List<Object?>) return value;
  if (value is List) return value.cast<Object?>();
  return null;
}
