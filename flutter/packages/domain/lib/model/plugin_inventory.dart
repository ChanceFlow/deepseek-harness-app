/// Read-only plugin-inventory vocabulary.
///
/// `pluginInventory/list` projects the Cordis Loader's current non-group
/// entries and, when an agent-preset roster is composed, each preset's
/// flattened composition. Wire truth:
/// `reference/deepseek-harness/packages/host/plugin-inventory/src/types.ts`.
library;

/// Lifecycle state of an entry's root fiber; null when it has no live root
/// fiber.
enum PluginFiberPhase { pending, loading, active, failed, unloading }

/// Effective enablement of one preset composition row.
enum PresetRowEnablement {
  enabled,
  disabled,

  /// A `!!js` disabled expression on a composition no session has mounted;
  /// only a Loader context can decide it.
  conditional,
}

/// One non-group Loader entry.
final class PluginInventoryEntry {
  const PluginInventoryEntry({
    required this.entryId,
    required this.moduleName,
    required this.enabled,
    this.fiberPhase,
  });

  /// Stable Loader-tree identity.
  final String entryId;

  /// Exact module specifier imported by the Loader entry.
  final String moduleName;

  /// Effective Loader enablement, including disabled ancestor groups.
  final bool enabled;

  /// Root-fiber phase; null when the entry has no live root fiber.
  final PluginFiberPhase? fiberPhase;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PluginInventoryEntry &&
          other.entryId == entryId &&
          other.moduleName == moduleName &&
          other.enabled == enabled &&
          other.fiberPhase == fiberPhase);

  @override
  int get hashCode => Object.hash(entryId, moduleName, enabled, fiberPhase);
}

/// One plugin row an agent preset's composition names.
final class AgentPresetPluginRow {
  const AgentPresetPluginRow({
    required this.moduleName,
    required this.enabled,
    this.entryId,
    this.condition,
    this.fiberPhase,
  });

  /// Composition row id; null when the row declares none.
  final String? entryId;

  final String moduleName;
  final PresetRowEnablement enabled;

  /// The row's own `!!js` disabled expression, when it carries one.
  final String? condition;

  /// Root-fiber phase when the composition is live.
  final PluginFiberPhase? fiberPhase;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AgentPresetPluginRow &&
          other.entryId == entryId &&
          other.moduleName == moduleName &&
          other.enabled == enabled &&
          other.condition == condition &&
          other.fiberPhase == fiberPhase);

  @override
  int get hashCode =>
      Object.hash(entryId, moduleName, enabled, condition, fiberPhase);
}

/// One agent preset's identity and flattened composition.
final class AgentPresetPluginGroup {
  const AgentPresetPluginGroup({
    required this.id,
    required this.trust,
    required this.isDefault,
    required this.rows,
    this.name,
    this.broken,
  });

  final String id;

  /// `'system'` or `'user'`.
  final String trust;

  /// Display name the preset published; null means fall back to [id].
  final String? name;

  /// Whether a session naming no preset composes this one.
  final bool isDefault;

  /// Why this preset's composition cannot be read; null when rows answer.
  final String? broken;

  /// Plugin rows in composition order; empty when the preset is broken.
  final List<AgentPresetPluginRow> rows;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AgentPresetPluginGroup &&
          other.id == id &&
          other.trust == trust &&
          other.name == name &&
          other.isDefault == isDefault &&
          other.broken == broken &&
          _listEquals(other.rows, rows));

  @override
  int get hashCode =>
      Object.hash(id, trust, name, isDefault, broken, Object.hashAll(rows));
}

/// Point-in-time `pluginInventory/list` snapshot.
final class PluginInventorySnapshot {
  const PluginInventorySnapshot({
    required this.entries,
    this.agentPresets = const <AgentPresetPluginGroup>[],
  });

  /// Current non-group Loader entries, in Loader order.
  final List<PluginInventoryEntry> entries;

  /// Per-preset compositions; empty when no roster is composed (the wire
  /// omits the member entirely).
  final List<AgentPresetPluginGroup> agentPresets;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PluginInventorySnapshot &&
          _listEquals(other.entries, entries) &&
          _listEquals(other.agentPresets, agentPresets));

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(entries), Object.hashAll(agentPresets));
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
