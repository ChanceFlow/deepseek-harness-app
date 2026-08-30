/// Chat sidebar — Flutter port of the dsh web sidebar's browsing region
/// (ui-workspace WorkspaceBrowser): the section header with its trailing
/// search toggle, the expanding search capsule, and the workspace-grouped
/// session tree with the per-group overflow control. The browsing toggles
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
import '../shared/backend_connection_dot.dart';
import '../shared/edge_fade.dart';
import '../shared/session_tree.dart';
import '../theme/theme.dart';
import 'brand_wordmark.dart';

/// One backend's slice of the sidebar's browsing region: that host's
/// config, whether it is the one the chat surface presents, and its
/// live session/workspace facts.
///
/// Value equality is load-bearing: the slices provider selects this out
/// of each host's chat state, so a slice whose roster did not change
/// compares equal and a streaming timeline publish never recomputes the
/// sidebar's slice list.
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

  @override
  bool operator ==(Object other) =>
      other is BackendSessionSlice &&
      other.backend == backend &&
      other.active == active &&
      _listEquals(other.sessions, sessions) &&
      _listEquals(other.workspaces, workspaces);

  @override
  int get hashCode => Object.hash(
    backend,
    active,
    Object.hashAll(sessions),
    Object.hashAll(workspaces),
  );

  static bool _listEquals<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Local state store key: per-group expansion overrides
/// (`sidebar.groupOverrides`, `Map<String, bool>`).
const String _groupOverridesKey = 'sidebar.groupOverrides';

/// Local state store key: groups whose overflow control is expanded
/// (`sidebar.overflowExpanded`, `List<String>`).
const String _overflowExpandedKey = 'sidebar.overflowExpanded';

class SessionPanel extends ConsumerStatefulWidget {
  const SessionPanel({
    required this.sessions,
    required this.workspaces,
    required this.searchResults,
    required this.selectedSessionId,
    required this.onSelectSession,
    required this.onCreateSession,
    required this.onSearchSessions,
    super.key,
    this.inDrawer = false,
    this.onRailChanged,
    this.backendSlices,
    this.onSelectBackend,
    this.onSelectBackendSession,
    this.backendId,
    this.onRenameSession,
    this.onForkSession,
    this.onArchiveSession,
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

  /// The backend this panel presents (the chat surface's backend); used
  /// as the action target for the flat single-host tree.
  final String? backendId;

  /// Web SessionNodeItem session verbs via long-press: rename / fork /
  /// archive one session under any backend's slice.
  final void Function(String backendId, String sessionId)? onRenameSession;
  final void Function(String backendId, String sessionId)? onForkSession;
  final void Function(String backendId, String sessionId)? onArchiveSession;

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
  /// expanded past [kCollapsedSessionLimit].
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
    final currentGroupKey = currentGroupKeyOf(
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

  /// The group holding the active session is ALWAYS expanded — the
  /// current session must never hide behind a fold the user has to
  /// hunt through. Every other group follows its persisted override
  /// (default collapsed).
  bool _isGroupExpanded(String key, String? currentGroupKey) =>
      key == currentGroupKey || (_groupOverrides[key] ?? false);

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

  /// The action target backend for a row: the slice's backend, or the
  /// panel's presented backend for the flat single-host tree.
  String? _actionBackend(BackendSessionSlice? slice) =>
      slice?.backend.id ?? widget.backendId;

  /// Web SessionNodeItem long-press verbs: rename / fork / archive one
  /// session. The row's slice routes to its backend; the flat tree uses
  /// the panel's presented backend.
  void _sessionVerb(
    BackendSessionSlice? slice,
    String sessionId,
    void Function(String backendId, String sessionId)? verb,
  ) {
    final backendId = _actionBackend(slice);
    if (backendId == null || verb == null) return;
    verb(backendId, sessionId);
  }

  /// Web tree.ts `labelOf`: the workspace title when an account holds the
  /// session, else the cwd basename (search-result context rows). The
  /// result list is active-backend scoped.
  String _workspaceLabel(SessionSummary session, AppLocalizations l10n) {
    for (final workspace in widget.workspaces) {
      if (workspace.sessionIds.contains(session.id)) return workspace.title;
    }
    return cwdBasename(session.cwd, l10n);
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
  /// toggle collapses the pane to the icon rail. Both forms ride the stock
  /// [IconButton]: the framework's own seat (a 48px interactive region) and
  /// default ink, and the seat fits the rail exactly (rail padding 4 + 48 =
  /// [kRailWidth]).
  Widget _buildBrandRow(BuildContext context) {
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
              onPressed: () {
                setState(() => _collapsedToRail = !rail);
                widget.onRailChanged?.call(_collapsedToRail);
              },
              icon: Icon(rail ? Icons.menu : Icons.view_sidebar_outlined),
            ),
        ],
      ),
    );
  }

