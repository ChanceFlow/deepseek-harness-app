/// Wire DTO decoders mirroring `DshWireTypes.kt`. Every decoder tolerates
/// unknown keys; fields that carried no Kotlin default are REQUIRED — a
/// missing or mistyped required field throws [FormatException], matching
/// kotlinx-serialization's decode failures (the repository converts those
/// into nulls with `runCatching` exactly like the Kotlin code).
library;

import 'package:domain/model/attachment.dart';
import 'package:domain/model/command.dart';
import 'package:domain/model/context_pressure.dart';
import 'package:domain/model/plugin_inventory.dart';
import 'package:domain/model/settings.dart';
import 'package:domain/model/token_usage.dart';

import 'rpc_map.dart';
import 'wire_json.dart';

// ---------------------------------------------------------------------------
// Required-field helpers (mirror kotlinx decode failures)
// ---------------------------------------------------------------------------

Never _missing(JsonMap json, String key) => throw FormatException(
  'required field "$key" missing or mistyped in ${json.keys.toList()}',
);

String _reqString(JsonMap json, String key) {
  final value = wireString(json, key);
  if (value == null) _missing(json, key);
  return value;
}

int _reqLong(JsonMap json, String key) {
  if (!json.containsKey(key)) _missing(json, key);
  final value = json[key];
  if (value is int) return value;
  if (value is num) {
    final truncated = value.truncateToDouble();
    if (value == truncated) return truncated.toInt();
  }
  if (value is String && int.tryParse(value) != null) {
    return int.parse(value);
  }
  _missing(json, key);
}

bool _reqBool(JsonMap json, String key) {
  final value = json[key];
  if (value is bool) return value;
  if (value is String && (value == 'true' || value == 'false')) {
    return value == 'true';
  }
  _missing(json, key);
}

JsonMap _reqObject(JsonMap json, String key) {
  final value = asJsonObject(json[key]);
  if (value == null) _missing(json, key);
  return value;
}

// ---------------------------------------------------------------------------
// Sessions
// ---------------------------------------------------------------------------

final class SessionWire {
  SessionWire.fromJson(JsonMap json)
    : sessionId = _reqString(json, 'sessionId'),
      updatedAt = wireLong(json, 'updatedAt'),
      running = wireBool(json, 'running'),
      blank = json.containsKey('blank') ? wireBool(json, 'blank') : true,
      parentSessionId = wireString(json, 'parentSessionId'),
      origin = wireString(json, 'origin'),
      cwd = wireString(json, 'cwd'),
      agentPreset =
          wireString(json, 'agentPreset') ??
          wireString(
            asJsonObject(asJsonObject(json['projections'])?['values']) ??
                const <String, Object?>{},
            'agentPreset',
          ),
      projections = asJsonObject(json['projections']);

  final String sessionId;
  final int updatedAt;
  final bool running;
  final bool blank;
  final String? parentSessionId;
  final String? origin;
  final String? cwd;
  final String? agentPreset;
  final JsonMap? projections;

  int get asOfSeq =>
      projections == null ? 0 : wireLong(projections!, 'asOfSeq');

  JsonMap? get projectionValues =>
      projections == null ? null : asJsonObject(projections!['values']);
}

List<SessionWire> decodeSessionListValue(JsonMap value) =>
    (asJsonArray(value['items']) ?? const <Object?>[])
        .map(asJsonObject)
        .whereType<JsonMap>()
        .map(SessionWire.fromJson)
        .toList();

// ---------------------------------------------------------------------------
// Workspaces
// ---------------------------------------------------------------------------

final class WorkspaceWire {
  WorkspaceWire.fromJson(JsonMap json)
    : workspaceId = _reqString(json, 'workspaceId'),
      path = _reqString(json, 'path'),
      title = _reqString(json, 'title'),
      sessionIds = _stringList(json['sessionIds']),
      createdAt = wireString(json, 'createdAt') ?? '',
      updatedAt = wireString(json, 'updatedAt') ?? '';

  final String workspaceId;
  final String path;
  final String title;
  final List<String> sessionIds;
  final String createdAt;
  final String updatedAt;
}

final class WorkspaceListValueWire {
  WorkspaceListValueWire.fromJson(JsonMap json)
    : items = (asJsonArray(json['items']) ?? const <Object?>[])
          .map(asJsonObject)
          .whereType<JsonMap>()
          .map(WorkspaceWire.fromJson)
          .toList(),
      archivedSessionIds = _stringList(json['archivedSessionIds']);

  final List<WorkspaceWire> items;
  final List<String> archivedSessionIds;
}

// ---------------------------------------------------------------------------
// Model catalog
// ---------------------------------------------------------------------------

