/// Agent-Team panel — the Lead session's roster and shared task board,
/// rendered from its `agentTeam` projection.
///
/// Port of the reference `client-ui-agent-team` panel
/// (`reference/deepseek-harness/packages/experimental/client-ui-agent-team/
/// src/client/TeamAction.tsx`), which is read-only: agents create and update
/// tasks through their own tools, and the surface only shows them. Member
/// activity is derived here because the projection carries durable phases
/// only: an `active` member's running bit comes from live Session status.
library;

import 'package:app/l10n/app_localizations.dart';
import 'package:app/ui/shared/state_dot.dart';
import 'package:domain/model/agent_team.dart';
import 'package:flutter/material.dart';

import '../theme/theme.dart';

/// The activity a roster row shows, localized.
String teamActivityLabel(TeamMemberActivity activity, AppLocalizations l10n) =>
    switch (activity) {
      TeamMemberActivity.running => l10n.teamMemberRunning,
      TeamMemberActivity.inactive => l10n.teamMemberInactive,
      TeamMemberActivity.provisioning => l10n.teamMemberProvisioning,
      TeamMemberActivity.failed => l10n.teamMemberFailed,
    };

/// The board's status label. A `deleted` tombstone never reaches a projection,
/// so it reads as its last durable state rather than a sixth label.
String teamTaskStatusLabel(TeamTaskStatus status, AppLocalizations l10n) =>
    switch (status) {
      TeamTaskStatus.pending => l10n.teamTaskPending,
      TeamTaskStatus.inProgress => l10n.teamTaskInProgress,
      TeamTaskStatus.completed => l10n.teamTaskCompleted,
      TeamTaskStatus.deleted => l10n.teamTaskCompleted,
    };

/// A member's row dot: running and provisioning are in flight, a failure is an
/// error, and an inactive member carries the person glyph instead of a dot.
StateDotState? teamMemberDot(TeamMemberActivity activity) => switch (activity) {
  TeamMemberActivity.running => StateDotState.ongoing,
  TeamMemberActivity.provisioning => StateDotState.ongoing,
  TeamMemberActivity.failed => StateDotState.error,
  TeamMemberActivity.inactive => null,
};

/// A task's row dot: pending reads as ready (neutral) or blocked (warning),
/// in-progress is ongoing, and a completed task is done.
StateDotState teamTaskDot(TeamTask task) => switch (task.status) {
  TeamTaskStatus.pending =>
    task.isReady ? StateDotState.disabled : StateDotState.warning,
  TeamTaskStatus.inProgress => StateDotState.ongoing,
  TeamTaskStatus.completed => StateDotState.done,
  TeamTaskStatus.deleted => StateDotState.disabled,
};

/// The Lead session's Team, read-only.
class TeamPanel extends StatelessWidget {
  const TeamPanel({
    required this.team,
    required this.currentSessionId,
    required this.leadSessionId,
    required this.runningBySession,
    required this.onOpenMember,
    super.key,
  });

  final AgentTeam team;

  /// The session the panel was opened from: its own row is tagged and inert.
  final String currentSessionId;

  /// The Team's Lead session; selecting it opens that session directly.
  final String leadSessionId;

  /// Live running bit per member Session id; a session the roster does not
  /// know is absent, which reads inactive.
  final Map<String, bool> runningBySession;

