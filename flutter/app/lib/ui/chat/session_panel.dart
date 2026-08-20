/// Chat sidebar — Flutter port of the dsh web sidebar's browsing region
/// (ui-workspace WorkspaceBrowser): the section header with its trailing
/// search toggle, the expanding search capsule, and the workspace-grouped
/// session tree with the per-group overflow control. The foot carries
/// the settings trigger (web `sidebar.settings` seat): a divider-topped
/// 44px row that selects the Settings destination. The browsing toggles
/// (per-group expansion overrides, per-group overflow expansions)
/// persist through the local state store — except that the group
/// holding the active session never folds, and within any group the
/// active session rides first (same-group pinning). Shares its design
/// language with the Workspaces tab (workspace_screen.dart): 44px touch
/// rows, folder group headers, and the flat search-result list that
/// replaces the tree while a query is active.
///
/// With more than one backend configured, the browsing region groups
/// under per-backend section headers (live connection dot + label +
/// host + the Active marker): every configured backend's sessions stay
/// browsable and live, tapping another backend's header or one of its
/// sessions makes it the backend the chat surface presents.
library;

import 'package:app/l10n/app_localizations.dart';
import 'package:domain/model/backend.dart';
import 'package:domain/model/session.dart';
import 'package:domain/model/workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../local_state/local_state_providers.dart';
import '../root/app_destination.dart';
import '../shared/backend_connection_dot.dart';
import '../theme/deepsuite_extension.dart' show DeepSuiteColors, dsOf;
import '../theme/deepsuite_tokens.dart' show DeepSuiteStatic, kDsDuration;
import 'brand_wordmark.dart';

/// One backend's slice of the sidebar's browsing region: that host's
/// config, whether it is the one the chat surface presents, and its
/// live session/workspace facts.
final class BackendSessionSlice {
  const BackendSessionSlice({
    required this.backend,
    required this.active,
    required this.sessions,
    required this.workspaces,
  });

  final BackendConfig backend;
  final bool active;
  final List<SessionSummary> sessions;
  final List<WorkspaceSummary> workspaces;
}

/// Web tree.ts `UNGROUPED_KEY`: group key for sessions outside every
/// registered workspace.
const String _ungroupedKey = '';

/// Web `COLLAPSED_SESSION_LIMIT`: session rows a group shows before its
/// local overflow control.
const int _collapsedSessionLimit = 5;

/// Web tree.ts `sessionVisible`: the coarse wire origin marking a subagent
/// child — such sessions browse through their parent's subagent catalog,
/// never as independent sidebar rows.
const String _subagentOrigin = 'subagent';

/// Local state store key: per-group expansion overrides
/// (`sidebar.groupOverrides`, `Map<String, bool>`).
const String _groupOverridesKey = 'sidebar.groupOverrides';

/// Local state store key: groups whose overflow control is expanded
/// (`sidebar.overflowExpanded`, `List<String>`).
const String _overflowExpandedKey = 'sidebar.overflowExpanded';

class SessionPanel extends ConsumerStatefulWidget {
  const SessionPanel({
    super.key,
    this.inDrawer = false,
    required this.sessions,
    required this.workspaces,
    required this.searchResults,
    required this.selectedSessionId,
    required this.onSelectSession,
    required this.onCreateSession,
    required this.onSearchSessions,
    this.onRailChanged,
    this.backendSlices,
    this.onSelectBackend,
    this.onSelectBackendSession,
  });

  /// Drawer form: no rail toggle, full-height fill.
  final bool inDrawer;

  /// Notifies the host pane when the icon-rail state flips (wide panes).
  final void Function(bool rail)? onRailChanged;

  final List<SessionSummary> sessions;
  final List<WorkspaceSummary> workspaces;
  final List<SessionSearchResult> searchResults;
  final String? selectedSessionId;
  final void Function(String sessionId) onSelectSession;
  final void Function(String? workspaceId) onCreateSession;
  final void Function(String query) onSearchSessions;

  /// Every configured backend's browsing slice; more than one switches
  /// the browsing region into backend-grouped form (null/one keeps the
  /// flat single-host tree). The active slice mirrors [sessions] and
  /// [workspaces].
  final List<BackendSessionSlice>? backendSlices;

  /// Backend section header tap: makes that backend the one the chat
  /// surface presents.
  final void Function(String backendId)? onSelectBackend;

  /// Session tap under any backend's slice; the active backend reduces
  /// to [onSelectSession].
  final void Function(String backendId, String sessionId)?
  onSelectBackendSession;

  @override
  ConsumerState<SessionPanel> createState() => _SessionPanelState();
}

class _SessionPanelState extends ConsumerState<SessionPanel> {
  final TextEditingController _queryController = TextEditingController();
  bool _collapsedToRail = false;

