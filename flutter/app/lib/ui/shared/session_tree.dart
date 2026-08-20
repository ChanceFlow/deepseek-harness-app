/// Shared session-tree derivation and rows — the web ui-workspace
/// `tree.ts` + `Rows.tsx` port consumed by both browsing surfaces (the
/// chat sidebar and the Workspaces tab): session visibility, workspace
/// grouping with the Ungrouped bucket, active-session pinning, recency
/// ordering, the compact relative-time label, and the session,
/// overflow, and search-result row widgets.
library;

import 'package:app/l10n/app_localizations.dart';
import 'package:domain/model/session.dart';
import 'package:domain/model/workspace.dart';
import 'package:flutter/material.dart';

import '../theme/deepsuite_extension.dart' show dsOf;
import '../theme/deepsuite_tokens.dart' show DeepSuiteStatic;

/// Web tree.ts `COLLAPSED_SESSION_LIMIT`: session rows visible per
/// workspace before the local overflow control.
const int kCollapsedSessionLimit = 5;

/// Web tree.ts `UNGROUPED_KEY`: the bucket key for sessions outside
/// every workspace account.
const String kUngroupedKey = '__ungrouped__';

/// Web tree.ts `subagentOrigin`: children of subagent sessions never
/// surface in the browsing surfaces.
const String _subagentOrigin = 'subagent';

/// Web tree.ts `GroupNode` facts the surfaces render: group key, display
/// label, and the member rows.
final class SessionGroupData {
  const SessionGroupData({
    required this.key,
    required this.label,
    required this.sessions,
  });

  /// Workspace id, or [kUngroupedKey] for the Ungrouped bucket.
  final String key;
  final String label;
  final List<SessionSummary> sessions;
}

/// Web tree.ts `sessionVisible`: subagent children never surface, and a
/// blank placeholder renders only while it is the selected session.
bool sessionVisible(SessionSummary session, String? selectedSessionId) =>
    session.origin != _subagentOrigin &&
    (!session.blank || session.id == selectedSessionId);

/// Web tree.ts `byRecency`: newest update first, session id as the
/// deterministic tiebreak.
List<SessionSummary> sortedByRecency(Iterable<SessionSummary> sessions) {
  final ordered = sessions.toList()
    ..sort((a, b) {
      final delta = b.updatedAtEpochMs - a.updatedAtEpochMs;
      if (delta != 0) return delta;
      return a.id.compareTo(b.id);
    });
  return ordered;
}

/// The sidebar's priority window: sessions updated within the last 24
/// hours form the "recently active" tier (below running and pending
/// interaction, above everything older).
const int kRecentWindowMs = 24 * 60 * 60 * 1000;

/// Priority tier for the sidebar's activity sort: running sessions first,
/// then sessions waiting on the user (pending interaction), then sessions
/// active within [kRecentWindowMs], then everything older. Lower ranks
/// first.
int sessionPriorityTier(
  SessionSummary session,
  int nowEpochMs,
) {
  if (session.running) return 0;
  if (session.pendingInteraction != null) return 1;
  if (nowEpochMs - session.updatedAtEpochMs <= kRecentWindowMs) return 2;
  return 3;
}

/// Orders a group's members for the sidebar: the selected session rides
/// the top (the current session must never hide behind a fold — the
/// [withActiveSessionPinned] invariant), then the priority tiers
/// (running > pending interaction > recent-24h > rest), recency within
/// each tier.
List<SessionSummary> priorityOrderedMembers(
  List<SessionSummary> members,
  String? selectedSessionId,
  int nowEpochMs,
) {
  final pinned = <SessionSummary>[];
  final rest = <SessionSummary>[];
  for (final member in members) {
    if (member.id == selectedSessionId) {
      pinned.add(member);
    } else {
      rest.add(member);
    }
  }
  rest.sort((a, b) {
    final byTier = sessionPriorityTier(a, nowEpochMs)
        .compareTo(sessionPriorityTier(b, nowEpochMs));
    if (byTier != 0) return byTier;
    final byRecency = b.updatedAtEpochMs.compareTo(a.updatedAtEpochMs);
    if (byRecency != 0) return byRecency;
    return a.id.compareTo(b.id);
  });
  return <SessionSummary>[...pinned, ...rest];
}

