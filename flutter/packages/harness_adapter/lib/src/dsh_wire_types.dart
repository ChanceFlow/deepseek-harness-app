/// Wire DTO decoders mirroring `DshWireTypes.kt`. Every decoder tolerates
/// unknown keys; fields that carried no Kotlin default are REQUIRED — a
/// missing or mistyped required field throws [FormatException], matching
/// kotlinx-serialization's decode failures (the repository converts those
/// into nulls with `runCatching` exactly like the Kotlin code).
library;

import 'package:domain/model/attachment.dart';
import 'package:domain/model/settings.dart';

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
      agentPreset = wireString(json, 'agentPreset'),
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
    : current = ModelSelectionWire.fromJson(_reqObject(json, 'current')),
      routable = wireBool(json, 'routable'),
      groups = (asJsonArray(json['groups']) ?? const <Object?>[])
          .map(asJsonObject)
          .whereType<JsonMap>()
          .map(ModelProviderGroupWire.fromJson)
          .toList(),
      failures = (asJsonArray(json['failures']) ?? const <Object?>[])
          .map(asJsonObject)
          .whereType<JsonMap>()
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

GoalRefWire decodeGoalRefValue(JsonMap value) =>
    GoalRefWire.fromJson(_reqObject(value, 'ref'));

// ---------------------------------------------------------------------------
// History
// ---------------------------------------------------------------------------

final class SessionHistoryValueWire {
  SessionHistoryValueWire.fromJson(JsonMap json)
    : events = (asJsonArray(json['events']) ?? const <Object?>[])
          .map(_reqEvent)
          .toList(),
      hasMore = wireBool(json, 'hasMore'),
      projections = asJsonObject(json['projections']);

  final List<JsonMap> events;
  final bool hasMore;
  final JsonMap? projections;

  JsonMap? get projectionValues =>
      projections == null ? null : asJsonObject(projections!['values']);

  static JsonMap _reqEvent(Object? json) {
    final event = asJsonObject(asJsonObject(json)?['event']);
    if (event == null) {
      throw const FormatException('history entry missing "event" object');
    }
    return event;
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
  final credentials =
      asJsonObject(value['credentials']) ?? const <String, Object?>{};
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
