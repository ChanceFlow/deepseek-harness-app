/// Settings-plane vocabulary (loopback-gated on the host).
library;

/// Read-only projection of one host settings namespace, mirrored from the
/// `settings.describe` wire view. Values stay on the host; the client renders
/// the summary columns and, for a namespace the host leaves to this client,
/// the field form its [schema] declares.
final class SettingsNamespace {
  const SettingsNamespace({
    required this.ns,
    required this.applies,
    required this.revision,
    required this.hasUserLayer,
    required this.secretCount,
    required this.schema,
    this.autoGenerate = false,
    this.value,
    this.user,
    this.base,
  });

  final String ns;
  final SettingsApplies applies;
  final int revision;
  final bool hasUserLayer;
  final int secretCount;

  /// Whether this client may render a generated page for the namespace when no
  /// custom page exists for it (`SettingsDescriptor.autoGenerate`). False
  /// covers both a host that withheld the field and one that refused.
  final bool autoGenerate;

  /// The namespace's field projection, decoded from the descriptor's
  /// `schema` (`form.toJSON()`). Wire data always carries one: the decoder
  /// fails loud on an absent or malformed envelope rather than rendering an
  /// empty form. [SettingsSchema.empty] is the no-declared-fields value a
  /// fixture or test builds directly.
  final SettingsSchema schema;

  /// Redacted resolved value (schema defaults, then composition base, then
  /// the user layer). Schema-declared secret slots are removed by the host's
  /// `redactSecrets` read, so this never carries a credential literal.
  final Object? value;

  /// Redacted raw user section; a field's presence here marks it
  /// user-overridden.
  final Object? user;

  /// Redacted composition base layer, when the registrant declared one.
  final Object? base;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SettingsNamespace &&
          other.ns == ns &&
          other.applies == applies &&
          other.revision == revision &&
          other.hasUserLayer == hasUserLayer &&
          other.secretCount == secretCount &&
          other.autoGenerate == autoGenerate &&
          other.schema == schema &&
          _jsonEquals(other.value, value) &&
          _jsonEquals(other.user, user) &&
          _jsonEquals(other.base, base));

  @override
  int get hashCode => Object.hash(
    ns,
    applies,
    revision,
    hasUserLayer,
    secretCount,
    autoGenerate,
    schema,
    _jsonHash(value),
    _jsonHash(user),
    _jsonHash(base),
  );
}

/// One namespace's decoded field projection: the `schema` envelope
/// `settings.describe` carries per entry (`form.toJSON()`).
///
/// Schemastery serializes a schema as a root [root] identity plus a [nodes]
/// table keyed by uid, because a config schema may reference the same node
/// twice or reference an ancestor. Child positions on a node are therefore
/// uids, and the `*Of` accessors resolve them against [nodes]; decoding never
/// builds a nested tree, so a recursive schema cannot loop.
final class SettingsSchema {
  const SettingsSchema({required this.root, required this.nodes});

  /// The schema with no declared fields: an object node with an empty
  /// dictionary. The host never emits this (an entry with no live field is
  /// left out of `describe` entirely); it is the projection a fixture or test
  /// builds when no schema is under test.
  static const SettingsSchema empty = SettingsSchema(
    root: SettingsSchemaNode(
      uid: 0,
      type: 'object',
      meta: SettingsSchemaMeta(),
    ),
    nodes: <int, SettingsSchemaNode>{
      0: SettingsSchemaNode(uid: 0, type: 'object', meta: SettingsSchemaMeta()),
    },
  );

  /// The envelope's root node identity.
  final SettingsSchemaNode root;

  /// Every node the envelope carries, keyed by the uid its children reference.
  final Map<int, SettingsSchemaNode> nodes;

  /// The node [uid] names, or null when the envelope does not carry it.
  SettingsSchemaNode? node(int uid) => nodes[uid];

  /// The dictionary key schema of a `dict` node (`sKey`).
  SettingsSchemaNode? sKeyOf(SettingsSchemaNode node) => nodes[node.sKeyUid];

  /// The element schema of an `array`, `dict`, `lazy`, or `transform` node.
  SettingsSchemaNode? innerOf(SettingsSchemaNode node) => nodes[node.innerUid];

  /// The member schemas of a `union`, `intersect`, or `tuple` node.
  List<SettingsSchemaNode> listOf(SettingsSchemaNode node) {
    final members = <SettingsSchemaNode>[];
    for (final uid in node.listUids) {
      final member = nodes[uid];
      if (member != null) members.add(member);
    }
    return members;
  }

  /// The field schemas of an `object` node, in declaration order.
  Map<String, SettingsSchemaNode> dictOf(SettingsSchemaNode node) {
    final fields = <String, SettingsSchemaNode>{};
    node.dictUids.forEach((key, uid) {
      final field = nodes[uid];
      if (field != null) fields[key] = field;
    });
    return fields;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SettingsSchema &&
          other.root == root &&
          _jsonEquals(other.nodes, nodes));

  @override
  int get hashCode => Object.hash(root, _jsonHash(nodes));
}

