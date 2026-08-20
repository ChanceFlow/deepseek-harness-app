/// Workspace screen — Flutter port of the dsh web workspace surfaces:
/// the ui-workspace WorkspaceBrowser (section header, search capsule,
/// grouped tree) and WorkspacePicker (add flow), plus the
/// ui-directory-picker-browse DirectoryBrowser (host directory card).
///
/// Mobile adaptations of the web design language: the browsing column
/// fills the tab on the sidebar fill token, rows grow to 44px touch
/// targets, hover-revealed row actions stay visible, drag reorder becomes
/// the row menu's move actions, hover popovers become menu-surface bottom
/// sheets, and the web dialogs keep their modal-card shape (r24,
/// bgLayer2, lv3 shadow) as bottom-docked cards and dialogs.
library;

import 'dart:async';

import 'package:app/l10n/app_localizations.dart';
import 'package:domain/model/backend.dart';
import 'package:domain/model/directory.dart';
import 'package:domain/model/session.dart';
import 'package:domain/model/workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../chat/chat_ui_state.dart';
import '../../di/providers.dart';
import '../root/app_destination.dart';
import '../shared/backend_connection_dot.dart';
import '../shared/session_tree.dart';
import '../theme/deepsuite_extension.dart';
import 'workspace_ui_state.dart';

class WorkspaceRoute extends ConsumerWidget {
  const WorkspaceRoute({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watching the keep-alive here pins every configured backend's
    // connection while this tab exists.
    ref.watch(allBackendConnectionsProvider);
    final registry = ref.watch(backendRegistryStateProvider);
    return registry.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (error, _) =>
          Scaffold(body: Center(child: Text(error.toString()))),
      data: (state) => _BackendAggregateScreen(
        backends: state.backends,
        activeId: state.activeId,
        onAction: (action) => ref
            .read(backendRegistryProvider.future)
            .then((controller) => controller.onAction(action)),
      ),
    );
  }
}

/// The aggregate Workspaces surface: every configured backend's browsing
/// region, grouped under a backend header (label + live connection dot +
/// active marker). Tapping a header makes that backend active; starting
/// a session in a workspace switches there too.
class _BackendAggregateScreen extends ConsumerWidget {
  const _BackendAggregateScreen({
    required this.backends,
    required this.activeId,
    required this.onAction,
  });

  final List<BackendConfig> backends;
  final String? activeId;
  final void Function(BackendAction action) onAction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ds = dsOf(context);
    return Scaffold(
      backgroundColor: ds.sidebarFill,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            for (final backend in backends)
              _BackendWorkspaceSection(
                key: ValueKey(backend.id),
                backend: backend,
                active: backend.id == activeId,
                onAction: onAction,
              ),
          ],
        ),
      ),
    );
  }
}

/// One backend's group: the header row plus its embedded browsing
/// region.
class _BackendWorkspaceSection extends ConsumerWidget {
  const _BackendWorkspaceSection({
    super.key,
    required this.backend,
    required this.active,
    required this.onAction,
  });

  final BackendConfig backend;
  final bool active;
  final void Function(BackendAction action) onAction;

  /// Session navigation from this backend's browsing rows: select the
  /// backend (a non-active row switches first), select the session on
  /// its chat controller, and land on the Chat destination.
  void _openSession(WidgetRef ref, String sessionId) {
    if (!active) onAction(SelectBackend(backend.id));
    ref
        .read(chatControllerProvider(backend.id))
        .onAction(SelectSession(sessionId));
    ref.read(appDestinationProvider.notifier).select(AppDestination.chat);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ds = dsOf(context);
    final theme = Theme.of(context);
    final controller = ref.watch(workspaceControllerProvider(backend.id));
    final l10n = AppLocalizations.of(context)!;
    // The chat surface's selection rides the active backend's slice only
    // — a non-active backend's controller keeps its own stale selection,
    // which must not highlight rows there (the sidebar's slice rule).
    final selectedSessionId = active
        ? (ref.watch(chatUiStateProvider(backend.id)).value ??
                  const ChatUiState()).selectedSessionId
        : null;
    return StreamBuilder<WorkspaceUiState>(
      stream: controller.uiState,
      initialData: controller.state,
      builder: (context, snapshot) {
        final uiState = snapshot.data ?? const WorkspaceUiState();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Backend header: connection dot + label + host, with the
            // active marker; tapping selects the backend.
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => onAction(SelectBackend(backend.id)),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                  decoration: BoxDecoration(
                    color: active ? ds.sidebarNavItemActive : null,
                    border: Border(bottom: BorderSide(color: ds.divider)),
                  ),
                  child: Row(
                    children: [
                      BackendConnectionDot(backendId: backend.id),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              backend.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall,
                            ),
                            Text(
                              '${backend.baseUri.host}:${backend.baseUri.port}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: ds.labelTertiary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (active)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: ds.specificSelector,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            l10n.backendStatusActive,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: ds.labelSecondary,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            // The embedded browsing region. Starting a session selects
            // the backend first (non-active), then lands the chat
            // surface on the resolved conversation (web
            // `startSession` → `sessions.open`).
            WorkspaceScreen(
              uiState: uiState,
              onAction: (action) {
                if (action is StartSessionInWorkspace) {
                  unawaited(() async {
                    if (!active) onAction(SelectBackend(backend.id));
                    final sessionId = await controller
                        .startSessionInWorkspace(action.workspaceId);
                    if (sessionId != null) {
                      _openSession(ref, sessionId);
                    }
                  }());
                  return;
                }
                controller.onAction(action);
              },
              selectedSessionId: selectedSessionId,
              onSelectSession: (sessionId) => _openSession(ref, sessionId),
              embedded: true,
              titleOverride: backend.label,
            ),
            const SizedBox(height: 16),
          ],
        );
      },
    );
  }
}

