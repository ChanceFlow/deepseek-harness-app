/// Shared session-tree derivation and rows — the web ui-workspace
/// `tree.ts` + `Rows.tsx` port consumed by both browsing surfaces (the
/// chat sidebar and the Workspaces tab): session visibility, workspace
/// grouping with the Ungrouped bucket, active-session pinning, recency
/// ordering, the compact relative-time label, and the session,
/// overflow, and search-result row widgets.
library;

import 'dart:async';

import 'package:app/l10n/app_localizations.dart';
import 'package:domain/model/session.dart';
import 'package:domain/model/workspace.dart';
import 'package:flutter/material.dart';

import '../theme/theme.dart';
import 'state_dot.dart';

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
int sessionPriorityTier(SessionSummary session, int nowEpochMs) {
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
    final byTier = sessionPriorityTier(
      a,
      nowEpochMs,
    ).compareTo(sessionPriorityTier(b, nowEpochMs));
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
/// the status dot slot, the title, and the compact relative time — now a
/// native [ListTile] carrying the sidebar nav-item treatment (active
/// fill on selection, hover fill) plus the M3 ripple, focus, and
/// selection semantics. Long-pressing a non-blank row opens the
/// session-verb menu (web SessionNodeItem ⋮: rename / fork / archive)
/// when any verb is provided — both the switching sidebar and the
/// Workspaces tab wire the verbs that belong to their surface. The
/// management surface (Workspaces tab) additionally renders an
/// always-visible ellipsis seat via [showVerbButton], keeping the verbs
/// discoverable for touch.
class SessionTreeRow extends StatelessWidget {
  const SessionTreeRow({
    required this.session,
    required this.selected,
    required this.nowEpochMs,
    super.key,
    this.onSelect,
    this.onRename,
    this.onFork,
    this.onArchive,
    this.showVerbButton = false,
  });

  final SessionSummary session;
  final bool selected;
  final int nowEpochMs;
  final VoidCallback? onSelect;

  /// Web SessionNodeItem row verbs; present verbs appear in the
  /// long-press menu (blank provisional rows carry no verbs, web rule).
  final VoidCallback? onRename;
  final VoidCallback? onFork;
  final VoidCallback? onArchive;

  /// Renders the always-visible ellipsis seat beside the timestamp when
  /// the row carries verbs (the Workspaces tab's touch idiom; the
  /// switching sidebar keeps the long-press-only form).
  final bool showVerbButton;

  bool get _hasVerbs => onRename != null || onFork != null || onArchive != null;

  void _openMenu(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final items = <(IconData, String, VoidCallback)>[
      if (onRename != null)
        (Icons.edit_outlined, l10n.renameSession, onRename!),
      if (onFork != null)
        (Icons.call_split_outlined, l10n.forkSession, onFork!),
      if (onArchive != null)
        (Icons.archive_outlined, l10n.archiveSession, onArchive!),
    ];
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (_) => _SessionVerbsSheet(
          title: session.blank ? l10n.newSession : session.displayTitle,
          items: items,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // Web `displayTitle`: blank rows show the New Session label.
    final title = session.blank ? l10n.newSession : session.displayTitle;
    final hasVerbs = !session.blank && _hasVerbs;
    return ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      minTileHeight: 44,
      // Web `.slot`: the fixed 16px status seat keeps titles aligned
      // whether or not a dot shows; the narrow leading keeps the compact
      // row density instead of the M3 40px minimum.
      minLeadingWidth: 16,
      horizontalTitleGap: 4,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      selected: selected,
      tileColor: Colors.transparent,
      // The web sidebar nav-item active fill (the 3px accent edge is a
      // web-only chrome the native tile drops; fill-only selection,
      // matching the timeline-native adoption).
      selectedTileColor: scheme.secondaryContainer,
      hoverColor: scheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      leading: SizedBox(width: 16, child: SessionStatusDot(session: session)),
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        // The body scale is set for transcript prose; a one-line row takes
        // the same size on a tighter leading.
        style: theme.textTheme.bodyMedium?.copyWith(height: 1.2),
      ),
      // Web rule: a blank provisional row carries no timestamp — nothing
      // has happened in it yet — so its trailing seat stays empty.
      trailing: session.blank
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  relativeTimeLabel(session.updatedAtEpochMs, nowEpochMs, l10n),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                // The management surface's always-visible verbs seat
                // (web ⋮): present only when the row carries verbs and
                // [showVerbButton] is set — the same menu the long-press
                // opens.
                if (showVerbButton && hasVerbs) ...[
                  const SizedBox(width: 4),
                  _SessionVerbButton(
                    session: session,
                    onTap: () => _openMenu(context),
                  ),
                ],
              ],
            ),
      onTap: onSelect,
      onLongPress: hasVerbs ? () => _openMenu(context) : null,
    );
  }
}