/// Same-group pinning: the active session rides first, so the row the
/// user is most likely to reach stays above the fold even past the
/// collapsed-session overflow limit.
List<SessionSummary> withActiveSessionPinned(
  List<SessionSummary> members,
  String? selectedSessionId,
) {
  if (selectedSessionId == null) return members;
  for (var i = 0; i < members.length; i++) {
    if (members[i].id == selectedSessionId) {
      if (i == 0) return members;
      return <SessionSummary>[
        members[i],
        ...members.sublist(0, i),
        ...members.sublist(i + 1),
      ];
    }
  }
  return members;
}

/// Web tree.ts `groupByWorkspace`: one group per workspace entity in
/// stable host order, members resolved from `sessionIds` in their
/// stored order; sessions outside every account trail in the
/// browser-local Ungrouped bucket by recency.
///
/// Members are [priorityOrderedMembers] when [priorityOrder] is set (the
/// sidebar's activity focus: selected, running, pending interaction,
/// recent-24h, then recency); otherwise the stored account order wins
/// (the Workspaces management tab). The Ungrouped bucket is added only
/// when it has members; workspace groups are added for every entity
/// unless [includeEmptyGroups] is false (the switching surface drops
/// groups with nothing visible).
List<SessionGroupData> deriveSessionGroups(
  List<SessionSummary> sessions,
  List<WorkspaceSummary> workspaces,
  String? selectedSessionId,
  AppLocalizations l10n, {
  int nowEpochMs = 0,
  bool includeEmptyGroups = true,
  bool priorityOrder = false,
}) {
  final sessionsById = <String, SessionSummary>{
    for (final session in sessions) session.id: session,
  };
  final accounted = <String>{};
  final groups = <SessionGroupData>[];
  for (final workspace in workspaces) {
    final members = <SessionSummary>[];
    for (final id in workspace.sessionIds) {
      final summary = sessionsById[id];
      // The account may lead the list pull; the row appears when the
      // summary lands (web rule).
      if (summary == null) continue;
      accounted.add(id);
      if (!sessionVisible(summary, selectedSessionId)) continue;
      members.add(summary);
    }
    if (!includeEmptyGroups && members.isEmpty) continue;
    groups.add(
      SessionGroupData(
        key: workspace.workspaceId,
        label: workspace.title,
        sessions: priorityOrder
            ? priorityOrderedMembers(members, selectedSessionId, nowEpochMs)
            : withActiveSessionPinned(members, selectedSessionId),
      ),
    );
  }
  final ungrouped = sortedByRecency(
    sessions.where(
      (session) =>
          !accounted.contains(session.id) &&
          sessionVisible(session, selectedSessionId),
    ),
  );
  if (ungrouped.isNotEmpty) {
    groups.add(
      SessionGroupData(
        key: kUngroupedKey,
        label: l10n.ungroupedLabel,
        sessions: priorityOrder
            ? priorityOrderedMembers(ungrouped, selectedSessionId, nowEpochMs)
            : withActiveSessionPinned(ungrouped, selectedSessionId),
      ),
    );
  }
  return groups;
}

/// The group key holding the selected session (the current group), or
/// null without one — the web `containsCurrent` derivation fact.
String? currentGroupKeyOf(
  List<SessionSummary> sessions,
  List<WorkspaceSummary> workspaces,
  String? selectedSessionId,
) {
  if (selectedSessionId == null) return null;
  SessionSummary? selected;
  for (final session in sessions) {
    if (session.id == selectedSessionId) {
      selected = session;
      break;
    }
  }
  if (selected == null) return null;
  for (final workspace in workspaces) {
    if (workspace.sessionIds.contains(selected.id)) {
      return workspace.workspaceId;
    }
  }
  return kUngroupedKey;
}

/// Web tree.ts `workspaceLabel`: the cwd basename, or the Ungrouped
/// label when there is no path to name.
String cwdBasename(String? cwd, AppLocalizations l10n) {
  if (cwd == null || cwd.isEmpty) return l10n.ungroupedLabel;
  final segments = cwd.split(RegExp(r'[/\\]+'));
  for (final segment in segments.reversed) {
    if (segment.isNotEmpty) return segment;
  }
  return cwd;
}