/// The browsing surface: renders the workspace tree and the embedded
/// directory browser. The aggregate form (embedded) drops the Scaffold —
/// the backend section owns the surface.
class WorkspaceScreen extends StatefulWidget {
  const WorkspaceScreen({
    super.key,
    required this.uiState,
    required this.onAction,
    this.selectedSessionId,
    this.onSelectSession,
    this.embedded = false,
    this.titleOverride,
  });

  final WorkspaceUiState uiState;
  final void Function(WorkspaceAction) onAction;

  /// The chat surface's selected session on this backend (row
  /// highlight + blank-placeholder visibility; null on non-active
  /// backends).
  final String? selectedSessionId;

  /// Opens a session row: selects it and lands on the Chat surface.
  final void Function(String sessionId)? onSelectSession;

  /// Aggregate form: render the browsing region without the Scaffold
  /// (the backend section owns the surface).
  final bool embedded;

  /// Replaces the section-header title in the aggregate form (the
  /// backend label names the region).
  final String? titleOverride;

  @override
  State<WorkspaceScreen> createState() => _WorkspaceScreenState();
}

class _WorkspaceScreenState extends State<WorkspaceScreen> {
  final TextEditingController _searchController = TextEditingController();
  final Set<String> _expandedGroups = <String>{};
  final Set<String> _overflowExpandedGroups = <String>{};
  bool _searchActive = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _toggleSearch() => setState(() {
    _searchActive = !_searchActive;
    if (!_searchActive) _searchController.clear();
  });

  /// Web `.clearButton`: clearing also collapses the search capsule.
  void _collapseSearch() => setState(() {
    _searchController.clear();
    _searchActive = false;
  });

  void _toggleGroup(String workspaceId) => setState(() {
    if (!_expandedGroups.remove(workspaceId)) {
      _expandedGroups.add(workspaceId);
    }
  });

  void _toggleOverflow(String workspaceId) => setState(() {
    if (!_overflowExpandedGroups.remove(workspaceId)) {
      _overflowExpandedGroups.add(workspaceId);
    }
  });

  void _startSession(String workspaceId) =>
      widget.onAction(StartSessionInWorkspace(workspaceId));

