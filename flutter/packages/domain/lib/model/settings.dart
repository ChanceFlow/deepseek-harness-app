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
  });

  final String ns;
  final SettingsApplies applies;
  final int revision;
  final bool hasUserLayer;
  final int secretCount;

  @override
  bool operator ==(Object other) =>
      other is SettingsNamespace &&
      other.ns == ns &&
      other.applies == applies &&
      other.revision == revision &&
      other.hasUserLayer == hasUserLayer &&
      other.secretCount == secretCount;

  @override
  int get hashCode =>
      Object.hash(ns, applies, revision, hasUserLayer, secretCount);
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
      other is SettingsSnapshot &&
      other.writable == writable &&
      other.hasDocument == hasDocument &&
      _listEquals(other.namespaces, namespaces) &&
      _listEquals(other.credentialRefs, credentialRefs);

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
    this.source,
    required this.writable,
  });

  final String ref;
  final bool configured;
  final String? source;
  final bool writable;

  @override
  bool operator ==(Object other) =>
      other is CredentialStatus &&
      other.ref == ref &&
      other.configured == configured &&
      other.source == source &&
      other.writable == writable;

  @override
  int get hashCode => Object.hash(ref, configured, source, writable);
}

/// One path-addressed settings mutation; [op] is "set" or "unset".
final class SettingPathOp {
  /// Throws [ArgumentError] when the op/path/value combination is invalid,
  /// mirroring the Kotlin `init` block contract checks.
  SettingPathOp({
    required this.op,
    required this.path,
    this.jsonValue,
  }) {
    if (op != 'set' && op != 'unset') {
      throw ArgumentError('op must be set or unset');
    }
    if (path.isEmpty) {
      throw ArgumentError('path must be non-empty');
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
      other is SettingPathOp &&
      other.op == op &&
      _listEquals(other.path, path) &&
      other.jsonValue == jsonValue;

  @override
  int get hashCode => Object.hash(op, Object.hashAll(path), jsonValue);
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