  /// Web `searchExpanded`: the capsule is mounted and owns the live query.
  bool _searchActive = false;

  /// Web `groupExpansion` (user-toggled half): explicit expansion by
  /// group key for the groups that can fold. The current group is
  /// exempt — it is always expanded regardless of any override.
  final Map<String, bool> _groupOverrides = <String, bool>{};

  /// Web `expandedSessionGroups`: groups whose overflow control is
  /// expanded past [_collapsedSessionLimit].
  final Set<String> _overflowExpandedGroups = <String>{};

  /// Whether the persisted browsing toggles have been applied once the
  /// store resolved; the defaults cover the pre-load window.
  bool _seededFromStore = false;

  /// Whether the user flipped any browsing toggle before the store
  /// resolved; a live toggle outranks the persisted snapshot.
  bool _userToggled = false;

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  /// Web `.searchButton`: the header control expands the capsule;
  /// collapsing also drops the query and resets the host results.
  void _toggleSearch() {
    setState(() => _searchActive = !_searchActive);
    if (!_searchActive) _resetSearch();
  }

  /// Web `.clearButton`: clearing also collapses the capsule.
  void _collapseSearch() {
    setState(() => _searchActive = false);
    _resetSearch();
  }

  void _resetSearch() {
    _queryController.clear();
    widget.onSearchSessions('');
  }

  /// Web search input: every keystroke re-dispatches the host content
  /// search (debounce lives in the host wiring) and flips the browsing
  /// region between the tree and the flat result list.
  void _onQueryChanged(String text) {
    setState(() {});
    widget.onSearchSessions(text);
  }

  /// Web rail search control: expanding the pane lands in the search box.
  void _openSearchFromRail() {
    setState(() {
      _collapsedToRail = false;
      _searchActive = true;
    });
    widget.onRailChanged?.call(false);
  }

  /// Web ProjectRowItem `onToggle` for the groups that CAN fold: flips
  /// one group's expansion and persists the override. The group holding
  /// the active session never folds (see [_isGroupExpanded]) — its
  /// toggle is a no-op, collapsing it would hide the active session
  /// behind a hunt.
  void _toggleGroup(String key) {
    final currentGroupKey = _currentGroupKeyOf(
      widget.sessions,
      widget.workspaces,
      widget.selectedSessionId,
    );
    if (key == currentGroupKey) return;
    final expanded = _groupOverrides[key] ?? false;
    _userToggled = true;
    setState(() => _groupOverrides[key] = !expanded);
    _persistBrowsingState();
  }

  /// Web `expandedSessionGroups` toggle: the per-group overflow control.
  void _toggleOverflow(String key) {
    _userToggled = true;
    setState(() {
      if (!_overflowExpandedGroups.remove(key)) {
        _overflowExpandedGroups.add(key);
      }
    });
    _persistBrowsingState();
  }

  /// Applies the persisted browsing toggles ([_groupOverridesKey],
  /// [_overflowExpandedKey]) once the store resolves; until then the
  /// panel runs on the defaults, and a user toggle inside that window
  /// cancels the snapshot (live intent wins). Runs inside build without
  /// setState — the same build pass renders the seeded values.
  void _seedBrowsingStateFromStore() {
    final store = ref.watch(localStateStoreProvider).value;
    if (store == null || _seededFromStore) return;
    _seededFromStore = true;
    if (_userToggled) return;
    _groupOverrides.addAll(
      _decodeGroupOverrides(store.read(_groupOverridesKey)),
    );
    _overflowExpandedGroups.addAll(
      _decodeOverflowExpanded(store.read(_overflowExpandedKey)),
    );
  }

  /// Mirrors the browsing toggles into the local state store; before the
  /// store resolves the toggles stay live-only — the next toggle after
  /// load persists the full maps.
  void _persistBrowsingState() {
    final store = ref.read(localStateStoreProvider).value;
    if (store == null) return;
    store.write(_groupOverridesKey, Map<String, bool>.of(_groupOverrides));
    store.write(_overflowExpandedKey, _overflowExpandedGroups.toList());
  }

  /// Web tree.ts current-group derivation: the workspace whose account
  /// holds the selected session, or the Ungrouped key when no account
  /// names it (null when nothing is selected or the summary has not
  /// landed yet).
  String? _currentGroupKeyOf(
    List<SessionSummary> sessions,
    List<WorkspaceSummary> workspaces,
    String? selectedSessionId,
  ) {
    if (selectedSessionId == null) return null;
    final session = sessions
        .where((session) => session.id == selectedSessionId)
        .firstOrNull;
    if (session == null) return null;
    for (final workspace in workspaces) {
      if (workspace.sessionIds.contains(selectedSessionId)) {
        return workspace.workspaceId;
      }
    }
    return _ungroupedKey;
  }