  /// Web ProjectRowItem "⋮" menu — mobile form: a menu-surface bottom
  /// sheet (Rename / Delete workspace / Move up / Move down).
  Future<void> _showWorkspaceActions(WorkspaceSummary workspace) {
    final workspaces = widget.uiState.workspaces;
    var position = 0;
    for (var i = 0; i < workspaces.length; i++) {
      if (workspaces[i].workspaceId == workspace.workspaceId) {
        position = i;
        break;
      }
    }
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _WorkspaceActionSheet(
        canMoveUp: position > 0,
        canMoveDown: position < workspaces.length - 1,
        onRename: () => _showRenameDialog(workspace),
        onDelete: () => _showDeleteDialog(workspace),
        onMoveUp: () =>
            widget.onAction(MoveWorkspaceUpAction(workspace.workspaceId)),
        onMoveDown: () =>
            widget.onAction(MoveWorkspaceDownAction(workspace.workspaceId)),
      ),
    );
  }

  Future<void> _showRenameDialog(WorkspaceSummary workspace) {
    return showDialog<void>(
      context: context,
      builder: (_) => _RenameWorkspaceDialog(
        initialTitle: workspace.title,
        existingTitles: widget.uiState.workspaces
            .map((item) => item.title)
            .toList(growable: false),
        onSave: (title) => widget.onAction(
          RenameWorkspaceAction(workspace.workspaceId, title),
        ),
      ),
    );
  }

  Future<void> _showDeleteDialog(WorkspaceSummary workspace) {
    return showDialog<void>(
      context: context,
      builder: (_) => _DeleteWorkspaceDialog(
        workspace: workspace,
        onDelete: () =>
            widget.onAction(DeleteWorkspaceAction(workspace.workspaceId)),
      ),
    );
  }

  /// Web tree.ts `deriveSearchResults` surface: content matches render
  /// only for visible non-blank summaries — the flat result list
  /// replaces the tree while a query is active.
  Widget _searchResults(
    BuildContext context,
    DeepSuiteColors ds,
    WorkspaceUiState uiState,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final sessionsById = <String, SessionSummary>{
      for (final session in uiState.sessions.where(
        (session) =>
            !session.blank && sessionVisible(session, widget.selectedSessionId),
      ))
        session.id: session,
    };
    final rows = <Widget>[
      for (final result in uiState.searchResults)
        if (sessionsById[result.sessionId] case final session?)
          SessionSearchResultRow(
            session: session,
            snippet: result.snippet,
            workspaceLabel: _workspaceLabel(session, uiState, l10n),
            selected: session.id == widget.selectedSessionId,
            onSelect: () => widget.onSelectSession?.call(session.id),
          ),
    ];
    if (rows.isEmpty) {
      rows.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Text(
            l10n.noMatchingSessions,
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(fontSize: 13, color: ds.labelTertiary),
          ),
        ),
      );
    }
    if (widget.embedded) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: rows,
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      children: rows,
    );
  }

  /// Web tree.ts `labelOf`: the workspace title when an account holds
  /// the session, else the cwd basename (search-result context rows).
  String _workspaceLabel(
    SessionSummary session,
    WorkspaceUiState uiState,
    AppLocalizations l10n,
  ) {
    for (final workspace in uiState.workspaces) {
      if (workspace.sessionIds.contains(session.id)) return workspace.title;
    }
    return cwdBasename(session.cwd, l10n);
  }

  @override
  Widget build(BuildContext context) {
    final uiState = widget.uiState;
    final ds = dsOf(context);
    final query = _searchController.text.trim();
    return Stack(
      children: [
        if (widget.embedded)
          _browsingRegion(context, ds, uiState, query)
        else
          Scaffold(
            // Web: the browser region lives on the sidebar fill.
            backgroundColor: ds.sidebarFill,
            body: SafeArea(
              child: _browsingRegionBody(context, ds, uiState, query),
            ),
          ),
        if (uiState.directoryBrowserOpen) ...[
          // Web Modal mask: rgba(0,0,0,0.24); tapping it closes.
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => widget.onAction(const CloseDirectoryBrowser()),
              child: ColoredBox(color: Colors.black.withValues(alpha: 0.24)),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              child: DirectoryBrowserDialog(
                listing: uiState.directoryListing,
                loading: uiState.directoryLoading,
                onNavigate: (destination) =>
                    widget.onAction(NavigateDirectory(destination)),
                onCreateDirectory: (name) {
                  final parent = uiState.directoryListing?.path;
                  if (parent != null) {
                    widget.onAction(CreateDirectoryAction(parent, name));
                  }
                },
                // Web adoption: picking a folder creates the workspace
                // (the flow's one action — no intermediate form).
                onSelect: (selected) {
                  widget.onAction(CreateWorkspaceAction(selected));
                  widget.onAction(const CloseDirectoryBrowser());
                },
                onClose: () => widget.onAction(const CloseDirectoryBrowser()),
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// The browsing region: header, search, errors, and the grouped
  /// session tree (or the flat search-result list while a query is
  /// active). The standalone form stretches the tree (Expanded); the
  /// embedded aggregate form shrink-wraps it onto the outer scroll.
  Widget _browsingRegion(
    BuildContext context,
    DeepSuiteColors ds,
    WorkspaceUiState uiState,
    String query,
  ) {
    return Material(
      color: ds.sidebarFill,
      child: _browsingRegionBody(context, ds, uiState, query),
    );
  }

  Widget _browsingRegionBody(
    BuildContext context,
    DeepSuiteColors ds,
    WorkspaceUiState uiState,
    String query,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final hasQuery = query.isNotEmpty;
    final tree = _WorkspaceTree(
      sessions: uiState.sessions,
      workspaces: uiState.workspaces,
      selectedSessionId: widget.selectedSessionId,
      expandedGroups: _expandedGroups,
      overflowExpandedGroups: _overflowExpandedGroups,
      onToggle: _toggleGroup,
      onToggleOverflow: _toggleOverflow,
      onMenu: _showWorkspaceActions,
      onStartSession: _startSession,
      onSelectSession: widget.onSelectSession,
      shrinkWrap: widget.embedded,
    );
    final results = hasQuery ? _searchResults(context, ds, uiState) : tree;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: widget.embedded ? MainAxisSize.min : MainAxisSize.max,
      children: [
        _SectionHeader(
          title: widget.titleOverride ?? l10n.destinationWorkspaces,
          searchActive: _searchActive,
          onToggleSearch: _toggleSearch,
          onAdd: () => widget.onAction(const OpenDirectoryBrowser()),
        ),
        if (_searchActive)
          _SearchCapsule(
            controller: _searchController,
            onChanged: (value) {
              setState(() {});
              widget.onAction(SearchSessionsAction(value.trim()));
            },
            onCollapse: () {
              _collapseSearch();
              widget.onAction(const SearchSessionsAction(''));
            },
          ),
        if (uiState.errorMessage case final String error)
          _ErrorBanner(
            message: error,
            onDismiss: () => widget.onAction(const DismissWorkspaceError()),
          ),
        if (uiState.isLoading) const LinearProgressIndicator(minHeight: 2),
        if (widget.embedded)
          results
        else
          Expanded(
            child: Stack(
              children: [
                results,
                // Web `.fade`: bottom continuation hint tracking the
                // sidebar fill across themes.
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: IgnorePointer(
                    child: Container(
                      height: 24,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            ds.sidebarFill.withValues(alpha: 0),
                            ds.sidebarFill,
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Web `.sectionHeader`: the section label with the trailing search and
/// add-workspace icon actions (28px circles on the web; 44px touch
/// targets here).
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.searchActive,
    required this.onToggleSearch,
    required this.onAdd,
  });

  final String title;
  final bool searchActive;
  final VoidCallback onToggleSearch;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final ds = dsOf(context);
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 12, 4),
      child: SizedBox(
        height: 44,
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall
                    ?.copyWith(color: ds.labelTertiary),
              ),
            ),
            _HeaderIconButton(
              tooltip: l10n.searchTooltip,
              icon: Icons.search,
              active: searchActive,
              onTap: onToggleSearch,
            ),
            const SizedBox(width: 4),
            _HeaderIconButton(
              tooltip: l10n.addWorkspace,
              icon: Icons.create_new_folder_outlined,
              onTap: onAdd,
            ),
          ],
        ),
      ),
    );
  }
}

/// Web `.iconButton`: circular hover-lit icon seat (label-secondary ink;
/// primary ink while its control is engaged).
class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({
    required this.tooltip,
    required this.icon,
    required this.onTap,
    this.active = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final ds = dsOf(context);
    return SizedBox(
      width: 44,
      height: 44,
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(22),
            hoverColor: ds.interactiveBgHover,
            onTap: onTap,
            child: Center(
              child: Icon(
                icon,
                size: 20,
                color: active
                    ? Theme.of(context).colorScheme.onSurface
                    : ds.labelSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Web `.searchExpanded`: the bordered search capsule (r10, border-l2,
/// 13px input, trailing clear circle).
class _SearchCapsule extends StatelessWidget {
  const _SearchCapsule({
    required this.controller,
    required this.onChanged,
    required this.onCollapse,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onCollapse;

  @override
  Widget build(BuildContext context) {
    final ds = dsOf(context);
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 12, 4),
      child: Container(
        height: 36,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: ds.borderL2),
        ),
        child: Row(
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 10),
              child: Icon(Icons.search, size: 14, color: ds.labelTertiary),
            ),
            Expanded(
              child: TextField(
                controller: controller,
                autofocus: true,
                style: theme.textTheme.bodyMedium?.copyWith(fontSize: 13),
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  hintText: l10n.searchWorkspacesHint,
                  hintStyle: theme.textTheme.bodyMedium?.copyWith(
                    fontSize: 13,
                    color: ds.labelTertiary,
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 6),
                ),
                onChanged: onChanged,
              ),
            ),
            SizedBox(
              width: 36,
              height: 36,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  hoverColor: ds.interactiveBgHover,
                  onTap: onCollapse,
                  child: Center(
                    child: Icon(
                      Icons.close,
                      size: 14,
                      color: ds.labelSecondary,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Controller-error surface: web surfaces flow errors inside its dialogs;
/// this controller funnels every failure into one dismissible line
/// (web `.renameError` typography on the error role).
class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ds = dsOf(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 12, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
          SizedBox(
            width: 36,
            height: 36,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                hoverColor: ds.interactiveBgHover,
                onTap: onDismiss,
                child: Center(
                  child: Icon(Icons.close, size: 14, color: ds.labelSecondary),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Web `.list`: the scrolling tree of workspace group sections.
class _WorkspaceTree extends StatelessWidget {
  const _WorkspaceTree({
    required this.sessions,
    required this.workspaces,
    required this.selectedSessionId,
    required this.expandedGroups,
    required this.overflowExpandedGroups,
    required this.onToggle,
    required this.onToggleOverflow,
    required this.onMenu,
    required this.onStartSession,
    required this.onSelectSession,
    this.shrinkWrap = false,
  });

  final List<SessionSummary> sessions;
  final List<WorkspaceSummary> workspaces;
  final String? selectedSessionId;
  final Set<String> expandedGroups;
  final Set<String> overflowExpandedGroups;
  final void Function(String workspaceId) onToggle;
  final void Function(String workspaceId) onToggleOverflow;
  final void Function(WorkspaceSummary workspace) onMenu;
  final void Function(String workspaceId) onStartSession;
  final void Function(String sessionId)? onSelectSession;

  /// Aggregate form: the tree rides the section's outer scroll view.
  final bool shrinkWrap;

  @override
  Widget build(BuildContext context) {
    final ds = dsOf(context);
    final l10n = AppLocalizations.of(context)!;
    final groups = deriveSessionGroups(
      sessions,
      workspaces,
      selectedSessionId,
      l10n,
    );
    if (groups.isEmpty) {
      // Web `.empty` (aligned with the row grid).
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: Text(
          l10n.noWorkspacesYet,
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(fontSize: 13, color: ds.labelTertiary),
        ),
      );
    }
    // The group holding the active session stays expanded (the sidebar
    // rule — the current session never hides behind a fold).
    final currentGroupKey = currentGroupKeyOf(
      sessions,
      workspaces,
      selectedSessionId,
    );
    final nowEpochMs = DateTime.now().millisecondsSinceEpoch;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      shrinkWrap: shrinkWrap,
      physics: shrinkWrap ? const NeverScrollableScrollPhysics() : null,
      children: [
        for (var i = 0; i < groups.length; i++) ...[
          // Web `.groupSection + .groupSection` inter-group spacing.
          if (i > 0) const SizedBox(height: 4),
          _WorkspaceGroup(
            group: groups[i],
            workspaces: workspaces,
            expanded: expandedGroups.contains(groups[i].key) ||
                groups[i].key == currentGroupKey,
            overflowExpanded: overflowExpandedGroups.contains(groups[i].key),
            nowEpochMs: nowEpochMs,
            selectedSessionId: selectedSessionId,
            onToggle: onToggle,
            onToggleOverflow: onToggleOverflow,
            onMenu: onMenu,
            onStartSession: onStartSession,
            onSelectSession: onSelectSession,
          ),
        ],
      ],
    );
  }
}

/// Web `.groupSection`: one workspace header row plus its session rows
/// (2px intra-group rhythm). The Ungrouped bucket renders the header
/// without the management actions — it has no backing Workspace (web
/// rule: no menu, no create seat).
class _WorkspaceGroup extends StatelessWidget {
  const _WorkspaceGroup({
    required this.group,
    required this.workspaces,
    required this.expanded,
    required this.overflowExpanded,
    required this.nowEpochMs,
    required this.selectedSessionId,
    required this.onToggle,
    required this.onToggleOverflow,
    required this.onMenu,
    required this.onStartSession,
    required this.onSelectSession,
  });

  final SessionGroupData group;
  final List<WorkspaceSummary> workspaces;
  final bool expanded;
  final bool overflowExpanded;
  final int nowEpochMs;
  final String? selectedSessionId;
  final void Function(String workspaceId) onToggle;
  final void Function(String workspaceId) onToggleOverflow;
  final void Function(WorkspaceSummary workspace) onMenu;
  final void Function(String workspaceId) onStartSession;
  final void Function(String sessionId)? onSelectSession;

  @override
  Widget build(BuildContext context) {
    final sessions = group.sessions;
    final visibleCount = overflowExpanded || sessions.length <= kCollapsedSessionLimit
        ? sessions.length
        : kCollapsedSessionLimit;
    final ungrouped = group.key == kUngroupedKey;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (ungrouped)
          _UngroupedHeaderRow(label: group.label, expanded: expanded,
              onToggle: () => onToggle(group.key))
        else
          _WorkspaceRow(
            workspace: _workspaceOf(group),
            expanded: expanded,
            onToggle: onToggle,
            onMenu: onMenu,
            onStartSession: onStartSession,
          ),
        if (expanded) ...[
          const SizedBox(height: 2),
          for (var i = 0; i < visibleCount; i++) ...[
            if (i > 0) const SizedBox(height: 2),
            SessionTreeRow(
              session: sessions[i],
              selected: sessions[i].id == selectedSessionId,
              nowEpochMs: nowEpochMs,
              onSelect: sessions[i].id == selectedSessionId
                  ? null
                  : () => onSelectSession?.call(sessions[i].id),
            ),
          ],
          if (sessions.length > kCollapsedSessionLimit) ...[
            const SizedBox(height: 2),
            SessionOverflowRow(
              expanded: overflowExpanded,
              totalCount: sessions.length,
              onTap: () => onToggleOverflow(group.key),
            ),
          ],
        ],
      ],
    );
  }

  WorkspaceSummary _workspaceOf(SessionGroupData group) {
    // The derive step keeps one group per workspace entity, so the row
    // re-resolves by id through the tree's own list.
    for (final workspace in workspaces) {
      if (workspace.workspaceId == group.key) return workspace;
    }
    throw StateError('group ${group.key} has no workspace summary');
  }
}

/// The Ungrouped bucket's header: folder + label, no management
/// actions (web rule — no backing Workspace).
class _UngroupedHeaderRow extends StatelessWidget {
  const _UngroupedHeaderRow({
    required this.label,
    required this.expanded,
    required this.onToggle,
  });

  final String label;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final ds = dsOf(context);
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        hoverColor: ds.interactiveBgHover,
        onTap: onToggle,
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: expanded ? ds.interactiveBgHover : null,
          ),
          child: Row(
            children: [
              Icon(
                expanded ? Icons.folder_open : Icons.folder_outlined,
                size: 16,
                color: ds.labelTertiary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Web `.projectRow`: folder slot, title, trailing actions (ellipsis menu
/// + new-session). Hover-revealed on the web; always visible here for
/// touch, with the expanded row keeping the hover fill (web pins it while
/// its menu is open).
class _WorkspaceRow extends StatelessWidget {
  const _WorkspaceRow({
    required this.workspace,
    required this.expanded,
    required this.onToggle,
    required this.onMenu,
    required this.onStartSession,
  });

  final WorkspaceSummary workspace;
  final bool expanded;
  final void Function(String workspaceId) onToggle;
  final void Function(WorkspaceSummary workspace) onMenu;
  final void Function(String workspaceId) onStartSession;

  @override
  Widget build(BuildContext context) {
    final ds = dsOf(context);
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        hoverColor: ds.interactiveBgHover,
        onTap: () => onToggle(workspace.workspaceId),
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: expanded ? ds.interactiveBgHover : null,
          ),
          child: Row(
            children: [
              // Web `.slot .folder`: tertiary folder glyph, open when the
              // group is expanded.
              Icon(
                expanded ? Icons.folder_open : Icons.folder_outlined,
                size: 16,
                color: ds.labelTertiary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  workspace.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall,
                ),
              ),
              _RowIconButton(
                tooltip: l10n.newSessionInWorkspace(workspace.title),
                icon: Icons.add_outlined,
                onTap: () => onStartSession(workspace.workspaceId),
              ),
              // Web `.rowActions` gap.
              const SizedBox(width: 12),
              _RowIconButton(
                tooltip: l10n.workspaceActionsFor(workspace.title),
                icon: Icons.more_horiz,
                onTap: () => onMenu(workspace),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Web `.rowActions .iconButton`: bare tertiary glyph in a circle seat.
class _RowIconButton extends StatelessWidget {
  const _RowIconButton({
    required this.tooltip,
    required this.icon,
    required this.onTap,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ds = dsOf(context);
    return SizedBox(
      width: 44,
      height: 44,
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(22),
            hoverColor: ds.interactiveBgHover,
            onTap: onTap,
            child: Center(child: Icon(icon, size: 18, color: ds.labelTertiary)),
          ),
        ),
      ),
    );
  }
}

/// Web Menu (figma MenuDropdown) as a bottom sheet: menu surface fill,
/// r12 card, inverted hairline, lv3 shadow, 4px inner padding; rows are
/// 44px (web 40px dense) r10 cells with a 16px leading glyph.
class _WorkspaceActionSheet extends StatelessWidget {
  const _WorkspaceActionSheet({
    required this.canMoveUp,
    required this.canMoveDown,
    required this.onRename,
    required this.onDelete,
    required this.onMoveUp,
    required this.onMoveDown,
  });

  final bool canMoveUp;
  final bool canMoveDown;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;

  @override
  Widget build(BuildContext context) {
    final ds = dsOf(context);
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: ds.menu,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: ds.borderInverted),
          boxShadow: kDsShadowLv3,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _MenuRow(
              icon: Icons.edit_outlined,
              label: l10n.rename,
              onTap: () {
                Navigator.of(context).pop();
                onRename();
              },
            ),
            _MenuRow(
              icon: Icons.delete_outline,
              label: l10n.deleteWorkspace,
              isDanger: true,
              onTap: () {
                Navigator.of(context).pop();
                onDelete();
              },
            ),
            const _MenuSeparator(),
            // Web reorders by drag; touch keeps the move verbs here.
            _MenuRow(
              icon: Icons.arrow_upward,
              label: l10n.moveUp,
              enabled: canMoveUp,
              onTap: () {
                Navigator.of(context).pop();
                onMoveUp();
              },
            ),
            _MenuRow(
              icon: Icons.arrow_downward,
              label: l10n.moveDown,
              enabled: canMoveDown,
              onTap: () {
                Navigator.of(context).pop();
                onMoveDown();
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Web Menu `.item`: min-h 40 (44 here), r10, 10/8 padding, 14px label,
/// 16px tertiary leading glyph; danger rows take the error role with the
/// danger hover fill.
class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isDanger = false,
    this.enabled = true,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isDanger;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final ds = dsOf(context);
    final theme = Theme.of(context);
    final error = theme.colorScheme.error;
    final ink = isDanger ? error : theme.colorScheme.onSurface;
    final row = Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        hoverColor: isDanger
            ? error.withValues(alpha: 0.05)
            : ds.interactiveBgHover,
        onTap: enabled ? onTap : null,
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              Icon(icon, size: 18, color: isDanger ? error : ds.labelTertiary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontSize: 14,
                    color: ink,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return enabled ? row : Opacity(opacity: 0.4, child: row);
  }
}

/// Web Menu `.separator`: 1px hairline with 4/2 margins.
class _MenuSeparator extends StatelessWidget {
  const _MenuSeparator();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1,
      margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
      color: dsOf(context).divider,
    );
  }
}

/// Web Modal card (figma Dialog 451:18655): r24, bgLayer2 fill, inverted
/// hairline, lv3 shadow, 24px column, 16px/500 title, trailing capsule
/// actions.
class _DsModalCard extends StatelessWidget {
  const _DsModalCard({
    required this.title,
    required this.child,
    required this.actions,
  });

  final String title;
  final Widget child;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final ds = dsOf(context);
    final theme = Theme.of(context);
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(maxWidth: 380),
        padding: const EdgeInsets.fromLTRB(24, 22, 24, 24),
        decoration: BoxDecoration(
          color: ds.bgLayer2,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: ds.borderInverted),
          boxShadow: kDsShadowLv3,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            child,
            const SizedBox(height: 20),
            // Capsule actions wrap to a second line on narrow cards (the
            // web dialog column does the same at small widths).
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: actions,
            ),
          ],
        ),
      ),
    );
  }
}

/// Web Button capsule geometry: h36, r18, 14px label, 72px floor.
ButtonStyle _dsCapsuleButton(ThemeData theme) => ButtonStyle(
  textStyle: WidgetStatePropertyAll<TextStyle?>(theme.textTheme.labelLarge),
  minimumSize: const WidgetStatePropertyAll<Size>(Size(72, 36)),
  padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
    EdgeInsets.symmetric(horizontal: 14),
  ),
  shape: WidgetStatePropertyAll<RoundedRectangleBorder>(
    RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
  ),
);

/// Web `.renameInput` / `.createInput`: 44px pill (r22, border-l2) with
/// 14px text and a caption-grey placeholder.
class _DsTextInput extends StatelessWidget {
  const _DsTextInput({
    required this.controller,
    this.hintText,
    this.autofocus = false,
    this.onChanged,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String? hintText;
  final bool autofocus;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final ds = dsOf(context);
    final theme = Theme.of(context);
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(22),
      borderSide: BorderSide(color: ds.borderL2),
    );
    final focusedBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(22),
      borderSide: BorderSide(color: ds.accent),
    );
    return TextField(
      controller: controller,
      autofocus: autofocus,
      style: theme.textTheme.bodyMedium,
      decoration: InputDecoration(
        isDense: true,
        hintText: hintText,
        hintStyle: theme.textTheme.bodyMedium?.copyWith(color: ds.labelCaption),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 11,
        ),
        border: border,
        enabledBorder: border,
        focusedBorder: focusedBorder,
      ),
      onChanged: onChanged,
      onSubmitted: onSubmitted,
    );
  }
}

/// Web workspace-rename modal: pill input, duplicate-title conflict
/// (web `conflict.named`), Cancel outline + Rename primary.
class _RenameWorkspaceDialog extends StatefulWidget {
  const _RenameWorkspaceDialog({
    required this.initialTitle,
    required this.existingTitles,
    required this.onSave,
  });

  final String initialTitle;
  final List<String> existingTitles;
  final void Function(String title) onSave;

  @override
  State<_RenameWorkspaceDialog> createState() => _RenameWorkspaceDialogState();
}

class _RenameWorkspaceDialogState extends State<_RenameWorkspaceDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialTitle,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final title = _controller.text.trim();
    if (title.isEmpty || title == widget.initialTitle || _duplicate) return;
    widget.onSave(title);
    Navigator.of(context).pop();
  }

  bool get _duplicate {
    final title = _controller.text.trim();
    return title.isNotEmpty &&
        title != widget.initialTitle &&
        widget.existingTitles.contains(title);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final trimmed = _controller.text.trim();
    final duplicate = _duplicate;
    final blocked =
        trimmed.isEmpty || trimmed == widget.initialTitle || duplicate;
    return _DsModalCard(
      title: l10n.renameWorkspaceTitle,
      actions: [
        OutlinedButton(
          style: _dsCapsuleButton(theme),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          style: _dsCapsuleButton(theme),
          onPressed: blocked ? null : _save,
          child: Text(l10n.rename),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _DsTextInput(
            controller: _controller,
            autofocus: true,
            // The conflict notice and the save enablement are live
            // functions of the draft.
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _save(),
          ),
          if (duplicate)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                l10n.workspaceNameExists(trimmed),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Web delete-workspace modal: description copy (`delete.desc`) plus the
/// error-ink outline confirm (`deleteAction`).
class _DeleteWorkspaceDialog extends StatelessWidget {
  const _DeleteWorkspaceDialog({
    required this.workspace,
    required this.onDelete,
  });

  final WorkspaceSummary workspace;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    return _DsModalCard(
      title: l10n.deleteWorkspace,
      actions: [
        OutlinedButton(
          style: _dsCapsuleButton(theme),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        OutlinedButton(
          style: _dsCapsuleButton(theme).copyWith(
            foregroundColor: WidgetStatePropertyAll<Color>(
              theme.colorScheme.error,
            ),
          ),
          onPressed: () {
            onDelete();
            Navigator.of(context).pop();
          },
          child: Text(l10n.deleteWorkspace),
        ),
      ],
      child: Text(
        l10n.deleteWorkspaceConfirm(workspace.title, l10n.ungroupedLabel),
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// Web nested create-folder dialog (`createDialog`): names one folder
/// inside the browsing target; slashes never enter a folder name.
class _NewFolderDialog extends StatefulWidget {
  const _NewFolderDialog({required this.targetName, required this.onCreate});

  final String targetName;
  final void Function(String name) onCreate;

  @override
  State<_NewFolderDialog> createState() => _NewFolderDialogState();
}

class _NewFolderDialogState extends State<_NewFolderDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _create() {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    widget.onCreate(name);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    return _DsModalCard(
      title: l10n.newFolder,
      actions: [
        OutlinedButton(
          style: _dsCapsuleButton(theme),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          style: _dsCapsuleButton(theme),
          onPressed: _controller.text.trim().isEmpty ? null : _create,
          child: Text(l10n.create),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l10n.newFolderIn(widget.targetName),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          _DsTextInput(
            controller: _controller,
            hintText: l10n.untitledFolderHint,
            autofocus: true,
            onChanged: (text) {
              final sanitized = text.replaceAll('/', '').replaceAll('\\', '');
              if (sanitized != text) {
                _controller.text = sanitized;
                _controller.selection = TextSelection.collapsed(
                  offset: sanitized.length,
                );
              }
              setState(() {});
            },
            onSubmitted: (_) => _create(),
          ),
        ],
      ),
    );
  }
}

/// Host-directory browser backing the add-workspace flow — the mobile
/// bottom-docked form of the web DirectoryBrowser dialog: title and
/// crumb path bar (with the click-to-edit path zone), the folder list,
/// and the New-folder / Show-hidden / Cancel / Open footer. Picking a
/// folder adopts it as a workspace (the flow's one action).
class DirectoryBrowserDialog extends StatefulWidget {
  const DirectoryBrowserDialog({
    super.key,
    required this.listing,
    required this.loading,
    required this.onNavigate,
    required this.onCreateDirectory,
    required this.onSelect,
    required this.onClose,
  });

  final DirectoryListing? listing;
  final bool loading;
  final void Function(String path) onNavigate;
  final void Function(String name) onCreateDirectory;
  final void Function(String path) onSelect;
  final VoidCallback onClose;

  @override
  State<DirectoryBrowserDialog> createState() => _DirectoryBrowserDialogState();
}

class _DirectoryBrowserDialogState extends State<DirectoryBrowserDialog> {
  final TextEditingController _pathController = TextEditingController();
  bool _showHidden = false;
  bool _editingPath = false;

  @override
  void dispose() {
    _pathController.dispose();
    super.dispose();
  }

  /// Web `displayCrumbs`: inside the home subtree the chain starts at a
  /// localized Home crumb; outside it the full ancestry shows.
  List<DirectoryEntry> _displayCrumbs(DirectoryListing listing) {
    final l10n = AppLocalizations.of(context)!;
    final homeIndex = listing.crumbs.indexWhere(
      (crumb) => crumb.path == listing.home,
    );
    if (homeIndex == -1) return listing.crumbs;
    return <DirectoryEntry>[
      DirectoryEntry(name: l10n.homeCrumb, path: listing.home, hidden: false),
      ...listing.crumbs.skip(homeIndex + 1),
    ];
  }

  /// Web crumb edit zone: seed the draft with the current level and a
  /// trailing separator so typing continues into child names. A failed
  /// home listing seeds nothing — the editor is the recovery path.
  void _beginPathEdit() {
    final listing = widget.listing;
    if (listing == null) {
      _pathController.text = '';
    } else {
      final separator = listing.home.contains('\\') ? '\\' : '/';
      _pathController.text = listing.path.endsWith(separator)
          ? listing.path
          : listing.path + separator;
    }
    setState(() => _editingPath = true);
  }

  void _submitPath(String value) {
    final path = value.trim();
    if (path.isEmpty) return;
    setState(() => _editingPath = false);
    widget.onNavigate(path);
  }

  Future<void> _showNewFolderDialog() {
    final listing = widget.listing;
    if (listing == null) return Future<void>.value();
    final crumbs = _displayCrumbs(listing);
    final targetName = crumbs.isEmpty ? listing.path : crumbs.last.name;
    return showDialog<void>(
      context: context,
      builder: (_) => _NewFolderDialog(
        targetName: targetName,
        // The dialog dismisses itself on confirm; the callback only
        // dispatches (one route pop per gesture).
        onCreate: widget.onCreateDirectory,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ds = dsOf(context);
    final media = MediaQuery.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      constraints: BoxConstraints(maxHeight: media.size.height * 0.85),
      decoration: BoxDecoration(
        // Web Modal card family: layer-2 fill, r24, lv3 shadow.
        color: ds.bgLayer2,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: ds.borderInverted),
        boxShadow: kDsShadowLv3,
      ),
      child: Material(
        color: Colors.transparent,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(context),
            // A listing in flight keeps the stale panes standing (web
            // quiet navigation); the bar is the only movement.
            if (widget.loading) const LinearProgressIndicator(minHeight: 2),
            Flexible(child: _buildBody(context)),
            _buildFooter(context),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final ds = dsOf(context);
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final listing = widget.listing;
    final crumbs = listing == null
        ? const <DirectoryEntry>[]
        : _displayCrumbs(listing);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 8, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  l10n.selectWorkspaceDirectoryTitle,
                  style: theme.textTheme.titleMedium,
                ),
              ),
              _SheetIconButton(
                tooltip: l10n.close,
                icon: Icons.close,
                onTap: widget.onClose,
              ),
            ],
          ),
        ),
        if (_editingPath)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: _PathEditorRow(
              controller: _pathController,
              onSubmit: _submitPath,
              onCancel: () => setState(() => _editingPath = false),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 8, 4),
            child: SizedBox(
              height: 44,
              child: Row(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final (i, crumb) in crumbs.indexed)
                            _CrumbSeat(
                              crumb: crumb,
                              leadingDivider: i > 0,
                              onNavigate: widget.onNavigate,
                            ),
                        ],
                      ),
                    ),
                  ),
                  _SheetIconButton(
                    tooltip: l10n.editPathTooltip,
                    icon: Icons.edit_outlined,
                    iconSize: 16,
                    onTap: _beginPathEdit,
                  ),
                ],
              ),
            ),
          ),
        // Web `.header` bottom rule (border-l3 family).
        Container(height: 1, color: ds.borderL2),
      ],
    );
  }

  Widget _buildBody(BuildContext context) {
    final ds = dsOf(context);
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final listing = widget.listing;
    if (listing == null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: widget.loading
              ? const CircularProgressIndicator()
              : Text(
                  l10n.unableToLoadDirectory,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
        ),
      );
    }
    final entries = listing.entries
        .where((entry) => _showHidden || !entry.hidden)
        .toList(growable: false);
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: [
        if (entries.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              l10n.noFolders,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontSize: 13,
                color: ds.labelTertiary,
              ),
            ),
          ),
        for (final entry in entries)
          _DirectoryEntryRow(
            entry: entry,
            onTap: () => widget.onNavigate(entry.path),
          ),
        if (listing.truncated)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              l10n.tooManyFoldersHint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: ds.labelSecondary,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildFooter(BuildContext context) {
    final ds = dsOf(context);
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final listing = widget.listing;
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: ds.borderL2)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              OutlinedButton.icon(
                style: _dsCapsuleButton(theme),
                onPressed: listing == null || widget.loading
                    ? null
                    : _showNewFolderDialog,
                icon: const Icon(Icons.add, size: 14),
                label: Text(l10n.newFolder),
              ),
              const Spacer(),
              // Web `.showHiddenToggle`: fixed label, trailing check.
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => setState(() => _showHidden = !_showHidden),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      Text(
                        l10n.showHiddenFiles,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: _showHidden
                              ? theme.colorScheme.onSurface
                              : ds.labelSecondary,
                        ),
                      ),
                      if (_showHidden) ...[
                        const SizedBox(width: 4),
                        Icon(
                          Icons.check,
                          size: 14,
                          color: theme.colorScheme.onSurface,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              OutlinedButton(
                style: _dsCapsuleButton(theme),
                onPressed: widget.onClose,
                child: Text(l10n.cancel),
              ),
              const SizedBox(width: 8),
              FilledButton(
                style: _dsCapsuleButton(theme),
                onPressed: listing == null || widget.loading
                    ? null
                    : () => widget.onSelect(listing.path),
                child: Text(l10n.open),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Web `.crumb`: 13px/500 tertiary breadcrumb chip with the chevron
/// divider between crumbs; tapping navigates to that level.
class _CrumbSeat extends StatelessWidget {
  const _CrumbSeat({
    required this.crumb,
    required this.leadingDivider,
    required this.onNavigate,
  });

  final DirectoryEntry crumb;
  final bool leadingDivider;
  final void Function(String path) onNavigate;

  @override
  Widget build(BuildContext context) {
    final ds = dsOf(context);
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (leadingDivider)
          Icon(Icons.chevron_right, size: 12, color: ds.labelTertiary),
        InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () => onNavigate(crumb.path),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 160),
              child: Text(
                crumb.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: ds.labelTertiary,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Web `.pathInput` seat: the crumb bar flips into this editor.
class _PathEditorRow extends StatelessWidget {
  const _PathEditorRow({
    required this.controller,
    required this.onSubmit,
    this.onCancel,
  });

  final TextEditingController controller;
  final ValueChanged<String> onSubmit;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final ds = dsOf(context);
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: ds.borderL2),
    );
    return TextField(
      controller: controller,
      autofocus: true,
      style: theme.textTheme.bodyMedium?.copyWith(fontSize: 13),
      decoration: InputDecoration(
        isDense: true,
        hintText: l10n.pathLabel,
        hintStyle: theme.textTheme.bodyMedium?.copyWith(
          fontSize: 13,
          color: ds.labelTertiary,
        ),
        prefixIcon: Icon(
          Icons.edit_outlined,
          size: 14,
          color: ds.labelTertiary,
        ),
        prefixIconConstraints: const BoxConstraints(minWidth: 36),
        suffixIcon: onCancel == null
            ? null
            : InkWell(
                onTap: onCancel,
                child: Icon(Icons.close, size: 14, color: ds.labelSecondary),
              ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
        border: border,
        enabledBorder: border,
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: ds.accent),
        ),
      ),
      onSubmitted: onSubmit,
    );
  }
}

/// Web `.row` (LevelColumn): folder glyph, 13px/500 name, trailing
/// chevron; 44px touch height with the row-family 8px radius.
class _DirectoryEntryRow extends StatelessWidget {
  const _DirectoryEntryRow({required this.entry, required this.onTap});

  final DirectoryEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ds = dsOf(context);
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        hoverColor: ds.interactiveBgHover,
        onTap: onTap,
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              Icon(Icons.folder_outlined, size: 16, color: ds.labelSecondary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  entry.hidden ? '.${entry.name}' : entry.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Icon(Icons.chevron_right, size: 14, color: ds.labelTertiary),
            ],
          ),
        ),
      ),
    );
  }
}

/// Web Modal `.close` / crumb-bar pencil: circle icon seat (label
/// secondary ink, hover fill) at touch size.
class _SheetIconButton extends StatelessWidget {
  const _SheetIconButton({
    required this.tooltip,
    required this.icon,
    required this.onTap,
    this.iconSize = 18,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final ds = dsOf(context);
    return SizedBox(
      width: 44,
      height: 44,
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(22),
            hoverColor: ds.interactiveBgHover,
            onTap: onTap,
            child: Center(
              child: Icon(icon, size: iconSize, color: ds.labelSecondary),
            ),
          ),
        ),
      ),
    );
  }
}