  /// Opens one member's conversation. The Lead is a session id; a teammate is
  /// the addressed child of [leadSessionId].
  final void Function(TeamMember member) onOpenMember;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 560),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 4, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.teamPanelTitle,
                        style: theme.textTheme.titleSmall,
                      ),
                    ),
                    IconButton(
                      tooltip: l10n.close,
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    if (team.failure case final failure?)
                      _FailureBanner(message: failure),
                    _SectionHeading(
                      title: l10n.teamRosterHeading,
                      count: team.members.length,
                      showCount: team.members.length > 1,
                    ),
                    for (final member in team.members)
                      _MemberRow(
                        member: member,
                        running: runningBySession[member.id],
                        isCurrent: member.id == currentSessionId,
                        showCurrentTag: team.members.length > 1,
                        onOpen: () => onOpenMember(member),
                      ),
                    _SectionHeading(
                      title: l10n.teamTasksHeading,
                      count: team.tasks.length,
                      showCount: true,
                    ),
                    if (team.tasks.isEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                        child: Text(
                          l10n.teamTaskBoardEmpty,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      )
                    else
                      for (final task in team.tasks) _TaskCard(task: task),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({
    required this.title,
    required this.count,
    required this.showCount,
  });

  final String title;
  final int count;
  final bool showCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Row(
        children: [
          Text(title, style: theme.textTheme.titleSmall),
          if (showCount) ...[
            const SizedBox(width: 8),
            Text(
              '$count',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _FailureBanner extends StatelessWidget {
  const _FailureBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(kShapeCard),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: StateDot(state: StateDotState.error, size: 8),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              l10n.teamFailure(message),
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onErrorContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({
    required this.member,
    required this.running,
    required this.isCurrent,
    required this.showCurrentTag,
    required this.onOpen,
  });

  final TeamMember member;
  final bool? running;
  final bool isCurrent;
  final bool showCurrentTag;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final activity = member.activity(running: running);
    final dot = teamMemberDot(activity);
    // The current conversation, a failed member, and one still provisioning
    // have no conversation to open.
    final openable =
        !isCurrent &&
        activity != TeamMemberActivity.failed &&
        activity != TeamMemberActivity.provisioning;
    return ListTile(
      dense: true,
      leading: SizedBox(
        width: 24,
        child: Center(
          child: dot == null
              ? Icon(Icons.person_outline, size: 18, color: scheme.outline)
              : StateDot(state: dot, size: 8),
        ),
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              member.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium,
            ),
          ),
          if (isCurrent && showCurrentTag) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: scheme.secondaryContainer,
                borderRadius: BorderRadius.circular(kShapeChip),
              ),
              child: Text(
                l10n.teamCurrentChat,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSecondaryContainer,
                ),
              ),
            ),
          ],
        ],
      ),
      subtitle: Text(
        member.error == null
            ? teamActivityLabel(activity, l10n)
            : '${teamActivityLabel(activity, l10n)} · ${member.error}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall?.copyWith(
          color: activity == TeamMemberActivity.failed
              ? scheme.error
              : scheme.onSurfaceVariant,
        ),
      ),
      trailing: openable
          ? IconButton(
              tooltip: l10n.teamOpenMember,
              iconSize: 18,
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.open_in_new),
              onPressed: onOpen,
            )
          : null,
    );
  }
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({required this.task});

  final TeamTask task;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(kShapeCard),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: StateDot(state: teamTaskDot(task), size: 8),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  task.subject,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                teamTaskStatusLabel(task.status, l10n),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          if (task.description.isNotEmpty)
            _ClampedDescription(text: task.description),
          const SizedBox(height: 4),
          Text(
            l10n.teamTaskOwner(task.ownerName ?? l10n.teamTaskUnowned),
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          if (task.status == TeamTaskStatus.pending)
            Text(
              task.isReady ? l10n.teamTaskReady : l10n.teamTaskBlocked,
              style: theme.textTheme.bodySmall?.copyWith(
                color: task.isReady ? scheme.onSurfaceVariant : scheme.warning,
              ),
            ),
          if (task.blockedBy.isNotEmpty)
            Text(
              l10n.teamTaskBlockedBy(task.blockedBy.join(', ')),
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          if (task.writeScopes.isNotEmpty)
            Text(
              l10n.teamTaskWriteScopes(task.writeScopes.join(', ')),
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          for (final warning in task.writeScopeWarnings)
            Text(
              warning,
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.warning),
            ),
        ],
      ),
    );
  }
}

/// Two-line description with an expand toggle that appears only when the text
/// actually exceeds the clamp — the reference measures its clamped rows the
/// same way instead of showing a dead control.
class _ClampedDescription extends StatefulWidget {
  const _ClampedDescription({required this.text});

  final String text;

  @override
  State<_ClampedDescription> createState() => _ClampedDescriptionState();
}

class _ClampedDescriptionState extends State<_ClampedDescription> {
  static const int _clampLines = 2;

  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final style = theme.textTheme.bodySmall;
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: widget.text, style: style),
          maxLines: _clampLines,
          textDirection: Directionality.of(context),
        )..layout(maxWidth: constraints.maxWidth);
        final clamped = painter.didExceedMaxLines;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.text,
              maxLines: _expanded ? null : _clampLines,
              overflow: _expanded ? null : TextOverflow.ellipsis,
              style: style,
            ),
            if (clamped)
              TextButton(
                onPressed: () => setState(() => _expanded = !_expanded),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  _expanded ? l10n.teamTaskShowLess : l10n.teamTaskShowMore,
                  style: theme.textTheme.labelSmall,
                ),
              ),
          ],
        );
      },
    );
  }
}
