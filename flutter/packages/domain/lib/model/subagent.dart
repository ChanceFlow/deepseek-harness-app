/// Subagent catalog vocabulary.
library;

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
  final String? mode;
  final String? activity;
  final bool hasChildren;
  final String? label;
  final String? reason;

  bool get isInterruptible =>
      kind == 'child' && mode == 'continuable' && activity == 'running';

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
  int get hashCode => Object.hash(
        parentSessionId,
        Object.hashAll(entries),
        parentAvailable,
      );
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
