/// Session-archive vocabulary: the running work a Host refusal names, and the
/// refusal that carries it (dsh `workspace/session-active`).
library;

/// Activity families a session-archive refusal may report. The owning
/// surface renders one line per family, naming the items that will stop.
///
/// The host's family set is open — each provider merges its own key from the
/// module both its host and client faces import — so a family this program
/// did not compile reads as [other] with the wire spelling kept in
/// [SessionActivityEntry.rawKind] for a generic description.
enum SessionActivityKind { turn, subagent, job, schedule, other }

/// One active item of a family that carries per-item identity: a session id
/// (subagent), a job id, or a schedule id.
final class SessionActivityItem {
  const SessionActivityItem({required this.id, this.label});

  /// Family-specific identity.
  final String id;

  /// Display label when the family carries one (a job label, a subagent
  /// label); null when the family has none to give.
  final String? label;

  /// The name a caller shows for this item: the label, else the id.
  String get displayName => label ?? id;
}

/// One family's running work for a session: its kind and, for a family with
/// per-item identity, the items themselves. [items] is empty for a family
/// without per-item identity (the turn family).
final class SessionActivityEntry {
  const SessionActivityEntry({
    required this.kind,
    required this.rawKind,
    this.items = const <SessionActivityItem>[],
  });

  /// The compiled family, or [SessionActivityKind.other] for a family this
  /// client does not know.
  final SessionActivityKind kind;

  /// The durable family key as the host spelled it; the generic line names
  /// it when [kind] is [SessionActivityKind.other].
  final String rawKind;

  /// Active items of the family; empty for a family without per-item
  /// identity.
  final List<SessionActivityItem> items;
}

/// The Host refused to archive a session because it still has running work
/// (dsh `workspace/session-active`): the archive was not written and
/// [activity] names what must stop first. Confirming the stop-and-archive
/// path asks the Host to stop that work and archive in one call; the stopped
/// work never resumes on its own.
final class SessionArchiveRefused implements Exception {
  const SessionArchiveRefused({
    required this.sessionId,
    required this.activity,
  });

  /// The session the refusal is about.
  final String sessionId;

  /// Running work the Host reported, in the order the host's providers
  /// contributed it.
  final List<SessionActivityEntry> activity;

  @override
  String toString() =>
      'SessionArchiveRefused($sessionId, '
      '${activity.map((entry) => entry.rawKind).join(', ')})';
}
