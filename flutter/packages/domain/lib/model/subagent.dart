/// Subagent catalog vocabulary.
library;

/// How one catalog row's continuation is owned, as reported by the host
/// (`subagent.list` `mode`): a `oneShot` run settles with its answer and
/// never accepts follow-ups, while a `continuable` child keeps its prompt
/// and interrupt verbs alive while the parent is available. The adapter
/// maps the wire literals; every `subagent.history` request must carry the
/// addressed row's own mode or the host rejects it as
/// `subagent-not-found`.
enum SubagentMode { oneShot, continuable }

final class SubagentEntry {
  const SubagentEntry({
    required this.id,
    required this.kind,
    this.mode,
    this.activity,
    this.hasChildren = false,
    this.label,
    this.reason,
  });

  final String id;
  final String kind;
  final SubagentMode? mode;
  final String? activity;
  final bool hasChildren;
  final String? label;
  final String? reason;

  bool get isInterruptible =>
      kind == 'child' &&
      mode == SubagentMode.continuable &&
      activity == 'running';

  @override
  bool operator ==(Object other) =>
      other is SubagentEntry &&
      other.id == id &&
      other.kind == kind &&
      other.mode == mode &&
      other.activity == activity &&
      other.hasChildren == hasChildren &&
      other.label == label &&
      other.reason == reason;

  @override
  int get hashCode =>
      Object.hash(id, kind, mode, activity, hasChildren, label, reason);
}

final class SubagentCatalog {
  const SubagentCatalog({
    this.parentSessionId = '',
    this.entries = const <SubagentEntry>[],
    this.parentAvailable = false,
  });

  final String parentSessionId;
  final List<SubagentEntry> entries;
  final bool parentAvailable;

  @override
  bool operator ==(Object other) =>
      other is SubagentCatalog &&
      other.parentSessionId == parentSessionId &&
      _listEquals(other.entries, entries) &&
      other.parentAvailable == parentAvailable;

  @override
  int get hashCode =>
      Object.hash(parentSessionId, Object.hashAll(entries), parentAvailable);
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