  /// The sidebar's primary action, above the browsing region (web sidebar
  /// order); workspace management itself lives in the Workspaces tab. A
  /// stock [FilledButton.icon] carries it: the panel's one filled seat, in
  /// the framework's own height and shape rather than a bordered slab.
  Widget _buildNewSessionButton(BuildContext context, ColorScheme scheme) {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      child: SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: _showNewSessionDialog,
          // Not a bare plus: the composer's ➕ already owns that glyph on
          // the same screen, and these are different verbs.
          icon: const Icon(Icons.add_comment_outlined, size: 18),
          label: Text(l10n.newSession),
        ),
      ),
    );
  }

  /// Rail form: the wide pane's controls as bare icon seats in the same
  /// top-down order — new session, then search (which expands the pane and
  /// lands in the box) — above the icon-per-session list. Rail avatars
  /// follow the same tree.ts `sessionVisible` rule as the grouped tree.
  ///
  /// The web rail carries no session seats (the shell's rail holds nav
  /// icons and the browser's two controls), so the avatar list is this
  /// app's own idiom and follows the tree's role pair: a selected seat
  /// wears the same `secondaryContainer` fill the tile's `selectedTileColor`
  /// uses, with its `onSecondaryContainer` ink (a filled seat pairs, never
  /// keeps quiet ink), and rides the stock [IconButton.isSelected] so the
  /// selection reads as selected semantics, not only as a tint. Status
  /// stays the expanded row's business: the rail switches sessions, it does
  /// not report them.
  List<Widget> _buildRailChildren(BuildContext context, ColorScheme scheme) {
    final l10n = AppLocalizations.of(context)!;
    return [
      IconButton(
        tooltip: l10n.newSession,
        onPressed: _showNewSessionDialog,
        // The expanded pane's filled button owns this verb with this
        // glyph; the rail repeats the verb, so it repeats the glyph (the
        // composer-➕ distinction is recorded there).
        icon: const Icon(Icons.add_comment_outlined),
      ),
      const SizedBox(height: kRailControlGap),
      IconButton(
        tooltip: l10n.searchSessions,
        onPressed: _openSearchFromRail,
        icon: const Icon(Icons.search),
      ),
      const SizedBox(height: kRailControlGap),
      Expanded(
        child: ScrollConfiguration(
          behavior: _SidebarScrollBehavior(glowColor: scheme.outlineVariant),
          child: ListView(
            padding: const EdgeInsets.only(top: 4, bottom: 16),
            children: [
              for (final session in widget.sessions.where(
                (session) => sessionVisible(session, widget.selectedSessionId),
              ))
                _buildRailAvatar(context, scheme, session),
            ],
          ),
        ),
      ),
    ];
  }

  Widget _buildRailAvatar(
    BuildContext context,
    ColorScheme scheme,
    SessionSummary session,
  ) {
    final selected = session.id == widget.selectedSessionId;
    return IconButton(
      tooltip: session.displayTitle,
      isSelected: selected,
      onPressed: () => widget.onSelectSession(session.id),
      icon: CircleAvatar(
        radius: 14,
        backgroundColor: selected
            ? scheme.secondaryContainer
            : scheme.surfaceContainerHigh,
        child: Text(
          // displayTitle never falls empty (title → cwd basename → id),
          // so the initial always exists; a CJK title reads its first
          // character.
          session.displayTitle.substring(0, 1),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: selected
                ? scheme.onSecondaryContainer
                : scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  /// Wide/drawer form: the browsing region below the brand row — New
  /// session bar, section header, search capsule, then the tree or the
  /// search-result list with the bottom continuation fade.
  List<Widget> _buildWideChildren(BuildContext context, ColorScheme scheme) {
    final l10n = AppLocalizations.of(context)!;
    return [
      _buildNewSessionButton(context, scheme),
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
        // Web listArea: a non-empty query replaces the tree with the
        // flat result list; clearing restores the tree. The web
        // `.fade` continuation hint rides as EdgeFade: the list
        // dissolves into the panel surface at its own edge, so no
        // overlay band reads as a stuck-on banner the row accents
        // bleed through.
        child: ScrollConfiguration(
          behavior: _SidebarScrollBehavior(glowColor: scheme.outlineVariant),
          child: EdgeFade(
            surface: scheme.surfaceContainerLow,
            child: _queryController.text.trim().isEmpty
                ? _buildSessionTree(
                    context,
                    scheme,
                    currentGroupKeyOf(
                      widget.sessions,
                      widget.workspaces,
                      widget.selectedSessionId,
                    ),
                  )
                : _buildSearchResults(context, scheme),
          ),
        ),
      ),
    ];
  }

  /// Web WorkspaceBrowser `SessionTree` (mobile form): the grouped
  /// browsing list — the panel's only scrolling region. With more than
  /// one backend configured, every backend gets its own section: a
  /// live-status header over its own workspace-grouped tree.
  Widget _buildSessionTree(
    BuildContext context,
    ColorScheme scheme,
    String? currentGroupKey,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final slices = widget.backendSlices;
    if (slices != null && slices.length > 1) {
      return _buildBackendSections(context, scheme);
    }
    final nowEpochMs = DateTime.now().millisecondsSinceEpoch;
    final groups = deriveSessionGroups(
      widget.sessions,
      widget.workspaces,
      widget.selectedSessionId,
      l10n,
      nowEpochMs: nowEpochMs,
      // The sidebar is a switching surface: a workspace group with no
      // visible sessions (all archived away, or never populated) is
      // noise — it stays manageable in the Workspaces tab. Members ride
      // the activity priority (selected, running, pending interaction,
      // recent-24h, recency).
      includeEmptyGroups: false,
      priorityOrder: true,
    );
    if (groups.isEmpty) {
      // Web `.empty` (aligned with the row grid).
      return Padding(
        padding: const EdgeInsets.fromLTRB(8, 16, 8, 0),
        child: Text(
          l10n.noSessionsYet,
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(fontSize: 13, color: scheme.onSurfaceVariant),
        ),
      );
    }
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
            onRenameSession: (sessionId) =>
                _sessionVerb(null, sessionId, widget.onRenameSession),
            onForkSession: (sessionId) =>
                _sessionVerb(null, sessionId, widget.onForkSession),
            onArchiveSession: (sessionId) =>
                _sessionVerb(null, sessionId, widget.onArchiveSession),
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
  Widget _buildBackendSections(BuildContext context, ColorScheme scheme) {
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
            scheme,
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
    ColorScheme scheme,
    BackendSessionSlice slice,
    int nowEpochMs,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final selectedSessionId = slice.active ? widget.selectedSessionId : null;
    final groups = deriveSessionGroups(
      slice.sessions,
      slice.workspaces,
      selectedSessionId,
      l10n,
      nowEpochMs: nowEpochMs,
      includeEmptyGroups: false,
      priorityOrder: true,
    );
    final currentGroupKey = currentGroupKeyOf(
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
          onRenameSession: (sessionId) =>
              _sessionVerb(slice, sessionId, widget.onRenameSession),
          onForkSession: (sessionId) =>
              _sessionVerb(slice, sessionId, widget.onForkSession),
          onArchiveSession: (sessionId) =>
              _sessionVerb(slice, sessionId, widget.onArchiveSession),
        ),
      ],
    ];
  }

  /// Web WorkspaceBrowser `SearchResults`: the flat result list replaces
  /// the tree while a query is active; rows whose session summary has not
  /// landed stay hidden until the list catches up (web drops them the
  /// same way).
  Widget _buildSearchResults(BuildContext context, ColorScheme scheme) {
    final l10n = AppLocalizations.of(context)!;
    // Web tree.ts `deriveSearchResults`: content matches render only for
    // visible non-blank summaries — subagent children never surface, and
    // blank placeholders never match a query (not even the current one).
    final sessionsById = <String, SessionSummary>{
      for (final session in widget.sessions.where(
        (session) =>
            !session.blank && sessionVisible(session, widget.selectedSessionId),
      ))
        session.id: session,
    };
    final rows = <Widget>[
      for (final result in widget.searchResults)
        if (sessionsById[result.sessionId] case final session?)
          SessionSearchResultRow(
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
                ?.copyWith(fontSize: 13, color: scheme.onSurfaceVariant),
          ),
        ),
      );
    }
    return ListView(padding: const EdgeInsets.only(bottom: 16), children: rows);
  }

  @override
  Widget build(BuildContext context) {
    _seedBrowsingStateFromStore();
    final scheme = Theme.of(context).colorScheme;
    final rail = !widget.inDrawer && _collapsedToRail;
    // The pane's own width is fixed geometry, not an animation: the
    // collapse slide belongs to the two-pane row's single AnimatedContainer
    // in chat_screen.dart, which owns the 320 ↔ 56 transition.
    return Container(
      width: rail ? kRailWidth : null,
      color: scheme.surfaceContainerLow,
      child: Material(
        color: Colors.transparent,
        child: Padding(
          padding: EdgeInsets.all(rail ? 4 : 8),
          child: Column(
            children: [
              _buildBrandRow(context),
              if (rail)
                ..._buildRailChildren(context, scheme)
              else
                ..._buildWideChildren(context, scheme),
            ],
          ),
        ),
      ),
    );
  }
}

