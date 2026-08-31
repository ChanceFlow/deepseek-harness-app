/// Subagents screen — mobile port of the web subagent surface.
///
/// Source of truth:
/// reference/deepseek-harness/packages/client/ui-subagent/src/client/
/// - `SubagentCatalogAction.tsx` — catalog tree rows: StateDot
///   (`activity === 'running' ? ongoing : done`), label (`label ?? id`),
///   secondary (`[title, mode, activity].join(' · ')`), expandable branches
///   (`hasChildren`), tap = openChild; diagnostic entries render disabled
///   with an error dot.
/// - `SubagentReadOnlyComposer.tsx` + `locales.ts` (EN) — the read-only
///   notice replacing the message field for one-shot records and
///   parent-offline children.
/// - `ui-conversation/src/client/queue/QueueDock.tsx` —
///   `queueMutable = subagent === null`: a child view renders its queue
///   without edit/steer/remove controls.
///
/// The child detail view renders through the real chat `TimelineRow`
/// (read-only usage: `onAction` no-ops, attachments resolve empty).
library;

import 'dart:typed_data';

import 'package:app/l10n/app_localizations.dart';
import 'package:domain/model/attachment.dart';
import 'package:domain/model/session.dart';
import 'package:domain/model/subagent.dart';
import 'package:domain/model/timeline_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../di/providers.dart';
import '../chat/activity_dot.dart';
import '../chat/chat_screen.dart' show PlanChip, TimelineRow, timelineKey;
import '../chat/sweep_highlight.dart';
import '../shared/state_dot.dart';
import '../theme/theme.dart';
import 'subagent_ui_state.dart';

/// Material's minimum touch-target height; every row on this screen rides
/// it as a [ListTile] `minTileHeight` (the same value the shared
/// session-tree rows wear).
const double _kRowMinHeight = 44;

/// Web catalog tree indentation: a 12px base inset plus 16px per level.
const double _kCatalogIndentBase = 12;
const double _kCatalogIndentStep = 16;

/// Web disclosure seat: the branch-toggle slot a leaf row reserves so
/// sibling labels stay aligned.
const double _kDisclosureWidth = 32;

/// Gap between a leading glyph (state dot, activity dot, queue icon) and
/// the row text — the web catalog/queue row spacing.
const double _kGlyphTextGap = 10;

/// The web `12 + 16 * level` catalog indent.
double _catalogIndent(int level) =>
    _kCatalogIndentBase + _kCatalogIndentStep * level;

class SubagentRoute extends ConsumerWidget {
  const SubagentRoute({super.key, this.backendId});

  /// The backend this surface presents; null uses the active backend.
  final String? backendId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resolved =
        backendId ?? ref.watch(activeBackendIdProvider).value ?? '';
    if (resolved.isEmpty) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final controller = ref.watch(subagentControllerProvider(resolved));
    return StreamBuilder<SubagentUiState>(
      stream: controller.uiState,
      initialData: controller.state,
      builder: (context, snapshot) {
        final uiState = snapshot.data ?? const SubagentUiState();
        return SubagentScreen(uiState: uiState, onAction: controller.onAction);
      },
    );
  }
}

class SubagentScreen extends StatefulWidget {
  const SubagentScreen({
    required this.uiState,
    required this.onAction,
    super.key,
  });

  final SubagentUiState uiState;
  final void Function(SubagentAction) onAction;

  @override
  State<SubagentScreen> createState() => _SubagentScreenState();
}

class _SubagentScreenState extends State<SubagentScreen> {
  /// Locally expanded branch ids (web `expanded` set); the branch catalog
  /// data itself is loaded by the controller.
  final Set<String> _expandedBranches = <String>{};

  @override
  void didUpdateWidget(covariant SubagentScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Branch expansion belongs to one parent's tree.
    if (oldWidget.uiState.selectedParentId != widget.uiState.selectedParentId) {
      _expandedBranches.clear();
    }
  }

  /// Web `toggleBranch`: expansion is local; expanding a node also asks
  /// the controller for that branch's catalog (`setCatalogOpen(id, true)`).
  void _toggleBranch(String childSessionId) {
    final wasExpanded = _expandedBranches.contains(childSessionId);
    setState(() {
      if (wasExpanded) {
        _expandedBranches.remove(childSessionId);
      } else {
        _expandedBranches.add(childSessionId);
      }
    });
    if (!wasExpanded) {
      widget.onAction(LoadSubagentBranch(childSessionId));
    }
  }