final class ModelSelectionWire {
  ModelSelectionWire.fromJson(JsonMap json)
    : provider = _reqString(json, 'provider'),
      model = _reqString(json, 'model'),
      reasoningEffort = wireString(json, 'reasoningEffort');

  final String provider;
  final String model;
  final String? reasoningEffort;
}

final class ModelReasoningEffortWire {
  ModelReasoningEffortWire.fromJson(JsonMap json)
    : id = _reqString(json, 'id'),
      name = _reqString(json, 'name'),
      description = wireString(json, 'description');

  final String id;
  final String name;
  final String? description;
}

final class ModelReasoningWire {
  ModelReasoningWire.fromJson(JsonMap json)
    : efforts = (asJsonArray(json['efforts']) ?? const <Object?>[])
          .map(asJsonObject)
          .whereType<JsonMap>()
          .map(ModelReasoningEffortWire.fromJson)
          .toList(),
      defaultEffort = wireString(json, 'defaultEffort');

  final List<ModelReasoningEffortWire> efforts;
  final String? defaultEffort;
}

final class ModelCatalogModelWire {
  ModelCatalogModelWire.fromJson(JsonMap json)
    : id = _reqString(json, 'id'),
      name = _reqString(json, 'name'),
      description = wireString(json, 'description'),
      reasoning = _nullable(json['reasoning'], ModelReasoningWire.fromJson);

  final String id;
  final String name;
  final String? description;
  final ModelReasoningWire? reasoning;
}

final class ModelProviderGroupWire {
  ModelProviderGroupWire.fromJson(JsonMap json)
    : id = _reqString(json, 'id'),
      name = _reqString(json, 'name'),
      models = (asJsonArray(json['models']) ?? const <Object?>[])
          .map(asJsonObject)
          .whereType<JsonMap>()
          .map(ModelCatalogModelWire.fromJson)
          .toList();

  final String id;
  final String name;
  final List<ModelCatalogModelWire> models;
}

final class ModelCatalogFailureWire {
  ModelCatalogFailureWire.fromJson(JsonMap json)
    : id = _reqString(json, 'id'),
      name = _reqString(json, 'name'),
      message = _reqString(json, 'message');

  final String id;
  final String name;
  final String message;
}

final class SessionModelsValueWire {
  SessionModelsValueWire.fromJson(JsonMap json)
    : current = ModelSelectionWire.fromJson(
        asJsonObject(json['default']) ??
            asJsonObject(json['current']) ??
            asJsonObject(json['defaultSelection']) ??
            const <String, Object?>{'provider': '', 'model': ''},
      ),
      routable = json.containsKey('routable')
          ? wireBool(json, 'routable')
          : (asJsonArray(json['routableProviders']) ?? const <Object?>[])
                .contains(
                  asJsonObject(json['default'])?['provider'] ??
                      asJsonObject(json['current'])?['provider'],
                ),
      groups =
          (asJsonArray(json['groups'] ?? json['entries']) ?? const <Object?>[])
              .map(asJsonObject)
              .whereType<JsonMap>()
              .map((entry) => asJsonObject(entry['group']) ?? entry)
              .where((m) => m.containsKey('id') && m.containsKey('models'))
              .map(ModelProviderGroupWire.fromJson)
              .toList(),
      failures =
          (asJsonArray(json['failures'] ?? json['entries']) ??
                  const <Object?>[])
              .map(asJsonObject)
              .whereType<JsonMap>()
              .where(
                (m) =>
                    wireString(m, 'kind') == 'failure' ||
                    m.containsKey('error'),
              )
              .map((m) => asJsonObject(m['failure']) ?? m)
              .map(ModelCatalogFailureWire.fromJson)
              .toList();

  final ModelSelectionWire current;
  final bool routable;
  final List<ModelProviderGroupWire> groups;
  final List<ModelCatalogFailureWire> failures;
}

// ---------------------------------------------------------------------------
// Subagents
// ---------------------------------------------------------------------------

final class SubagentEntryWire {
  SubagentEntryWire.fromJson(JsonMap json)
    : kind = wireString(json, 'kind') ?? 'child',
      id = _reqString(json, 'id'),
      mode = wireString(json, 'mode'),
      activity = wireString(json, 'activity'),
      hasChildren = wireBool(json, 'hasChildren'),
      label = wireString(json, 'label'),
      reason = wireString(json, 'reason');

  final String kind;
  final String id;
  final String? mode;
  final String? activity;
  final bool hasChildren;
  final String? label;
  final String? reason;
}

final class SubagentListValueWire {
  SubagentListValueWire.fromJson(JsonMap json)
    : entries = (asJsonArray(json['entries']) ?? const <Object?>[])
          .map(asJsonObject)
          .whereType<JsonMap>()
          .map(SubagentEntryWire.fromJson)
          .toList(),
      parentAvailable = wireBool(json, 'parentAvailable');