  /// The group holding the active session is ALWAYS expanded — the
  /// current session must never hide behind a fold the user has to
  /// hunt through. Every other group follows its persisted override
  /// (default collapsed).
  bool _isGroupExpanded(String key, String? currentGroupKey) =>
      key == currentGroupKey || (_groupOverrides[key] ?? false);

  /// Web tree.ts `sessionVisible`: ordinary sessions are visible; among
  /// blank sessions, only the current one is visible. Subagent children
  /// use their parent header catalog. Archived sessions never reach this
  /// panel — the adapter's `observeSessions` drops ids in the workspace
  /// registry's archived set — so this port does not re-filter them.
  /// A non-active backend's slice passes a null selection: blank
  /// placeholders never browse there.
  bool _sessionVisibleOf(SessionSummary session, String? selectedSessionId) =>
      session.origin != _subagentOrigin &&
      (!session.blank || session.id == selectedSessionId);

  /// The workspace account holding one session, if any (web membership is
  /// the Workspace's `sessionIds` — the wire session summary carries no
  /// workspace field).
  WorkspaceSummary? _workspaceOf(
    SessionSummary session,
    List<WorkspaceSummary> workspaces,
  ) {
    for (final workspace in workspaces) {
      if (workspace.sessionIds.contains(session.id)) return workspace;
    }
    return null;
  }

  /// Web tree.ts `groupByWorkspace`: one group per workspace entity in
  /// stable host order, members resolved from `sessionIds` in their
  /// stored order; sessions outside every account trail in the
  /// browser-local Ungrouped bucket by recency. Within a group the
  /// active session rides first (same-group pinning — the row the user
  /// is most likely to reach stays above the fold even past the
  /// collapsed-session overflow limit).
  List<_SessionGroupData> _deriveSessionGroupsOf(
    List<SessionSummary> sessions,
    List<WorkspaceSummary> workspaces,
    String? selectedSessionId,
    AppLocalizations l10n,
  ) {
    final sessionsById = <String, SessionSummary>{
      for (final session in sessions) session.id: session,
    };
    final accounted = <String>{};
    final groups = <_SessionGroupData>[];
    for (final workspace in workspaces) {
      final members = <SessionSummary>[];
      for (final id in workspace.sessionIds) {
        final summary = sessionsById[id];
        // The account may lead the list pull; the row appears when the
        // summary lands (web rule).
        if (summary == null) continue;
        accounted.add(id);
        if (!_sessionVisibleOf(summary, selectedSessionId)) continue;
        members.add(summary);
      }
      groups.add(
        _SessionGroupData(
          key: workspace.workspaceId,
          label: workspace.title,
          sessions: _withActiveSessionPinned(members, selectedSessionId),
        ),
      );
    }
    final ungrouped = _sortedByRecency(
      sessions.where(
        (session) =>
            !accounted.contains(session.id) &&
            _sessionVisibleOf(session, selectedSessionId),
      ),
    );
    if (ungrouped.isNotEmpty) {
      groups.add(
        _SessionGroupData(
          key: _ungroupedKey,
          label: l10n.ungroupedLabel,
          sessions: _withActiveSessionPinned(ungrouped, selectedSessionId),
        ),
      );
    }
    return groups;
  }

  /// Moves the active session (when present) to the head of [members],
  /// preserving the rest of the order.
  List<SessionSummary> _withActiveSessionPinned(
    List<SessionSummary> members,
    String? selectedSessionId,
  ) {
    if (selectedSessionId == null) return members;
    final index = members.indexWhere(
      (session) => session.id == selectedSessionId,
    );
    if (index <= 0) return members;
    return <SessionSummary>[
      members[index],
      ...members.sublist(0, index),
      ...members.sublist(index + 1),
    ];
  }

  /// The browsing-slice group key: the active backend keeps its raw
  /// workspace ids (persisted expansion overrides from the
  /// single-backend era stay valid), other backends namespace under
  /// their backend id.
  String _sliceGroupKey(BackendSessionSlice slice, String key) =>
      slice.active ? key : '${slice.backend.id}\u0000$key';

  /// Session tap under one slice: the active backend selects directly;
  /// another backend's row routes through the backend-aware callback
  /// (which switches the active backend first).
  void _selectSessionOn(BackendSessionSlice slice, String sessionId) {
    final backendAware = widget.onSelectBackendSession;
    if (backendAware == null || slice.active) {
      widget.onSelectSession(sessionId);
    } else {
      backendAware(slice.backend.id, sessionId);
    }
  }

