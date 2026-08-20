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

import 'package:domain/model/attachment.dart';
import 'package:domain/model/session.dart';
import 'package:domain/model/subagent.dart';
import 'package:domain/model/timeline_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../di/providers.dart';
import '../chat/chat_screen.dart' show PlanChip, TimelineRow, timelineKey;
import '../theme/deepsuite_extension.dart';
import '../theme/deepsuite_tokens.dart';
import 'subagent_ui_state.dart';

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
    super.key,
    required this.uiState,
    required this.onAction,
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
      // menu fill, 12px radius, lv3 elevation, 4px inner padding.
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: dsOf(sheetContext).menu,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: dsOf(sheetContext).borderInverted),
            boxShadow: kDsShadowLv3,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 520),
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
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
                  tooltip: 'Back',
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => widget.onAction(const CloseChildView()),
                ),
          title: Text(
            childId == null ? 'Subagents' : childEntry?.label ?? childId,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            if (childId == null) ...[
              if (uiState.selectedParentId != null)
                IconButton(
                  tooltip: 'Refresh',
                  icon: const Icon(Icons.refresh),
                  onPressed: () =>
                      widget.onAction(const RefreshSubagentsAction()),
                ),
            ] else if (childEntry?.isInterruptible ?? false)
              IconButton(
                tooltip: 'Stop',
                icon: const Icon(Icons.stop_circle_outlined),
                onPressed: () => widget.onAction(InterruptSubagent(childId)),
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
                'Select a parent session',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: dsOf(context).labelTertiary,
                ),
              ),
            ),
            _ when uiState.isLoading && uiState.catalog.entries.isEmpty =>
              const Center(child: CircularProgressIndicator()),
            _ when uiState.catalog.entries.isEmpty => Center(
              child: Text(
                'No subagents',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: dsOf(context).labelTertiary,
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
/// catalog trigger pill, mobile sheet form).
class _ParentSelectorRow extends StatelessWidget {
  const _ParentSelectorRow({required this.session, required this.onTap});

  final SessionSummary? session;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ds = dsOf(context);
    final theme = Theme.of(context);
    final selected = session;
    final title = selected == null
        ? 'Select a parent session'
        : selected.blank
        ? 'New session'
        : selected.displayTitle;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Row(
            children: [
              SizedBox(
                width: 16,
                child: selected?.running ?? false
                    ? const SubagentStateDot(state: SubagentDotState.ongoing)
                    : null,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Parent session',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: ds.labelCaption,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: selected == null ? ds.labelTertiary : null,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.expand_more, size: 18, color: ds.labelSecondary),
            ],
          ),
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
    final theme = Theme.of(context);
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: Text('Parent session', style: theme.textTheme.titleSmall),
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
    );
  }
}

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
    final ds = dsOf(context);
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onSelect,
      child: SizedBox(
        height: 44,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              SizedBox(
                width: 16,
                child: session.running
                    ? const SubagentStateDot(state: SubagentDotState.ongoing)
                    : null,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  session.blank ? 'New session' : session.displayTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              if (selected)
                Icon(Icons.check, size: 16, color: ds.labelSecondary),
            ],
          ),
        ),
      ),
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
              onOpen: () => onAction(OpenChild(entry.id)),
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
/// tap opens the child detail view.
class _CatalogEntryRow extends StatelessWidget {
  const _CatalogEntryRow({
    super.key,
    required this.entry,
    required this.summary,
    required this.level,
    required this.expanded,
    required this.reserveDisclosure,
    required this.onOpen,
    required this.onToggleBranch,
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
    final ds = dsOf(context);
    final theme = Theme.of(context);
    final label = entry.label ?? entry.id;
    final secondary = _secondaryLine(entry, summary);
    return Padding(
      padding: EdgeInsets.only(left: 12 + 16.0 * level),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onOpen,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Row(
            children: [
              if (entry.hasChildren)
                SizedBox(
                  width: 32,
                  height: 44,
                  child: Center(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: onToggleBranch,
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: AnimatedRotation(
                          turns: expanded ? 0.25 : 0,
                          duration: kDsDuration,
                          child: Icon(
                            Icons.chevron_right,
                            size: 18,
                            color: ds.labelSecondary,
                          ),
                        ),
                      ),
                    ),
                  ),
                )
              else if (reserveDisclosure)
                const SizedBox(width: 32),
              SubagentStateDot(
                state: entry.activity == 'running'
                    ? SubagentDotState.ongoing
                    : SubagentDotState.done,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium,
                    ),
                    if (secondary.isNotEmpty)
                      Text(
                        secondary,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: ds.labelTertiary,
                        ),
                      ),
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

/// Diagnostic catalog entry (web `entry.kind === 'diagnostic'`): disabled
/// row with the error dot and the reason as its only summary.
class _DiagnosticEntryRow extends StatelessWidget {
  const _DiagnosticEntryRow({
    super.key,
    required this.entry,
    required this.level,
    required this.reserveDisclosure,
  });

  final SubagentEntry entry;
  final int level;
  final bool reserveDisclosure;

  @override
  Widget build(BuildContext context) {
    final ds = dsOf(context);
    final theme = Theme.of(context);
    final reason = _diagnosticReasonLabel(entry.reason);
    return Padding(
      padding: EdgeInsets.only(left: 12 + 16.0 * level),
      child: Semantics(
        enabled: false,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Row(
            children: [
              if (reserveDisclosure) const SizedBox(width: 32),
              const SubagentStateDot(state: SubagentDotState.error),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      entry.id,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: ds.labelSecondary,
                      ),
                    ),
                    if (reason != null)
                      Text(
                        reason,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: ds.labelTertiary,
                        ),
                      ),
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

/// Web `CatalogLoadingRows` placeholder: 'Loading subagents…'.
class _BranchLoadingRow extends StatelessWidget {
  const _BranchLoadingRow({required this.level});

  final int level;

  @override
  Widget build(BuildContext context) {
    final ds = dsOf(context);
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(left: 12 + 16.0 * level),
      child: SizedBox(
        height: 44,
        child: Row(
          children: [
            const SizedBox(width: 32),
            const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 10),
            Text(
              'Loading subagents…',
              style: theme.textTheme.bodySmall?.copyWith(
                color: ds.labelTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Web catalog `state === 'error'` row: message + Retry.
class _BranchErrorRow extends StatelessWidget {
  const _BranchErrorRow({required this.level, required this.onRetry});

  final int level;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(left: 12 + 16.0 * level),
      child: SizedBox(
        height: 44,
        child: Row(
          children: [
            const SizedBox(width: 32),
            Expanded(
              child: Text(
                'Unable to load subagents',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
            TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
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

/// Read-only queue dock for the child record — the app QueueDock container
/// (tip fill, r12 top corners, l1 border) with plain preview rows only:
/// on a child view `queueMutable` is false, so no edit/steer/remove
/// controls exist.
class _ReadOnlyQueueDock extends StatelessWidget {
  const _ReadOnlyQueueDock({required this.items});

  final List<SessionQueueItem> items;

  @override
  Widget build(BuildContext context) {
    final ds = dsOf(context);
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(
        color: ds.tip,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
        border: Border(
          top: BorderSide(color: ds.divider),
          left: BorderSide(color: ds.divider),
          right: BorderSide(color: ds.divider),
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
                  Icon(Icons.queue, size: 14, color: ds.labelTertiary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      item.text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontSize: 13,
                        color: ds.labelPrimaryDimmed,
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
/// one-shot records and parent-offline children.
class _ReadOnlyComposerNotice extends StatelessWidget {
  const _ReadOnlyComposerNotice({required this.reason});

  final SubagentReadOnlyReason reason;

  @override
  Widget build(BuildContext context) {
    final ds = dsOf(context);
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ds.tip,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ds.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _readOnlyTitle(reason),
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _readOnlyBody(reason),
            style: theme.textTheme.bodySmall?.copyWith(
              color: ds.labelSecondary,
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
    super.key,
    required this.enabled,
    required this.isSending,
    required this.onSend,
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
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _draftController,
            enabled: widget.enabled,
            decoration: const InputDecoration(
              hintText: 'Message selected subagent',
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
            child: Text(widget.isSending ? 'Sending' : 'Send'),
          ),
        ),
      ],
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ),
          IconButton(
            iconSize: 16,
            visualDensity: VisualDensity.compact,
            tooltip: 'Dismiss',
            onPressed: onDismiss,
            icon: Icon(Icons.close, size: 16, color: theme.colorScheme.error),
          ),
        ],
      ),
    );
  }
}

/// Web StateDot (job-list-action port): halo + solid core riding the
/// state color — ongoing blue while running, done green otherwise, error
/// red for diagnostics.
enum SubagentDotState { ongoing, done, error }

class SubagentStateDot extends StatelessWidget {
  const SubagentStateDot({super.key, required this.state, this.size = 8});

  final SubagentDotState state;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = switch (state) {
      SubagentDotState.ongoing => DeepSuiteStatic.deepseek450,
      SubagentDotState.done => DeepSuiteStatic.green500,
      SubagentDotState.error => Theme.of(context).colorScheme.error,
    };
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
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
          ),
        ],
      ),
    );
  }
}

/// Web secondary line: `[summary?.title, mode, activity].join(' · ')` —
/// parts render only when known. Token/duration metrics (web
/// `tokenTotal`/`activityDuration`) need `tokenUsage`/`subagentTiming`
/// projections the domain does not expose yet, so rows carry no metric
/// chip.
String _secondaryLine(SubagentEntry entry, SessionSummary? summary) {
  return <String?>[
    summary?.title,
    _modeLabel(entry.mode),
    _activityLabel(entry.activity),
  ].whereType<String>().where((part) => part.isNotEmpty).join(' · ');
}

/// Web locales.ts EN `mode.*`; unknown mode strings surface verbatim
/// rather than being swallowed.
String? _modeLabel(String? mode) => switch (mode) {
  null => null,
  'one-shot' => 'one-shot',
  'continuable' => 'continuable',
  final other => other,
};

/// Web locales.ts EN `activity.*`; unknown activities surface verbatim.
String? _activityLabel(String? activity) => switch (activity) {
  null => null,
  'running' => 'running',
  'inactive' => 'not running',
  final other => other,
};

/// Web locales.ts EN `diagnostic.*` reasons.
String? _diagnosticReasonLabel(String? reason) => switch (reason) {
  null => null,
  'corrupt' => 'corrupted session record',
  'unsupported' => 'unsupported subagent record version',
  'unavailable' => 'session record temporarily unavailable',
  final other => other,
};

/// Web locales.ts EN `readonly.oneShot.*`.
String _readOnlyTitle(SubagentReadOnlyReason reason) => switch (reason) {
  SubagentReadOnlyReason.oneShot => 'One-shot subagent record',
  SubagentReadOnlyReason.parentUnavailable =>
    'This subagent is read-only for now',
};

/// Web locales.ts EN `readonly.oneShot.body` / `readonly.body`.
String _readOnlyBody(SubagentReadOnlyReason reason) => switch (reason) {
  SubagentReadOnlyReason.oneShot => 'One-shot tasks do not accept follow-ups; review the full execution record here.',
  SubagentReadOnlyReason.parentUnavailable =>
    'The parent session is offline; reopen it to continue sending messages.',
};

/// Child records render without durable attachments: the loader always
/// resolves empty (the null-returning seat `TimelineRow` requires).
Future<Uint8List?> _noChildAttachment(String sessionId, AttachmentRef ref) =>
    Future<Uint8List?>.value();
