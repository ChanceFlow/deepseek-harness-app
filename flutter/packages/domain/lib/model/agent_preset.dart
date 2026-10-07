/// Agent-preset roster vocabulary.
///
/// Mirrors the `agentPresets/list` response
/// (reference/deepseek-harness/packages/preset/agent-preset-registry/src/types.ts):
/// the roster a surface offers when composing a session's agent. Rows are
/// path-free and carry no trust signal — the host stopped publishing both the
/// per-row `trust` and the roster-level `authorable` when preset authoring
/// left the Remote surface, so a surface here can read and switch presets but
/// never manage them.
library;

/// One preset the deployment can compose a session's agent from.
final class AgentPresetEntry {
  const AgentPresetEntry({
    required this.id,
    this.isDefault = false,
    this.name,
    this.description,
    this.broken,
  });

  final String id;

  /// Whether a session that names no preset gets this one.
  final bool isDefault;

  /// Display name the preset published; null when it published none.
  /// Never a second identity — a surface falls back to [id].
  final String? name;

  /// One sentence on what the preset is for; null when unpublished.
  final String? description;

  /// Why this preset cannot compose a session; null when it can. A
  /// broken preset stays listed (its declaration still occupies the id)
  /// but offering it for selection would only defer this reason to a
  /// failed session start.
  final String? broken;

  /// Label a surface shows when the preset published no [name].
  String get displayName => name ?? id;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AgentPresetEntry &&
          other.id == id &&
          other.isDefault == isDefault &&
          other.name == name &&
          other.description == description &&
          other.broken == broken);

  @override
  int get hashCode => Object.hash(id, isDefault, name, description, broken);
}

/// The whole roster of one `agentPresets/list` response.
final class AgentPresetRoster {
  const AgentPresetRoster({this.entries = const <AgentPresetEntry>[]});

  /// Every preset the deployment supplies, in the host's own order
  /// (ordered by each declaration's `order`, then by id). An empty roster
  /// means the deployment composes no presets and every session shares
  /// the host composition.
  final List<AgentPresetEntry> entries;

  /// The entry a session naming no preset gets; null when the roster
  /// carries no default.
  AgentPresetEntry? get defaultEntry =>
      entries.where((entry) => entry.isDefault).firstOrNull;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AgentPresetRoster && _listEquals(other.entries, entries));

  @override
  int get hashCode => Object.hashAll(entries);
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// One preset's declared composition, rendered for reading
/// (`agentPresets/read` → the reference `AgentPresetDocument`).
///
/// [content] is the declared child-plugin list as entry-list YAML — the
/// Loader's own dialect, so `!!js` conditions read as declared rather than as
/// expression objects. This is a *view*: the roster [AgentPresetEntry] stays
/// the identity, and nothing here writes.
final class AgentPresetDocument {
  const AgentPresetDocument({
    required this.agentPreset,
    required this.content,
    this.name,
    this.description,
  });

  /// The preset this composition belongs to.
  final String agentPreset;

  /// The declared composition, as YAML text.
  final String content;

  /// Display name the preset published; null when it published none.
  final String? name;

  /// One sentence on what this preset is for; null when unpublished.
  final String? description;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AgentPresetDocument &&
          other.agentPreset == agentPreset &&
          other.content == content &&
          other.name == name &&
          other.description == description);

  @override
  int get hashCode => Object.hash(agentPreset, content, name, description);
}