  /// Web tree.ts `labelOf`: the workspace title when an account holds the
  /// session, else the cwd basename (search-result context rows). The
  /// result list is active-backend scoped.
  String _workspaceLabel(SessionSummary session, AppLocalizations l10n) {
    final workspace = _workspaceOf(session, widget.workspaces);
    if (workspace != null) return workspace.title;
    return _cwdBasename(session.cwd, l10n);
  }

  Future<void> _showNewSessionDialog() {
    return showDialog<void>(
      context: context,
      builder: (context) => _NewSessionDialog(
        workspaces: widget.workspaces,
        onCreateSession: widget.onCreateSession,
      ),
    );
  }

  /// Web logo row (60px): wordmark doubles as a New Session shortcut; the
  /// toggle collapses to the icon rail.
  Widget _buildBrandRow(BuildContext context, DeepSuiteColors ds) {
    final l10n = AppLocalizations.of(context)!;
    final rail = !widget.inDrawer && _collapsedToRail;
    return SizedBox(
      height: 60,
      child: Row(
        children: [
          if (!rail)
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: () => widget.onCreateSession(null),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 6),
                    child: BrandWordmark(height: 22),
                  ),
                ),
              ),
            ),
          if (!rail) const SizedBox(width: 8),
          if (!widget.inDrawer)
            IconButton(
              tooltip: rail ? l10n.openSidebar : l10n.collapseSidebar,
              constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
              padding: EdgeInsets.zero,
              onPressed: () {
                setState(() => _collapsedToRail = !rail);
                widget.onRailChanged?.call(_collapsedToRail);
              },
              icon: Icon(
                rail ? Icons.menu : Icons.view_sidebar_outlined,
                size: rail ? 22 : 16,
                color: ds.labelSecondary,
              ),
            ),
        ],
      ),
    );
  }

  /// Web `.newSession`: 38px, border l2, r12, elevated fill, icon + label.
  /// The sidebar keeps it above the browsing region (web sidebar order);
  /// workspace management itself lives in the Workspaces tab.
  Widget _buildNewSessionButton(BuildContext context, DeepSuiteColors ds) {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 0, 2, 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _showNewSessionDialog,
        child: Container(
          height: 38,
          width: double.infinity,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border.all(color: ds.borderL2),
            borderRadius: BorderRadius.circular(12),
            color: ds.buttonElevatedFill,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.chat_bubble_outline,
                size: 14,
                color: ds.labelSecondary,
              ),
              const SizedBox(width: 6),
              Text(
                l10n.newSession,
                style: Theme.of(context).textTheme.labelMedium
                    ?.copyWith(fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Rail form: the wide pane's controls as bare icon seats in the same
  /// top-down order — new session, then search (which expands the pane and
  /// lands in the box) — above the icon-per-session list. Rail avatars
  /// follow the same tree.ts `sessionVisible` rule as the grouped tree.
  List<Widget> _buildRailChildren(BuildContext context, DeepSuiteColors ds) {
    final l10n = AppLocalizations.of(context)!;
    return [
      IconButton(
        tooltip: l10n.newSession,
        constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
        padding: EdgeInsets.zero,
        onPressed: _showNewSessionDialog,
        icon: Icon(
          Icons.chat_bubble_outline,
          size: 20,
          color: ds.labelSecondary,
        ),
      ),
      const SizedBox(height: 12),
      IconButton(
        tooltip: l10n.searchSessions,
        constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
        padding: EdgeInsets.zero,
        onPressed: _openSearchFromRail,
        icon: Icon(Icons.search, size: 20, color: ds.labelSecondary),
      ),
      const SizedBox(height: 12),
      Expanded(
        child: ListView(
          padding: const EdgeInsets.only(top: 4, bottom: 16),
          children: [
            for (final session in widget.sessions.where(
              (session) => _sessionVisibleOf(session, widget.selectedSessionId),
            ))
              IconButton(
                tooltip: session.displayTitle,
                onPressed: () => widget.onSelectSession(session.id),
                icon: CircleAvatar(
                  radius: 14,
                  backgroundColor: session.id == widget.selectedSessionId
                      ? ds.sidebarNavItemActive
                      : ds.sidebarNavItemHover,
                  child: Text(
                    session.displayTitle.substring(0, 1),
                    style: Theme.of(context).textTheme.labelSmall
                        ?.copyWith(color: ds.labelSecondary),
                  ),
                ),
              ),
          ],
        ),
      ),
    ];
  }

  /// Wide/drawer form: the browsing region below the brand row — New
  /// session bar, section header, search capsule, then the tree or the
  /// search-result list with the bottom continuation fade, and the
  /// settings trigger pinned in the foot below it all.
  List<Widget> _buildWideChildren(BuildContext context, DeepSuiteColors ds) {
    final l10n = AppLocalizations.of(context)!;
    return [
      _buildNewSessionButton(context, ds),
      _SectionHeader(
        title: l10n.destinationWorkspaces,
        searchActive: _searchActive,
        onToggleSearch: _toggleSearch,
      ),
      if (_searchActive)
        _SearchCapsule(
          controller: _queryController,
          onChanged: _onQueryChanged,
          onCollapse: _collapseSearch,
        ),
      Expanded(
        child: Stack(
          children: [
            // Web listArea: a non-empty query replaces the tree with the
            // flat result list; clearing restores the tree.
            if (_queryController.text.trim().isEmpty)
              _buildSessionTree(
                context,
                ds,
                _currentGroupKeyOf(
                  widget.sessions,
                  widget.workspaces,
                  widget.selectedSessionId,
                ),
              )
            else
              _buildSearchResults(context, ds),
            // Web WorkspaceBrowser `.fade`: bottom continuation hint
            // tracking the sidebar fill across themes.
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
      _buildSettingsFooter(context, ds),
    ];
  }

  /// Web sidebar foot (`sidebar.settings` seat; ui-settings-general
  /// chrome.tsx `TriggerContent` + SettingsRoot.module.css `.trigger`):
  /// the bottom-pinned settings row — hairline divider, 44px touch
  /// height, gear glyph, label, interactive-bg-hover fill. The web
  /// drops the label in the collapsed rail column; both mobile forms
  /// (wide pane and drawer) are wide enough for the one-word label,
  /// so each shows icon + label. Tapping selects the Settings
  /// destination through [appDestinationProvider].
  Widget _buildSettingsFooter(BuildContext context, DeepSuiteColors ds) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Divider(height: 1, thickness: 1, color: ds.divider),
        Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            hoverColor: ds.interactiveBgHover,
            highlightColor: ds.interactiveBgHover,
            onTap: () => ref
                .read(appDestinationProvider.notifier)
                .select(AppDestination.settings),
            child: SizedBox(
              height: 44,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    Icon(
                      Icons.settings_outlined,
                      size: 18,
                      color: ds.labelSecondary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      l10n.destinationSettings,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Web WorkspaceBrowser `SessionTree` (mobile form): the grouped
  /// browsing list — the panel's only scrolling region. With more than
  /// one backend configured, every backend gets its own section: a
  /// live-status header over its own workspace-grouped tree.
  Widget _buildSessionTree(
    BuildContext context,
    DeepSuiteColors ds,
    String? currentGroupKey,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final slices = widget.backendSlices;
    if (slices != null && slices.length > 1) {
      return _buildBackendSections(context, ds);
    }
    final groups = _deriveSessionGroupsOf(
      widget.sessions,
      widget.workspaces,
      widget.selectedSessionId,
      l10n,
    );
    if (groups.isEmpty) {
      // Web `.empty` (aligned with the row grid).
      return Padding(
        padding: const EdgeInsets.fromLTRB(8, 16, 8, 0),
        child: Text(
          l10n.noSessionsYet,
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(fontSize: 13, color: ds.labelTertiary),
        ),
      );
    }
    final nowEpochMs = DateTime.now().millisecondsSinceEpoch;
    return ListView(
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        for (var i = 0; i < groups.length; i++) ...[
          // Web `.groupSection + .groupSection` inter-group spacing.
          if (i > 0) const SizedBox(height: 4),
          _GroupSection(
            group: groups[i],
            expanded: _isGroupExpanded(groups[i].key, currentGroupKey),
            overflowExpanded: _overflowExpandedGroups.contains(groups[i].key),
            containsCurrent: groups[i].key == currentGroupKey,
            selectedSessionId: widget.selectedSessionId,
            nowEpochMs: nowEpochMs,
            onToggle: () => _toggleGroup(groups[i].key),
            onToggleOverflow: () => _toggleOverflow(groups[i].key),
            onSelectSession: widget.onSelectSession,
          ),
        ],
      ],
    );
  }

  /// The multi-backend browsing region: one section per configured
  /// backend — live connection dot + label + host + the Active marker,
  /// tapping another backend's header selects it — over that backend's
  /// own grouped tree. The active backend's group keys stay raw
  /// (persisted overrides compatible); others namespace under their
  /// backend id and default collapsed.
  Widget _buildBackendSections(BuildContext context, DeepSuiteColors ds) {
    final nowEpochMs = DateTime.now().millisecondsSinceEpoch;
    return ListView(
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        for (var i = 0; i < widget.backendSlices!.length; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          _BackendSectionHeader(
            slice: widget.backendSlices![i],
            // The active backend's header is not a switch control (the
            // registry would no-op the redundant select anyway).
            onSelectBackend: widget.backendSlices![i].active
                ? null
                : () => widget.onSelectBackend?.call(
                    widget.backendSlices![i].backend.id,
                  ),
          ),
          ..._sliceGroupSections(
            context,
            ds,
            widget.backendSlices![i],
            nowEpochMs,
          ),
        ],
      ],
    );
  }

  /// One backend's grouped-tree rows (no header): the slice's own
  /// sessions/workspaces, its own selection highlight (only the active
  /// backend carries one), and backend-aware row taps.
  List<Widget> _sliceGroupSections(
    BuildContext context,
    DeepSuiteColors ds,
    BackendSessionSlice slice,
    int nowEpochMs,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final selectedSessionId = slice.active ? widget.selectedSessionId : null;
    final groups = _deriveSessionGroupsOf(
      slice.sessions,
      slice.workspaces,
      selectedSessionId,
      l10n,
    );
    final currentGroupKey = _currentGroupKeyOf(
      slice.sessions,
      slice.workspaces,
      selectedSessionId,
    );
    return [
      for (var i = 0; i < groups.length; i++) ...[
        if (i > 0) const SizedBox(height: 4),
        _GroupSection(
          group: groups[i],
          expanded: _isGroupExpanded(
            _sliceGroupKey(slice, groups[i].key),
            currentGroupKey,
          ),
          overflowExpanded: _overflowExpandedGroups.contains(
            _sliceGroupKey(slice, groups[i].key),
          ),
          containsCurrent: slice.active && groups[i].key == currentGroupKey,
          selectedSessionId: selectedSessionId,
          nowEpochMs: nowEpochMs,
          onToggle: () => _toggleGroup(_sliceGroupKey(slice, groups[i].key)),
          onToggleOverflow: () =>
              _toggleOverflow(_sliceGroupKey(slice, groups[i].key)),
          onSelectSession: (sessionId) => _selectSessionOn(slice, sessionId),
        ),
      ],
    ];
  }

  /// Web WorkspaceBrowser `SearchResults`: the flat result list replaces
  /// the tree while a query is active; rows whose session summary has not
  /// landed stay hidden until the list catches up (web drops them the
  /// same way).
  Widget _buildSearchResults(BuildContext context, DeepSuiteColors ds) {
    final l10n = AppLocalizations.of(context)!;
    // Web tree.ts `deriveSearchResults`: content matches render only for
    // visible non-blank summaries — subagent children never surface, and
    // blank placeholders never match a query (not even the current one).
    final sessionsById = <String, SessionSummary>{
      for (final session in widget.sessions.where(
        (session) =>
            !session.blank &&
            _sessionVisibleOf(session, widget.selectedSessionId),
      ))
        session.id: session,
    };
    final rows = <Widget>[
      for (final result in widget.searchResults)
        if (sessionsById[result.sessionId] case final session?)
          _SearchResultRow(
            session: session,
            snippet: result.snippet,
            workspaceLabel: _workspaceLabel(session, l10n),
            selected: session.id == widget.selectedSessionId,
            onSelect: () => widget.onSelectSession(session.id),
          ),
    ];
    if (rows.isEmpty) {
      rows.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 16, 8, 0),
          child: Text(
            l10n.noMatchingSessions,
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(fontSize: 13, color: ds.labelTertiary),
          ),
        ),
      );
    }
    return ListView(padding: const EdgeInsets.only(bottom: 16), children: rows);
  }

  @override
  Widget build(BuildContext context) {
    _seedBrowsingStateFromStore();
    final ds = dsOf(context);
    final rail = !widget.inDrawer && _collapsedToRail;
    return AnimatedContainer(
      duration: kDsDuration,
      curve: Curves.easeInOut,
      width: rail ? 56 : null,
      color: ds.sidebarFill,
      child: Material(
        color: Colors.transparent,
        child: Padding(
          padding: EdgeInsets.all(rail ? 4 : 8),
          child: Column(
            children: [
              _buildBrandRow(context, ds),
              if (rail)
                ..._buildRailChildren(context, ds)
              else
                ..._buildWideChildren(context, ds),
            ],
          ),
        ),
      ),
    );
  }
}

/// Web tree.ts `GroupNode` facts this sidebar renders: group key, display
/// label, and the newest-first member rows.
final class _SessionGroupData {
  const _SessionGroupData({
    required this.key,
    required this.label,
    required this.sessions,
  });

  /// Workspace id, or [_ungroupedKey] for the Ungrouped bucket.
  final String key;
  final String label;
  final List<SessionSummary> sessions;
}

/// Web tree.ts `byRecency`: newest update first, session id as the
/// deterministic tiebreak.
List<SessionSummary> _sortedByRecency(Iterable<SessionSummary> sessions) {
  final ordered = sessions.toList()
    ..sort((a, b) {
      final delta = b.updatedAtEpochMs - a.updatedAtEpochMs;
      if (delta != 0) return delta;
      return a.id.compareTo(b.id);
    });
  return ordered;
}

/// Decodes [_groupOverridesKey]: the store's JSON round-trip yields
/// `Map<String, dynamic>`, so members are checked, not cast wholesale —
/// a malformed entry drops out, never throws.
Map<String, bool> _decodeGroupOverrides(Object? raw) {
  if (raw is! Map) return const <String, bool>{};
  return <String, bool>{
    for (final entry in raw.entries)
      if (entry.key is String && entry.value is bool)
        entry.key as String: entry.value as bool,
  };
}

/// Decodes [_overflowExpandedKey] under the same checked rule.
List<String> _decodeOverflowExpanded(Object? raw) {
  if (raw is! List) return const <String>[];
  return <String>[
    for (final item in raw)
      if (item is String) item,
  ];
}

/// Web tree.ts `workspaceLabel`: the cwd basename, or the Ungrouped label
/// when there is no path to name.
String _cwdBasename(String? cwd, AppLocalizations l10n) {
  if (cwd == null || cwd.isEmpty) return l10n.ungroupedLabel;
  final segments = cwd.split(RegExp(r'[/\\]+'));
  for (final segment in segments.reversed) {
    if (segment.isNotEmpty) return segment;
  }
  return cwd;
}

/// Web tree.ts `relativeTime` plus the en dictionary: the compact trailing
/// label for session rows ("now"/"5min"/"3h"/"2d"/"4mo"/"1y").
String _relativeTimeLabel(
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

/// Web WorkspaceBrowser `.sectionHeader` (Workspaces-tab idiom): the
/// section label with the trailing search icon action. The sidebar keeps
/// only the search control — workspace management lives in the Workspaces
/// tab.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.searchActive,
    required this.onToggleSearch,
  });

  final String title;
  final bool searchActive;
  final VoidCallback onToggleSearch;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final ds = dsOf(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 4, 4),
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
              tooltip: l10n.searchSessions,
              icon: Icons.search,
              active: searchActive,
              onTap: onToggleSearch,
            ),
          ],
        ),
      ),
    );
  }
}

