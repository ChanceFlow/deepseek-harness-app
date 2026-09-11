/// Durable workflow-run card — the mobile port of the reference
/// `WorkflowRunPanel`
/// (`reference/deepseek-harness/packages/client/ui-workflow-run/src/client/
/// WorkflowRunPanel.tsx`).
///
/// The reference renders a run header (name, member count, status dot) whose
/// disclosure opens a phase list; each phase is its own disclosure holding
/// its member rows, and a member whose running child session is an ordinary
/// subagent of the open session opens that child's transcript. This card
/// keeps the same tree and the same status vocabulary, with two phone
/// decisions: a phase's members render inline under their phase header
/// (Material [ExpansionTile]) instead of a second custom disclosure, and a
/// fan-out run opens its phases collapsed so a 40-member run is one screen
/// line until asked. The run's own disclosure carries the reference's
/// status-driven default only in the sense that a finished, clean run opens
/// closed; the card never force-opens, because a phone transcript cannot
/// afford a card that grows itself while the reader scrolls.
library;

import 'package:app/l10n/app_localizations.dart';
import 'package:domain/model/timeline_item.dart';
import 'package:flutter/material.dart';

import '../shared/state_dot.dart';
import '../theme/theme.dart';

/// Opens one workflow member's child transcript. Null when this surface has
/// no navigation seat (a read-only child record renders the card without it).
typedef WorkflowMemberOpener = void Function(WorkflowMember member);

/// One durable workflow run as a transcript card.
class WorkflowRunRow extends StatefulWidget {
  const WorkflowRunRow({
    required this.run,
    super.key,
    this.onOpenChild,
    this.initiallyExpanded = false,
  });

  final TimelineWorkflowRun run;

  /// Jump into one member's child session; null leaves member rows
  /// non-interactive.
  final WorkflowMemberOpener? onOpenChild;

  /// Whether the run's phase panel starts open. Collapsed by default: a
  /// fan-out run must not push the conversation down.
  final bool initiallyExpanded;

  @override
  State<WorkflowRunRow> createState() => _WorkflowRunRowState();
}

