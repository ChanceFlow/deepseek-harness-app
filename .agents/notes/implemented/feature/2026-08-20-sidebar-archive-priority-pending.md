# Agent Note: Sidebar activity priority, pending-interaction dot, and workspace archive

Status: implemented

## Problem

The chat sidebar surfaced every workspace account in stored order with
no sense of what needs the user, so running conversations, sessions
waiting on an approval/plan-review/question, and recent activity were
buried under idle rows — the user asked the sidebar to focus on what is
currently active. The sidebar also had no archive affordance at all,
and the "unread" tier the user wanted (needs-a-user-interaction) has no
wire field: `SessionSummary` carries nothing about outstanding
interactions, and the adapter only tracked approval/question frames for
sessions already opened in the app, so a never-opened session could
never light up.

## Decision

- **Per-session pending interaction fold** (harness_repository_impl.dart):
  the registry-global pending status is folded from the raw mux frame
  stream before the per-session fan-out, so every session — opened or
  not — carries its outstanding wait (web SessionManager list-level
  parity). `approval/requested` tracks `a:<approvalId>` as approval,
  `question/requested` tracks `q:<rpcId>` classified by the web's
  `questionInteractionStatus` rule (a single binary plan-review intent
  is `planReview`, everything else `question`), and the matching
  `* /resolved` frames drop the key. Keys make replays idempotent; a
  new connection generation clears the mirror (the reopen replay
  re-adds still-pending frames), and a session dropped from the list
  loses its pending status. `SessionSummary` gains
  `SessionPendingInteraction?` (approval/planReview/question), enriched
  at the `observeSessions` boundary via `combineLatest3` with the
  archived set.
- **Sidebar activity priority** (session_tree.dart): within each
  workspace group, members sort by activity — selected session pinned
  first (the current session must never hide behind the fold), then
  running, then pending interaction, then updated within the last 24
  hours, then recency. This is the sidebar's `priorityOrder`; the
  Workspaces management tab keeps the stored account order
  (`deriveSessionGroups` takes a `priorityOrder` flag).
- **Status dot parity** (session_tree.dart): every row renders the web
  `sessionStatuses` dot — amber warning for pending interaction,
  blue ongoing for running, green done otherwise (the reference always
  shows a dot). The sidebar is a switching surface and now hides
  workspace groups with no visible sessions (`includeEmptyGroups:
  false`), which also makes fully-archived workspaces vanish from it.
- **Workspace archive in the Workspaces tab**: the workspace-row ⋮
  sheet gains "Archive workspace" (a confirm dialog, then
  `ArchiveWorkspaceAction` — the controller batch-archives every
  accounted session through the existing `workspace.archiveSession`
  RPC, since the wire has no workspace-level archive). Session rows
  gain the per-row "Archive session" verb (web SessionNodeItem
  parity, no confirm — reference archive semantics), which also
  reaches ungrouped sessions. The sidebar itself carries no archive
  action (it is for switching only).

## Alternatives considered

- **A workspace-level `archived` field**: rejected — the wire has no
  such field (`WorkspaceView` is workspaceId/path/title/sessionIds/
  timestamps); archiving is per-session through the registry-global
  `archivedSessionIds` set, so "archive this workspace" is a batch of
  per-session archives.
- **Priority sort in both surfaces**: rejected — the Workspaces tab is
  the management surface and must keep the stored account order; only
  the switching sidebar reorders by activity.
- **Client-computed pending from per-session timelines**: rejected —
  the sidebar must light up for sessions never opened in the app, which
  requires folding the raw frame stream globally, not per opened
  session.
- **Archive with confirmation on session rows too**: rejected — the web
  archives sessions without a dialog ("not styled as destructive");
  only the multi-session workspace batch confirms.

## Consequences

The sidebar now leads with running and needs-your-attention sessions
(yellow dot), then recent activity, matching the user's "focus on what
is active" direction while the Workspaces tab owns management
(rename/delete/archive/move). The pending fold adds wire decoding
coverage for the four approval/question frame types at the list level
(the per-session timeline already rendered them as cards). Because the
pending status is derived from live frames, it is only as current as
the last frame — a cold session with a stale projection shows no
pending until its frames replay. Unarchive remains unexposed (the wire
has no unarchive RPC), so an archived workspace's sessions stay hidden
until the host restores them.

## Testing

Adapter integration tests cover the pending fold (approval
requested/resolved, plan-review vs plain question classification,
question resolution by rpcId, and that a never-opened session still
lights up). session_tree_test.dart covers the priority ordering, the
empty-group hiding, the management-surface account order, and the
status-dot mapping. session_panel_test.dart assertions move to the
priority semantics (selected pinned, recency tail below the fold).
workspace_screen_test.dart adds the archive-workspace confirm dispatch
and the per-session archive verb.