/// Web WorkspaceBrowser `.iconButton`: circular hover-lit icon seat
/// (label-secondary ink; primary ink while its control is engaged).
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

/// Web WorkspaceBrowser `.searchExpanded` (Workspaces-tab idiom): the
/// bordered search capsule — r10, border-l2, 13px input, trailing clear
/// circle that clears and collapses.
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
    final l10n = AppLocalizations.of(context)!;
    final ds = dsOf(context);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 4, 4),
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
                  hintText: l10n.searchSessionsHint,
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

/// Web WorkspaceBrowser `.groupSection`: the group header row plus its
/// expanded session run (2px intra-group rhythm) and the local overflow
/// control.
/// One backend's section header in the multi-backend browsing region:
/// the live connection dot, the backend label over `host:port`, and
/// the Active marker — the same vocabulary as the Workspaces tab's
/// backend headers. Tapping a non-active header selects that backend.
class _BackendSectionHeader extends StatelessWidget {
  const _BackendSectionHeader({
    required this.slice,
    required this.onSelectBackend,
  });

  final BackendSessionSlice slice;

  /// Null on the active backend (nothing to switch to) and when no
  /// switch wiring was provided.
  final VoidCallback? onSelectBackend;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final ds = dsOf(context);
    final backend = slice.backend;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onSelectBackend,
        child: Container(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
          decoration: BoxDecoration(
            color: slice.active ? ds.sidebarNavItemActive : null,
            borderRadius: BorderRadius.circular(8),
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
                      style: theme.textTheme.labelMedium,
                    ),
                    Text(
                      '${backend.baseUri.host}:${backend.baseUri.port}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: ds.labelTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: slice.active ? ds.specificSelector : null,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  slice.active
                      ? l10n.backendStatusActive
                      : l10n.backendStatusStandby,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: slice.active ? ds.labelSecondary : ds.labelTertiary,
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

class _GroupSection extends StatelessWidget {
  const _GroupSection({
    required this.group,
    required this.expanded,
    required this.overflowExpanded,
    required this.containsCurrent,
    required this.selectedSessionId,
    required this.nowEpochMs,
    required this.onToggle,
    required this.onToggleOverflow,
    required this.onSelectSession,
  });

  final _SessionGroupData group;
  final bool expanded;
  final bool overflowExpanded;
  final bool containsCurrent;
  final String? selectedSessionId;
  final int nowEpochMs;
  final VoidCallback onToggle;
  final VoidCallback onToggleOverflow;
  final void Function(String sessionId) onSelectSession;

  @override
  Widget build(BuildContext context) {
    final sessions = group.sessions;
    final visibleCount =
        overflowExpanded || sessions.length <= _collapsedSessionLimit
        ? sessions.length
        : _collapsedSessionLimit;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _GroupHeaderRow(
          label: group.label,
          sessionCount: sessions.length,
          expanded: expanded,
          folderActive: expanded && containsCurrent,
          onToggle: onToggle,
        ),
        if (expanded) ...[
          const SizedBox(height: 2),
          for (var i = 0; i < visibleCount; i++) ...[
            if (i > 0) const SizedBox(height: 2),
            _SessionRow(
              session: sessions[i],
              selected: sessions[i].id == selectedSessionId,
              nowEpochMs: nowEpochMs,
              onSelect: sessions[i].id == selectedSessionId
                  ? null
                  : () => onSelectSession(sessions[i].id),
            ),
          ],
          if (sessions.length > _collapsedSessionLimit) ...[
            const SizedBox(height: 2),
            _OverflowRow(
              expanded: overflowExpanded,
              totalCount: sessions.length,
              onTap: onToggleOverflow,
            ),
          ],
        ],
      ],
    );
  }
}

/// Web Rows.tsx `ProjectRowItem` (Workspaces-tab row idiom): folder glyph
/// that opens with the group, title, session-count caption; the expanded
/// row keeps the hover fill. Workspace rename/delete stay in the
/// Workspaces tab — the sidebar row only toggles expansion.
class _GroupHeaderRow extends StatelessWidget {
  const _GroupHeaderRow({
    required this.label,
    required this.sessionCount,
    required this.expanded,
    required this.folderActive,
    required this.onToggle,
  });