class _WorkflowRunRowState extends State<WorkflowRunRow> {
  late bool _expanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final run = widget.run;
    final memberCount = run.phases.fold<int>(
      0,
      (total, phase) => total + phase.members.length,
    );
    final statusLabel = workflowStatusLabel(run.status, l10n);
    // A run is never published without a status, so this label is always a
    // real one — `interrupted` included, which is the projected state of a
    // turn that closed before the run's terminal event arrived.
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(kShapeCard),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  StateDot(state: workflowStatusDot(run.status), size: 12),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      run.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        height: 1.2,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '· ${l10n.workflowMemberCount(memberCount)} · '
                      '$statusLabel',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        height: 1.2,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Icon(
                    _expanded ? Icons.expand_more : Icons.chevron_right,
                    size: 18,
                    color: scheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            Container(
              height: 1,
              color: scheme.outlineVariant.withValues(alpha: 0.4),
            ),
            if (run.phases.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                child: Text(
                  l10n.workflowRunEmpty,
                  style: theme.textTheme.bodySmall?.copyWith(
                    height: 1.2,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              )
            else
              Theme(
                // Phases are a plain grouping, not a second card: the
                // ExpansionTile dividers are the only chrome the panel
                // needs, and Material's default phase divider is the
                // hairline this surface already uses.
                data: theme.copyWith(dividerColor: scheme.outlineVariant),
                child: Column(
                  children: [
                    for (final phase in run.phases)
                      _PhaseSection(
                        phase: phase,
                        onOpenChild: widget.onOpenChild,
                      ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// One phase group: its header carries the phase name, the member count and
/// the status roll-up; its body holds the member rows.
class _PhaseSection extends StatelessWidget {
  const _PhaseSection({required this.phase, required this.onOpenChild});

  final WorkflowPhase phase;
  final WorkflowMemberOpener? onOpenChild;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;
    return ExpansionTile(
      // The phase key is collision-free across the absent field and the
      // empty string (`workflowPhaseKey`), so it is the row's identity.
      key: ValueKey('workflow-phase:${phase.key}'),
      shape: const Border(),
      collapsedShape: const Border(),
      tilePadding: const EdgeInsets.symmetric(horizontal: 10),
      childrenPadding: const EdgeInsets.only(bottom: 4),
      dense: true,
      visualDensity: VisualDensity.compact,
      title: Text(
        workflowPhaseLabel(phase.phase, l10n),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall?.copyWith(
          height: 1.2,
          fontWeight: FontWeight.w600,
          color: scheme.onSurface,
        ),
      ),
      subtitle: Text(
        '${l10n.workflowMemberCount(phase.members.length)}'
        ' · ${workflowPhaseStatusSummary(phase.members, l10n)}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.labelSmall?.copyWith(
          height: 1.2,
          color: scheme.onSurfaceVariant,
        ),
      ),
      children: [
        for (final member in phase.members)
          _MemberRow(member: member, onOpenChild: onOpenChild),
      ],
    );
  }
}

/// One member row: state dot, label, status. Tappable exactly when the
/// surface supplied an opener — a member whose child transcript this client
/// cannot address stays a plain row rather than a seat that fails.
class _MemberRow extends StatelessWidget {
  const _MemberRow({required this.member, required this.onOpenChild});

  final WorkflowMember member;
  final WorkflowMemberOpener? onOpenChild;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final label = member.label.isEmpty
        ? l10n.workflowMemberEmpty
        : member.label;
    final opener = onOpenChild;
    final row = Padding(
      padding: const EdgeInsets.fromLTRB(18, 3, 10, 3),
      child: Row(
        children: [
          StateDot(state: workflowStatusDot(member.status), size: 10),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                height: 1.2,
                color: scheme.onSurface,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            workflowStatusLabel(member.status, l10n),
            style: theme.textTheme.labelSmall?.copyWith(
              height: 1.2,
              color: scheme.onSurfaceVariant,
            ),
          ),
          if (opener != null) ...[
            const SizedBox(width: 4),
            Icon(Icons.chevron_right, size: 16, color: scheme.onSurfaceVariant),
          ],
        ],
      ),
    );
    if (opener == null) return row;
    return Semantics(
      button: true,
      label: l10n.workflowMemberOpen(label),
      child: InkWell(onTap: () => opener(member), child: row),
    );
  }
}

/// The dot a run, phase or member status wears — the reference
/// `dotState` mapping: running is ongoing, completed is done, failed is
/// error, and cancelled/interrupted are the warning state (waiting on a
/// decision that never came, not a failure).
StateDotState workflowStatusDot(WorkflowRunStatus status) => switch (status) {
  WorkflowRunStatus.running => StateDotState.ongoing,
  WorkflowRunStatus.completed => StateDotState.done,
  WorkflowRunStatus.failed => StateDotState.error,
  WorkflowRunStatus.cancelled => StateDotState.warning,
  WorkflowRunStatus.interrupted => StateDotState.warning,
};

/// Localized status label (the reference `status.*` dictionary).
String workflowStatusLabel(WorkflowRunStatus status, AppLocalizations l10n) =>
    switch (status) {
      WorkflowRunStatus.running => l10n.workflowStatusRunning,
      WorkflowRunStatus.completed => l10n.workflowStatusCompleted,
      WorkflowRunStatus.failed => l10n.workflowStatusFailed,
      WorkflowRunStatus.cancelled => l10n.workflowStatusCancelled,
      WorkflowRunStatus.interrupted => l10n.workflowStatusInterrupted,
    };

/// Readable phase name: an omitted phase is a distinct identity from an
/// empty one (the reference `phase.unassigned` / `phase.empty`).
String workflowPhaseLabel(String? phase, AppLocalizations l10n) => phase == null
    ? l10n.workflowPhaseUnassigned
    : phase.isEmpty
    ? l10n.workflowPhaseEmpty
    : phase;

/// The reference `phaseStatusSummary`: completed only when nothing else is
/// active, otherwise every non-completed status in the fixed
/// running/failed/cancelled/interrupted order, with completed prepended when
/// an interruption coexists with finished members.
String workflowPhaseStatusSummary(
  List<WorkflowMember> members,
  AppLocalizations l10n,
) {
  final counts = <WorkflowRunStatus, int>{};
  for (final member in members) {
    counts[member.status] = (counts[member.status] ?? 0) + 1;
  }
  int count(WorkflowRunStatus status) => counts[status] ?? 0;
  const activeOrder = <WorkflowRunStatus>[
    WorkflowRunStatus.running,
    WorkflowRunStatus.failed,
    WorkflowRunStatus.cancelled,
    WorkflowRunStatus.interrupted,
  ];
  final active = activeOrder.where((status) => count(status) > 0).toList();
  if (active.isEmpty) {
    return _countLabel(WorkflowRunStatus.completed, count, l10n);
  }
  final visible =
      active.contains(WorkflowRunStatus.interrupted) &&
          count(WorkflowRunStatus.completed) > 0
      ? <WorkflowRunStatus>[WorkflowRunStatus.completed, ...active]
      : active;
  return visible.map((status) => _countLabel(status, count, l10n)).join(' · ');
}

String _countLabel(
  WorkflowRunStatus status,
  int Function(WorkflowRunStatus) count,
  AppLocalizations l10n,
) => switch (status) {
  WorkflowRunStatus.running => l10n.workflowStatusCountRunning(count(status)),
  WorkflowRunStatus.completed => l10n.workflowStatusCountCompleted(
    count(status),
  ),
  WorkflowRunStatus.failed => l10n.workflowStatusCountFailed(count(status)),
  WorkflowRunStatus.cancelled => l10n.workflowStatusCountCancelled(
    count(status),
  ),
  WorkflowRunStatus.interrupted => l10n.workflowStatusCountInterrupted(
    count(status),
  ),
};