  final List<SubagentEntryWire> entries;
  final bool parentAvailable;
}

// ---------------------------------------------------------------------------
// Goals
// ---------------------------------------------------------------------------

final class GoalRefWire {
  GoalRefWire.fromJson(JsonMap json)
    : id = _reqString(json, 'id'),
      revision = _reqLong(json, 'revision');

  final String id;
  final int revision;
}

final class GoalSnapshotWire {
  GoalSnapshotWire.fromJson(JsonMap json)
    : id = _reqString(json, 'id'),
      revision = _reqLong(json, 'revision'),
      objective = _reqString(json, 'objective'),
      phase = _reqString(json, 'phase'),
      blockedReasonMessage = wireString(
        asJsonObject(json['blockedReason']) ?? const <String, Object?>{},
        'message',
      ),
      maxGoalRounds = _reqLong(json, 'maxGoalRounds');

  final String id;
  final int revision;
  final String objective;
  final String phase;

  /// The `blockedReason.code` field stays unread; the domain only carries
  /// the message.
  final String? blockedReasonMessage;
  final int maxGoalRounds;
}

final class GoalProjectionWire {
  GoalProjectionWire.fromJson(JsonMap json)
    : goal = GoalSnapshotWire.fromJson(_reqObject(json, 'goal')),
      roundsStarted = wireLong(json, 'roundsStarted'),
      createdAt = wireLong(json, 'createdAt'),
      updatedAt = wireLong(json, 'updatedAt');

  final GoalSnapshotWire goal;
  final int roundsStarted;
  final int createdAt;
  final int updatedAt;
}

GoalRefWire decodeGoalRefValue(JsonMap value) {
  final refObj = asJsonObject(value['ref']) ?? value;
  return GoalRefWire.fromJson(refObj);
}

// ---------------------------------------------------------------------------
// History
// ---------------------------------------------------------------------------

final class SessionHistoryValueWire {
  SessionHistoryValueWire.fromJson(JsonMap json)
    : events =
          (asJsonArray(json['events'] ?? json['records']) ?? const <Object?>[])
              .expand(_expandRecord)
              .toList(),
      hasMore = wireBool(json, 'hasMore'),
      projections = asJsonObject(json['projections']);

  final List<JsonMap> events;
  final bool hasMore;
  final JsonMap? projections;

  int get asOfSeq =>
      projections == null ? -1 : wireLong(projections!, 'asOfSeq');

  JsonMap? get projectionValues =>
      projections == null ? null : asJsonObject(projections!['values']);

  static Iterable<JsonMap> _expandRecord(Object? record) {
    if (record is! Map) return const <JsonMap>[];
    final map = record.cast<String, Object?>();
    final type = map['type'] as String?;
    if (type == 'chunks') {
      final event = asJsonObject(map['event']);
      if (event != null) {
        final eventType = wireString(event, 'type');
        final seq0 = wireLong(event, 'seq');
        final time0 = wireLong(event, 'time');
        final data = asJsonObject(event['data']);
        if (data != null) {
          final turn = wireLong(data, 'turn');
          final step = wireLong(data, 'step');
          final index = wireLong(data, 'index');
          if (eventType == 'chunkrow/text-chunks' ||
              eventType == 'chunkrow/reasoning-chunks') {
            final texts = (asJsonArray(data['texts']) ?? const <Object?>[])
                .whereType<String>()
                .toList();
            final isReasoning = eventType == 'chunkrow/reasoning-chunks';
            final deltaType = isReasoning ? 'reasoning-delta' : 'text-delta';
            return <JsonMap>[
              for (var k = 0; k < texts.length; k++)
                <String, Object?>{
                  'type': 'assistant/chunk',
                  'seq': seq0 + k,
                  'time': time0,
                  'data': <String, Object?>{
                    'turn': turn,
                    'step': step,
                    'chunk': <String, Object?>{
                      'type': deltaType,
                      'index': index,
                      'text': texts[k],
                    },
                  },
                },
            ];
          } else if (eventType == 'chunkrow/tool-call-chunks') {
            final args = (asJsonArray(data['args']) ?? const <Object?>[])
                .whereType<String>()
                .toList();
            final id = wireString(data, 'id') ?? '';
            final name = wireString(data, 'name');
            return <JsonMap>[
              for (var k = 0; k < args.length; k++)
                <String, Object?>{
                  'type': 'assistant/chunk',
                  'seq': seq0 + k,
                  'time': time0,
                  'data': <String, Object?>{
                    'turn': turn,
                    'step': step,
                    'chunk': <String, Object?>{
                      'type': 'tool-call-delta',
                      'index': index,
                      'id': id,
                      if (name != null) 'name': name,
                      'argumentsDelta': args[k],
                    },
                  },
                },
            ];
          }
        }
      }
    }
    final event = asJsonObject(map['event']);
    if (event != null) return <JsonMap>[event];
    if (map.containsKey('seq') && map.containsKey('type')) {
      return <JsonMap>[map];
    }
    return const <JsonMap>[];
  }
}