/// Local scroll behavior for the sidebar's browsing lists (the tree, search
/// results, and rail avatars): neutralizes the Android overscroll glow to
/// [scheme.outlineVariant] (a quiet hairline tone) rather than the default
/// [scheme.secondary] brand blue, so overscrolling at the top of the list
/// never paints a saturated blue arc across the boundary between the header
/// banner and the list content.
class _SidebarScrollBehavior extends MaterialScrollBehavior {
  const _SidebarScrollBehavior({required this.glowColor});

  final Color glowColor;

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    final AndroidOverscrollIndicator indicator = Theme.of(context).useMaterial3
        ? AndroidOverscrollIndicator.stretch
        : AndroidOverscrollIndicator.glow;
    switch (getPlatform(context)) {
      case TargetPlatform.iOS:
      case TargetPlatform.linux:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
        return child;
      case TargetPlatform.android:
        switch (indicator) {
          case AndroidOverscrollIndicator.stretch:
            return StretchingOverscrollIndicator(
              axisDirection: details.direction,
              clipBehavior: details.decorationClipBehavior ?? Clip.hardEdge,
              child: child,
            );
          case AndroidOverscrollIndicator.glow:
            break;
        }
      case TargetPlatform.fuchsia:
        break;
    }
    return GlowingOverscrollIndicator(
      axisDirection: details.direction,
      color: glowColor,
      child: child,
    );
  }
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
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 4, 2),
      child: SizedBox(
        height: 36,
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                // A list section label, not a heading: small, tracked, and
                // quiet enough that the session titles stay the content.
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                  letterSpacing: 0.4,
                ),
              ),
            ),
            // Web WorkspaceBrowser `.iconButton`: the section's search
            // seat as a standard M3 IconButton (label-secondary ink;
            // on-surface ink while the capsule is engaged).
            IconButton(
              tooltip: l10n.searchSessions,
              onPressed: onToggleSearch,
              visualDensity: VisualDensity.compact,
              icon: Icon(
                Icons.search,
                size: 20,
                color: searchActive
                    ? Theme.of(context).colorScheme.onSurface
                    : scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Web WorkspaceBrowser `.searchExpanded` (Workspaces-tab idiom): the
/// bordered search capsule — r10, border-l2, 13px input, trailing clear
/// circle that clears and collapses — now an inline M3 [SearchBar]
/// squeezed to the capsule's 36px footprint (native field internals,
/// focus, and keyboard behavior on the compact sidebar density).
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final textStyle = theme.textTheme.bodyMedium?.copyWith(fontSize: 13);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 4, 4),
      child: SearchBar(
        controller: controller,
        autoFocus: true,
        onChanged: onChanged,
        hintText: l10n.searchSessionsHint,
        // Flat, bordered capsule: no elevation, no tint, the capsule's
        // own border and radius carried onto the component's surface.
        elevation: const WidgetStatePropertyAll(0),
        shadowColor: const WidgetStatePropertyAll(Colors.transparent),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
        side: WidgetStatePropertyAll(BorderSide(color: scheme.outlineVariant)),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        constraints: const BoxConstraints.tightFor(height: 36),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 8),
        ),
        leading: Icon(Icons.search, size: 16, color: scheme.onSurfaceVariant),
        trailing: [
          IconButton(
            visualDensity: VisualDensity.compact,
            iconSize: 16,
            onPressed: onCollapse,
            icon: Icon(Icons.close, color: scheme.onSurfaceVariant),
          ),
        ],
        textStyle: WidgetStatePropertyAll(textStyle),
        hintStyle: WidgetStatePropertyAll(
          textStyle?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ),
    );
  }
}