/// Web tree.ts `relativeTime` plus the dictionary: the compact trailing
/// label for session rows ("now"/"5min"/"3h"/"2d"/"4mo"/"1y").
String relativeTimeLabel(
  int updatedAtEpochMs,
  int nowEpochMs,
  AppLocalizations l10n,
) {
  const minuteMs = 60 * 1000;
  const hourMs = 60 * minuteMs;
  const dayMs = 24 * hourMs;
  final diff = nowEpochMs - updatedAtEpochMs;
  final elapsed = diff < 0 ? 0 : diff;
  return switch (elapsed) {
    < minuteMs => l10n.relativeTimeNow,
    < hourMs => l10n.relativeTimeMinutes(elapsed ~/ minuteMs),
    < dayMs => l10n.relativeTimeHours(elapsed ~/ hourMs),
    < 30 * dayMs => l10n.relativeTimeDays(elapsed ~/ dayMs),
    < 365 * dayMs => l10n.relativeTimeMonths(elapsed ~/ (30 * dayMs)),
    _ => l10n.relativeTimeYears(elapsed ~/ (365 * dayMs)),
  };
}

/// Web Rows.tsx `SessionNodeItem` (mobile form): a 44px touch row with
/// the status dot slot, the title, and the compact relative time; the
/// selected row keeps the sidebar nav-item treatment (active fill +
/// accent edge). A trailing ellipsis menu with the session verbs
/// (archive) renders when [onArchive] is provided — the Workspaces tab
/// wires it, the switching sidebar does not.
class SessionTreeRow extends StatelessWidget {
  const SessionTreeRow({
    super.key,
    required this.session,
    required this.selected,
    required this.nowEpochMs,
    this.onSelect,
    this.onArchive,
  });

  final SessionSummary session;
  final bool selected;
  final int nowEpochMs;
  final VoidCallback? onSelect;

