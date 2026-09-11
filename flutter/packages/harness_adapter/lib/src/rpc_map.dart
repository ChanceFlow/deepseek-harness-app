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

  // Skills (DSH 0.1.2 plural namespace)
  static const String skillsList = 'skills/list';

  // Subagents (DSH 0.1.2 plural namespace and renamed verbs)
  static const String subagentsList = 'subagents/list';
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

  // Workspace Files (DSH 0.1.5 workspaceFiles service)
  static const String workspaceFilesStat = 'workspaceFiles/stat';
  static const String workspaceFilesRead = 'workspaceFiles/read';
  static const String workspaceFilesReadBytes = 'workspaceFiles/readBytes';
  static const String workspaceFilesReadAll = 'workspaceFiles/readAll';
  static const String workspaceFilesList = 'workspaceFiles/list';

  // Settings & Commands
  static const String commandsList = 'commands/list';
  static const String commandsExecute = 'commands/execute';
  static const String settingsDescribe = 'settings/describe';
  static const String settingsUpdate = 'settings/update';
  static const String settingsReplace = 'settings/replace';
  static const String settingsMutate = 'settings/mutate';
  static const String credentialsDescribe = 'credentials/describe';
  static const String credentialsSet = 'credentials/set';
  static const String credentialsUnset = 'credentials/unset';

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