// ---------------------------------------------------------------------------
// Directory browser
// ---------------------------------------------------------------------------

final class DirectoryEntryWire {
  DirectoryEntryWire.fromJson(JsonMap json)
    : name = _reqString(json, 'name'),
      path = _reqString(json, 'path'),
      hidden = _reqBool(json, 'hidden');

  final String name;
  final String path;
  final bool hidden;
}

final class DirectoryListingValueWire {
  DirectoryListingValueWire.fromJson(JsonMap json)
    : path = _reqString(json, 'path'),
      home = _reqString(json, 'home'),
      crumbs = _entries(json['crumbs']),
      entries = _entries(json['entries']),
      truncated = _reqBool(json, 'truncated');

  final String path;
  final String home;
  final List<DirectoryEntryWire> crumbs;
  final List<DirectoryEntryWire> entries;
  final bool truncated;

  static List<DirectoryEntryWire> _entries(Object? json) =>
      (asJsonArray(json) ?? const <Object?>[])
          .map(asJsonObject)
          .whereType<JsonMap>()
          .map(DirectoryEntryWire.fromJson)
          .toList();
}

// ---------------------------------------------------------------------------
// Settings / credentials
// ---------------------------------------------------------------------------

final class SettingsNamespaceWire {
  SettingsNamespaceWire.fromJson(JsonMap json)
    : ns = _reqString(json, 'ns'),
      value = json['value'],
      user = json['user'],
      applies = wireString(json, 'applies') ?? 'live',
      secrets = (asJsonArray(json['secrets']) ?? const <Object?>[])
          .map(asJsonObject)
          .whereType<JsonMap>()
          .toList(),
      revision = wireLong(json, 'revision');

  final String ns;
  final Object? value;

  /// Raw `user` layer element; `hasUserLayer` checks object non-emptiness.
  final Object? user;
  final String applies;
  final List<JsonMap> secrets;
  final int revision;

  bool get hasUserLayer => user is Map && (user as Map).isNotEmpty;

  int get secretCount =>
      secrets.where((secret) => wireBool(secret, 'set')).length;

  /// Credential references the resolved namespace value names, mirroring
  /// the web models page: every profile records its reference as
  /// `apiKeyEnv`.
  List<String> get credentialRefs {
    final refs = <String>[];
    void walk(Object? element) {
      if (element is Map) {
        element.forEach((key, child) {
          if (key == 'apiKeyEnv' && child is String && child.isNotEmpty) {
            refs.add(child);
          } else {
            walk(child);
          }
        });
      } else if (element is List) {
        for (final child in element) {
          walk(child);
        }
      }
    }

    walk(value);
    return refs;
  }
}

final class SettingsDescribeValueWire {
  SettingsDescribeValueWire.fromJson(JsonMap json)
    : writable = _reqBool(json, 'writable'),
      hasDocument = wireBool(json, 'hasDocument'),
      namespaces = (asJsonArray(json['namespaces']) ?? const <Object?>[])
          .map(asJsonObject)
          .whereType<JsonMap>()
          .map(SettingsNamespaceWire.fromJson)
          .toList();

  final bool writable;
  final bool hasDocument;
  final List<SettingsNamespaceWire> namespaces;
}

CredentialStatus decodeCredentialView(String ref, JsonMap view) =>
    CredentialStatus(
      ref: ref,
      configured: _reqBool(view, 'configured'),
      source: wireString(view, 'source'),
      writable: wireBool(view, 'writable'),
    );

List<CredentialStatus> decodeCredentialsDescribeValue(JsonMap value) {
  final credentials = asJsonObject(value['credentials']) ?? value;
  final statuses = credentials.entries
      .map(
        (entry) => decodeCredentialView(
          entry.key,
          asJsonObject(entry.value) ?? const <String, Object?>{},
        ),
      )
      .toList();
  statuses.sort((a, b) => a.ref.compareTo(b.ref));
  return statuses;
}

SettingsApplies decodeApplies(String applies) => switch (applies) {
  'live' => SettingsApplies.live,
  'restart' => SettingsApplies.restart,
  _ => SettingsApplies.unknown,
};

// ---------------------------------------------------------------------------
// Attachments / skills / plan
// ---------------------------------------------------------------------------

final class AttachmentRefWire {
  AttachmentRefWire.fromJson(JsonMap json)
    : attachmentId = _reqString(json, 'attachmentId'),
      mediaType = _reqString(json, 'mediaType'),
      bytes = wireLong(json, 'bytes'),
      width = wireLong(json, 'width'),
      height = wireLong(json, 'height'),
      name = wireString(json, 'name');