/// Web SessionNodeItem "⋮" seat — mobile form: an always-visible
/// ellipsis [IconButton] that opens the session-verbs menu on tap.
class _SessionVerbButton extends StatelessWidget {
  const _SessionVerbButton({required this.session, required this.onTap});

  final SessionSummary session;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    return IconButton(
      tooltip: l10n.sessionActionsFor(session.displayTitle),
      onPressed: onTap,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints.tightFor(width: 32, height: 32),
      padding: EdgeInsets.zero,
      icon: Icon(Icons.more_horiz, size: 18, color: scheme.onSurfaceVariant),
    );
  }
}

/// Web Menu (figma MenuDropdown) as a bottom sheet for the session-verb
/// menu: the same menu surface as the workspace action sheet — the shared
/// [kShapeMenuSheet] card, inverted hairline, lv3 shadow — with the row's
/// title as a caption and one row per provided verb.
class _SessionVerbsSheet extends StatelessWidget {
  const _SessionVerbsSheet({required this.title, required this.items});

  final String title;
  final List<(IconData, String, VoidCallback)> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: scheme.surfaceContainer,
          borderRadius: BorderRadius.circular(kShapeMenuSheet),
          border: Border.all(color: scheme.outlineVariant),
          boxShadow: kM3ShadowElevation3,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            for (final (icon, label, onTap) in items)
              _VerbRow(icon: icon, label: label, onTap: onTap),
          ],
        ),
      ),
    );
  }
}

/// Web Menu `.item`: min-h 44, r10, 14px label, 16px tertiary leading
/// glyph — now a native [ListTile]; tapping pops the sheet and runs the
/// verb. The transparent [Material] gives the tile an ink host (the sheet
/// card behind it is a decorated container).
class _VerbRow extends StatelessWidget {
  const _VerbRow({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: Colors.transparent,
      child: ListTile(
        dense: true,
        visualDensity: VisualDensity.compact,
        minTileHeight: 44,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10),
        leading: Icon(icon, size: 18, color: scheme.onSurfaceVariant),
        title: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(fontSize: 14),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        onTap: () {
          Navigator.of(context).pop();
          onTap();
        },
      ),
    );
  }
}

/// Web Rows.tsx `sessionStatuses` + StateDot (mobile form): the session
/// row's status dot. Pending user interaction (approval / plan-review /
/// question) outranks everything and renders the amber warning dot;
/// running renders the blue ongoing dot; a finished-but-unviewed session
/// (`completed`) renders the green done dot; idle renders nothing (the
/// web's `showStatus` is false for an idle row — the status seat stays
/// empty).
class SessionStatusDot extends StatelessWidget {
  const SessionStatusDot({required this.session, super.key});

  final SessionSummary session;

  @override
  Widget build(BuildContext context) {
    if (session.pendingInteraction != null) {
      return const WarningDot(size: 10);
    }
    if (session.running) {
      return const RunningDot(size: 10);
    }
    if (session.completed) {
      return const DoneDot(size: 10);
    }
    // Idle: the web shows no dot (slot reserved for alignment).
    return const SizedBox(width: 10, height: 10);
  }
}

