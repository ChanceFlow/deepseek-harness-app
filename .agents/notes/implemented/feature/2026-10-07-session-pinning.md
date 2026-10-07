# Agent Note: Session pinning on the phone

Status: implemented

## Problem

dsh carries a registry-global pin set: the `workspace/follow` stream's
baseline (`WorkspaceBaseline.pinnedSessionIds`) and its `pinned` increment
frame carry it, and `workspace/pinSession` / `workspace/unpinSession` mutate
it, answering with the complete resulting set, most recently pinned first
(`packages/api/workspace-controller/src/{index,commands,types}.ts`). The web
browser uses it to lift a row into its group's leading pinned block
(`packages/client/ui-workspace/src/client/{pin-order,tree,rows/WorkspaceBrowser}.tsx`).

The phone mirrored the *archive* set from that same stream but dropped the pin
set on the floor: `WorkspaceListValueWire` decoded `archivedSessionIds` only,
`_handleWorkspaceFollowFrame` had no `pinned` case, and neither verb existed
in the registry. A session pinned from the web or desktop client kept its
ordinary position in the phone's tree, and the phone had no way to pin one —
the whole pin surface was missing from the phone's display and edit scope.

## Decision

- **The adapter mirrors the ordered set, not a boolean.** A new
  `_pinnedSessionIds` `StateStream<List<String>>` is fed from the baseline
  (`WorkspaceListValueWire.pinnedSessionIds`) and from the `pinned` frame, and
  replaced whole by every mutation reply. `observePinnedSessionIds()`,
  `pinSession()` and `unpinSession()` join the domain repository next to the
  archive trio.
- **`withPinsLeading` orders the tree.** Each group's pinned rows form one
  leading block in the Host's own order (most recently pinned first); the
  unpinned remainder keeps the order that surface already had (activity
  priority in the switching sidebar, stored order in the management tree),
  and the active session keeps its own lead *above* the block — the row the
  reader is in never hides behind a pin (the invariant
  `withActiveSessionPinned` protects).
- **The row owns the verbs.** The long-press/⋮ menu offers pin, or unpin once
  pinned, and a pinned row wears a small pin glyph: the block order says which
  rows the user lifted, the glyph says why they lead. An archived row offers
  no pin verb at all — the Host refuses `gateway/bad-request` there — while
  unpin stays available on it so an archive cannot strand a pin.
- **Failures are logged, not announced.** The verb is hidden where the Host
  would refuse, so a refusal is a race; `_runCatchingForUi` records it and the
  row simply does not move. This mirrors rename/fork rather than the archive
  flow, whose refusal is the one a reader must answer.

## Alternatives considered

- **Fold a `pinned` boolean into `SessionSummary`** (the shape the archive
  fact took): rejected — the *order* is the feature. Most recently pinned
  first is the Host's own order and cannot be recovered from a boolean.
- **A separate "Pinned" group above the workspaces**: rejected — the
  reference fronts pinned rows inside the group they belong to, so a pinned
  session is still found where its workspace is; a separate group would move
  rows between surfaces and duplicate them.
- **Clone the archive plumbing and re-derive on `refreshSessions`**:
  rejected — the workspace roster is push-only on this contract (no unary
  list), so the follow stream and the mutation replies are the only sources.
- **Optimistically reorder locally before the reply lands**: rejected — the
  reply already carries the authoritative complete set, and the mirror is
  replaced with it; a second order would only be a source of drift.

## Consequences

A 0.1.x Host that predates the verbs simply reports no pin set and the surface
reads as "nothing pinned" (the decoder defaults an absent list to empty). Pin
state is per-deployment, so a phone cannot pin a session on a Host whose
`workspace-controller` has not been repinned. Unpin is idempotent Host-side, so
a double tap resolves as a no-op instead of an error.

## Testing

`packages/harness_adapter/test/harness_repository_integration_test.dart`
covers the wire payload, the reply-mirroring order, idempotent unpin, the
`pinned` frame replacing the mirror, and a refusal surfacing as
`RepositoryFailure`. `app/test/ui/shared/session_tree_test.dart` covers the
block order, the active-session lead, and the no-pin case;
`app/test/ui/shared/session_tree_pin_test.dart` covers the glyph and the three
menu states; `app/test/ui/chat/chat_controller_test.dart` covers delegation
and the logged refusal.