/// One node of a [SettingsSchema].
///
/// [uid] is the identity the envelope's `refs` table keys this node by; the
/// child positions are uids too, so a caller resolves them through
/// [SettingsSchema.sKeyOf], [SettingsSchema.innerOf], [SettingsSchema.listOf],
/// and [SettingsSchema.dictOf].
final class SettingsSchemaNode {
  const SettingsSchemaNode({
    required this.uid,
    required this.type,
    required this.meta,
    this.value,
    this.callback,
    this.bits = const <String, int>{},
    this.sKeyUid,
    this.innerUid,
    this.listUids = const <int>[],
    this.dictUids = const <String, int>{},
  });

  final int uid;

  /// The schemastery node kind (`object`, `string`, `number`, `boolean`,
  /// `const`, `union`, `intersect`, `tuple`, `array`, `dict`, `lazy`,
  /// `transform`, `bitset`, `is`, `any`, `never`, `function`, …). The set is
  /// open: `Schema.extend` lets a plugin register a custom kind, so a renderer
  /// falls back on an unrecognized value rather than failing the decode.
  final String type;

  /// The UI and validation metadata the schema builder attached.
  final SettingsSchemaMeta meta;

  /// The literal a `const` node requires — the option values a `union` of
  /// constants offers.
  final Object? value;

  /// The JavaScript source text of a `transform` node's callback, as a
  /// directly serialized schema carries it. A descriptor's `schema` rebuilds
  /// the form through `plainSchema` first, which turns that text back into a
  /// function, so a `transform` field reaches this client with its [inner]
  /// node and no callback. Carried for fidelity; never evaluated here.
  final String? callback;

  /// The bit positions of a `bitset` node, by bit name.
  final Map<String, int> bits;

  /// Uid of the dictionary key schema (`dict`).
  final int? sKeyUid;

  /// Uid of the element or target schema (`array`, `dict`, `lazy`,
  /// `transform`).
  final int? innerUid;

  /// Uids of the member schemas (`union`, `intersect`, `tuple`).
  final List<int> listUids;

  /// Uids of the field schemas, by field name (`object`).
  final Map<String, int> dictUids;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SettingsSchemaNode &&
          other.uid == uid &&
          other.type == type &&
          other.meta == meta &&
          _jsonEquals(other.value, value) &&
          other.callback == callback &&
          _jsonEquals(other.bits, bits) &&
          other.sKeyUid == sKeyUid &&
          other.innerUid == innerUid &&
          _jsonEquals(other.listUids, listUids) &&
          _jsonEquals(other.dictUids, dictUids));

  @override
  int get hashCode => Object.hash(
    uid,
    type,
    meta,
    _jsonHash(value),
    callback,
    _jsonHash(bits),
    sKeyUid,
    innerUid,
    _jsonHash(listUids),
    _jsonHash(dictUids),
  );
}

/// The UI and validation metadata one [SettingsSchemaNode] carries
/// (`Schemastery.Meta`; `reference/deepseek-harness/vendor/schemastery/src/
/// index.ts:113-136`). Every key is optional; an unrecognized key is ignored
/// rather than failing the decode.
final class SettingsSchemaMeta {
  const SettingsSchemaMeta({
    this.defaultValue,
    this.required = false,
    this.volatile = false,
    this.disabled = false,
    this.collapse = false,
    this.hidden = false,
    this.loose = false,
    this.role,
    this.extra,
    this.link,
    this.description,
    this.comment,
    this.pattern,
    this.max,
    this.min,
    this.step,
    this.badges = const <SettingsSchemaBadge>[],
  });

  /// The fallback value the host uses for an absent field (`meta.default`).
  final Object? defaultValue;

  /// Whether the field must be present.
  final bool required;

  /// Whether the field is a stable config reference; the settings form only
  /// exposes volatile fields.
  final bool volatile;

  /// Whether a form renderer must disable the field.
  final bool disabled;

  /// Whether a nested form should render collapsed.
  final bool collapse;

  /// Whether a form renderer must omit the field.
  final bool hidden;

  /// Whether validation returns the default instead of throwing.
  final bool loose;

  /// The renderer role the schema declared (for example `secret`, `regexp`),
  /// or null when it declared none.
  final String? role;

  /// Arbitrary renderer metadata the schema attached.
  final Object? extra;

  /// External documentation link.
  final String? link;

  /// The field's label, keyed by locale; `''` is the unlocalized entry. Null
  /// when the schema declares none.
  final Map<String, String>? description;

  /// Auxiliary note for documentation and form UIs.
  final String? comment;

  /// String constraint, when the schema declared one.
  final SettingsSchemaPattern? pattern;

  /// Inclusive maximum for a number or collection length.
  final num? max;

  /// Inclusive minimum for a number or collection length.
  final num? min;

  /// Numeric increment constraint.
  final num? step;

  /// Labels the schema attached (`deprecated`, `experimental`).
  final List<SettingsSchemaBadge> badges;