  Future<void> _openParentSheet() {
    final root = Navigator.of(context);
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      // Menu-surface sheet (MenuDropdown family — the model-select form):
      // menu fill, hairline, lv3 elevation, 4px inner padding. The shape
      // and height ceiling are the shared menu-sheet constants; the form
      // is the recorded house convention (2026-08-25 dropdown redesign),
      // so this surface keeps it verbatim.
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final scheme = Theme.of(sheetContext).colorScheme;
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
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: kMenuSheetMaxHeight),
              child: _ParentSessionSheet(
                sessions: widget.uiState.sessions,
                selectedParentId: widget.uiState.selectedParentId,
                onSelect: (sessionId) {
                  widget.onAction(SelectParent(sessionId));
                  root.pop();
                },
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final uiState = widget.uiState;
    final childId = uiState.selectedChildId;
    final childEntry = uiState.selectedChildEntry;
    return PopScope(
      // Android back closes the child record first; the catalog stays.
      canPop: childId == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) widget.onAction(const CloseChildView());
      },
      child: Scaffold(
        appBar: AppBar(
          leading: childId == null
              ? null
              : IconButton(
                  tooltip: l10n.back,
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => widget.onAction(const CloseChildView()),
                ),
          title: Text(
            childId == null
                ? l10n.subagentsTitle
                : childEntry?.label ?? childId,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            if (childId == null) ...[
              if (uiState.selectedParentId != null)
                IconButton(
                  tooltip: l10n.refresh,
                  icon: const Icon(Icons.refresh),
                  onPressed: () =>
                      widget.onAction(const RefreshSubagentsAction()),
                ),
            ] else if (childEntry?.isInterruptible ?? false)
              IconButton(
                tooltip: l10n.stopTooltip,
                icon: const Icon(Icons.stop_circle_outlined),
                onPressed: () => widget.onAction(
                  InterruptSubagent(
                    childId,
                    parentSessionId:
                        uiState.selectedChildCatalog?.parentSessionId ??
                        uiState.selectedChildParentId ??
                        uiState.selectedParentId,
                  ),
                ),
              ),
          ],
        ),
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (uiState.errorMessage case final message?)
                _ErrorBanner(
                  message: message,
                  onDismiss: () =>
                      widget.onAction(const DismissSubagentError()),
                ),
              Expanded(
                child: childId == null
                    ? _CatalogView(
                        uiState: uiState,
                        onAction: widget.onAction,
                        expandedBranches: _expandedBranches,
                        onToggleBranch: _toggleBranch,
                        onOpenParentSheet: _openParentSheet,
                      )
                    : _ChildDetailView(
                        uiState: uiState,
                        onAction: widget.onAction,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The parent selector + the subagent catalog tree.
class _CatalogView extends StatelessWidget {
  const _CatalogView({
    required this.uiState,
    required this.onAction,
    required this.expandedBranches,
    required this.onToggleBranch,
    required this.onOpenParentSheet,
  });

  final SubagentUiState uiState;
  final void Function(SubagentAction) onAction;
  final Set<String> expandedBranches;
  final void Function(String childSessionId) onToggleBranch;
  final VoidCallback onOpenParentSheet;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final selectedParent = uiState.sessions
        .where((session) => session.id == uiState.selectedParentId)
        .firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ParentSelectorRow(session: selectedParent, onTap: onOpenParentSheet),
        Expanded(
          child: switch (uiState.selectedParentId) {
            null => Center(
              child: Text(
                l10n.selectParentSession,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            _ when uiState.isLoading && uiState.catalog.entries.isEmpty =>
              const Center(child: CircularProgressIndicator()),
            _ when uiState.catalog.entries.isEmpty => Center(
              child: Text(
                l10n.noSubagents,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            _ => ListView(
              padding: const EdgeInsets.symmetric(vertical: 4),
              children: [
                _CatalogBranch(
                  catalog: uiState.catalog,
                  branchCatalogs: uiState.branchCatalogs,
                  branchFailures: uiState.branchFailures,
                  sessions: uiState.sessions,
                  expanded: expandedBranches,
                  level: 0,
                  onAction: onAction,
                  onToggleBranch: onToggleBranch,
                ),
              ],
            ),
          },
        ),
      ],
    );
  }
}

/// The selected parent session as a menu-surface trigger row (web
/// catalog trigger pill, mobile sheet form): a [ListTile] wearing the
/// caption over the resolved title, the running dot in its seat.
class _ParentSelectorRow extends StatelessWidget {
  const _ParentSelectorRow({required this.session, required this.onTap});

  final SessionSummary? session;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final selected = session;
    final title = selected == null
        ? l10n.selectParentSession
        : selected.blank
        ? l10n.newSession
        : selected.displayTitle;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        dense: true,
        visualDensity: VisualDensity.compact,
        minTileHeight: _kRowMinHeight,
        minLeadingWidth: 16,
        horizontalTitleGap: 8,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: _kCatalogIndentBase,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(kShapeChip),
        ),
        onTap: onTap,
        leading: SizedBox(
          width: 16,
          child: selected?.running ?? false
              ? const StateDot(state: StateDotState.ongoing, size: 8)
              : null,
        ),
        title: Text(
          l10n.parentSession,
          style: theme.textTheme.labelSmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        subtitle: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(
            height: 1.2,
            color: selected == null ? scheme.onSurfaceVariant : null,
          ),
        ),
        trailing: Icon(
          Icons.expand_more,
          size: 18,
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// Parent picker body (menu-surface sheet): 44px session rows.
class _ParentSessionSheet extends StatelessWidget {
  const _ParentSessionSheet({
    required this.sessions,
    required this.selectedParentId,
    required this.onSelect,
  });

  final List<SessionSummary> sessions;
  final String? selectedParentId;
  final void Function(String sessionId) onSelect;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    // The sheet card is a decorated container; a transparent Material
    // gives the ListTiles their ink host (the session-verbs sheet's
    // idiom).
    return SafeArea(
      child: Material(
        color: Colors.transparent,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
              child: Text(
                l10n.parentSession,
                style: theme.textTheme.titleSmall,
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final session in sessions)
                    _ParentSessionRow(
                      session: session,
                      selected: session.id == selectedParentId,
                      onSelect: () => onSelect(session.id),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One parent option in the picker sheet: a [ListTile] with the running
/// dot seat, the title, and the check affordance on the selected row.
class _ParentSessionRow extends StatelessWidget {
  const _ParentSessionRow({
    required this.session,
    required this.selected,
    required this.onSelect,
  });

  final SessionSummary session;
  final bool selected;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      minTileHeight: _kRowMinHeight,
      minLeadingWidth: 16,
      horizontalTitleGap: 8,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: _kCatalogIndentBase,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kShapeChip),
      ),
      onTap: onSelect,
      leading: SizedBox(
        width: 16,
        child: session.running
            ? const StateDot(state: StateDotState.ongoing, size: 8)
            : null,
      ),
      title: Text(
        session.blank ? l10n.newSession : session.displayTitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        // The body scale is set for transcript prose; a one-line row
        // takes the same size on a tighter leading.
        style: theme.textTheme.bodyMedium?.copyWith(height: 1.2),
      ),
      trailing: selected
          ? Icon(Icons.check, size: 16, color: scheme.onSurfaceVariant)
          : null,
    );
  }
}

/// One catalog level of the subagent tree (web `CatalogRows`), recursing
/// only through explicitly expanded rows.
class _CatalogBranch extends StatelessWidget {
  const _CatalogBranch({
    required this.catalog,
    required this.branchCatalogs,
    required this.branchFailures,
    required this.sessions,
    required this.expanded,
    required this.level,
    required this.onAction,
    required this.onToggleBranch,
  });

  final SubagentCatalog catalog;
  final Map<String, SubagentCatalog> branchCatalogs;
  final Set<String> branchFailures;
  final List<SessionSummary> sessions;
  final Set<String> expanded;
  final int level;
  final void Function(SubagentAction) onAction;
  final void Function(String childSessionId) onToggleBranch;

  @override
  Widget build(BuildContext context) {
    // Web reserveDisclosure: leaf rows keep the disclosure seat when any
    // sibling has a branch so labels stay aligned.
    final reserveDisclosure = catalog.entries.any(
      (entry) => entry.kind != 'diagnostic' && entry.hasChildren,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final entry in catalog.entries)
          if (entry.kind == 'diagnostic')
            _DiagnosticEntryRow(
              key: ValueKey(
                'diagnostic-${catalog.parentSessionId}-${entry.id}',
              ),
              entry: entry,
              level: level,
              reserveDisclosure: reserveDisclosure,
            )
          else ...[
            _CatalogEntryRow(
              key: ValueKey('catalog-${catalog.parentSessionId}-${entry.id}'),
              entry: entry,
              summary: sessions
                  .where((session) => session.id == entry.id)
                  .firstOrNull,
              level: level,
              expanded: expanded.contains(entry.id),
              reserveDisclosure: reserveDisclosure,
              onOpen: () {
                // A child opens under its own catalog mode:
                // `subagent.history` is host-guarded against a mode
                // mismatch (`subagent-not-found`). The adapter decodes
                // child rows with a required mode, so only a row lacking
                // one — impossible past fail-loud decode — stays closed.
                final mode = entry.mode;
                if (mode != null) {
                  onAction(
                    OpenChild(
                      entry.id,
                      mode,
                      parentSessionId: catalog.parentSessionId,
                    ),
                  );
                }
              },
              onToggleBranch: entry.hasChildren
                  ? () => onToggleBranch(entry.id)
                  : null,
            ),
            if (entry.hasChildren && expanded.contains(entry.id))
              _branchBody(context, entry),
          ],
      ],
    );
  }

  /// Web expanded `<div role="group">`: the branch's own catalog, its
  /// loading placeholder, or its error + retry.
  Widget _branchBody(BuildContext context, SubagentEntry entry) {
    if (branchFailures.contains(entry.id)) {
      return _BranchErrorRow(
        level: level + 1,
        onRetry: () => onAction(LoadSubagentBranch(entry.id)),
      );
    }
    final branchCatalog = branchCatalogs[entry.id];
    if (branchCatalog == null) {
      return _BranchLoadingRow(level: level + 1);
    }
    return _CatalogBranch(
      catalog: branchCatalog,
      branchCatalogs: branchCatalogs,
      branchFailures: branchFailures,
      sessions: sessions,
      expanded: expanded,
      level: level + 1,
      onAction: onAction,
      onToggleBranch: onToggleBranch,
    );
  }
}

/// One child catalog row (web treeitem): StateDot, label, secondary line;
/// tap opens the child detail view. A [ListTile]; the branch toggle is a
/// separate ink seat inside the leading row, and the expanded state shows
/// as the icon swap (right → down chevron) rather than a bespoke
/// rotation curve.
class _CatalogEntryRow extends StatelessWidget {
  const _CatalogEntryRow({
    required this.entry,
    required this.summary,
    required this.level,
    required this.expanded,
    required this.reserveDisclosure,
    required this.onOpen,
    required this.onToggleBranch,
    super.key,
  });

  final SubagentEntry entry;
  final SessionSummary? summary;
  final int level;
  final bool expanded;
  final bool reserveDisclosure;
  final VoidCallback onOpen;
  final VoidCallback? onToggleBranch;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final label = entry.label ?? entry.id;
    final secondary = _secondaryLine(entry, summary, l10n);
    return Padding(
      padding: EdgeInsets.only(left: _catalogIndent(level)),
      child: ListTile(
        dense: true,
        visualDensity: VisualDensity.compact,
        minTileHeight: _kRowMinHeight,
        minLeadingWidth: 0,
        horizontalTitleGap: _kGlyphTextGap,
        contentPadding: const EdgeInsets.only(right: _kCatalogIndentBase),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(kShapeChip),
        ),
        onTap: onOpen,
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (entry.hasChildren)
              SizedBox(
                width: _kDisclosureWidth,
                child: InkWell(
                  borderRadius: BorderRadius.circular(kShapeChip),
                  onTap: onToggleBranch,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      expanded ? Icons.expand_more : Icons.chevron_right,
                      size: 18,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              )
            else if (reserveDisclosure)
              const SizedBox(width: _kDisclosureWidth),
            StateDot(
              state: entry.activity == 'running'
                  ? StateDotState.ongoing
                  : StateDotState.done,
              size: 8,
            ),
          ],
        ),
        title: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          // The body scale is set for transcript prose; a one-line row
          // takes the same size on a tighter leading.
          style: theme.textTheme.bodyMedium?.copyWith(height: 1.2),
        ),
        subtitle: secondary.isEmpty
            ? null
            : Text(
                secondary,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  height: 1.2,
                  color: scheme.onSurfaceVariant,
                ),
              ),
      ),
    );
  }
}