  final String attachmentId;
  final String mediaType;
  final int bytes;
  final int width;
  final int height;
  final String? name;
}

final class SessionAttachmentValueWire {
  SessionAttachmentValueWire.fromJson(JsonMap json)
    : attachment = AttachmentRefWire.fromJson(_reqObject(json, 'attachment')),
      data = _reqString(json, 'data');

  final AttachmentRefWire attachment;

  /// Base64-encoded image bytes.
  final String data;
}

ImageLimits decodeImageLimitsWire(JsonMap json) {
  final mediaTypes = _stringList(json['mediaTypes']);
  return ImageLimits(
    maxImageBytes: _reqLong(json, 'maxImageBytes'),
    maxImagesPerMessage: _reqLong(json, 'maxImagesPerMessage'),
    maxMessageImageBytes: _reqLong(json, 'maxMessageImageBytes'),
    maxImagePixels: _reqLong(json, 'maxImagePixels'),
    maxImageDimension:
        wireLongOrNull(json, 'maxImageDimension') ??
        ImageLimits.defaultMaxImageDimension,
    mediaTypes: mediaTypes.isEmpty ? ImageLimits.defaultMediaTypes : mediaTypes,
  );
}

/// `plan` session projection: the logged plan-mode collaboration state.
typedef PlanProjectionWire = ({bool active, bool pending});

PlanProjectionWire? decodePlanProjection(Object? value) {
  final json = asJsonObject(value);
  if (json == null) return null;
  return (active: _reqBool(json, 'active'), pending: _reqBool(json, 'pending'));
}

/// `contextPressure` session projection: provider-reported prompt pressure,
/// route capacity, and projected tokens (reference token-meter
/// usage-projection.ts).
ContextPressure decodeContextPressureProjection(Object? value) {
  final json = asJsonObject(value);
  if (json == null) {
    throw const FormatException('contextPressure: not an object');
  }
  return ContextPressure(
    pressureTokens: wireLongOrNull(json, 'pressureTokens'),
    projectedTokens: wireLongOrNull(json, 'projectedTokens'),
    contextWindow: wireLongOrNull(json, 'contextWindow'),
  );
}

/// `contextBreakdown` session projection: system, tools, and message tokens
/// (reference token-meter breakdown-projection.ts).
ContextBreakdown decodeContextBreakdownProjection(Object? value) {
  final json = asJsonObject(value);
  if (json == null) {
    throw const FormatException('contextBreakdown: not an object');
  }
  return ContextBreakdown(
    systemTokens: wireLong(json, 'systemTokens'),
    toolsTokens: wireLong(json, 'toolsTokens'),
    messageTokens: wireLong(json, 'messageTokens'),
  );
}

final class SkillEntryWire {
  SkillEntryWire.fromJson(JsonMap json)
    : name = _reqString(json, 'name'),
      description = _reqString(json, 'description'),
      whenToUse = wireString(json, 'whenToUse'),
      modelInvocable = wireBool(json, 'modelInvocable');

  final String name;
  final String description;
  final String? whenToUse;
  final bool modelInvocable;
}

List<SkillEntryWire> decodeSkillListValue(JsonMap value) =>
    (asJsonArray(value['skills']) ?? const <Object?>[])
        .map(asJsonObject)
        .whereType<JsonMap>()
        .map(SkillEntryWire.fromJson)
        .toList();

// ---------------------------------------------------------------------------
// Agent presets (agentPreset.list / agentPreset.select —
// reference/deepseek-harness/packages/preset/agent-presets/src/types.ts)
// ---------------------------------------------------------------------------

final class AgentPresetEntryWire {
  AgentPresetEntryWire.fromJson(JsonMap json)
    : id = _reqString(json, 'id'),
      trust = _reqString(json, 'trust'),
      isDefault = _reqBool(json, 'isDefault'),
      name = wireString(json, 'name'),
      description = wireString(json, 'description'),
      broken = wireString(json, 'broken');

  final String id;

  /// `'system'` or `'user'`; the repository maps it to the domain enum
  /// and fails loud on any other value.
  final String trust;
  final bool isDefault;
  final String? name;
  final String? description;
  final String? broken;
}

final class AgentPresetListValueWire {
  AgentPresetListValueWire.fromJson(JsonMap json)
    : presets = (asJsonArray(json['presets']) ?? const <Object?>[])
          .map(asJsonObject)
          .whereType<JsonMap>()
          .map(AgentPresetEntryWire.fromJson)
          .toList(),
      authorable = _reqBool(json, 'authorable'),
      hasDocument = wireBool(json, 'hasDocument');

  final List<AgentPresetEntryWire> presets;
  final bool authorable;
  final bool hasDocument;
}

