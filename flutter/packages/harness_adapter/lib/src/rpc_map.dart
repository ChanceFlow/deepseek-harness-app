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
  static const String workspaceList = 'workspace/list';

  // Host & Settings & Commands
  static const String hostDescribe = 'host/describe';
  static const String commandsExecute = 'commands/execute';
  static const String settingsDescribe = 'settings/describe';
  static const String settingsUpdate = 'settings/update';
  static const String settingsReplace = 'settings/replace';
  static const String settingsMutate = 'settings/mutate';
  static const String credentialsDescribe = 'credentials/describe';
  static const String credentialsSet = 'credentials/set';
  static const String credentialsUnset = 'credentials/unset';
}

/// Fallback mapping from canonical DSH 0.1.2 endpoints to legacy 0.1.1 endpoints.
///
/// Kept empty since all communication is strictly locked to DSH 0.1.2.
const Map<String, List<String>> kDshEndpointFallbacks =
    <String, List<String>>{};

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