/// Web StateDot 'done': the named seat for the green completed indicator
/// on session rows; the geometry and colors live in the shared [StateDot].
class DoneDot extends StatelessWidget {
  const DoneDot({super.key, this.size = 10});

  final double size;

  @override
  Widget build(BuildContext context) =>
      StateDot(state: StateDotState.done, size: size);
}

/// Web StateDot 'warning': the named seat for the "needs the user"
/// indicator (approval / plan-review / question) on session rows; the
/// geometry and colors live in the shared [StateDot].
class WarningDot extends StatelessWidget {
  const WarningDot({super.key, this.size = 10});

  final double size;

  @override
  Widget build(BuildContext context) =>
      StateDot(state: StateDotState.warning, size: size);
}

/// Web WorkspaceBrowser `.sessionOverflowButton`: the local overflow
/// control under a group (28px on the web, a 44px touch row here) —
/// now a native [TextButton] styled to the tertiary label, aligned
/// under the session titles.
class SessionOverflowRow extends StatelessWidget {
  const SessionOverflowRow({
    required this.expanded,
    required this.totalCount,
    required this.onTap,
    super.key,
  });

  final bool expanded;
  final int totalCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(left: 28),
        child: TextButton(
          onPressed: onTap,
          style: TextButton.styleFrom(
            foregroundColor: scheme.onSurfaceVariant,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            minimumSize: const Size(0, 44),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
            textStyle: Theme.of(context).textTheme.bodySmall
                ?.copyWith(fontSize: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: Text(
            expanded ? l10n.showLess : l10n.showAll(totalCount),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}

/// Web Rows.tsx `SearchResultItem` (mobile form): a two-line result — the
/// title with its status slot, then the workspace label and the content
/// snippet at 12px — now a native two-line [ListTile]; the selected row
/// keeps the sidebar nav-item treatment.
class SessionSearchResultRow extends StatelessWidget {
  const SessionSearchResultRow({
    required this.session,
    required this.snippet,
    required this.workspaceLabel,
    required this.selected,
    required this.onSelect,
    super.key,
  });

  final SessionSummary session;
  final String snippet;
  final String workspaceLabel;
  final bool selected;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final title = session.blank ? l10n.newSession : session.displayTitle;
    return ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      minTileHeight: 48,
      minLeadingWidth: 16,
      horizontalTitleGap: 4,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      selected: selected,
      tileColor: Colors.transparent,
      selectedTileColor: scheme.secondaryContainer,
      hoverColor: scheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      leading: SizedBox(
        width: 16,
        // Web `SearchResultItem` runs the same `sessionStatuses` state
        // machine as the main session row: pending interaction is the
        // amber warning dot, running the blue ongoing dot, a finished
        // session the green done dot, idle stays empty.
        child: SessionStatusDot(session: session),
      ),
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        // The body scale is set for transcript prose; a one-line row takes
        // the same size on a tighter leading.
        style: theme.textTheme.bodyMedium?.copyWith(height: 1.2),
      ),
      // Web `.searchResultMeta`: the workspace context then the content
      // excerpt; the native subtitle auto-indents under the title, which
      // is the web's `left: 20` inset.
      subtitle: Row(
        children: [
          Flexible(
            flex: 2,
            child: Text(
              workspaceLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 12,
                color: scheme.onSurfaceVariant,
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
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
      onTap: onSelect,
    );
  }
}

/// Web StateDot 'ongoing': the named seat for the blue running indicator
/// on session rows; the geometry and colors live in the shared [StateDot].
class RunningDot extends StatelessWidget {
  const RunningDot({super.key, this.size = 10});

  final double size;

  @override
  Widget build(BuildContext context) =>
      StateDot(state: StateDotState.ongoing, size: size);
}