// ---------------------------------------------------------------------------
// Permission select (the `permissions` session projection value —
// reference/deepseek-harness/packages/interaction/permission-presets/
// src/types.ts)
// ---------------------------------------------------------------------------

final class PermissionPresetOptionWire {
  PermissionPresetOptionWire.fromJson(JsonMap json)
    : value = _reqString(json, 'value'),
      name = _reqString(json, 'name'),
      description = wireString(json, 'description');

  final String value;
  final String name;
  final String? description;
}

final class PermissionSelectWire {
  PermissionSelectWire.fromJson(JsonMap json)
    : options = (asJsonArray(json['options']) ?? const <Object?>[])
          .map(asJsonObject)
          .whereType<JsonMap>()
          .map(PermissionPresetOptionWire.fromJson)
          .toList(),
      currentValue = _reqString(json, 'currentValue');

  final List<PermissionPresetOptionWire> options;
  final String currentValue;
}

// ---------------------------------------------------------------------------
// Command execution (commands/execute value)
// ---------------------------------------------------------------------------

/// The settled host-command execution: reference
/// packages/interaction/commands/src/index.ts `CommandExecution` and
/// types.ts `CommandResult` (kind is required; text is optional on
/// success, required on error).
final class CommandExecutionWire {
  CommandExecutionWire.fromJson(JsonMap json)
    : commandId = _reqString(json, 'commandId'),
      result = CommandResultWire.fromJson(_reqObject(json, 'result'));

  final String commandId;
  final CommandResultWire result;
}

final class CommandResultWire {
  CommandResultWire.fromJson(JsonMap json)
    : kind = _reqString(json, 'kind'),
      text = wireString(json, 'text');

  final String kind;
  final String? text;
}

// ---------------------------------------------------------------------------
// Command registry roster (commands/list value — a bare JSON array; the
// envelope parks a non-object result under `value`, so the shape mirrors the
// `llm/*` listings). Reference:
// packages/interaction/commands/src/types.ts `CommandDescriptor`.
// ---------------------------------------------------------------------------

final class CommandDescriptorWire {
  CommandDescriptorWire.fromJson(JsonMap json)
    : name = _reqString(json, 'name'),
      description = _reqString(json, 'description'),
      input = _nullable(json['input'], CommandInputDescriptorWire.fromJson);

  final String name;
  final String description;
  final CommandInputDescriptorWire? input;
}

/// `CommandInputDescriptor`: the `hint` is required when `input` is present;
/// `attachments` is optional and defaults to false.
final class CommandInputDescriptorWire {
  CommandInputDescriptorWire.fromJson(JsonMap json)
    : hint = _reqString(json, 'hint'),
      attachments = json.containsKey('attachments')
          ? wireBool(json, 'attachments')
          : false;

  final String hint;
  final bool attachments;
}

/// Decodes the `commands/list` result: the addressed agent's effective
/// command descriptors, name-sorted by the host. The result is a bare array,
/// so it rides the envelope's `value` slot.
List<CommandDescriptor> decodeCommandDescriptorList(JsonMap value) {
  final raw = value['value'];
  if (raw is! List) {
    throw FormatException(
      '${DshRpcEndpoints.commandsList} "value" must be a JSON array, '
      'got: ${value.keys.toList()}',
    );
  }
  return raw.map((Object? entry) {
    final obj = asJsonObject(entry);
    if (obj == null) {
      throw const FormatException(
        '${DshRpcEndpoints.commandsList} entry is not an object',
      );
    }
    final wire = CommandDescriptorWire.fromJson(obj);
    return CommandDescriptor(
      name: wire.name,
      description: wire.description,
      inputHint: wire.input?.hint,
      acceptsAttachments: wire.input?.attachments ?? false,
    );
  }).toList();
}

// ---------------------------------------------------------------------------
// Plugin inventory (pluginInventory/list value). Reference:
// packages/host/plugin-inventory/src/types.ts.
// ---------------------------------------------------------------------------

PluginFiberPhase? _pluginFiberPhase(Object? value) {
  if (value == null) return null;
  return switch (value) {
    'pending' => PluginFiberPhase.pending,
    'loading' => PluginFiberPhase.loading,
    'active' => PluginFiberPhase.active,
    'failed' => PluginFiberPhase.failed,
    'unloading' => PluginFiberPhase.unloading,
    final other => throw FormatException(
      'plugin inventory "fiberPhase" has unknown value "$other"',
    ),
  };
}

PresetRowEnablement _presetRowEnablement(Object? value) {
  if (value is bool) {
    return value ? PresetRowEnablement.enabled : PresetRowEnablement.disabled;
  }
  if (value == 'conditional') return PresetRowEnablement.conditional;
  throw FormatException(
    'plugin inventory preset row "enabled" must be a boolean or '
    '"conditional", got: $value',
  );
}

