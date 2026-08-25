/// Agent-preset roster vocabulary.
///
/// Mirrors the `agentPreset.list` response
/// (reference/deepseek-harness/packages/host/apiproxy/src/api/
/// agent-presets.schema.ts): the roster a surface offers when composing
/// a session's agent, plus the deployment-level facts riding the same
/// response.
library;

/// Whether a preset ships with the deployment or was authored locally.
enum AgentPresetTrust { system, user }

/// One preset the deployment can compose a session's agent from.
final class AgentPresetEntry {
  const AgentPresetEntry({
    required this.id,
    required this.trust,
    this.isDefault = false,
    this.name,
    this.description,
    this.broken,
  });

  final String id;
  final AgentPresetTrust trust;

  /// Whether a session that names no preset gets this one.
  final bool isDefault;

  /// Display name the preset published; null when it published none.
  /// Never a second identity and never a trust signal — a surface falls
  /// back to [id].
  final String? name;

  /// One sentence on what the preset is for; null when unpublished.
  final String? description;

  /// Why this preset cannot compose a session; null when it can. A
  /// broken preset stays listed (its directory still occupies the id)
  /// but offering it for selection would only defer this reason to a
  /// failed session start.
  final String? broken;

  /// Label a surface shows when the preset published no [name].
  String get displayName => name ?? id;

  @override
  bool operator ==(Object other) =>
      other is AgentPresetEntry &&
      other.id == id &&
      other.trust == trust &&
      other.isDefault == isDefault &&
      other.name == name &&
      other.description == description &&
      other.broken == broken;

  @override
  int get hashCode =>
      Object.hash(id, trust, isDefault, name, description, broken);
}

/// The whole roster plus the deployment-level facts of one
/// `agentPreset.list` response.
final class AgentPresetRoster {
  const AgentPresetRoster({
    this.entries = const <AgentPresetEntry>[],
    this.authorable = false,
    this.hasDocument = false,
  });

  /// Every preset the deployment supplies, in root-precedence order
  /// (the order is not globally sorted; a user root's preset sits in
  /// that root's block, not among the shipped ids). An empty roster
  /// means the deployment composes no presets and every session shares
  /// the host composition.
  final List<AgentPresetEntry> entries;

  /// Whether the deployment configures a root new presets can be
  /// written to.
  final bool authorable;

  /// Whether the platform can hand a preset directory to a native
  /// opener.
  final bool hasDocument;

  /// The entry a session naming no preset gets; null when the roster
  /// carries no default.
  AgentPresetEntry? get defaultEntry =>
      entries.where((entry) => entry.isDefault).firstOrNull;

  @override
  bool operator ==(Object other) =>
      other is AgentPresetRoster &&
      _listEquals(other.entries, entries) &&
      other.authorable == authorable &&
      other.hasDocument == hasDocument;

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(entries), authorable, hasDocument);
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