/// Diagnostic catalog entry (web `entry.kind === 'diagnostic'`): disabled
/// row with the error dot and the reason as its only summary. A [ListTile]
/// without a tap handler, wrapped in the disabled semantics the web tree
/// row carries.
class _DiagnosticEntryRow extends StatelessWidget {
  const _DiagnosticEntryRow({
    required this.entry,
    required this.level,
    required this.reserveDisclosure,
    super.key,
  });

  final SubagentEntry entry;
  final int level;
  final bool reserveDisclosure;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final reason = _diagnosticReasonLabel(entry.reason, l10n);
    return Padding(
      padding: EdgeInsets.only(left: _catalogIndent(level)),
      child: Semantics(
        enabled: false,
        child: ListTile(
          dense: true,
          visualDensity: VisualDensity.compact,
          minTileHeight: _kRowMinHeight,
          minLeadingWidth: 0,
          horizontalTitleGap: _kGlyphTextGap,
          contentPadding: const EdgeInsets.only(right: _kCatalogIndentBase),
          leading: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (reserveDisclosure) const SizedBox(width: _kDisclosureWidth),
              const StateDot(state: StateDotState.error, size: 8),
            ],
          ),
          title: Text(
            entry.id,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              height: 1.2,
              color: scheme.onSurfaceVariant,
            ),
          ),
          subtitle: reason == null
              ? null
              : Text(
                  reason,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    height: 1.2,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
        ),
      ),
    );
  }
}

