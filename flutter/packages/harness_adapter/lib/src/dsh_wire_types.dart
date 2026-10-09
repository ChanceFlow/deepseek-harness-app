/// Wire DTO decoders mirroring `DshWireTypes.kt`. Every decoder tolerates
/// unknown keys; fields that carried no Kotlin default are REQUIRED — a
/// missing or mistyped required field throws [FormatException], matching
/// kotlinx-serialization's decode failures (the repository converts those
/// into nulls with `runCatching` exactly like the Kotlin code).
library;

import 'dart:typed_data';

import 'package:domain/model/account.dart';
import 'package:domain/model/agent_team.dart';
import 'package:domain/model/attachment.dart';
import 'package:domain/model/command.dart';
import 'package:domain/model/context_pressure.dart';
import 'package:domain/model/file_reference.dart';
import 'package:domain/model/file_upload.dart';
import 'package:domain/model/jobs.dart';
import 'package:domain/model/message_feedback.dart';
import 'package:domain/model/open_in_app.dart';
import 'package:domain/model/plugin_inventory.dart';
import 'package:domain/model/plugin_management.dart';
import 'package:domain/model/schedule.dart';
import 'package:domain/model/session_reference.dart';
import 'package:domain/model/settings.dart';
import 'package:domain/model/terminal.dart';
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

/// Reads one byte view.
///
/// The transport splices the attachment's bytes over the codec's `null`
/// placeholder, so a present `data` is a [Uint8List] (or a JSON number array
/// from a fixture); a `null` placeholder, an absent key, or a non-byte element
/// is host breakage and fails loud naming [key].
Uint8List _reqBytes(JsonMap json, String key) {
  if (!json.containsKey(key)) _missing(json, key);
  final value = json[key];
  if (value is Uint8List) return value;
  if (value is List) {
    final bytes = Uint8List(value.length);
    for (var i = 0; i < value.length; i++) {
      final byte = value[i];
      if (byte is! int || byte < 0 || byte > 255) _missing(json, key);
      bytes[i] = byte;
    }
    return bytes;
  }
  _missing(json, key);
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
      agentAvailable = json.containsKey('agentAvailable')
          ? wireBool(json, 'agentAvailable')
          : null,
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

  /// Whether the Session currently owns a live Agent (0.1.7's
  /// `SessionSummary.agentAvailable`); null when the row does not state it,
  /// which a consumer must read as unknown rather than offline.
  final bool? agentAvailable;
  final String? parentSessionId;
  final String? origin;
  final String? cwd;
  final String? agentPreset;
  final JsonMap? projections;

  int get asOfSeq =>
      projections == null ? 0 : wireLong(projections!, 'asOfSeq');

  /// Which sequence space [asOfSeq] belongs to (`SessionProjectionHints.kind`,
  /// added in 0.1.7): `sequenced` blocks come from the Host's live registry for
  /// an attached Session and are comparable with its baselines and frames;
  /// `cached` blocks were viewed from the persisted checkpoint by a
  /// header-only listing and must not be compared with them at all. Null is a
  /// host that publishes no kind, which behaved as `sequenced`.
  String? get projectionKind =>
      projections == null ? null : wireString(projections!, 'kind');

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
      archivedSessionIds = _stringList(json['archivedSessionIds']),
      pinnedSessionIds = _stringList(json['pinnedSessionIds']);

  final List<WorkspaceWire> items;
  final List<String> archivedSessionIds;

  /// Registry-global pin set, most recently pinned first. Absent on a Host
  /// that predates `workspace/pinSession`, which reads as "nothing pinned".
  final List<String> pinnedSessionIds;
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
      routableProviders =
          (asJsonArray(json['routableProviders']) ?? const <Object?>[])
              .whereType<String>()
              .toList(),
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
  final List<String> routableProviders;
  final List<ModelProviderGroupWire> groups;
  final List<ModelCatalogFailureWire> failures;
}

// ---------------------------------------------------------------------------
// Subagents — the `subagentCatalog` session projection
// (reference/deepseek-harness/packages/subagent/subagent/src/catalog.ts
// `viewSchema`; row shape in `projection-types.ts` `SubagentCatalogEntry`).
//
// 0.1.7 deleted the `subagents/list` RPC, so the roster is the parent
// Session's projection value. That value is narrower than the deleted RPC's
// answer: it carries no `kind`, `reason` or `hasChildren`, and `mode` may be
// `'unknown'` for a child recorded by a newer catalog event version.
// ---------------------------------------------------------------------------

final class SubagentCatalogEntryWire {
  SubagentCatalogEntryWire.fromJson(JsonMap json)
    : id = _reqString(json, 'id'),
      createdAt = _reqLong(json, 'createdAt'),
      mode = _reqString(json, 'mode'),
      label = wireString(json, 'label');

  final String id;
  final int createdAt;

  /// `'one-shot'`, `'continuable'` or `'unknown'`.
  final String mode;
  final String? label;
}

/// Decodes one `subagentCatalog` projection value: an array of direct-child
/// rows. An absent value is an empty catalog; a malformed row throws.
List<SubagentCatalogEntryWire> decodeSubagentCatalogProjection(Object? value) =>
    (asJsonArray(value) ?? const <Object?>[])
        .map(asJsonObject)
        .whereType<JsonMap>()
        .map(SubagentCatalogEntryWire.fromJson)
        .toList();

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

/// Decodes the `schema` one settings namespace's descriptor carries
/// (`reference/deepseek-harness/packages/settings/settings/src/index.ts:326`
/// `schema: form.toJSON()`; the wire view forwards it verbatim at
/// `packages/api/settings-controller/src/index.ts:52`).
///
/// Schemastery serializes a schema as `{uid, refs}` rather than a nested tree:
/// `refs` maps a uid to that node's plain JSON, and a node's child positions
/// (`sKey`, `inner`, `list`, `dict`) hold uids into the same table, because one
/// schema may reference a node twice or reference an ancestor
/// (`reference/deepseek-harness/vendor/schemastery/src/index.ts` `toJSON` and
/// the `options.refs` branch of the `Schema` constructor). This decode keeps
/// the table and resolves nothing eagerly, so a recursive schema cannot loop.
///
/// Fails loud — naming the offending key — on an envelope that is not an
/// object, a missing or empty `refs` table, a refs key that is not a uid or a
/// node object, a node without a `type`, a child reference the table does not
/// carry, or a mistyped `meta` member. An empty form is never the result of a
/// decode failure.
SettingsSchema decodeSettingsSchema(Object? json) {
  final envelope = asJsonObject(json);
  if (envelope == null) {
    throw const FormatException('settings namespace "schema" is not an object');
  }
  final refs = asJsonObject(envelope['refs']);
  if (refs == null || refs.isEmpty) {
    throw const FormatException(
      'settings namespace "schema" carries no "refs" table',
    );
  }
  final raw = <int, JsonMap>{};
  refs.forEach((key, value) {
    final uid = int.tryParse(key);
    final node = asJsonObject(value);
    if (uid == null || node == null) {
      throw FormatException('settings schema ref "$key" is not a node object');
    }
    raw[uid] = node;
  });
  final nodes = <int, SettingsSchemaNode>{};
  raw.forEach((uid, node) {
    nodes[uid] = _settingsSchemaNode(uid, node, raw);
  });
  final rootUid = _reqLong(envelope, 'uid');
  final root = nodes[rootUid];
  if (root == null) {
    throw FormatException('settings schema root uid $rootUid names no ref');
  }
  return SettingsSchema(root: root, nodes: nodes);
}

SettingsSchemaNode _settingsSchemaNode(
  int uid,
  JsonMap json,
  Map<int, JsonMap> refs,
) {
  final meta = asJsonObject(json['meta']);
  return SettingsSchemaNode(
    uid: uid,
    type: _reqString(json, 'type'),
    meta: meta == null ? const SettingsSchemaMeta() : _settingsSchemaMeta(meta),
    value: json['value'],
    callback: wireString(json, 'callback'),
    bits: _settingsSchemaBits(json['bits']),
    sKeyUid: _settingsSchemaRef(json, 'sKey', refs),
    innerUid: _settingsSchemaRef(json, 'inner', refs),
    listUids: _settingsSchemaRefList(json['list'], refs),
    dictUids: _settingsSchemaRefMap(json['dict'], refs),
  );
}

int? _settingsSchemaRef(JsonMap json, String key, Map<int, JsonMap> refs) {
  if (json[key] == null) return null;
  final uid = _reqLong(json, key);
  if (!refs.containsKey(uid)) {
    throw FormatException('settings schema "$key" names missing ref $uid');
  }
  return uid;
}

