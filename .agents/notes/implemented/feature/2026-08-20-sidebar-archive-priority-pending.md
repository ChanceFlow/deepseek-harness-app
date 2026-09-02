# Agent Note: Sidebar activity priority, pending-interaction dot, session verbs and completion dot

Status: implemented

## Problem

The chat sidebar surfaced every workspace account in stored order with
no sense of what needs the user, so running conversations, sessions
waiting on an approval/plan-review/question, and recent activity were
buried under idle rows — the user asked the sidebar to focus on what is
currently active. The "unread" tier the user wanted (needs-a-user-
interaction) has no wire field, and the adapter only tracked approval/
question frames for sessions already opened in the app, so a
never-opened session could never light up. Session rows had no
long-press actions at all, and the finished-but-unviewed session had no
reminder dot, while a first implementation wrongly (a) batch-archived
whole workspaces (the reference has no such concept — only per-session
`workspace.archiveSession`) and (b) showed the status dot on idle
sessions.

## Decision

- **Per-session pending interaction fold** (harness_repository_impl.dart):
  the registry-global pending status is folded from the raw mux frame
  stream before the per-session fan-out, so every session — opened or
  not — carries its outstanding wait (web SessionManager list-level
  parity). `approval/requested` tracks `a:<approvalId>` as approval,
  `question/requested` tracks `q:<rpcId>` classified by the web's
  `questionInteractionStatus` rule (a single binary plan-review intent
  is `planReview`, else `question`); matching `* /resolved` frames drop
  the key. Keys make replays idempotent, a new connection generation
  clears the mirror, and a session dropped from the list loses its
  pending status. `SessionSummary` gains `SessionPendingInteraction?`,
  enriched at the `observeSessions` boundary via `combineLatest3`.
- **Sidebar activity priority** (session_tree.dart): within each
  workspace group, members sort by activity — selected session pinned
  first (the current session must never hide behind the fold), then
  running, then pending interaction, then updated within the last 24
  hours, then recency. This is the sidebar's `priorityOrder`; the
  Workspaces management tab keeps stored account order.
- **Status dot parity** (session_tree.dart): rows render the web
  `sessionStatuses` dot only at the reference's `showStatus` times —
  amber warning for a pending interaction, blue ongoing while running,
  and green done ONLY for a session that finished while not being
  viewed (`completed`). Idle sessions show no dot. The sidebar hides
  workspace groups with no visible sessions (`includeEmptyGroups:
  false`), which also makes fully-archived workspaces vanish from it.
- **Long-press session verbs** (session_tree.dart + workspace/chat
  wiring): a long-press on a session row opens a bottom sheet with
  Archive session, Rename session, and Fork session (web SessionNodeItem
  parity). Sidebar rows and Workspaces-tab rows share the same widget;
  rename prompts for a title (`RenameSessionAction`), archive and fork
  dispatch immediately (`ArchiveSessionAction`, `ForkSessionAction`).
  There is NO workspace-level archive — the reference archives only per
  session via the `workspace.archiveSession` RPC, so workspace rows
  keep their existing sheet (move/delete controls only).
- **Finished-but-unviewed fold** (harness_repository_impl.dart): the
  adapter tracks last-seen `running` per session and folds the
  running→idle edge from every observation source (frames and pulls;
  web `syncCompletedNotifications`) into a `completed` bit on
  `SessionSummary` (web `completedNotifications`) while the session is
  unviewed. First observation records the baseline without arming;
  running or opening clears the bit; refreshes preserve and extend it.
  The `observeSessions` projection forwards the bit (dropping it
  silently resets).

## Alternatives considered

- **A workspace-level `archived` field / workspace batch archive**:
  rejected — the wire has no such field and the reference has no
  workspace-archive action (archiving is per-session only through the
  registry-global `archivedSessionIds` set).
- **Priority sort in both surfaces**: rejected — the Workspaces tab is
  the management surface and must keep the stored account order.
- **Client-computed pending from per-session timelines**: rejected —
  the sidebar must light up for sessions never opened in the app, so
  the raw frame stream folds globally.
- **Status dot on idle sessions**: rejected — the reference renders no
  dot when the session is idle and not completed; a constant dot misread
  as unread.

## Consequences

The sidebar leads with running and needs-your-attention sessions
(yellow dot), then recent activity, matching the user's "focus on what
is active" direction while the Workspaces tab owns management
(rename/delete/archive/move). Long-press verbs on session rows reach
both surfaces; archive stays per-session (no workspace-level concept,
matching the reference). The pending status is only as current as the
last frame — a cold session shows no pending until its frames replay;
unarchive remains unexposed. The completed bit is client-derived: it
survives refreshes and reconnect pulls; idle-at-first-observation never
arms.

## Testing

Adapter integration tests cover the pending fold (approval
requested/resolved, plan-review vs plain question classification,
question resolution by rpcId, never-opened session lights up) and the
completed fold (finished-while-unviewed arms, opening/running again
clears it, finished-while-viewed never arms, pull-carried transitions
arm). session_tree_test.dart covers the priority ordering, empty-group
hiding, management-surface account order, the status-dot mapping (idle
no dot, pending amber, running blue, completed green) and the long-press
sheet verbs. session_panel_test.dart assertions move to the priority
semantics (selected pinned, recency tail below the fold).
workspace_screen_test.dart covers the long-press verbs and the rename
dialog dispatch.