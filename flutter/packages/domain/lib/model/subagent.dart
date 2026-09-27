/// Subagent catalog vocabulary.
library;

/// How one catalog row's continuation is owned, as the parent Session's
/// `subagentCatalog` projection reports it: a `oneShot` run settles with its
/// answer and never accepts follow-ups, while a `continuable` child keeps its
/// prompt and interrupt verbs alive.
///
/// [unknown] is a child whose catalog event used a mode this client does not
/// recognize — 0.1.7 added the arm so a newer host's rows are retained rather
/// than dropped. It is not a synonym for either real mode: the address such a
/// row produces omits the mode, and the host resolves it when child history is
/// read. Every child-history read (`session/page` with a `subagent` address)
/// must carry a known mode or the host rejects it as `subagent/unauthorized`.
enum SubagentMode { oneShot, continuable, unknown }

final class SubagentEntry {
  const SubagentEntry({
    required this.id,
    this.mode,
    this.activity,
    this.hasChildren = false,
    this.label,
  });

  final String id;
  final SubagentMode? mode;
  final String? activity;

  /// Whether this child owns children of its own. A parent's projection lists
  /// direct children only and does not publish this fact, so the adapter
  /// derives it from [mode]: only a continuable child can host descendants.
  final bool hasChildren;
  final String? label;

  bool get isInterruptible =>
      mode == SubagentMode.continuable && activity == 'running';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SubagentEntry &&
          other.id == id &&
          other.mode == mode &&
          other.activity == activity &&
          other.hasChildren == hasChildren &&
          other.label == label);

  @override
  int get hashCode => Object.hash(id, mode, activity, hasChildren, label);
}

final class SubagentCatalog {
  const SubagentCatalog({
    this.parentSessionId = '',
    this.entries = const <SubagentEntry>[],
  });

  final String parentSessionId;
  final List<SubagentEntry> entries;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SubagentCatalog &&
          other.parentSessionId == parentSessionId &&
          _listEquals(other.entries, entries));

  @override
  int get hashCode => Object.hash(parentSessionId, Object.hashAll(entries));
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
