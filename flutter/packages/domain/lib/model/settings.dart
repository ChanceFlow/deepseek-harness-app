/// Settings-plane vocabulary (loopback-gated on the host).
library;

/// Read-only projection of one host settings namespace, mirrored from the
/// `settings.describe` wire view. Values stay on the host; the client only
/// renders the summary columns.
final class SettingsNamespace {
  const SettingsNamespace({
    required this.ns,
    required this.applies,
    required this.revision,
    required this.hasUserLayer,
    required this.secretCount,
    this.value,
    this.user,
    this.base,
  });

  final String ns;
  final SettingsApplies applies;
  final int revision;
  final bool hasUserLayer;
  final int secretCount;

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
    _jsonHash(value),
    _jsonHash(user),
    _jsonHash(base),
  );
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