PluginInventoryEntry _pluginEntryFromJson(JsonMap json) => PluginInventoryEntry(
  entryId: _reqString(json, 'entryId'),
  moduleName: _reqString(json, 'moduleName'),
  enabled: _reqBool(json, 'enabled'),
  fiberPhase: _pluginFiberPhase(json['fiberPhase']),
);

AgentPresetPluginRow _presetRowFromJson(JsonMap json) => AgentPresetPluginRow(
  entryId: wireString(json, 'entryId'),
  moduleName: _reqString(json, 'moduleName'),
  enabled: _presetRowEnablement(json['enabled']),
  condition: wireString(json, 'condition'),
  fiberPhase: _pluginFiberPhase(json['fiberPhase']),
);

AgentPresetPluginGroup _presetGroupFromJson(JsonMap json) =>
    AgentPresetPluginGroup(
      id: _reqString(json, 'id'),
      trust: _reqString(json, 'trust'),
      name: wireString(json, 'name'),
      isDefault: _reqBool(json, 'isDefault'),
      broken: wireString(json, 'broken'),
      rows: wireRequiredObjectArray(
        json,
        'rows',
      ).map(_presetRowFromJson).toList(),
    );

/// Decodes the `pluginInventory/list` result. `entries` is required;
/// `agentPresets` is present only when a roster is composed.
PluginInventorySnapshot decodePluginInventorySnapshot(JsonMap value) =>
    PluginInventorySnapshot(
      entries: wireRequiredObjectArray(
        value,
        'entries',
      ).map(_pluginEntryFromJson).toList(),
      agentPresets: value.containsKey('agentPresets')
          ? wireRequiredObjectArray(
              value,
              'agentPresets',
            ).map(_presetGroupFromJson).toList()
          : const <AgentPresetPluginGroup>[],
    );

/// One `dynamicCordisRunner/resolveRequestRun` acknowledgment
/// (`DynamicCordisResolveAck`): false for a late, unknown, or stale answer.
final class CordisResolveAckWire {
  CordisResolveAckWire.fromJson(JsonMap json)
    : accepted = _reqBool(json, 'accepted');

  final bool accepted;
}

// ---------------------------------------------------------------------------
// Workspace Files (DSH 0.1.5 workspaceFiles service)
// ---------------------------------------------------------------------------

final class WorkspaceFileStatWire {
  WorkspaceFileStatWire.fromJson(JsonMap json)
    : absolutePath = _reqString(json, 'absolutePath'),
      version = _reqString(json, 'version'),
      bytes = wireLongOrNull(json, 'bytes');

  final String absolutePath;
  final String version;
  final int? bytes;
}

final class WorkspaceFileTextWire {
  WorkspaceFileTextWire.fromJson(JsonMap json)
    : absolutePath = _reqString(json, 'absolutePath'),
      version = _reqString(json, 'version'),
      bytes = wireLongOrNull(json, 'bytes'),
      offset = _reqLong(json, 'offset'),
      text = _reqString(json, 'text'),
      lines = _reqLong(json, 'lines'),
      eof = _reqBool(json, 'eof');

  final String absolutePath;
  final String version;
  final int? bytes;
  final int offset;
  final String text;
  final int lines;
  final bool eof;
}

final class WorkspaceDirectoryEntryWire {
  WorkspaceDirectoryEntryWire.fromJson(JsonMap json)
    : name = _reqString(json, 'name'),
      type = _reqString(json, 'type'),
      size = wireLongOrNull(json, 'size');

  final String name;
  final String type;
  final int? size;
}

final class WorkspaceDirectoryListingWire {
  WorkspaceDirectoryListingWire.fromJson(JsonMap json)
    : path = _reqString(json, 'path'),
      entries = (asJsonArray(json['entries']) ?? const <Object?>[])
          .map(asJsonObject)
          .whereType<JsonMap>()
          .map(WorkspaceDirectoryEntryWire.fromJson)
          .toList(),
      truncated = _reqBool(json, 'truncated');

  final String path;
  final List<WorkspaceDirectoryEntryWire> entries;
  final bool truncated;
}

// ---------------------------------------------------------------------------
// Assistant token usage and recorded stream timing
// (reference packages/llm/llm/src/types.ts `TokenUsage` and
// packages/llm/llm/src/assistant-stream.ts `AssistantStreamRecord`)
// ---------------------------------------------------------------------------

