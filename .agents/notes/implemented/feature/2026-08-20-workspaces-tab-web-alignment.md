# Agent Note: Workspaces tab web alignment and the sidebar settings seat

Status: implemented

## Problem

The Workspaces tab rendered a degenerate browser: workspace rows whose
expanded form showed a path-and-count caption instead of the session
tree the web WorkspaceBrowser renders under each group, and the search
capsule filtered workspace titles client-side while the web searches
session content. Separately, the chat sidebar carried a bottom-pinned
settings trigger (the web `sidebar.settings` seat) that duplicated the
bottom tab bar's Settings entry — a web necessity (the web has no tab
bar) that is pure duplication on mobile.

## Decision

- **Sidebar settings seat removed** (session_panel.dart): the foot row,
  its divider, and the destination dispatch are gone; the bottom tab
  bar owns Settings navigation on mobile. The destination selection's
  store-restore test now drives the provider the way the tab bar does.
- **Shared tree module** (ui/shared/session_tree.dart): the web
  `tree.ts`/`Rows.tsx` port — visibility, groupByWorkspace with the
  Ungrouped bucket, active-session pinning, recency order, relative
  time, and the session/overflow/search-result rows — moved out of
  session_panel.dart so both browsing surfaces render the identical
  rows.
- **Workspaces tab renders the session tree** (workspace_screen.dart):
  each backend's browsing region derives groups from its controller's
  session summaries (now published into WorkspaceUiState), shows the
  session rows with the selected-row treatment, folds groups past the
  web `COLLAPSED_SESSION_LIMIT` (5) behind the overflow control,
  force-expands the current session's group, and trails unaccounted
  sessions in an Ungrouped bucket whose header carries no management
  actions (no backing Workspace — web rule). The path/count caption
  run is deleted.
- **Session navigation**: tapping a session row selects the backend
  (when non-active), dispatches SelectSession on that backend's chat
  controller, and lands on the Chat destination — the web row's
  `open`. Starting a session from a row's ➕ follows the same path:
  `startSessionInWorkspace` is now a public Future returning the
  resolved session id (web `startSession` ends in `sessions.open`),
  and the section wrapper navigates after it settles.
- **Search**: the capsule dispatches `SearchSessionsAction` (the
  controller's `session.search` wiring, mirroring the chat sidebar);
  the flat result list replaces the tree while a query is active, and
  clearing the query restores it. Client-side workspace-title
  filtering is gone.

## Alternatives considered

- **Keeping the sidebar settings trigger** for web parity: rejected —
  the web seat exists because the web shell has no tab bar; on mobile
  it duplicated the Settings tab one gesture away.
- **Rendering only the count caption and keeping the tab as a
  management-only surface**: rejected — the web browser's primary
  content is the session tree; a management-only tab diverges from
  the original design the user asked to align with.
- **A single aggregate search field above the backend sections**:
  rejected — each backend's host answers its own `session.search`;
  per-section search keeps the aggregate's one-section-per-backend
  grouping and reuses the section's own capsule.

## Consequences

Both surfaces now render the same rows from one module, so future row
changes land in both. The tab's tree is session-visible per backend
(blank placeholders browse only on the active backend's selection).
Backend headers keep the aggregate grouping the multi-backend design
requires — the web has no equivalent (single host), so they remain a
mobile-only addition above each browsing region. Workspace drag
reorder and the web view-options menu (grouped/flat, sort order) stay
unported.

## Testing

session_panel_test.dart: the four settings-trigger tests are removed;
the destination-restore test drives the provider directly.
workspace_screen_test.dart: groups expand to session rows; session
rows select through with the selected row a no-op; groups past the
limit fold behind Show all N; unaccounted sessions trail in Ungrouped;
the search test dispatches the query and renders the flat result list.
