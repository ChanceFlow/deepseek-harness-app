/// Chat sidebar — Flutter port of the dsh web sidebar's browsing region
/// (ui-workspace WorkspaceBrowser): the section header with its trailing
/// search toggle, the expanding search capsule, and the workspace-grouped
/// session tree with the per-group overflow control. Shares its design
/// language with the Workspaces tab (workspace_screen.dart): 44px touch
/// rows, folder group headers, and the flat search-result list that
/// replaces the tree while a query is active.
library;

import 'package:domain/model/session.dart';
import 'package:domain/model/workspace.dart';
import 'package:flutter/material.dart';

import '../theme/deepsuite_extension.dart' show DeepSuiteColors, dsOf;
import '../theme/deepsuite_tokens.dart' show DeepSuiteStatic, kDsDuration;
import 'brand_wordmark.dart';

/// Web tree.ts `UNGROUPED_KEY`: group key for sessions outside every
/// registered workspace.
const String _ungroupedKey = '';

/// Web `COLLAPSED_SESSION_LIMIT`: session rows a group shows before its
/// local overflow control.
const int _collapsedSessionLimit = 5;

class SessionPanel extends StatefulWidget {
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

  @override
  State<SessionPanel> createState() => _SessionPanelState();
}

class _SessionPanelState extends State<SessionPanel> {
  final TextEditingController _queryController = TextEditingController();
  bool _collapsedToRail = false;

  /// Web `searchExpanded`: the capsule is mounted and owns the live query.
  bool _searchActive = false;

  /// Web `groupExpansion` (user-toggled half): explicit expansion by group
  /// key. Absent keys default to the selected session's group, mirroring
  /// the web auto-expand of the current group.
  final Map<String, bool> _groupOverrides = <String, bool>{};

  /// Web `expandedSessionGroups`: groups whose overflow control is
  /// expanded past [_collapsedSessionLimit].
  final Set<String> _overflowExpandedGroups = <String>{};

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

  /// Web ProjectRowItem `onToggle`: flip one group's expansion, pinning it
  /// so later selection changes no longer auto-expand it.
  void _toggleGroup(String key) {
    final currentGroupKey = _currentGroupKey();
    final expanded = _groupOverrides[key] ?? key == currentGroupKey;
    setState(() => _groupOverrides[key] = !expanded);
  }

  /// Web `expandedSessionGroups` toggle: the per-group overflow control.
  void _toggleOverflow(String key) => setState(() {
    if (!_overflowExpandedGroups.remove(key)) {
      _overflowExpandedGroups.add(key);
    }
  });

  /// Web tree.ts current-group derivation: the selected session's
  /// workspace key, or the Ungrouped key when it belongs to none (null
  /// when nothing is selected or the summary has not landed yet).
  String? _currentGroupKey() {
    final selectedSessionId = widget.selectedSessionId;
    if (selectedSessionId == null) return null;
    final session = widget.sessions
        .where((session) => session.id == selectedSessionId)
        .firstOrNull;
    if (session == null) return null;
    final workspaceId = session.workspaceId;
    if (workspaceId != null &&
        widget.workspaces.any((w) => w.workspaceId == workspaceId)) {
      return workspaceId;
    }
    return _ungroupedKey;
  }

  bool _isGroupExpanded(String key, String? currentGroupKey) =>
      _groupOverrides[key] ?? key == currentGroupKey;

  /// Web tree.ts `deriveGroups`: one group per workspace in registry order
  /// plus the trailing Ungrouped bucket for sessions outside every
  /// workspace; members sort newest-first.
  List<_SessionGroupData> _deriveSessionGroups() {
    final knownWorkspaceIds = <String>{
      for (final workspace in widget.workspaces) workspace.workspaceId,
    };
    final groups = <_SessionGroupData>[
      for (final workspace in widget.workspaces)
        _SessionGroupData(
          key: workspace.workspaceId,
          label: workspace.title,
          sessions: _sortedByRecency(
            widget.sessions.where(
              (session) => session.workspaceId == workspace.workspaceId,
            ),
          ),
        ),
    ];
    final ungrouped = _sortedByRecency(
      widget.sessions.where(
        (session) =>
            session.workspaceId == null ||
            !knownWorkspaceIds.contains(session.workspaceId),
      ),
    );
    if (ungrouped.isNotEmpty) {
      groups.add(
        _SessionGroupData(
          key: _ungroupedKey,
          label: 'Ungrouped',
          sessions: ungrouped,
        ),
      );
    }
    return groups;
  }