/// One backend's section header in the multi-backend browsing region:
/// the live connection dot, the backend label over `host:port`, and
/// the Active marker — the same vocabulary as the Workspaces tab's
/// backend headers — now a native [ListTile] carrying the sidebar
/// nav-item active fill on the active backend. Tapping a non-active
/// header selects that backend.
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
    final scheme = theme.colorScheme;
    final backend = slice.backend;
    return ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      minLeadingWidth: 24,
      horizontalTitleGap: 8,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      selected: slice.active,
      tileColor: Colors.transparent,
      selectedTileColor: scheme.secondaryContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      leading: BackendConnectionDot(backendId: backend.id),
      title: Text(
        backend.label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.labelMedium,
      ),
      subtitle: Text(
        '${backend.baseUri.host}:${backend.baseUri.port}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.labelSmall?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: slice.active ? scheme.primaryContainer : null,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          slice.active ? l10n.backendStatusActive : l10n.backendStatusStandby,
          style: theme.textTheme.labelSmall?.copyWith(
            color: slice.active
                ? scheme.onSurfaceVariant
                : scheme.onSurfaceVariant,
          ),
        ),
      ),
      onTap: onSelectBackend,
    );
  }
}

/// Web WorkspaceBrowser `.groupSection`: the group header plus its
/// expanded session run (2px intra-group rhythm) and the local overflow
/// control — now a native [ExpansionTile] with the M3 expansion
/// animation, ripple, and semantics.
///
/// The tile is controller-driven so the parent's browsing state (seeded
/// from the local store, or the always-expanded current group) stays the
/// single source of truth: [didUpdateWidget] syncs an external
/// [expanded] change through the [ExpansibleController], and the
/// onExpansionChanged guard only reports a user tap (a value that
/// differs from the last-rendered [expanded]) to the parent — a
/// programmatic sync never writes a browsing override. The current group
/// (holds the active session) never folds: its header is inert
/// (`enabled: false` with the disabled ink overridden so it is not
/// visually dimmed).
class _GroupSection extends StatefulWidget {
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
    this.onRenameSession,
    this.onForkSession,
    this.onArchiveSession,
  });

  final SessionGroupData group;
  final bool expanded;
  final bool overflowExpanded;
  final bool containsCurrent;
  final String? selectedSessionId;
  final int nowEpochMs;
  final VoidCallback onToggle;
  final VoidCallback onToggleOverflow;
  final void Function(String sessionId) onSelectSession;

  /// Web SessionNodeItem session verbs (long-press row menu).
  final void Function(String sessionId)? onRenameSession;
  final void Function(String sessionId)? onForkSession;
  final void Function(String sessionId)? onArchiveSession;

  @override
  State<_GroupSection> createState() => _GroupSectionState();
}