/// Web `CatalogLoadingRows` placeholder: 'Loading subagents…' in the
/// timeline's in-flight language — [ActivityDot] in the leading slot with
/// the shared [SweepHighlight] glare over the row text, not an inline
/// spinner ([the sweep-only note](../../../../../.agents/notes/implemented/bug-fix/2026-08-29-timeline-inflight-sweep-only.md));
/// reduce-motion passes the null controller like the timeline callers.
class _BranchLoadingRow extends StatefulWidget {
  const _BranchLoadingRow({required this.level});

  final int level;

  @override
  State<_BranchLoadingRow> createState() => _BranchLoadingRowState();
}

class _BranchLoadingRowState extends State<_BranchLoadingRow>
    with SingleTickerProviderStateMixin {
  /// The timeline rows' sweep period (2600 ms, [ToolCallRow] parity).
  static const Duration _kSweepPeriod = Duration(milliseconds: 2600);

  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: _kSweepPeriod,
  );

  @override
  void initState() {
    super.initState();
    // The row exists only while the branch catalog is in flight.
    _sweep.repeat();
  }

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: EdgeInsets.only(left: _catalogIndent(widget.level)),
      child: ListTile(
        dense: true,
        visualDensity: VisualDensity.compact,
        minTileHeight: _kRowMinHeight,
        minLeadingWidth: 0,
        horizontalTitleGap: _kGlyphTextGap,
        contentPadding: const EdgeInsets.only(right: _kCatalogIndentBase),
        leading: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(width: _kDisclosureWidth),
            ActivityDot(),
          ],
        ),
        title: ClipRect(
          child: SweepHighlight(
            controller: MediaQuery.disableAnimationsOf(context) ? null : _sweep,
            child: Text(
              l10n.loadingSubagents,
              style: theme.textTheme.bodySmall?.copyWith(
                height: 1.2,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Web catalog `state === 'error'` row: message + Retry, as a [ListTile]
/// with the retry verb in the trailing seat.
class _BranchErrorRow extends StatelessWidget {
  const _BranchErrorRow({required this.level, required this.onRetry});

  final int level;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(left: _catalogIndent(level)),
      child: ListTile(
        dense: true,
        visualDensity: VisualDensity.compact,
        minTileHeight: _kRowMinHeight,
        minLeadingWidth: 0,
        horizontalTitleGap: _kGlyphTextGap,
        contentPadding: const EdgeInsets.only(right: 4),
        leading: const SizedBox(width: _kDisclosureWidth),
        title: Text(
          l10n.unableToLoadSubagents,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            height: 1.2,
            color: theme.colorScheme.error,
          ),
        ),
        trailing: TextButton(onPressed: onRetry, child: Text(l10n.retry)),
      ),
    );
  }
}

/// The child conversation record (web `openChild` target): real chat
/// timeline rows, the read-only plan chip, read-only queued messages, and
/// — only for continuable children with the parent online — the message
/// field.
class _ChildDetailView extends StatelessWidget {
  const _ChildDetailView({required this.uiState, required this.onAction});

  final SubagentUiState uiState;
  final void Function(SubagentAction) onAction;

  @override
  Widget build(BuildContext context) {
    final rows = uiState.childTimelineRows;
    final queueItems = uiState.childQueueItems;
    final childId = uiState.selectedChildId!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: uiState.isChildLoading && rows.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  itemCount: rows.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final item = rows[index];
                    return TimelineRow(
                      key: ValueKey(timelineKey(item)),
                      item: item,
                      // Read-only record view: interactive seats (approval
                      // answers, question replies, queue edits) no-op.
                      onAction: (_) {},
                      loadAttachment: _noChildAttachment,
                    );
                  },
                ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Web composer plan seat, read-only form: the warn pill
              // renders only while the child targets plan mode and its
              // tap stays disabled.
              PlanChip(plan: uiState.childPlan, onExit: () {}, locked: true),
              if (queueItems.isNotEmpty) ...[
                _ReadOnlyQueueDock(items: queueItems),
                const SizedBox(height: 4),
              ],
              if (uiState.childReadOnlyReason case final reason?)
                _ReadOnlyComposerNotice(reason: reason)
              else
                _ChildComposerBar(
                  key: ValueKey('child-composer-$childId'),
                  enabled: !uiState.isSendingChild,
                  isSending: uiState.isSendingChild,
                  onSend: (text) => onAction(SendSubagentPrompt(text)),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Read-only queue dock for the child record — the app QueueDock's
/// container language (tip fill, r12 top corners, l1 border) with plain
/// preview rows only: on a child view `queueMutable` is false, so no
/// edit/steer/remove controls exist. The corner value mirrors the chat
/// `QueueDock` verbatim (a deliberate port of
/// [the queue-dock note](../../../../../.agents/notes/implemented/feature/2026-08-19-queue-dock-tab-persistent-draft.md)
/// — divergence here would read as a broken seam above the composer);
/// sharing the widget itself would reach into `chat/` and is recorded as
/// a follow-up.
class _ReadOnlyQueueDock extends StatelessWidget {
  const _ReadOnlyQueueDock({required this.items});

  final List<SessionQueueItem> items;

  /// The chat QueueDock's top corner, mirrored so the read-only dock
  /// seams exactly under where the composer card would sit.
  static const double _kTopRadius = 12;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(_kTopRadius),
        ),
        border: Border(
          top: BorderSide(color: scheme.outlineVariant),
          left: BorderSide(color: scheme.outlineVariant),
          right: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final item in items)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
              child: Row(
                children: [
                  Icon(Icons.queue, size: 14, color: scheme.onSurfaceVariant),
                  const SizedBox(width: _kGlyphTextGap),
                  Expanded(
                    child: Text(
                      item.text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      // The theme role, not a typed size: this row is
                      // body text with metadata color.
                      style: theme.textTheme.bodyMedium?.copyWith(
                        height: 1.2,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Web `SubagentReadOnlyComposer` (EN copy from `locales.ts`
/// `readonly.*`): the status card that replaces the message field for
/// one-shot records and parent-offline children. A tone card on the
/// four-step scale (`kShapeCard`, `surfaceContainerHigh` over the page's
/// `surface`) — no hairline: space and tone carry the boundary.
class _ReadOnlyComposerNotice extends StatelessWidget {
  const _ReadOnlyComposerNotice({required this.reason});

  final SubagentReadOnlyReason reason;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(kShapeCard),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _readOnlyTitle(reason, l10n),
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _readOnlyBody(reason, l10n),
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// Message field for a continuable child with its parent online — the
/// only seat that keeps sending (SendSubagentPrompt). The draft is scoped
/// to the child through the widget key.
class _ChildComposerBar extends StatefulWidget {
  const _ChildComposerBar({
    required this.enabled,
    required this.isSending,
    required this.onSend,
    super.key,
  });

  final bool enabled;
  final bool isSending;
  final void Function(String text) onSend;

  @override
  State<_ChildComposerBar> createState() => _ChildComposerBarState();
}

class _ChildComposerBarState extends State<_ChildComposerBar> {
  final TextEditingController _draftController = TextEditingController();

  @override
  void dispose() {
    _draftController.dispose();
    super.dispose();
  }

  void _send() {
    final text = _draftController.text;
    if (text.trim().isEmpty || widget.isSending) return;
    widget.onSend(text);
    _draftController.clear();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _draftController,
            enabled: widget.enabled,
            decoration: InputDecoration(
              hintText: l10n.messageSelectedSubagentHint,
              isDense: true,
            ),
            onSubmitted: (_) => _send(),
            onChanged: (_) => setState(() {}),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 8),
          child: FilledButton(
            onPressed:
                _draftController.text.trim().isNotEmpty && !widget.isSending
                ? _send
                : null,
            child: Text(widget.isSending ? l10n.sending : l10n.send),
          ),
        ),
      ],
    );
  }
}

/// A host failure rides the top of the screen as a native [MaterialBanner]
/// (errorContainer tone, dismiss action) — the app never silently drops an
/// error fact; the message stays until the user dismisses it (the web
/// error strip's contract, on the framework surface).
class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return MaterialBanner(
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      backgroundColor: scheme.errorContainer,
      content: Text(
        message,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: scheme.onErrorContainer,
        ),
      ),
      actions: [
        IconButton(
          tooltip: l10n.dismiss,
          visualDensity: VisualDensity.compact,
          onPressed: onDismiss,
          icon: Icon(Icons.close, size: 18, color: scheme.onErrorContainer),
        ),
      ],
    );
  }
}

/// Web secondary line: `[summary?.title, mode, activity].join(' · ')` —
/// parts render only when known. Token/duration metrics (web
/// `tokenTotal`/`activityDuration`) need `tokenUsage`/`subagentTiming`
/// projections the domain does not expose yet, so rows carry no metric
/// chip.
String _secondaryLine(
  SubagentEntry entry,
  SessionSummary? summary,
  AppLocalizations l10n,
) {
  return <String?>[
    summary?.title,
    _modeLabel(entry.mode, l10n),
    _activityLabel(entry.activity, l10n),
  ].whereType<String>().where((part) => part.isNotEmpty).join(' · ');
}

/// Web locales.ts EN `mode.*`. Modes arrive as the closed `SubagentMode`
/// enum — the adapter maps the wire literals and fails loud on anything
/// else — so this switch stays exhaustive.
String? _modeLabel(SubagentMode? mode, AppLocalizations l10n) => switch (mode) {
  null => null,
  SubagentMode.oneShot => l10n.modeOneShot,
  SubagentMode.continuable => l10n.modeContinuable,
};

/// Web locales.ts EN `activity.*`; unknown activities surface verbatim.
String? _activityLabel(String? activity, AppLocalizations l10n) =>
    switch (activity) {
      null => null,
      'running' => l10n.activityRunning,
      'inactive' => l10n.activityNotRunning,
      final other => other,
    };

/// Web locales.ts EN `diagnostic.*` reasons.
String? _diagnosticReasonLabel(String? reason, AppLocalizations l10n) =>
    switch (reason) {
      null => null,
      'corrupt' => l10n.diagnosticCorrupt,
      'unsupported' => l10n.diagnosticUnsupported,
      'unavailable' => l10n.diagnosticUnavailable,
      final other => other,
    };

/// Web locales.ts EN `readonly.oneShot.*`.
String _readOnlyTitle(SubagentReadOnlyReason reason, AppLocalizations l10n) =>
    switch (reason) {
      SubagentReadOnlyReason.oneShot => l10n.oneShotRecordTitle,
      SubagentReadOnlyReason.parentUnavailable => l10n.parentUnavailableTitle,
    };

/// Web locales.ts EN `readonly.oneShot.body` / `readonly.body`.
String _readOnlyBody(SubagentReadOnlyReason reason, AppLocalizations l10n) =>
    switch (reason) {
      SubagentReadOnlyReason.oneShot => l10n.oneShotRecordBody,
      SubagentReadOnlyReason.parentUnavailable => l10n.parentUnavailableBody,
    };

/// Child records render without durable attachments: the loader always
/// resolves empty (the null-returning seat `TimelineRow` requires).
Future<Uint8List?> _noChildAttachment(String sessionId, AttachmentRef ref) =>
    Future<Uint8List?>.value();
