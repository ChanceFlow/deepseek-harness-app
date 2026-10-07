# Agent Note: The archive prompt family and the app-wide action-notice seat

Status: implemented

## Problem

The reference answers an archive in two steps and the phone did neither: a Host
refusal over running work (`workspace/session-active`, whose details name the
running turn, subagents, jobs and schedules) becomes a confirmation listing that
work, and a successful archive raises a transient notice carrying an undo and
the archived-rows filter (`packages/client/ui-workspace/src/client/index.ts`
`activeSessionRefusal`/`stopAndArchiveSession`,
`session-actions/ArchiveSession.tsx`, `RowActionToast.tsx`).

This client leaked the refusal as a raw strip
(`DshBusinessException: workspace/session-active: … (details: …)`), archived
silently, offered no undo, and could not restore at all: the adapter filtered
archived sessions out of `observeSessions()` and no surface read
`observeArchivedSessionIds()`. The refusal's structured facts were unreachable
besides — the adapter's local `valueOrThrow()` dropped `RpcError.details`.

Three more outcomes were missing or raw: a refused New Session showed a
formatted exception, a plugin-refresh failure unmounted with its page, and a
dead inline link said nothing.

## Decision

- **One shared archive flow** (`ui/shared/session_archive_flow.dart`):
  `archive()` raises the archived notice, maps a refusal to a stop-and-archive
  request, and maps anything else to an archive-failed notice; `unarchive()` is
  silent. Both browsing controllers hold it.
- **The refusal crosses the boundary as itself**: `valueOrThrow()` keeps
  `RpcError.details`, and the adapter decodes the refusal into the domain
  `SessionArchiveRefused`/`SessionActivityEntry` (a family this program did not
  compile keeps its wire spelling). Other business failures flatten to
  `RepositoryFailure` (`code: message`, the shape the reference's create notice
  quotes).
- **One app-wide notice seat** (`notifications/session_notice*.dart`,
  `di/providers.dart`, `ui/root/app_root.dart`): controllers raise facts through
  a per-backend sink; the root renders a SnackBar per notice (6 s and an Undo
  action for the archive notices) and shows the confirmation dialog for a
  request. Streams, not state: two archives look equal and a state holder would
  drop the second.
- **The dialog archives** (`ui/shared/session_archive_confirm_dialog.dart`),
  like the reference: it calls `archiveSession(stopActivity: true)`, shows the
  pending line, keeps a failure inline, and blocks dismissal while in flight.
- **Archiving is direct; the prompt is conditional.** The chat app bar's
  unconditional confirmation is gone — a quiet archive commits and the undo
  notice is the safety net, as both browsing surfaces already did.
- **Archivedness is a fact, visibility is a view.** `SessionSummary.archived`
  is folded from the registry-global set and `observeSessions()` publishes every
  root session; `sessionVisible`/`deriveSessionGroups` take an `ArchivedFilter`
  (`hide`/`show`/`only`, persisted as `app.archivedFilter`) and both surfaces
  mount one menu. A restored row returns to its stored position; an archived row
  is grayed, badged, carries no status dot, and cannot be opened (the tap
  explains).
- **The other three outcomes use the same seat**: a refused New Session quotes
  the Host's `code: message` (the already-owned code keeps its specific copy), a
  failed plugin refresh outlives its page, and an inline link that opens nothing
  says so on the ambient messenger.

## Alternatives considered

- **Keep the unconditional confirm and add a second dialog**: rejected — two
  confirmations for one action, and the sidebar never had one.
- **Keep the adapter's archived filtering and add an unfiltered roster
  stream**: rejected — two streams from one source that must agree. The five
  secondary listeners are indifferent to the flag, and the notification fold now
  skips archived rows explicitly.
- **The reference's six-second toast with two actions**: rejected — a SnackBar
  carries one action, and an undo that vanishes would leave no way back; the
  persistent filter menu is the second action's home.
- **Decode the running work from the refusal's message**: rejected —
  `details.activity` is the contract, and dropping it at `valueOrThrow` made the
  structured branch unreachable.
- **Let the controller run the confirmed archive**: rejected — the form owns its
  in-flight and error state, and a failure must keep the dialog open.
- **Per-surface SnackBars**: rejected — the outcome belongs to the action, and a
  sidebar row archives another backend's session.

## Consequences

A quiet archive no longer asks first; recovery rests on the undo notice or the
filter, as upstream ships it. Archived sessions are visible again under their
filter, and unarchive exists on both surfaces and in the notice. A non-refusal
archive failure raises a notice the reference lacks (it only logs). A deep link
at an archived session explains instead of opening — the reference guards its
rows, this client the shared selection. `docs/spec.md` §4.6 and the
README coverage line move with `workspace/unarchiveSession` (declared 81,
identical 79, missing 49).

## Testing

Adapter tests cover the `stopActivity` payload, the refusal decoded into domain
activity (unknown family, item without a label), the unarchive endpoint, and the
archived roster flag. `chat_controller_test` covers the archived notice, the
confirmation request, the silent unarchive, the not-openable guard and the
refused create; `session_tree_test` the three filter modes, the archived badge
and the unarchive verb; the dialog and `session_notice_host` tests the work
list, pending/error states and copy; `app_root_notification_test`
the end-to-end notice, undo and confirmation.