  /// The field's label for [locale]: its localized [description], then the
  /// unlocalized description entry, then [comment]. Null when the schema
  /// declares no text at all, which leaves the field name as the only label.
  String? labelFor(String locale) {
    final texts = description;
    if (texts != null) {
      final localized = texts[locale];
      if (localized != null && localized.isNotEmpty) return localized;
      final plain = texts[''];
      if (plain != null && plain.isNotEmpty) return plain;
    }
    final note = comment;
    return note == null || note.isEmpty ? null : note;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SettingsSchemaMeta &&
          _jsonEquals(other.defaultValue, defaultValue) &&
          other.required == required &&
          other.volatile == volatile &&
          other.disabled == disabled &&
          other.collapse == collapse &&
          other.hidden == hidden &&
          other.loose == loose &&
          other.role == role &&
          _jsonEquals(other.extra, extra) &&
          other.link == link &&
          _jsonEquals(other.description, description) &&
          other.comment == comment &&
          other.pattern == pattern &&
          other.max == max &&
          other.min == min &&
          other.step == step &&
          _listEquals(other.badges, badges));

  @override
  int get hashCode => Object.hash(
    _jsonHash(defaultValue),
    required,
    volatile,
    disabled,
    collapse,
    hidden,
    loose,
    role,
    _jsonHash(extra),
    link,
    _jsonHash(description),
    comment,
    pattern,
    max,
    min,
    step,
    Object.hashAll(badges),
  );
}

/// A string constraint declared on a schema node (`meta.pattern`).
final class SettingsSchemaPattern {
  const SettingsSchemaPattern({required this.source, this.flags});

  final String source;
  final String? flags;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SettingsSchemaPattern &&
          other.source == source &&
          other.flags == flags);

  @override
  int get hashCode => Object.hash(source, flags);
}

/// One label a schema node carries (`meta.badges`).
final class SettingsSchemaBadge {
  const SettingsSchemaBadge({required this.text, required this.type});

  final String text;

  /// The badge's severity the reference pairs with a color: `danger` or
  /// `warning`.
  final String type;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SettingsSchemaBadge &&
          other.text == text &&
          other.type == type);

  @override
  int get hashCode => Object.hash(text, type);
}

/// Structural equality for a decoded JSON value.
bool _jsonEquals(Object? a, Object? b) {
  if (identical(a, b)) return true;
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final Object? key in a.keys) {
      if (!b.containsKey(key) || !_jsonEquals(a[key], b[key])) return false;
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_jsonEquals(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}

int _jsonHash(Object? value) {
  if (value is Map) {
    return Object.hashAll(
      value.entries.map(
        (MapEntry<Object?, Object?> e) =>
            Object.hash(e.key, _jsonHash(e.value)),
      ),
    );
  }
  if (value is List) return Object.hashAll(value.map(_jsonHash));
  return value.hashCode;
}

/// When a namespace edit takes effect, as the host reports it.
enum SettingsApplies { live, restart, unknown }

/// Read-only settings snapshot: whether the host accepts writes, whether a
/// settings document exists, and one row per namespace. `credentialRefs`
/// collects every credential reference the namespace values name, so the UI
/// can follow up with one batched `credentials.describe`.
final class SettingsSnapshot {
  const SettingsSnapshot({
    required this.writable,
    required this.hasDocument,
    required this.namespaces,
    required this.credentialRefs,
  });

  final bool writable;
  final bool hasDocument;
  final List<SettingsNamespace> namespaces;
  final List<String> credentialRefs;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SettingsSnapshot &&
          other.writable == writable &&
          other.hasDocument == hasDocument &&
          _listEquals(other.namespaces, namespaces) &&
          _listEquals(other.credentialRefs, credentialRefs));

  @override
  int get hashCode => Object.hash(
    writable,
    hasDocument,
    Object.hashAll(namespaces),
    Object.hashAll(credentialRefs),
  );
}

/// One credential-reference state: whether the host holds a value, where it
/// comes from, and whether this client could store one.
final class CredentialStatus {
  const CredentialStatus({
    required this.ref,
    required this.configured,
    required this.writable,
    this.source,
  });

  final String ref;
  final bool configured;
  final String? source;
  final bool writable;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CredentialStatus &&
          other.ref == ref &&
          other.configured == configured &&
          other.source == source &&
          other.writable == writable);

  @override
  int get hashCode => Object.hash(ref, configured, source, writable);
}

/// One path-addressed settings mutation; [op] is "set" or "unset".
final class SettingPathOp {
  /// Throws [ArgumentError] when the op/path/value combination is invalid,
  /// mirroring the Kotlin `init` block contract checks.
  SettingPathOp({required this.op, required this.path, this.jsonValue}) {
    if (op != 'set' && op != 'unset') {
      throw ArgumentError('op must be set or unset');
    }
    if (op == 'set' && jsonValue == null) {
      throw ArgumentError('set op requires a value');
    }
  }

  final String op;
  final List<String> path;
  final String? jsonValue;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SettingPathOp &&
          other.op == op &&
          _listEquals(other.path, path) &&
          other.jsonValue == jsonValue);

  @override
  int get hashCode => Object.hash(op, Object.hashAll(path), jsonValue);
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
