# Agent Note: Selected-session restore on cold start

Status: implemented

## Problem

The reference web client persists the open session
(`dsh.sessions.current` in localStorage) and reopens it on the next
visit; the phone client started every cold launch on no session at all —
the reader reopened the app and landed on the empty hero, then re-picked
the conversation they were in. The client already persisted per-session
view state (drafts, reading offsets, expansion states), so the missing
piece was exactly the one key the web keeps at the surface level: which
session the surface had open.

## Decision

Persist each backend's selected session in the device-local
[LocalStateStore](../../../../flutter/app/lib/local_state/local_state_store.dart)
document (`chat.selectedSession.<backendId>` — one scope per backend,
matching the web's single-host entry with per-host isolation).
[ChatController](../../../../flutter/app/lib/ui/chat/chat_controller.dart)
owns the restore:

- Every selection change (`SelectSession`, session create, fork, and the
  removal-driven clear) writes through the
  `SessionSelectionPersistence` seam wired per backend in
  [providers.dart](../../../../flutter/app/lib/di/providers.dart).
- The restore arms when the seam resolves and adjudicates against the
  session list: select when the stored session exists; give up when a
  non-empty list proves it gone (deleted or archived — the repository's
  `observeSessions` already filters archived). A selection made before
  the seam resolves wins and cancels the restore. An empty list stays
  inconclusive (it may be the pre-load state).

## Alternatives considered

- **Restore inside the repository or connection layer**: rejected —
  selection is a surface fact (the web's store lives in the SessionManager
  UI service, not the wire layer), and the controller already owns every
  other selection transition.
- **One global key instead of per-backend scopes**: rejected — each
  backend's chat surface restores its own session; a shared key would
  reopen the same session id on a host that never saw it.
- **Restoring into a session that no longer exists by opening it
  anyway**: rejected — the host accepts opens for deleted sessions in
  some paths, which strands the surface on a conversation that is not in
  the list; adjudicating against the loaded list is the web's own
  behavior (a missing session restores to no selection).

## Consequences

- Cold start reopens the conversation the reader left, per backend, with
  the already-persisted reading offset landing them back where they were.
- A restored selection is a real selection: the open loads history and
  the notification center's selected-session suppression applies exactly
  as it did before the restart.
- Controller tests pin the contract: selection persists on change, the
  stored session restores once the list loads, a stored id absent from a
  loaded list does not restore, and a late-resolving seam still restores.