List<int> _settingsSchemaRefList(Object? value, Map<int, JsonMap> refs) {
  if (value == null) return const <int>[];
  final list = asJsonArray(value);
  if (list == null) {
    throw const FormatException('settings schema "list" is not an array');
  }
  return list.map((entry) {
    if (entry is! int || !refs.containsKey(entry)) {
      throw FormatException('settings schema "list" names missing ref $entry');
    }
    return entry;
  }).toList();
}

Map<String, int> _settingsSchemaRefMap(Object? value, Map<int, JsonMap> refs) {
  if (value == null) return const <String, int>{};
  final map = asJsonObject(value);
  if (map == null) {
    throw const FormatException('settings schema "dict" is not an object');
  }
  final fields = <String, int>{};
  map.forEach((key, entry) {
    if (entry is! int || !refs.containsKey(entry)) {
      throw FormatException(
        'settings schema "dict" field "$key" names missing ref $entry',
      );
    }
    fields[key] = entry;
  });
  return fields;
}

Map<String, int> _settingsSchemaBits(Object? value) {
  if (value == null) return const <String, int>{};
  final map = asJsonObject(value);
  if (map == null) {
    throw const FormatException('settings schema "bits" is not an object');
  }
  final bits = <String, int>{};
  map.forEach((key, entry) {
    if (entry is! int) {
      throw FormatException('settings schema bit "$key" is not an integer');
    }
    bits[key] = entry;
  });
  return bits;
}

SettingsSchemaMeta _settingsSchemaMeta(JsonMap json) => SettingsSchemaMeta(
  defaultValue: json['default'],
  required: wireBool(json, 'required'),
  volatile: wireBool(json, 'volatile'),
  disabled: wireBool(json, 'disabled'),
  collapse: wireBool(json, 'collapse'),
  hidden: wireBool(json, 'hidden'),
  loose: wireBool(json, 'loose'),
  role: wireString(json, 'role'),
  extra: json['extra'],
  link: wireString(json, 'link'),
  description: _settingsSchemaDescription(json['description']),
  comment: wireString(json, 'comment'),
  pattern: _settingsSchemaPattern(json['pattern']),
  max: _settingsSchemaNumber(json, 'max'),
  min: _settingsSchemaNumber(json, 'min'),
  step: _settingsSchemaNumber(json, 'step'),
  badges: _settingsSchemaBadges(json['badges']),
);

num? _settingsSchemaNumber(JsonMap json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is num) return value;
  throw FormatException('settings schema "$key" is not a number');
}

/// Decodes `meta.description`, which schemastery stores either as one string
/// or as a locale map whose `''` entry is the unlocalized text
/// (`vendor/schemastery/src/index.ts:357` `mergeDesc`).
Map<String, String>? _settingsSchemaDescription(Object? value) {
  if (value == null) return null;
  if (value is String) return <String, String>{'': value};
  final map = asJsonObject(value);
  if (map == null) {
    throw const FormatException(
      'settings schema "description" is neither a string nor a locale map',
    );
  }
  final texts = <String, String>{};
  map.forEach((locale, text) {
    if (text is! String) {
      throw FormatException(
        'settings schema "description" locale "$locale" is not a string',
      );
    }
    texts[locale] = text;
  });
  return texts;
}

SettingsSchemaPattern? _settingsSchemaPattern(Object? value) {
  if (value == null) return null;
  final map = asJsonObject(value);
  if (map == null) {
    throw const FormatException('settings schema "pattern" is not an object');
  }
  return SettingsSchemaPattern(
    source: _reqString(map, 'source'),
    flags: wireString(map, 'flags'),
  );
}

List<SettingsSchemaBadge> _settingsSchemaBadges(Object? value) {
  if (value == null) return const <SettingsSchemaBadge>[];
  final list = asJsonArray(value);
  if (list == null) {
    throw const FormatException('settings schema "badges" is not an array');
  }
  return list.map((entry) {
    final map = asJsonObject(entry);
    if (map == null) {
      throw const FormatException(
        'settings schema "badges" entry is not an object',
      );
    }
    return SettingsSchemaBadge(
      text: _reqString(map, 'text'),
      type: _reqString(map, 'type'),
    );
  }).toList();
}

final class SettingsNamespaceWire {
  SettingsNamespaceWire.fromJson(JsonMap json)
    : ns = _reqString(json, 'ns'),
      // A host that withheld the field offers this client no generated page.
      autoGenerate = wireBool(json, 'autoGenerate'),
      schema = decodeSettingsSchema(json['schema']),
      value = json['value'],
      user = json['user'],
      applies = wireString(json, 'applies') ?? 'live',
      secrets = (asJsonArray(json['secrets']) ?? const <Object?>[])
          .map(asJsonObject)
          .whereType<JsonMap>()
          .toList(),
      revision = wireLong(json, 'revision');

  final String ns;

  /// Whether this client may render a generated page for the namespace when no
  /// custom page exists (`SettingsDescriptor.autoGenerate`).
  final bool autoGenerate;

  /// The namespace's decoded field projection ([decodeSettingsSchema]).
  final SettingsSchema schema;
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

/// `FileAttachmentRef` of a staged file upload (reference
/// packages/attachment/attachment/src/types.ts): verbatim bytes, so `name`
/// and `bytes` are required alongside the content-addressed id.
final class FileAttachmentRefWire {
  FileAttachmentRefWire.fromJson(JsonMap json)
    : attachmentId = _reqString(json, 'attachmentId'),
      name = _reqString(json, 'name'),
      bytes = _reqLong(json, 'bytes');

  final String attachmentId;

  /// Host-sanitized display filename.
  final String name;

  final int bytes;
}

/// `FileUploadValue` (`packages/client/file-upload/src/types.ts`): the staged
/// receipt a prompt cites plus the durable file reference behind it.
final class FileUploadValueWire {
  FileUploadValueWire.fromJson(JsonMap json)
    : receiptId = _reqString(json, 'receiptId'),
      file = FileAttachmentRefWire.fromJson(_reqObject(json, 'file'));