class _GroupSectionState extends State<_GroupSection> {
  late final ExpansibleController _controller = ExpansibleController();

  @override
  void didUpdateWidget(covariant _GroupSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.expanded == oldWidget.expanded) return;
    // An external browsing-state change (store seed, or the group
    // becoming / ceasing to be current) drives the native tile.
    if (widget.expanded) {
      if (!_controller.isExpanded) _controller.expand();
    } else if (_controller.isExpanded) {
      _controller.collapse();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final group = widget.group;
    final expanded = widget.expanded;
    final sessions = group.sessions;
    final visibleCount =
        widget.overflowExpanded || sessions.length <= kCollapsedSessionLimit
        ? sessions.length
        : kCollapsedSessionLimit;

    final tile = ExpansionTile(
      key: ValueKey('sidebar-group-${group.key}'),
      controller: _controller,
      initiallyExpanded: expanded,
      dense: true,
      visualDensity: VisualDensity.compact,
      minTileHeight: 40,
      // The stock tile rules its expanded self off top and bottom; the
      // panel separates groups with space, not with two full-width lines.
      shape: const Border(),
      collapsedShape: const Border(),
      // The current group never folds: its header is inert (no tap), the
      // native tile stays expanded.
      enabled: !widget.containsCurrent,
      leading: Icon(
        expanded ? Icons.folder_open : Icons.folder_outlined,
        size: 16,
        // Web `.slot .folder`: tertiary folder glyph (brand tint while
        // the group holds the selected session and is open).
        color: expanded && widget.containsCurrent
            ? scheme.primary
            : scheme.onSurfaceVariant,
      ),
      // The session-count caption rides beside the label (the web's
      // single-line header), ahead of the M3 trailing chevron.
      title: Row(
        children: [
          Expanded(
            child: Text(
              group.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelLarge?.copyWith(height: 1.2),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            l10n.sessionCount(sessions.length),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      tilePadding: const EdgeInsets.symmetric(horizontal: 8),
      childrenPadding: const EdgeInsets.only(top: 2, bottom: 2),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      onExpansionChanged: (value) {
        // Programmatic syncs (seed / current-group change) already equal
        // the rendered [expanded]; only a user tap differs and routes to
        // the parent's browsing toggle.
        if (value == widget.expanded) return;
        widget.onToggle();
      },
      children: [
        if (expanded) ...[
          for (var i = 0; i < visibleCount; i++) ...[
            if (i > 0) const SizedBox(height: 2),
            SessionTreeRow(
              session: sessions[i],
              selected: sessions[i].id == widget.selectedSessionId,
              nowEpochMs: widget.nowEpochMs,
              onSelect: sessions[i].id == widget.selectedSessionId
                  ? null
                  : () => widget.onSelectSession(sessions[i].id),
              onRename: widget.onRenameSession == null
                  ? null
                  : () => widget.onRenameSession!(sessions[i].id),
              onFork: widget.onForkSession == null
                  ? null
                  : () => widget.onForkSession!(sessions[i].id),
              onArchive: widget.onArchiveSession == null
                  ? null
                  : () => widget.onArchiveSession!(sessions[i].id),
            ),
          ],
          if (sessions.length > kCollapsedSessionLimit) ...[
            const SizedBox(height: 2),
            SessionOverflowRow(
              expanded: widget.overflowExpanded,
              totalCount: sessions.length,
              onTap: widget.onToggleOverflow,
            ),
          ],
        ],
      ],
    );

    // An inert current-group header must not render dimmed: ListTile's
    // disabled ink follows ThemeData.disabledColor, so the scoped theme
    // points it back at the normal on-surface ink. The leading folder
    // glyph keeps its explicit accent/tertiary color regardless.
    if (widget.containsCurrent) {
      return Theme(
        data: theme.copyWith(disabledColor: theme.colorScheme.onSurface),
        child: tile,
      );
    }
    return tile;
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
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kShapeCard),
      ),
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      contentPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      title: Row(
        children: [
          Icon(Icons.add_comment_outlined, size: 20, color: scheme.primary),
          const SizedBox(width: 8),
          Text(l10n.newSession, style: theme.textTheme.titleMedium),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380, maxHeight: 420),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                workspaces.isEmpty
                    ? l10n.noWorkspacesRegistered
                    : l10n.chooseWorkspaceOrDefault,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              if (workspaces.isEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  l10n.noWorkspacesRegisteredBody,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ] else ...[
                const SizedBox(height: 12),
                // Default workspace card
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () {
                      onCreateSession(null);
                      Navigator.of(context).pop();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: scheme.outlineVariant),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.home_outlined,
                            size: 18,
                            color: scheme.primary,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              l10n.defaultBadge,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Icon(
                            Icons.chevron_right_rounded,
                            size: 18,
                            color: scheme.onSurfaceVariant,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                for (final workspace in workspaces) ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () {
                          onCreateSession(workspace.workspaceId);
                          Navigator.of(context).pop();
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainerLow,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: scheme.outlineVariant),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.folder_outlined,
                                size: 18,
                                color: scheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      workspace.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w500,
                                            fontSize: 13,
                                          ),
                                    ),
                                    const SizedBox(height: 1),
                                    Text(
                                      workspace.path,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            fontSize: 11,
                                            color: scheme.onSurfaceVariant,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(
                                Icons.chevron_right_rounded,
                                size: 18,
                                color: scheme.outline,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
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