  /// Web tree.ts `labelOf`: the workspace title when known, else the cwd
  /// basename (search-result context rows).
  String _workspaceLabel(SessionSummary session) {
    final workspaceId = session.workspaceId;
    if (workspaceId != null) {
      for (final workspace in widget.workspaces) {
        if (workspace.workspaceId == workspaceId) return workspace.title;
      }
    }
    return _cwdBasename(session.cwd);
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
              tooltip: rail ? 'Open sidebar' : 'Collapse sidebar',
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
                'New session',
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
  /// lands in the box) — above the icon-per-session list.
  List<Widget> _buildRailChildren(BuildContext context, DeepSuiteColors ds) {
    return [
      IconButton(
        tooltip: 'New session',
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
        tooltip: 'Search sessions',
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
            for (final session in widget.sessions)
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
  /// search-result list with the bottom continuation fade.
  List<Widget> _buildWideChildren(BuildContext context, DeepSuiteColors ds) {
    return [
      _buildNewSessionButton(context, ds),
      _SectionHeader(
        title: 'Workspaces',
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
              _buildSessionTree(context, ds, _currentGroupKey())
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
    ];
  }

  /// Web WorkspaceBrowser `SessionTree` (mobile form): the grouped
  /// browsing list — the panel's only scrolling region.
  Widget _buildSessionTree(
    BuildContext context,
    DeepSuiteColors ds,
    String? currentGroupKey,
  ) {
    final groups = _deriveSessionGroups();
    if (groups.isEmpty) {
      // Web `.empty` (aligned with the row grid).
      return Padding(
        padding: const EdgeInsets.fromLTRB(8, 16, 8, 0),
        child: Text(
          'No sessions yet',
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

  /// Web WorkspaceBrowser `SearchResults`: the flat result list replaces
  /// the tree while a query is active; rows whose session summary has not
  /// landed stay hidden until the list catches up (web drops them the
  /// same way).
  Widget _buildSearchResults(BuildContext context, DeepSuiteColors ds) {
    final sessionsById = <String, SessionSummary>{
      for (final session in widget.sessions) session.id: session,
    };
    final rows = <Widget>[
      for (final result in widget.searchResults)
        if (sessionsById[result.sessionId] case final session?)
          _SearchResultRow(
            session: session,
            snippet: result.snippet,
            workspaceLabel: _workspaceLabel(session),
            selected: session.id == widget.selectedSessionId,
            onSelect: () => widget.onSelectSession(session.id),
          ),
    ];
    if (rows.isEmpty) {
      rows.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 16, 8, 0),
          child: Text(
            'No matching sessions',
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

/// Web tree.ts `workspaceLabel`: the cwd basename, or the Ungrouped label
/// when there is no path to name.
String _cwdBasename(String? cwd) {
  if (cwd == null || cwd.isEmpty) return 'Ungrouped';
  final segments = cwd.split(RegExp(r'[/\\]+'));
  for (final segment in segments.reversed) {
    if (segment.isNotEmpty) return segment;
  }
  return cwd;
}

/// Web tree.ts `relativeTime` plus the en dictionary: the compact trailing
/// label for session rows ("now"/"5min"/"3h"/"2d"/"4mo"/"1y").
String _relativeTimeLabel(int updatedAtEpochMs, int nowEpochMs) {
  const minuteMs = 60 * 1000;
  const hourMs = 60 * minuteMs;
  const dayMs = 24 * hourMs;
  final diff = nowEpochMs - updatedAtEpochMs;
  final elapsed = diff < 0 ? 0 : diff;
  return switch (elapsed) {
    < minuteMs => 'now',
    < hourMs => '${elapsed ~/ minuteMs}min',
    < dayMs => '${elapsed ~/ hourMs}h',
    < 30 * dayMs => '${elapsed ~/ dayMs}d',
    < 365 * dayMs => '${elapsed ~/ (30 * dayMs)}mo',
    _ => '${elapsed ~/ (365 * dayMs)}y',
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
              tooltip: 'Search sessions',
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
                  hintText: 'Search sessions...',
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
                sessionCount == 1 ? '1 session' : '$sessionCount sessions',
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
    final ds = dsOf(context);
    final theme = Theme.of(context);
    // Web `displayTitle`: blank rows show the New Session label.
    final title = session.blank ? 'New session' : session.displayTitle;
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
                expanded ? 'Show less' : 'Show all $totalCount',
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
    final ds = dsOf(context);
    final theme = Theme.of(context);
    final title = session.blank ? 'New session' : session.displayTitle;
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
    return AlertDialog(
      title: const Text('New session'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (workspaces.isEmpty) ...[
            const Text('No workspaces registered.'),
            Text(
              'Use the Workspaces tab to register a directory first, '
              'or choose Default to create an unaccounted session.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ] else ...[
            Text(
              'Choose a workspace or keep the default.',
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
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            onCreateSession(null);
            Navigator.of(context).pop();
          },
          child: const Text('Default'),
        ),
      ],
    );
  }
}