/// Decode the `assistant/message` event's optional `usage`.
///
/// [value] is the raw event member: absent or null yields null (the adapter
/// reported no accounting), anything that is not an object fails loud.
/// `inputTokens` and `outputTokens` are non-optional on the reference
/// record, so their absence is host breakage, not a zero.
TokenUsage? decodeTokenUsage(Object? value) {
  if (value == null) return null;
  final json = asJsonObject(value);
  if (json == null) {
    throw const FormatException('assistant/message "usage" is not an object');
  }
  return TokenUsage(
    inputTokens: _reqLong(json, 'inputTokens'),
    outputTokens: _reqLong(json, 'outputTokens'),
    totalTokens: wireLongOrNull(json, 'totalTokens'),
    cacheReadTokens: wireLongOrNull(json, 'cacheReadTokens'),
    cacheWriteTokens: wireLongOrNull(json, 'cacheWriteTokens'),
    reasoningTokens: wireLongOrNull(json, 'reasoningTokens'),
  );
}

/// Epoch millisecond of the first model output token in one recorded
/// assistant stream, or null when the stream carries none.
///
/// The durable `assistant/message` stream is a list of packed delta runs
/// (`{type: '*-chunks', time0, dt, texts|args}`) and raw records
/// (`{type: 'chunk', time, chunk}`). A packed run's member `i` sits at
/// `time0 + sum(dt[0..i-1])`; a token delta is a non-empty text/reasoning
/// fragment or a tool-call fragment carrying arguments or a name
/// (`assistantStreamFirstTokenTime` walks the same order). Malformed runs
/// are skipped rather than throwing: the first-token figure is an optional
/// inspector fact, and a bad run must not fail the whole session replay.
int? assistantStreamFirstTokenTime(Object? stream) {
  final records = asJsonArray(stream);
  if (records == null) return null;
  for (final entry in records) {
    final record = asJsonObject(entry);
    if (record == null) continue;
    switch (wireType(record)) {
      case 'text-chunks':
      case 'reasoning-chunks':
        final time = _firstRunMemberTime(record, 'texts', _nonEmpty);
        if (time != null) return time;
      case 'tool-call-chunks':
        // A name-bearing run starts at its first member; otherwise the run's
        // first member qualifies when it carries an arguments fragment.
        final time = wireString(record, 'name') != null
            ? wireLongOrNull(record, 'time0')
            : _firstRunMemberTime(record, 'args', _nonEmpty);
        if (time != null) return time;
      case 'chunk':
        final chunk = asJsonObject(record['chunk']);
        if (chunk == null) continue;
        final isToken = switch (wireType(chunk)) {
          'text-delta' ||
          'reasoning-delta' => (wireString(chunk, 'text') ?? '') != '',
          'tool-call-delta' =>
            (wireString(chunk, 'argumentsDelta') ?? '') != '' ||
                chunk.containsKey('name'),
          _ => false,
        };
        if (isToken) return wireLongOrNull(record, 'time');
    }
  }
  return null;
}

/// Reconstructed timestamp of the first member of one packed delta run that
/// satisfies [accept], accumulating the run's inter-member gaps.
///
/// The run is validated as a whole before any member time is read, matching
/// the reference's `validateRecord` + `firstRunMemberTime` order: a run whose
/// `texts`/`args` or `dt` members are malformed is unusable, and reading a
/// prefix of it would report a boundary the log does not support. Null means
/// "this run carries no usable boundary", never "the first member is at
/// time0".
int? _firstRunMemberTime(
  JsonMap record,
  String membersKey,
  bool Function(String) accept,
) {
  final rawMembers = asJsonArray(record[membersKey]);
  if (rawMembers == null) return null;
  final members = <String>[];
  for (final member in rawMembers) {
    if (member is! String) return null;
    members.add(member);
  }
  final gapCount = members.isEmpty ? 0 : members.length - 1;
  final rawGaps = asJsonArray(record['dt']);
  if (rawGaps == null || rawGaps.length < gapCount) return null;
  final gaps = <int>[];
  for (var index = 0; index < gapCount; index++) {
    final gap = _asInt(rawGaps[index]);
    if (gap == null) return null;
    gaps.add(gap);
  }
  final start = wireLongOrNull(record, 'time0');
  if (start == null) return null;
  var time = start;
  for (var index = 0; index < members.length; index++) {
    if (index > 0) time += gaps[index - 1];
    if (accept(members[index])) return time;
  }
  return null;
}

bool _nonEmpty(String value) => value != '';

int? _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) {
    final truncated = value.truncateToDouble();
    return value == truncated ? truncated.toInt() : null;
  }
  return null;
}

// ---------------------------------------------------------------------------
// Shared helpers
// ---------------------------------------------------------------------------

List<String> _stringList(Object? json) =>
    (asJsonArray(json) ?? const <Object?>[])
        .map((entry) => entry is String ? entry : null)
        .whereType<String>()
        .toList();

T? _nullable<T>(Object? json, T Function(JsonMap) decode) {
  final obj = asJsonObject(json);
  return obj == null ? null : decode(obj);
}
