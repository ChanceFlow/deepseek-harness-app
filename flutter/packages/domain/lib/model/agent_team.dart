/// Agent-team vocabulary: the Lead Session's `agentTeam` projection, its
/// durable roster, and its shared task board.
///
/// Wire shapes come from
/// `reference/deepseek-harness/packages/experimental/agent-team/src/types.ts`
/// (`TeamProjection`, `TeamMemberProjection`, `TeamTaskView`) and reach this
/// client as a Session projection — there is no Team RPC namespace.
library;

/// Durable teammate lifecycle (`TeamMemberPhase`).
enum TeamMemberPhase { provisioning, active, failed }

/// Durable task lifecycle; a `deleted` row never reaches a projection.
enum TeamTaskStatus { pending, inProgress, completed, deleted }

/// What the roster shows for one member.
///
/// [TeamMemberPhase] is durable only: an `active` member may or may not be
/// inside a turn right now, and that bit comes from live Session status. The
/// reference derives the same four states for its roster rows.
enum TeamMemberActivity { running, inactive, provisioning, failed }

/// One durable roster row (`TeamMemberProjection`).
///
/// The Lead row is synthesized by the projection itself
/// (`name: 'lead'`, `role: lead`, `phase: active`), never by this client.
final class TeamMember {
  const TeamMember({
    required this.id,
    required this.name,
    required this.isLead,
    required this.phase,
    this.error,
  });

  final String id;
  final String name;
  final bool isLead;
  final TeamMemberPhase phase;

  /// The projection's first rejected persisted record for this member.
  final String? error;

  /// The activity to show, given the member's live running bit.
  ///
  /// A provisioning or failed member keeps its durable phase; an active one
  /// reads `running` from the roster, with `null` meaning the roster does not
  /// know that Session and the member reads inactive.
  TeamMemberActivity activity({required bool? running}) => switch (phase) {
    TeamMemberPhase.provisioning => TeamMemberActivity.provisioning,
    TeamMemberPhase.failed => TeamMemberActivity.failed,
    TeamMemberPhase.active =>
      running == true
          ? TeamMemberActivity.running
          : TeamMemberActivity.inactive,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TeamMember &&
          other.id == id &&
          other.name == name &&
          other.isLead == isLead &&
          other.phase == phase &&
          other.error == error);

  @override
  int get hashCode => Object.hash(id, name, isLead, phase, error);
}

/// One row of the shared task board (`TeamTaskView`).
///
/// [ready] is computed host-side as "pending with every blocker completed";
/// [writeScopeWarnings] names the in-progress tasks whose write scopes overlap
/// this one's.
final class TeamTask {
  const TeamTask({
    required this.id,
    required this.revision,
    required this.subject,
    required this.description,
    required this.status,
    this.blockedBy = const <String>[],
    this.writeScopes = const <String>[],
    this.ownerName,
    this.ready = false,
    this.writeScopeWarnings = const <String>[],
  });

  final String id;
  final int revision;
  final String subject;
  final String description;
  final TeamTaskStatus status;
  final List<String> blockedBy;
  final List<String> writeScopes;

  /// The owner's display name; absent for an unowned task.
  final String? ownerName;

  /// True only for a pending task whose blockers are all completed.
  final bool ready;

  final List<String> writeScopeWarnings;

  /// Whether the board labels this pending task ready rather than blocked.
  bool get isReady => status == TeamTaskStatus.pending && ready;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TeamTask &&
          other.id == id &&
          other.revision == revision &&
          other.subject == subject &&
          other.description == description &&
          other.status == status &&
          _listEquals(other.blockedBy, blockedBy) &&
          _listEquals(other.writeScopes, writeScopes) &&
          other.ownerName == ownerName &&
          other.ready == ready &&
          _listEquals(other.writeScopeWarnings, writeScopeWarnings));

  @override
  int get hashCode => Object.hash(
    id,
    revision,
    subject,
    description,
    status,
    Object.hashAll(blockedBy),
    Object.hashAll(writeScopes),
    ownerName,
    ready,
    Object.hashAll(writeScopeWarnings),
  );
}

/// The Lead Session's durable team state (`TeamProjection`).
///
/// [tasks] never carries `deleted` rows — the host filters its tombstones
/// before publishing. A non-null [failure] is terminal: the host keeps the
/// last valid roster and board and stops applying records, so a surface shows
/// that failure above them rather than presenting them as current.
final class AgentTeam {
  const AgentTeam({
    this.members = const <TeamMember>[],
    this.tasks = const <TeamTask>[],
    this.failure,
  });

  final List<TeamMember> members;
  final List<TeamTask> tasks;
  final String? failure;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AgentTeam &&
          _listEquals(other.members, members) &&
          _listEquals(other.tasks, tasks) &&
          other.failure == failure);

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(members), Object.hashAll(tasks), failure);
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