  final String label;
  final int sessionCount;
  final bool expanded;
  final bool folderActive;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
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
              // Web `.slot .folder`: tertiary folder glyph (brand tint
              // while the group holds the selected session and is open).
              Icon(
                expanded ? Icons.folder_open : Icons.folder_outlined,
                size: 16,
                color: folderActive ? ds.accent : ds.labelTertiary,
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
              const SizedBox(width: 6),
              Text(
                l10n.sessionCount(sessionCount),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 12,
                  color: ds.labelTertiary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Web Rows.tsx `SessionNodeItem` (mobile form): a 44px touch row with
/// the 16px status slot, the running state dot, the title, and the compact
/// relative time; the selected row keeps the sidebar nav-item treatment
/// (active fill + brand accent edge).
class _SessionRow extends StatelessWidget {
  const _SessionRow({
    required this.session,
    required this.selected,
    required this.nowEpochMs,
    required this.onSelect,
  });

  final SessionSummary session;
  final bool selected;
  final int nowEpochMs;
  final VoidCallback? onSelect;

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
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      children: [
                        // Web `.slot`: the fixed status seat keeps titles
                        // aligned whether or not a dot shows.
                        SizedBox(
                          width: 16,
                          child: session.running
                              ? const _RunningDot(size: 8)
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
                        // Web rule: a blank provisional row carries no
                        // timestamp — nothing has happened in it yet.
                        if (!session.blank) ...[
                          const SizedBox(width: 6),
                          Text(
                            _relativeTimeLabel(
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

/// Web WorkspaceBrowser `.sessionOverflowButton`: the local overflow
/// control under a group (28px on the web, a 44px touch row here),
/// aligned under the session titles.
class _OverflowRow extends StatelessWidget {
  const _OverflowRow({
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
class _SearchResultRow extends StatelessWidget {
  const _SearchResultRow({
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
                                  ? const _RunningDot(size: 8)
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
class _RunningDot extends StatelessWidget {
  const _RunningDot({this.size = 10});

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

class _NewSessionDialog extends StatelessWidget {
  const _NewSessionDialog({
    required this.workspaces,
    required this.onCreateSession,
  });

  final List<WorkspaceSummary> workspaces;
  final void Function(String? workspaceId) onCreateSession;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(l10n.newSession),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (workspaces.isEmpty) ...[
            Text(l10n.noWorkspacesRegistered),
            Text(
              l10n.noWorkspacesRegisteredBody,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ] else ...[
            Text(
              l10n.chooseWorkspaceOrDefault,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            for (final workspace in workspaces)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () {
                    onCreateSession(workspace.workspaceId);
                    Navigator.of(context).pop();
                  },
                  child: Text(
                    '${workspace.title} — ${workspace.path}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
          ],
        ],
      ),
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () {
            onCreateSession(null);
            Navigator.of(context).pop();
          },
          child: Text(l10n.defaultBadge),
        ),
      ],
    );
  }
}