  /// Archive-this-session action; present makes the row's ellipsis menu
  /// visible (blank provisional rows carry no verbs, web rule).
  final VoidCallback? onArchive;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final ds = dsOf(context);
    final theme = Theme.of(context);
    // Web `displayTitle`: blank rows show the New Session label.
    final title = session.blank ? l10n.newSession : session.displayTitle;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: selected ? ds.sidebarNavItemActive : null,
        borderRadius: BorderRadius.circular(8),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        hoverColor: ds.sidebarNavItemHover,
        onTap: onSelect,
        child: IntrinsicHeight(
          child: Row(
            children: [
              if (selected)
                VerticalDivider(
                  thickness: 3,
                  width: 3,
                  color: ds.sidebarNavItemActiveAccent,
                ),
              Expanded(
                child: SizedBox(
                  height: 44,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 8, right: 4),
                    child: Row(
                      children: [
                        // Web `.slot`: the fixed status seat keeps titles
                        // aligned whether or not a dot shows.
                        SizedBox(
                          width: 16,
                          child: SessionStatusDot(session: session),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                        // Web rule: a blank provisional row carries no
                        // timestamp — nothing has happened in it yet.
                        if (!session.blank) ...[
                          const SizedBox(width: 6),
                          Text(
                            relativeTimeLabel(
                              session.updatedAtEpochMs,
                              nowEpochMs,
                              l10n,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontSize: 12,
                              color: ds.labelTertiary,
                            ),
                          ),
                        ],
                        // Web row menu (rename/fork/archive): present on
                        // the management surface, always-visible for
                        // touch (the Workspaces tab's idiom).
                        if (onArchive != null && !session.blank) ...[
                          const SizedBox(width: 4),
                          _RowArchiveButton(
                            session: session,
                            onArchive: onArchive!,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Web SessionNodeItem "⋮" menu — mobile form: an always-visible
/// ellipsis seat that opens a menu-surface bottom sheet with the session
/// verbs. Archive is the management surface's verb (the switching
/// sidebar wires none).
class _RowArchiveButton extends StatelessWidget {
  const _RowArchiveButton({
    required this.session,
    required this.onArchive,
  });

  final SessionSummary session;
  final VoidCallback onArchive;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final ds = dsOf(context);
    return SizedBox(
      width: 32,
      height: 44,
      child: Tooltip(
        message: l10n.archiveSession,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            hoverColor: ds.interactiveBgHover,
            onTap: onArchive,
            child: Center(
              child: Icon(
                Icons.archive_outlined,
                size: 16,
                color: ds.labelTertiary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Web Rows.tsx `sessionStatuses` + StateDot (mobile form): the session
/// row's status dot. Pending user interaction (approval / plan-review /
/// question) outranks everything and renders the amber warning dot;
/// running renders the blue ongoing dot; otherwise the green done dot
/// (web always shows a dot, idle included).
class SessionStatusDot extends StatelessWidget {
  const SessionStatusDot({super.key, required this.session});

  final SessionSummary session;

  @override
  Widget build(BuildContext context) {
    if (session.pendingInteraction != null) {
      return const WarningDot(size: 10);
    }
    if (session.running) {
      return const RunningDot(size: 10);
    }
    return const DoneDot(size: 10);
  }
}

/// Web StateDot 'done' (static form): success-primary halo plus solid
/// core, the green idle/completed indicator.
class DoneDot extends StatelessWidget {
  const DoneDot({super.key, this.size = 10});

  final double size;

  @override
  Widget build(BuildContext context) {
    final color = dsOf(context).stateSuccessPrimary;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
          ),
          Center(
            child: Container(
              width: size * 0.6,
              height: size * 0.6,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Web StateDot 'warning' (static form): warn-primary halo plus solid
/// core, the amber "needs the user" indicator (approval / plan-review /
/// question).
class WarningDot extends StatelessWidget {
  const WarningDot({super.key, this.size = 10});

  final double size;

  @override
  Widget build(BuildContext context) {
    final color = dsOf(context).warnPrimary;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
          ),
          Center(
            child: Container(
              width: size * 0.6,
              height: size * 0.6,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Web WorkspaceBrowser `.sessionOverflowButton`: the local overflow
/// control under a group (28px on the web, a 44px touch row here),
/// aligned under the session titles.
class SessionOverflowRow extends StatelessWidget {
  const SessionOverflowRow({
    super.key,
    required this.expanded,
    required this.totalCount,
    required this.onTap,
  });

  final bool expanded;
  final int totalCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final ds = dsOf(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: SizedBox(
          height: 44,
          child: Padding(
            padding: const EdgeInsets.only(left: 28),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                expanded ? l10n.showLess : l10n.showAll(totalCount),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(fontSize: 12, color: ds.labelTertiary),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Web Rows.tsx `SearchResultItem` (mobile form): a two-line result — the
/// title with its status slot, then the workspace label and the content
/// snippet at 12px; the selected row keeps the sidebar nav-item treatment.
class SessionSearchResultRow extends StatelessWidget {
  const SessionSearchResultRow({
    super.key,
    required this.session,
    required this.snippet,
    required this.workspaceLabel,
    required this.selected,
    required this.onSelect,
  });

  final SessionSummary session;
  final String snippet;
  final String workspaceLabel;
  final bool selected;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final ds = dsOf(context);
    final theme = Theme.of(context);
    final title = session.blank ? l10n.newSession : session.displayTitle;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: selected ? ds.sidebarNavItemActive : null,
        borderRadius: BorderRadius.circular(8),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        hoverColor: ds.sidebarNavItemHover,
        onTap: onSelect,
        child: IntrinsicHeight(
          child: Row(
            children: [
              if (selected)
                VerticalDivider(
                  thickness: 3,
                  width: 3,
                  color: ds.sidebarNavItemActiveAccent,
                ),
              Expanded(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            SizedBox(
                              width: 16,
                              child: session.running
                                  ? const RunningDot(size: 8)
                                  : null,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium,
                              ),
                            ),
                          ],
                        ),
                        // Web `.searchResultMeta`: workspace context then
                        // the content excerpt, both single-line.
                        Padding(
                          padding: const EdgeInsets.only(left: 20),
                          child: Row(
                            children: [
                              Flexible(
                                flex: 2,
                                child: Text(
                                  workspaceLabel,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    fontSize: 12,
                                    color: ds.labelTertiary,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                flex: 3,
                                child: Text(
                                  snippet,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    fontSize: 12,
                                    color: ds.labelSecondary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Web StateDot 'ongoing' (static form): deepseek-450 halo plus solid
/// core, the blue running indicator on session rows.
class RunningDot extends StatelessWidget {
  const RunningDot({super.key, this.size = 10});

  final double size;

  @override
  Widget build(BuildContext context) {
    const color = DeepSuiteStatic.deepseek450;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
          ),
          Center(
            child: Container(
              width: size * 0.6,
              height: size * 0.6,
              decoration: const BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