  final String receiptId;
  final FileAttachmentRefWire file;
}

/// Decodes the `fileUploads/upload` result into the staged domain receipt.
UploadedFile decodeFileUploadValue(JsonMap value) {
  final wire = FileUploadValueWire.fromJson(value);
  return UploadedFile(
    receiptId: wire.receiptId,
    attachmentId: wire.file.attachmentId,
    name: wire.file.name,
    byteSize: wire.file.bytes,
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
// Agent presets (agentPresets/list / agentPresets/select —
// reference/deepseek-harness/packages/preset/agent-preset-registry/src/types.ts).
// 0.1.7 removed the per-row `trust` and the roster-level `authorable`: preset
// authoring moved off the Remote surface (`copy`, `deletePreset`, and the
// directory-opening settings methods are all gone), so the roster is now a
// path-free, trust-free row list.
// ---------------------------------------------------------------------------

final class AgentPresetEntryWire {
  AgentPresetEntryWire.fromJson(JsonMap json)
    : id = _reqString(json, 'id'),
      isDefault = _reqBool(json, 'isDefault'),
      name = wireString(json, 'name'),
      description = wireString(json, 'description'),
      broken = wireString(json, 'broken');

  final String id;
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
          .toList();

  final List<AgentPresetEntryWire> presets;
}

// ---------------------------------------------------------------------------
// Permission select (the `permissions` session projection value —
// reference/deepseek-harness/packages/interaction/permission-presets/
// src/types.ts)
// ---------------------------------------------------------------------------

/// `agentPresets/read` value
/// (`packages/preset/agent-preset-registry/src/types.ts`
/// `AgentPresetDocument`): the preset identity, its declared composition as
/// entry-list YAML, and the published display copy.
final class AgentPresetDocumentWire {
  AgentPresetDocumentWire.fromJson(JsonMap json)
    : agentPreset = _reqString(json, 'agentPreset'),
      content = _reqString(json, 'content'),
      name = wireString(json, 'name'),
      description = wireString(json, 'description');

  final String agentPreset;
  final String content;
  final String? name;
  final String? description;
}

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

/// `permissionPresets/catalog` value
/// (`packages/interaction/permission-presets/src/types.ts`
/// `PermissionCatalog`): the whole composed table, the subset a new session
/// may default to, and the effective default key.
final class PermissionCatalogWire {
  PermissionCatalogWire.fromJson(JsonMap json)
    : options = _permissionOptions(json['options']),
      defaultOptions = _permissionOptions(json['defaultOptions']),
      defaultPreset = _reqString(json, 'defaultPreset');

  static List<PermissionPresetOptionWire> _permissionOptions(Object? json) =>
      (asJsonArray(json) ?? const <Object?>[])
          .map(asJsonObject)
          .whereType<JsonMap>()
          .map(PermissionPresetOptionWire.fromJson)
          .toList();

  final List<PermissionPresetOptionWire> options;
  final List<PermissionPresetOptionWire> defaultOptions;
  final String defaultPreset;
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
// File-reference discovery (fileReferences/list value — a bare JSON array;
// the envelope parks a non-object result under `value`, so the shape mirrors
// the `llm/*` listings and `commands/list`). Reference:
// reference/deepseek-harness/packages/context/file-reference/src/types.ts
// `FileReferenceCandidate` (both `path` and `kind` are required; there are no
// optional fields).
// ---------------------------------------------------------------------------

final class FileReferenceCandidateWire {
  FileReferenceCandidateWire.fromJson(JsonMap json)
    : path = _reqString(json, 'path'),
      kind = _fileReferenceKind(json, 'kind');

  final String path;
  final FileReferenceKind kind;
}

/// Reads the candidate discriminant; an absent or unknown `kind` fails loud
/// naming the field, so a new host variant cannot decode as a file.
FileReferenceKind _fileReferenceKind(JsonMap json, String key) {
  final value = wireString(json, key);
  return switch (value) {
    'file' => FileReferenceKind.file,
    'directory' => FileReferenceKind.directory,
    _ => throw FormatException(
      'required field "$key" missing or mistyped in ${json.keys.toList()}',
    ),
  };
}

/// Decodes the `fileReferences/list` result: the addressed agent's ranked
/// path candidates, in host order. The result is a bare array, so it rides
/// the envelope's `value` slot.
List<FileReferenceCandidate> decodeFileReferenceCandidateList(JsonMap value) {
  final raw = value['value'];
  if (raw is! List) {
    throw FormatException(
      '${DshRpcEndpoints.fileReferencesList} "value" must be a JSON array, '
      'got: ${value.keys.toList()}',
    );
  }
  return raw.map((Object? entry) {
    final obj = asJsonObject(entry);
    if (obj == null) {
      throw const FormatException(
        '${DshRpcEndpoints.fileReferencesList} entry is not an object',
      );
    }
    final wire = FileReferenceCandidateWire.fromJson(obj);
    return FileReferenceCandidate(path: wire.path, kind: wire.kind);
  }).toList();
}

// ---------------------------------------------------------------------------
// Cross-session `@` discovery (sessionReferenceResolver/candidates value — a
// bare JSON array, so it rides the envelope's `value` slot exactly like the
// file-reference list). Reference:
// reference/deepseek-harness/packages/context/session-reference/src/types.ts
// `SessionReferenceMentionCandidate`: `sessionId`, `label`, `sameWorkspace`,
// `createdAt` and `mention` are required; `displayTitle` and `cwd` are
// optional (`SessionReferenceCandidate` at types.ts:59-73 marks exactly those
// two optional).
// ---------------------------------------------------------------------------

final class SessionReferenceMentionCandidateWire {
  SessionReferenceMentionCandidateWire.fromJson(JsonMap json)
    : sessionId = _reqString(json, 'sessionId'),
      label = _reqString(json, 'label'),
      mention = _reqString(json, 'mention'),
      sameWorkspace = _reqBool(json, 'sameWorkspace'),
      createdAtEpochMs = _reqLong(json, 'createdAt'),
      displayTitle = wireString(json, 'displayTitle'),
      cwd = wireString(json, 'cwd');

  final String sessionId;
  final String label;
  final String mention;
  final bool sameWorkspace;
  final int createdAtEpochMs;
  final String? displayTitle;
  final String? cwd;
}

/// Decodes the `sessionReferenceResolver/candidates` result: the addressed
/// agent's ranked session mentions, in host order.
List<SessionReferenceCandidate> decodeSessionReferenceCandidateList(
  JsonMap value,
) {
  final raw = value['value'];
  if (raw is! List) {
    throw FormatException(
      '${DshRpcEndpoints.sessionReferenceResolverCandidates} "value" must be '
      'a JSON array, got: ${value.keys.toList()}',
    );
  }
  return raw.map((Object? entry) {
    final obj = asJsonObject(entry);
    if (obj == null) {
      throw const FormatException(
        '${DshRpcEndpoints.sessionReferenceResolverCandidates} entry is not '
        'an object',
      );
    }
    final wire = SessionReferenceMentionCandidateWire.fromJson(obj);
    return SessionReferenceCandidate(
      sessionId: wire.sessionId,
      label: wire.label,
      displayTitle: wire.displayTitle,
      cwd: wire.cwd,
      sameWorkspace: wire.sameWorkspace,
      createdAtEpochMs: wire.createdAtEpochMs,
      mention: wire.mention,
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

/// One `pluginInventory/list` preset composition
/// (`reference/deepseek-harness/packages/host/plugin-inventory/src/types.ts`
/// `AgentPresetPluginGroup`). 0.1.7 dropped the group-level `trust` and gained
/// an optional per-row `meta`; neither changes the fields the client shows.
AgentPresetPluginGroup _presetGroupFromJson(JsonMap json) =>
    AgentPresetPluginGroup(
      id: _reqString(json, 'id'),
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
      managementAvailable: value['managementAvailable'] == true,
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

final class WorkspaceFileBytesWire {
  WorkspaceFileBytesWire.fromJson(JsonMap json)
    : absolutePath = _reqString(json, 'absolutePath'),
      version = _reqString(json, 'version'),
      bytes = wireLongOrNull(json, 'bytes'),
      offset = _reqLong(json, 'offset'),
      data = _reqBytes(json, 'data'),
      eof = _reqBool(json, 'eof');

  final String absolutePath;
  final String version;
  final int? bytes;
  final int offset;
  final Uint8List data;
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

// ---------------------------------------------------------------------------
// Background jobs — the `JobView` roster row and the `job/follow` frame
// vocabulary. Reference:
// packages/api/job-controller/src/types.ts (`JobFollowFrame`, `JobListFrame`)
// and packages/jobs/jobs/src/view.ts (`JobView`, `JobChunk`).
// ---------------------------------------------------------------------------

JobStatus _jobStatus(Object? value) => switch (value) {
  'running' => JobStatus.running,
  'stopping' => JobStatus.stopping,
  'completed' => JobStatus.completed,
  'killed' => JobStatus.killed,
  'failed' => JobStatus.failed,
  final other => throw FormatException(
    'job "status" has unknown value "$other"',
  ),
};

JobChannel? _jobChannel(Object? value) {
  if (value == null) return null;
  return switch (value) {
    'stdout' => JobChannel.stdout,
    'stderr' => JobChannel.stderr,
    'log' => JobChannel.log,
    final other => throw FormatException(
      'job chunk "channel" has unknown value "$other"',
    ),
  };
}

/// One `JobView` row: the `job/list` roster member and the `job` field of both
/// `opened` and `status` follow frames.
///
/// `kind` stays an open string — the wire type is `string`, not the closed
/// producer union. `output` is the retained ring's bounds; a host that omits
/// it reports nothing retained.
JobView decodeJobView(JsonMap json) {
  final output = asJsonObject(json['output']);
  final spillPaths = output == null ? null : asJsonArray(output['spillPaths']);
  return JobView(
    id: _reqString(json, 'id'),
    kind: _reqString(json, 'kind'),
    label: _reqString(json, 'label'),
    owner: wireString(json, 'owner'),
    status: _jobStatus(json['status']),
    progress: wireString(json, 'progress'),
    detail: wireString(json, 'detail'),
    startedAt: _reqLong(json, 'startedAt'),
    finishedAt: wireLongOrNull(json, 'finishedAt'),
    output: output == null
        ? null
        : JobOutputWindow(
            total: _reqLong(output, 'total'),
            earliest: _reqLong(output, 'earliest'),
            spillPaths:
                spillPaths?.map((Object? path) {
                  if (path is! String) _missing(output, 'spillPaths');
                  return path;
                }).toList() ??
                const <String>[],
          ),
  );
}

JobOutputChunk _jobChunkFromJson(JsonMap json) => JobOutputChunk(
  at: _reqLong(json, 'at'),
  text: _reqString(json, 'text'),
  channel: _jobChannel(json['channel']),
  // `gapBefore` is only ever present as `true`; absence means no gap.
  gapBefore: json['gapBefore'] == true,
);

/// One `job/follow` frame (`JobFollowFrame`).
///
/// The discriminant is closed: an unknown `type` throws rather than being
/// skipped, so a host that adds a frame kind fails compilation-adjacent
/// decoding instead of silently truncating a job's output.
JobOutputFrame decodeJobFollowFrame(JsonMap frame) {
  final type = _reqString(frame, 'type');
  switch (type) {
    case 'opened':
      return JobOutputOpened(
        job: decodeJobView(wireRequiredObject(frame, 'job')),
        from: _reqLong(frame, 'from'),
      );
    case 'output':
      return JobOutputChunks(
        chunks: wireRequiredArray(frame, 'chunks').map((Object? chunk) {
          final object = asJsonObject(chunk);
          if (object == null) _missing(frame, 'chunks');
          return _jobChunkFromJson(object);
        }).toList(),
        next: _reqLong(frame, 'next'),
        lossy: frame['lossy'] == true,
      );
    case 'status':
      return JobOutputStatus(
        job: decodeJobView(wireRequiredObject(frame, 'job')),
      );
    default:
      throw FormatException('job/follow "type" has unknown value "$type"');
  }
}

// ---------------------------------------------------------------------------
// Agent teams — the Lead Session's `agentTeam` projection value. Reference:
// packages/experimental/agent-team/src/types.ts (`TeamProjection`,
// `TeamMemberProjection`, `TeamTaskView`).
// ---------------------------------------------------------------------------

TeamMemberPhase _teamMemberPhase(Object? value) => switch (value) {
  'provisioning' => TeamMemberPhase.provisioning,
  'active' => TeamMemberPhase.active,
  'failed' => TeamMemberPhase.failed,
  final other => throw FormatException(
    'agentTeam member "phase" has unknown value "$other"',
  ),
};

String _teamRole(Object? value) => switch (value) {
  'lead' => 'lead',
  'teammate' => 'teammate',
  final other => throw FormatException(
    'agentTeam member "role" has unknown value "$other"',
  ),
};

TeamTaskStatus _teamTaskStatus(Object? value) => switch (value) {
  'pending' => TeamTaskStatus.pending,
  'in_progress' => TeamTaskStatus.inProgress,
  'completed' => TeamTaskStatus.completed,
  'deleted' => TeamTaskStatus.deleted,
  final other => throw FormatException(
    'agentTeam task "status" has unknown value "$other"',
  ),
};

List<String> _teamStringList(JsonMap json, String key) {
  final raw = asJsonArray(json[key]);
  if (raw == null) return const <String>[];
  return raw.map((Object? entry) {
    if (entry is! String) _missing(json, key);
    return entry;
  }).toList();
}

/// One `TeamMemberProjection`: the durable roster row. A member's live
/// running bit is not here — it comes from Session status.
TeamMember _teamMemberFromJson(JsonMap json) => TeamMember(
  id: _reqString(json, 'id'),
  name: _reqString(json, 'name'),
  isLead: _teamRole(json['role']) == 'lead',
  phase: _teamMemberPhase(json['phase']),
  error: wireString(json, 'error'),
);

/// One `TeamTaskView`; `deleted` tombstones never reach this decoder because
/// the host filters them before publishing.
TeamTask _teamTaskFromJson(JsonMap json) => TeamTask(
  id: _reqString(json, 'id'),
  revision: _reqLong(json, 'revision'),
  subject: _reqString(json, 'subject'),
  description: _reqString(json, 'description'),
  status: _teamTaskStatus(json['status']),
  blockedBy: _teamStringList(json, 'blockedBy'),
  writeScopes: _teamStringList(json, 'writeScopes'),
  ownerName: wireString(json, 'ownerName'),
  ready: _reqBool(json, 'ready'),
  writeScopeWarnings: _teamStringList(json, 'writeScopeWarnings'),
);

/// Decodes one `agentTeam` projection value. `members` and `tasks` are
/// required; `failure` is present only once the host rejected a persisted
/// Team record, after which it stops applying further ones.
AgentTeam decodeAgentTeamProjection(Object? value) {
  final json = asJsonObject(value);
  if (json == null) {
    throw const FormatException('agentTeam projection value must be an object');
  }
  return AgentTeam(
    members: wireRequiredObjectArray(
      json,
      'members',
    ).map(_teamMemberFromJson).toList(),
    tasks: wireRequiredObjectArray(
      json,
      'tasks',
    ).map(_teamTaskFromJson).toList(),
    failure: wireString(json, 'failure'),
  );
}

// ---------------------------------------------------------------------------
// Plugin management — the `pluginManager` Remote surface. Reference:
// packages/boot/plugin-manager/src/types.ts.
// ---------------------------------------------------------------------------

PluginReadOnlyReason _readOnlyReason(Object? value) => switch (value) {
  'management-required' => PluginReadOnlyReason.managementRequired,
  'unaddressable' => PluginReadOnlyReason.unaddressable,
  final other => throw FormatException(
    'plugin "readOnlyReason" has unknown value "$other"',
  ),
};

PluginLocalizedText? _localizedText(Object? value) {
  if (value is String) {
    return value.isEmpty
        ? null
        : PluginLocalizedText(<String, String>{'en': value});
  }
  final json = asJsonObject(value);
  if (json == null) return null;
  final values = <String, String>{};
  for (final entry in json.entries) {
    final text = entry.value;
    if (text is String && text.isNotEmpty) values[entry.key] = text;
  }
  return values.isEmpty ? null : PluginLocalizedText(values);
}

PluginManagementErrorCode _managementErrorCode(Object? value) =>
    switch (value) {
      'management-required' => PluginManagementErrorCode.managementRequired,
      'unaddressable' => PluginManagementErrorCode.unaddressable,
      'unknown-plugin' => PluginManagementErrorCode.unknownPlugin,
      'invalid-spec' => PluginManagementErrorCode.invalidSpec,
      'ambiguous-install' => PluginManagementErrorCode.ambiguousInstall,
      'not-bundle' => PluginManagementErrorCode.notBundle,
      'not-removable' => PluginManagementErrorCode.notRemovable,
      'stop-profile' => PluginManagementErrorCode.stopProfile,
      'bundle-in-use' => PluginManagementErrorCode.bundleInUse,
      'stale-approval' => PluginManagementErrorCode.staleApproval,
      'incompatible-version' => PluginManagementErrorCode.incompatibleVersion,
      'operation-error' => PluginManagementErrorCode.operationError,
      final other => throw FormatException(
        'plugin management error has unknown code "$other"',
      ),
    };

IncompatiblePlugin _incompatiblePluginFromJson(JsonMap json) {
  final peers = <String, String>{};
  final raw = asJsonObject(json['peers']);
  if (raw != null) {
    for (final entry in raw.entries) {
      if (entry.value is String) peers[entry.key] = entry.value! as String;
    }
  }
  return IncompatiblePlugin(
    name: _reqString(json, 'name'),
    version: _reqString(json, 'version'),
    runtimeVersion: _reqString(json, 'runtimeVersion'),
    peers: peers,
  );
}

PluginManagementError _managementErrorFromJson(JsonMap json) =>
    PluginManagementError(
      code: _managementErrorCode(json['code']),
      diagnostic: wireString(json, 'diagnostic'),
      incompatible:
          asJsonArray(json['incompatible'])?.map((Object? entry) {
            final object = asJsonObject(entry);
            if (object == null) _missing(json, 'incompatible');
            return _incompatiblePluginFromJson(object);
          }).toList() ??
          const <IncompatiblePlugin>[],
    );

List<String> _pluginStringList(JsonMap json, String key) {
  final raw = asJsonArray(json[key]);
  if (raw == null) return const <String>[];
  return raw.map((Object? entry) {
    if (entry is! String) _missing(json, key);
    return entry;
  }).toList();
}

/// One `BundleRowInfo`: a switchable row inside a bundle.
PluginBundleRow _bundleRowFromJson(JsonMap json) {
  final meta = asJsonObject(json['meta']);
  return PluginBundleRow(
    rowId: _reqString(json, 'rowId'),
    moduleName: _reqString(json, 'moduleName'),
    entryId: wireString(json, 'entryId'),
    title: _localizedText(meta?['title']),
    description: _localizedText(meta?['description']),
    icon: wireString(meta ?? const <String, Object?>{}, 'icon'),
    metaError: wireString(meta ?? const <String, Object?>{}, 'error'),
  );
}

/// Decodes one `pluginManager/listBundles` row (`BundleInfo`).
PluginBundle decodePluginBundle(JsonMap json) {
  final meta = asJsonObject(json['meta']);
  return PluginBundle(
    name: _reqString(json, 'name'),
    version: wireString(json, 'version'),
    title: _localizedText(meta?['title']),
    description: wireString(json, 'description'),
    metaDescription: _localizedText(meta?['description']),
    icon: wireString(meta ?? const <String, Object?>{}, 'icon'),
    metaError: wireString(meta ?? const <String, Object?>{}, 'error'),
    enabled: _reqBool(json, 'enabled'),
    installed: _reqBool(json, 'installed'),
    optional: _reqBool(json, 'optional'),
    removable: _reqBool(json, 'removable'),
    readOnlyReason: json.containsKey('readOnlyReason')
        ? _readOnlyReason(json['readOnlyReason'])
        : null,
    error: json.containsKey('error')
        ? _managementErrorFromJson(wireRequiredObject(json, 'error'))
        : null,
    rows: wireRequiredObjectArray(
      json,
      'rows',
    ).map(_bundleRowFromJson).toList(),
    overrides: _pluginStringList(json, 'overrides'),
  );
}

/// Decodes one `pluginManager/listPlugins` row (`PluginInfo`): an inventory
/// entry plus exactly one of `patchId` (addressable) or `readOnlyReason`.
PluginInfo decodeManagedPlugin(JsonMap json) {
  final meta = asJsonObject(json['meta']);
  return PluginInfo(
    entryId: _reqString(json, 'entryId'),
    moduleName: _reqString(json, 'moduleName'),
    enabled: _reqBool(json, 'enabled'),
    patchId: wireString(json, 'patchId'),
    readOnlyReason: json.containsKey('readOnlyReason')
        ? _readOnlyReason(json['readOnlyReason'])
        : null,
    title: _localizedText(meta?['title']),
    description: _localizedText(meta?['description']),
    icon: wireString(meta ?? const <String, Object?>{}, 'icon'),
    metaError: wireString(meta ?? const <String, Object?>{}, 'error'),
  );
}

/// Decodes `pluginManager/registries` (`PluginRegistries`).
PluginRegistries decodePluginRegistries(JsonMap json) => PluginRegistries(
  registry: wireString(json, 'registry'),
  fallbackRegistries: _pluginStringList(json, 'fallbackRegistries'),
  resolved: wireString(json, 'resolved'),
);

/// Decodes `pluginManager/listVersionExemptions`.
PluginVersionExemptions decodePluginVersionExemptions(JsonMap json) {
  final exemptions = <String, List<String>>{};
  final raw = asJsonObject(json['exemptions']);
  if (raw != null) {
    for (final entry in raw.entries) {
      final versions = asJsonArray(entry.value);
      exemptions[entry.key] =
          versions?.map((Object? version) {
            if (version is! String) _missing(json, 'exemptions');
            return version;
          }).toList() ??
          const <String>[];
    }
  }
  return PluginVersionExemptions(
    exemptions: exemptions,
    warnings: _pluginStringList(json, 'warnings'),
  );
}

PluginPackageResult _packageResultFromJson(JsonMap json) => PluginPackageResult(
  exitCode: _reqLong(json, 'exitCode'),
  output: _reqString(json, 'output'),
  truncated: _reqBool(json, 'truncated'),
  logPath: _reqString(json, 'logPath'),
  kind: json.containsKey('kind')
      ? switch (json['kind']) {
          'pnpm-missing' => PluginInstallFailureKind.pnpmMissing,
          'timeout' => PluginInstallFailureKind.timeout,
          'not-found' => PluginInstallFailureKind.notFound,
          'no-matching-version' => PluginInstallFailureKind.noMatchingVersion,
          'network' => PluginInstallFailureKind.network,
          'disk-full' => PluginInstallFailureKind.diskFull,
          'permission' => PluginInstallFailureKind.permission,
          'build-blocked' => PluginInstallFailureKind.buildBlocked,
          'integrity' => PluginInstallFailureKind.integrity,
          'unknown' => PluginInstallFailureKind.unknown,
          final other => throw FormatException(
            'package result "kind" has unknown value "$other"',
          ),
        }
      : null,
  timedOut: json['timedOut'] == true,
  incompatible:
      asJsonArray(json['incompatible'])?.map((Object? entry) {
        final object = asJsonObject(entry);
        if (object == null) _missing(json, 'incompatible');
        return _incompatiblePluginFromJson(object);
      }).toList() ??
      const <IncompatiblePlugin>[],
);

/// Decodes one `ChangeResult` — the answer every mutating manager method
/// gives. Expected refusals ride [PluginChangeResult.error] rather than the
/// transport error branch.
PluginChangeResult decodePluginChangeResult(JsonMap json) => PluginChangeResult(
  changed: _reqBool(json, 'changed'),
  application: switch (_reqString(json, 'application')) {
    'applied' => PluginChangeApplication.applied,
    'restart-required' => PluginChangeApplication.restartRequired,
    'overridden' => PluginChangeApplication.overridden,
    'failed' => PluginChangeApplication.failed,
    'cancelled' => PluginChangeApplication.cancelled,
    final other => throw FormatException(
      'change result "application" has unknown value "$other"',
    ),
  },
  stage: switch (_reqString(json, 'stage')) {
    'install' => PluginChangeStage.install,
    'enable' => PluginChangeStage.enable,
    'remove' => PluginChangeStage.remove,
    final other => throw FormatException(
      'change result "stage" has unknown value "$other"',
    ),
  },
  target: _reqString(json, 'target'),
  enabled: json.containsKey('enabled') ? wireBool(json, 'enabled') : null,
  error: json.containsKey('error')
      ? _managementErrorFromJson(wireRequiredObject(json, 'error'))
      : null,
  warnings: _pluginStringList(json, 'warnings'),
  packageResult: json.containsKey('packageResult')
      ? _packageResultFromJson(wireRequiredObject(json, 'packageResult'))
      : null,
  bundle: wireString(json, 'bundle'),
  pendingBuilds: _pluginStringList(json, 'pendingBuilds'),
  approvedBuilds: _pluginStringList(json, 'approvedBuilds'),
  registries: _pluginStringList(json, 'registries'),
  failedAt: wireString(json, 'failedAt'),
);

/// Decodes `pluginManager/inspect`'s `PluginSpecInspection`.
PluginSpecInspection decodePluginSpecInspection(JsonMap json) {
  final status = _reqString(json, 'status');
  if (status == 'refused') {
    return PluginSpecRefused(
      problem: switch (_reqString(json, 'problem')) {
        'invalid-spec' => PluginInspectProblem.invalidSpec,
        'already-installed' => PluginInspectProblem.alreadyInstalled,
        'not-found' => PluginInspectProblem.notFound,
        'not-a-package' => PluginInspectProblem.notAPackage,
        'not-a-bundle' => PluginInspectProblem.notABundle,
        'network' => PluginInspectProblem.network,
        'unknown' => PluginInspectProblem.unknown,
        final other => throw FormatException(
          'inspection "problem" has unknown value "$other"',
        ),
      },
      reason: _reqString(json, 'reason'),
      registries: _pluginStringList(json, 'registries'),
    );
  }
  if (status != 'accepted') {
    throw FormatException('inspection "status" has unknown value "$status"');
  }
  return PluginSpecAccepted(
    kind: switch (_reqString(json, 'kind')) {
      'registry' => PluginSpecKind.registry,
      'path' => PluginSpecKind.path,
      'git' => PluginSpecKind.git,
      'tarball' => PluginSpecKind.tarball,
      final other => throw FormatException(
        'inspection "kind" has unknown value "$other"',
      ),
    },
    name: wireString(json, 'name'),
    version: wireString(json, 'version'),
    description: wireString(json, 'description'),
    // `bundle` is `boolean | null`: null is "not yet knowable", which is not
    // the same answer as false.
    bundle: json['bundle'] is bool ? json['bundle']! as bool : null,
    registry: wireString(json, 'registry'),
    host: wireString(json, 'host'),
  );
}

/// Decodes one `plugin-manager/install-state` event (`PluginInstallProgress`).
PluginInstallProgress decodePluginInstallProgress(JsonMap json) {
  final attempt = asJsonObject(json['attempt']);
  return PluginInstallProgress(
    requestId: _reqString(json, 'requestId'),
    phase: switch (_reqString(json, 'phase')) {
      'installing' => PluginInstallPhase.installing,
      'cancelling' => PluginInstallPhase.cancelling,
      'applying' => PluginInstallPhase.applying,
      final other => throw FormatException(
        'install progress "phase" has unknown value "$other"',
      ),
    },
    registry: wireString(attempt ?? const <String, Object?>{}, 'registry'),
    attemptIndex: attempt == null ? null : _reqLong(attempt, 'index'),
    attemptTotal: attempt == null ? null : _reqLong(attempt, 'total'),
  );
}

/// Decodes one `plugin-manager/install-log` event
/// (`PluginInstallLogChunk`).
PluginInstallLogChunk decodePluginInstallLogChunk(JsonMap json) =>
    PluginInstallLogChunk(
      requestId: wireString(json, 'requestId'),
      jobId: _reqString(json, 'jobId'),
      argv: _pluginStringList(json, 'argv'),
      cwd: _reqString(json, 'cwd'),
      isStderr: _reqString(json, 'stream') == 'stderr',
      text: _reqString(json, 'text'),
      exitCode: wireLongOrNull(json, 'exitCode'),
    );

// ---------------------------------------------------------------------------
// Scheduled tasks — the `schedule` Remote surface. Reference:
// packages/schedule/schedule/src/types.ts.
// ---------------------------------------------------------------------------

ScheduleKind _scheduleKind(Object? value) => switch (value) {
  'after' => ScheduleKind.after,
  'at' => ScheduleKind.at,
  'every' => ScheduleKind.every,
  'daily' => ScheduleKind.daily,
  'weekly' => ScheduleKind.weekly,
  'cron' => ScheduleKind.cron,
  final other => throw FormatException(
    'schedule record "kind" has unknown value "$other"',
  ),
};

/// A `weekly` record's ISO weekdays: required, and every member an integer —
/// a week with no days is not a rule the host stores.
List<int> _requiredScheduleWeekdays(JsonMap json) {
  final raw = asJsonArray(json['weekdays']);
  if (raw == null) _missing(json, 'weekdays');
  return raw.map((Object? entry) {
    if (entry is! int) _missing(json, 'weekdays');
    return entry;
  }).toList();
}

/// Decodes one `ScheduleRecord`. The union is keyed by `kind`, and each
/// variant's own required fields are enforced here — a `weekly` record
/// without its weekdays fails loud rather than rendering as an every-week
/// rule.
ScheduleRecord decodeScheduleRecordWire(JsonMap json) {
  final kind = _scheduleKind(json['kind']);
  return ScheduleRecord(
    id: _reqString(json, 'id'),
    kind: kind,
    title: _reqString(json, 'title'),
    prompt: _reqString(json, 'prompt'),
    scheduledAt: _reqString(json, 'scheduledAt'),
    afterSeconds: kind == ScheduleKind.after
        ? _reqLong(json, 'afterSeconds')
        : wireLongOrNull(json, 'afterSeconds'),
    everySeconds: kind == ScheduleKind.every
        ? _reqLong(json, 'everySeconds')
        : wireLongOrNull(json, 'everySeconds'),
    time: switch (kind) {
      ScheduleKind.daily || ScheduleKind.weekly => _reqString(json, 'time'),
      _ => wireString(json, 'time'),
    },
    timeZone: switch (kind) {
      ScheduleKind.daily ||
      ScheduleKind.weekly ||
      ScheduleKind.cron => _reqString(json, 'timeZone'),
      _ => wireString(json, 'timeZone'),
    },
    weekdays: kind == ScheduleKind.weekly
        ? _requiredScheduleWeekdays(json)
        : const <int>[],
    expression: kind == ScheduleKind.cron
        ? _reqString(json, 'expression')
        : wireString(json, 'expression'),
  );
}

ScheduleStatus _scheduleStatus(Object? value) => switch (value) {
  'active' => ScheduleStatus.active,
  'inactive' => ScheduleStatus.inactive,
  final other => throw FormatException(
    'schedule status has unknown value "$other"',
  ),
};

ScheduleDeliveryReceipt _scheduleReceipt(JsonMap json) =>
    ScheduleDeliveryReceipt(
      scheduledAt: _reqString(json, 'scheduledAt'),
      deliveredAt: _reqString(json, 'deliveredAt'),
      messageId: _reqString(json, 'messageId'),
    );

ScheduleDeliveryRecord _scheduleDelivery(JsonMap json) =>
    ScheduleDeliveryRecord(
      scheduledAt: _reqString(json, 'scheduledAt'),
      deliveredAt: _reqString(json, 'deliveredAt'),
      messageId: _reqString(json, 'messageId'),
      prompt: wireString(json, 'prompt'),
    );

/// Decodes one `schedule/catalog` row: the record plus its session binding,
/// status, and latest delivery.
ScheduleCatalogEntry decodeScheduleCatalogEntry(JsonMap json) =>
    ScheduleCatalogEntry(
      record: decodeScheduleRecordWire(json),
      sessionId: _reqString(json, 'sessionId'),
      status: _scheduleStatus(json['status']),
      lastDelivery: json.containsKey('lastDelivery')
          ? _scheduleReceipt(wireRequiredObject(json, 'lastDelivery'))
          : null,
    );

/// Decodes `schedule/history` (`ScheduleDeliveryHistoryResult`): a page, or
/// the non-mutating miss the host answers inside the value.
ScheduleHistoryResult decodeScheduleHistoryResult(JsonMap json) {
  final id = _reqString(json, 'id');
  if (json.containsKey('code')) {
    return ScheduleHistoryMiss(id: id, code: _reqString(json, 'code'));
  }
  final retention = wireRequiredObject(json, 'retention');
  return ScheduleHistoryPage(
    id: id,
    records: wireRequiredObjectArray(
      json,
      'records',
    ).map(_scheduleDelivery).toList(),
    earlierRecordsUnavailable: wireRequiredBool(
      json,
      'earlierRecordsUnavailable',
    ),
    earlierRecordsPruned: wireRequiredBool(json, 'earlierRecordsPruned'),
    retention: ScheduleRetentionBounds(
      days: _reqLong(retention, 'days'),
      records: _reqLong(retention, 'records'),
    ),
    nextBefore: wireString(json, 'nextBefore'),
  );
}

/// Decodes `schedule/update` (`ScheduleUpdateResult`): the committed record,
/// a non-mutating miss, or a tool-level refusal. All three ride the success
/// branch; only a storage failure is a transport error.
ScheduleUpdateResult decodeScheduleUpdateResult(JsonMap json) {
  final id = _reqString(json, 'id');
  if (json['updated'] == true) {
    return ScheduleUpdateCommitted(
      record: decodeScheduleRecordWire(wireRequiredObject(json, 'record')),
    );
  }
  final code = _reqString(json, 'code');
  return ScheduleUpdateMiss(
    id: id,
    code: code,
    message: wireString(json, 'message') ?? code,
  );
}

/// Decodes `schedule/delete` (`ScheduleDeleteResult`).
ScheduleDeleteResult decodeScheduleDeleteResult(JsonMap json) =>
    ScheduleDeleteResult(
      id: _reqString(json, 'id'),
      deleted: _reqBool(json, 'deleted'),
      code: wireString(json, 'code'),
    );

/// Encodes one `ScheduleTimingChange` into its wire record.
JsonMap encodeScheduleTimingChange(
  ScheduleTimingChange change,
) => switch (change) {
  ScheduleAtChange(:final at) => <String, Object?>{'kind': 'at', 'at': at},
  ScheduleEveryChange(:final everySeconds) => <String, Object?>{
    'kind': 'every',
    'every_seconds': everySeconds,
  },
  ScheduleDailyChange(:final time, :final timeZone) => <String, Object?>{
    'kind': 'daily',
    'daily': <String, Object?>{'time': time, 'time_zone': timeZone},
  },
  ScheduleWeeklyChange(:final time, :final timeZone, :final weekdays) =>
    <String, Object?>{
      'kind': 'weekly',
      'weekly': <String, Object?>{
        'time': time,
        'time_zone': timeZone,
        'weekdays': weekdays,
      },
    },
  ScheduleCronChange(:final expression, :final timeZone) => <String, Object?>{
    'kind': 'cron',
    'cron': <String, Object?>{'expression': expression, 'time_zone': timeZone},
  },
};

/// Encodes one observed record as the `expected` value `schedule/update`
/// compares against: only the persisted rule fields, never the catalog's
/// binding or status (`task-timing.ts` `timingSnapshot`).
JsonMap encodeScheduleRecordSnapshot(ScheduleRecord record) =>
    <String, Object?>{
      'id': record.id,
      'kind': record.kind.name,
      'title': record.title,
      'prompt': record.prompt,
      'scheduledAt': record.scheduledAt,
      if (record.afterSeconds != null) 'afterSeconds': record.afterSeconds,
      if (record.everySeconds != null) 'everySeconds': record.everySeconds,
      if (record.time != null) 'time': record.time,
      if (record.timeZone != null) 'timeZone': record.timeZone,
      if (record.weekdays.isNotEmpty) 'weekdays': record.weekdays,
      if (record.expression != null) 'expression': record.expression,
    };

// ---------------------------------------------------------------------------
// Terminals — the `terminal` namespace. Reference:
// packages/api/terminal-controller/src/types.ts.
// ---------------------------------------------------------------------------

TerminalState _terminalState(Object? value) => switch (value) {
  'running' => TerminalState.running,
  'exited' => TerminalState.exited,
  'failed' => TerminalState.failed,
  final other => throw FormatException(
    'terminal info "state" has unknown value "$other"',
  ),
};

/// One `TerminalShell` from `terminal/shells`.
TerminalShell decodeTerminalShell(JsonMap json) => TerminalShell(
  path: _reqString(json, 'path'),
  name: _reqString(json, 'name'),
  args: _pluginStringList(json, 'args'),
);

/// Decodes one `WebTerminalInfo`.
TerminalInfo decodeTerminalInfo(JsonMap json) => TerminalInfo(
  id: _reqString(json, 'id'),
  title: _reqString(json, 'title'),
  shell: decodeTerminalShell(wireRequiredObject(json, 'shell')),
  cwd: _reqString(json, 'cwd'),
  cols: _reqLong(json, 'cols'),
  rows: _reqLong(json, 'rows'),
  state: _terminalState(json['state']),
  // `exitCode` is `number | null`: null is "still running", not zero.
  exitCode: json['exitCode'] is int ? json['exitCode']! as int : null,
  error: wireString(json, 'error'),
  controllerId: wireString(json, 'controllerId'),
);

/// Decodes `terminal/environment`.
TerminalEnvironment decodeTerminalEnvironment(JsonMap json) =>
    TerminalEnvironment(
      cwd: _reqString(json, 'cwd'),
      maxInputBytes: _reqLong(json, 'maxInputBytes'),
      maxCols: _reqLong(json, 'maxCols'),
      maxRows: _reqLong(json, 'maxRows'),
      scrollback: _reqLong(json, 'scrollback'),
    );

/// Decodes one `TerminalFrame`. The discriminant is closed: `snapshot`,
/// `output`, `state`.
TerminalFrame decodeTerminalFrame(JsonMap frame) {
  final type = _reqString(frame, 'type');
  switch (type) {
    case 'snapshot':
      return TerminalSnapshot(
        sequence: _reqLong(frame, 'sequence'),
        screen: _reqString(frame, 'screen'),
        info: decodeTerminalInfo(wireRequiredObject(frame, 'info')),
      );
    case 'output':
      return TerminalOutput(
        sequence: _reqLong(frame, 'sequence'),
        data: _reqString(frame, 'data'),
      );
    case 'state':
      return TerminalStateChange(
        info: decodeTerminalInfo(wireRequiredObject(frame, 'info')),
      );
    default:
      throw FormatException('terminal frame "type" has unknown value "$type"');
  }
}

// ---------------------------------------------------------------------------
// Account (`account/getState`, `account/getProfile`, `account/getBalance`,
// `account/getUnnotifiedBonuses`). Reference:
// reference/deepseek-harness/packages/credentials/deepseek-account/src/types.ts
// (`AccountView`, `SignInAttemptView`, `AccountLinks`, `AccountProfile`,
// `AccountWallet`, `AccountDetails`, `AccountBonusNotification`,
// `AccountBonusBatch`). The one optional field in the whole projection is
// `AccountProfile.avatarUrl`; `attempt`, `id`, `name` and `contact` are
// required keys that may hold null, so their absence is host breakage while
// null is a fact.
// ---------------------------------------------------------------------------

/// One required key whose value may be null: absence throws naming the field,
/// null stays null. The `AccountProfile` identity fields and `AccountView`
/// `attempt` are declared this way in the reference.
String? _reqNullableString(JsonMap json, String key) {
  if (!json.containsKey(key)) _missing(json, key);
  final value = json[key];
  if (value == null) return null;
  final text = wireString(json, key);
  if (text == null) _missing(json, key);
  return text;
}

/// One required array of objects; a non-array field or a non-object member
/// fails loud naming the field. Sibling of the package-level
/// `wireRequiredObjectArray`, which drops a malformed member instead.
List<JsonMap> _reqObjectArray(JsonMap json, String key) {
  final raw = json[key];
  if (raw is! List) _missing(json, key);
  final values = <JsonMap>[];
  for (final Object? entry in raw) {
    final object = asJsonObject(entry);
    if (object == null) _missing(json, key);
    values.add(object);
  }
  return values;
}

/// The `AccountClientMetadata` request argument: the identity of the
/// requesting UI, from which the host derives the Platform request headers.
JsonMap accountClientMetadataJson(AccountClientIdentity client) =>
    <String, Object?>{
      'version': client.version,
      'locale': client.locale,
      'timezoneOffsetSeconds': client.timezoneOffsetSeconds,
    };

/// Reads one `AccountWallet` / bonus `currency`; the reference union is
/// closed, so an unknown value fails loud naming the field rather than
/// decoding as either currency.
AccountCurrency _accountCurrency(JsonMap json, String key) {
  final value = _reqString(json, key);
  switch (value) {
    case 'CNY':
      return AccountCurrency.cny;
    case 'USD':
      return AccountCurrency.usd;
  }
  throw FormatException('account "$key" has unknown value "$value"');
}

/// Reads one `SignInAttemptView.phase`; the reference union is closed.
AccountSignInPhase _accountSignInPhase(JsonMap json, String key) {
  final value = _reqString(json, key);
  switch (value) {
    case 'initializing':
      return AccountSignInPhase.initializing;
    case 'waiting-browser':
      return AccountSignInPhase.waitingBrowser;
    case 'exchanging':
      return AccountSignInPhase.exchanging;
    case 'committing':
      return AccountSignInPhase.committing;
    case 'succeeded':
      return AccountSignInPhase.succeeded;
    case 'cancelled':
      return AccountSignInPhase.cancelled;
    case 'expired':
      return AccountSignInPhase.expired;
    case 'failed':
      return AccountSignInPhase.failed;
  }
  throw FormatException('account "$key" has unknown value "$value"');
}

AccountSignInAttempt _decodeAccountAttempt(
  JsonMap json,
) => AccountSignInAttempt(
  id: _reqString(json, 'id'),
  phase: _accountSignInPhase(json, 'phase'),
  // The three optional members (`authorizeUrl?`, `expiresAt?`, `errorCode?`).
  authorizeUrl: wireString(json, 'authorizeUrl'),
  expiresAt: wireLongOrNull(json, 'expiresAt'),
  errorCode: wireString(json, 'errorCode'),
);

AccountLinks _decodeAccountLinks(JsonMap json) => AccountLinks(
  usageUrl: _reqString(json, 'usageUrl'),
  topUpUrl: _reqString(json, 'topUpUrl'),
);

/// Decodes `account/getState`'s `AccountView`.
///
/// The `status` discriminant is closed and `attempt` is a required key that
/// may be null — null is "the host holds no attempt", not a missing field.
AccountState decodeAccountState(JsonMap json) {
  final status = _reqString(json, 'status');
  final AccountSignInStatus presence;
  switch (status) {
    case 'signed-out':
      presence = AccountSignInStatus.signedOut;
    case 'credential-stored':
      presence = AccountSignInStatus.credentialStored;
    default:
      throw FormatException(
        'account/getState "status" has unknown value "$status"',
      );
  }
  if (!json.containsKey('attempt')) _missing(json, 'attempt');
  final attempt = json['attempt'];
  return AccountState(
    status: presence,
    links: _decodeAccountLinks(_reqObject(json, 'links')),
    attempt: attempt == null
        ? null
        : _decodeAccountAttempt(
            asJsonObject(attempt) ?? _missing(json, 'attempt'),
          ),
  );
}

AccountWallet _decodeAccountWallet(JsonMap json) => AccountWallet(
  currency: _accountCurrency(json, 'currency'),
  balance: _reqString(json, 'balance'),
);

/// Decodes `account/getProfile`'s `AccountDetails['profile']` outcome.
///
/// A null result (the host holds no account grant) is the caller's business,
/// not this decoder's: it never invents `failed` from absence.
AccountProfileResult decodeAccountProfileResult(JsonMap json) {
  final status = _reqString(json, 'status');
  switch (status) {
    case 'ready':
      final value = _reqObject(json, 'value');
      return AccountProfileReady(
        AccountProfile(
          id: _reqNullableString(value, 'id'),
          name: _reqNullableString(value, 'name'),
          contact: _reqNullableString(value, 'contact'),
          // `avatarUrl` is the one optional member of the projection.
          avatarUrl: wireString(value, 'avatarUrl'),
        ),
      );
    case 'failed':
      return const AccountProfileFailed();
  }
  throw FormatException(
    'account/getProfile "status" has unknown value "$status"',
  );
}

/// Decodes `account/getBalance`'s `AccountDetails['balance']` outcome: the
/// recharge wallets under `value` and the granted wallets under
/// `bonusWallets`, kept separate because the reference keeps them separate.
AccountBalanceResult decodeAccountBalanceResult(JsonMap json) {
  final status = _reqString(json, 'status');
  switch (status) {
    case 'ready':
      return AccountBalanceReady(
        wallets: _reqObjectArray(
          json,
          'value',
        ).map(_decodeAccountWallet).toList(),
        bonusWallets: _reqObjectArray(
          json,
          'bonusWallets',
        ).map(_decodeAccountWallet).toList(),
      );
    case 'failed':
      return const AccountBalanceFailed();
  }
  throw FormatException(
    'account/getBalance "status" has unknown value "$status"',
  );
}

AccountBonusGrant _decodeAccountBonusGrant(JsonMap json) => AccountBonusGrant(
  orderId: _reqString(json, 'orderId'),
  campaign: _reqString(json, 'campaign'),
  amount: _reqString(json, 'amount'),
  currency: _accountCurrency(json, 'currency'),
  grantedAt: _reqString(json, 'grantedAt'),
  expiresAt: _reqString(json, 'expiresAt'),
  message: _reqString(json, 'message'),
);

/// Decodes `account/getUnnotifiedBonuses`'s `AccountBonusBatch`: the account
/// every grant belongs to plus the grants in Platform order.
AccountBonusBatch decodeAccountBonusBatch(JsonMap json) => AccountBonusBatch(
  accountId: _reqString(json, 'accountId'),
  bonuses: _reqObjectArray(
    json,
    'bonuses',
  ).map(_decodeAccountBonusGrant).toList(),
);

// ---------------------------------------------------------------------------
// Human feedback (`messageFeedback/{list,put,delete}`, `sessionFeedback/record`
// — reference/deepseek-harness/packages/feedback/*/src/{index,types}.ts)
// ---------------------------------------------------------------------------

/// The Host's business result envelope shared by all four feedback
/// operations (`message-feedback/src/types.ts` `MessageFeedbackSuccess` /
/// `MessageFeedbackRejected`; `sessionFeedback/record` answers the same shape).
///
/// It rides inside the transport's success branch: a refusal is a business
/// verdict, not a failed call. Exactly one of [value] / [error] is non-null.
final class MessageFeedbackResultWire {
  const MessageFeedbackResultWire._({required this.value, required this.error});

  /// Reads one envelope; an absent or non-boolean `ok` fails loud naming it.
  factory MessageFeedbackResultWire.fromJson(JsonMap json) =>
      _reqBool(json, 'ok')
      ? MessageFeedbackResultWire._(
          value: _reqObject(json, 'value'),
          error: null,
        )
      : MessageFeedbackResultWire._(
          value: null,
          error: _reqObject(json, 'error'),
        );

  /// The success branch's payload; null when the Host refused.
  final JsonMap? value;

  /// The refusal branch's error object; null on success.
  final JsonMap? error;
}

/// One current judgment (`message-feedback/src/types.ts` `MessageFeedbackItem`):
/// its message, rating, optional note and category, compare-and-set version,
/// and the Host's creation and update times.
MessageFeedbackItem decodeMessageFeedbackItem(JsonMap json) =>
    MessageFeedbackItem(
      messageId: _reqString(json, 'messageId'),
      rating: messageFeedbackRatingFromWire(_reqString(json, 'rating')),
      note: wireString(json, 'note'),
      category: json.containsKey('category')
          ? messageFeedbackCategoryFromWire(_reqString(json, 'category'))
          : null,
      version: _reqString(json, 'version'),
      createdAtEpochMs: _reqLong(json, 'createdAt'),
      updatedAtEpochMs: _reqLong(json, 'updatedAt'),
    );

/// The refusal a feedback operation answered, as the domain value the surface
/// states beside the control: the stable code plus the authoritative item a
/// `version-conflict` carries (`types.ts` `MessageFeedbackVersionConflict`).
MessageFeedbackRefused _messageFeedbackRefused(JsonMap error) {
  final current = asJsonObject(error['current']);
  return MessageFeedbackRefused(
    _reqString(error, 'code'),
    current: current == null ? null : decodeMessageFeedbackItem(current),
  );
}

/// Decodes the `messageFeedback/list` success value: the Session's current
/// items, in first-creation order.
List<MessageFeedbackItem> decodeMessageFeedbackListValue(JsonMap value) =>
    _reqObjectArray(value, 'items').map(decodeMessageFeedbackItem).toList();

/// Decodes the `messageFeedback/put` result: the durable item the Host
/// committed, or its explicit refusal.
MessageFeedbackWrite decodeMessageFeedbackPutResult(JsonMap json) {
  final result = MessageFeedbackResultWire.fromJson(json);
  final error = result.error;
  if (error != null) return _messageFeedbackRefused(error);
  return MessageFeedbackCommitted(decodeMessageFeedbackItem(result.value!));
}

/// Decodes the `messageFeedback/delete` result: the idempotent absence
/// postcondition, or the Host's explicit refusal.
MessageFeedbackWrite decodeMessageFeedbackDeleteResult(JsonMap json) {
  final result = MessageFeedbackResultWire.fromJson(json);
  final error = result.error;
  if (error != null) return _messageFeedbackRefused(error);
  final value = result.value!;
  if (!_reqBool(value, 'absent')) {
    throw FormatException(
      'messageFeedback/delete "absent" must be true in ${value.keys.toList()}',
    );
  }
  return const MessageFeedbackCommitted(null);
}

/// Encodes one judgment for `messageFeedback/put`.
String encodeMessageFeedbackRating(MessageFeedbackRating rating) =>
    switch (rating) {
      MessageFeedbackRating.positive => 'positive',
      MessageFeedbackRating.negative => 'negative',
    };

/// Encodes one category id for a feedback write; the ids are durable log
/// vocabulary (`command-feedback/src/types.ts` `FeedbackCategory`).
String encodeMessageFeedbackCategory(MessageFeedbackCategory category) =>
    switch (category) {
      MessageFeedbackCategory.taskResult => 'task-result',
      MessageFeedbackCategory.instructionFollowing => 'instruction-following',
      MessageFeedbackCategory.productInteraction => 'product-interaction',
      MessageFeedbackCategory.serviceStability => 'service-stability',
      MessageFeedbackCategory.resourceCost => 'resource-cost',
      MessageFeedbackCategory.securityPrivacyPermission =>
        'security-privacy-permission',
      MessageFeedbackCategory.other => 'other',
    };

// ---------------------------------------------------------------------------
// Open in app (`session/canOpenWorkspacePath`, `session/openWorkspacePath`,
// `session/workspacePathApplications` —
// reference/deepseek-harness/packages/api/session-controller/src/{index,types}
// .ts:318-395; the application row is
// packages/util/native-command/src/types.ts `NativeFileApplication`)
// ---------------------------------------------------------------------------

/// Decodes the `session/canOpenWorkspacePath` result: the bare boolean
/// response, parked under the envelope's `value` key by
/// `RpcResult.fromJson` (`packages/network/lib/rpc_envelope.dart`).
bool decodeCanOpenWorkspacePath(JsonMap result) => _reqBool(result, 'value');

/// One OS-registered application (`NativeFileApplication`): its id, display
/// name, whether the desktop would open with it by default, and the icon data
/// URL the desktop supplied (`null` when it supplied none).
///
/// All four keys are required by the reference's parser — absence of `icon`
/// is host breakage, while `icon: null` is the stated "no icon" fact.
final class WorkspacePathApplicationWire {
  WorkspacePathApplicationWire.fromJson(JsonMap json)
    : id = _reqString(json, 'id'),
      name = _reqString(json, 'name'),
      isDefault = _reqBool(json, 'default'),
      icon = _reqNullableString(json, 'icon');

  final String id;
  final String name;
  final bool isDefault;
  final String? icon;
}

/// Decodes the `session/workspacePathApplications` result: the bare array of
/// registered applications, parked under the envelope's `value` key. An
/// absent or non-array `value` — or a member that is not an object — throws
/// naming `value`.
List<WorkspacePathApplication> decodeWorkspacePathApplications(
  JsonMap result,
) => _reqObjectArray(result, 'value')
    .map((JsonMap json) => WorkspacePathApplicationWire.fromJson(json))
    .map(
      (WorkspacePathApplicationWire wire) => WorkspacePathApplication(
        id: wire.id,
        name: wire.name,
        isDefault: wire.isDefault,
        icon: wire.icon,
      ),
    )
    .toList();

/// Decodes the `session/openWorkspacePath` result
/// (`SessionOpenWorkspacePathValue`): the host confirms it handed the path to
/// its native opener. `opened` is required, and any value but `true` is host
/// breakage — the Host has no failure branch inside a success envelope here.
void decodeOpenWorkspacePathValue(JsonMap value) {
  if (!_reqBool(value, 'opened')) {
    throw FormatException(
      'session/openWorkspacePath "opened" must be true in '
      '${value.keys.toList()}',
    );
  }
}
