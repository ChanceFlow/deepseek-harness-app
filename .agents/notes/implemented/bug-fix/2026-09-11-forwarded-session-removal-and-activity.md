# Agent Note: The forwarded session removal and activity folds

Status: implemented

## Problem

The `$events` forwarded-event fold (`_applyForwardedEvent`) handled
`agent-preset/selected`, `api-session/status` and `api-session/added`, and
listed `api-session/removed` and `api-session/activity` among the names it left
unfolded on purpose. Both have a user-visible consequence on the pinned host
(`dsh-v0.1.5-rc.2`, `fb2c4b9e698e30edb738bca4cf0618587db7d203`):

- **`api-session/removed`** — a session another client deleted stayed in the
  roster until the next `session.list` pull, which only fires on a reconnect
  resync, a `turn/end` of a session this client already follows, or a workspace
  change. Nothing removed the row.
- **`api-session/activity`** — `args [sessionId, updatedAt]` is the roster's
  ordering key, so a working session did not re-sort to the top until the same
  pull.

Wire truth: `'api-session/removed'(sessionId: SessionId)` and
`'api-session/activity'(sessionId: SessionId, updatedAt: number)` in
`packages/api/session-controller/src/types.ts`, allowlisted in
`packages/api/remotes/src/remote-events.ts`.

## Decision

`_applySessionRemovedEvent` and `_applySessionActivityEvent` fold both, and the
shared `_copySession` gains an `updatedAtEpochMs` override.

**Removal mirrors the web client's `handleSessionRemoved`.** A summary whose
`origin` is `subagent` keeps its roster row with `running: false` — the
subagent catalog still navigates that child's transcript after its Agent ends,
so the row is a navigation target rather than a live session — and every other
session leaves the roster on the event.

**Activity advances the row's time**, which re-sorts the roster. A session the
roster does not hold is ignored: the tick carries no summary, so the row
arrives with `api-session/added`.

`api-session/error` stays unfolded. It carries an Agent-level failure message
that the web client puts on the Session handle, and `domain.SessionSummary` has
no field to hold it, so folding it needs a model field and a roster surface
rather than a switch arm.

## Alternatives considered

- **Re-pull `session.list` on removal**: rejected — the event names the session
  and a pull would re-fetch the whole roster to drop one row, on every peer
  deletion.
- **Drop a subagent child like any other session**: rejected — its transcript
  remains reachable from the catalog, and the web client keeps the record with
  its Agent stopped.
- **Synthesize a roster row from an activity tick for an unknown session**:
  rejected — the tick carries no summary, so the row would invent title, blank
  and cwd.
- **Fold `api-session/error` in the same change**: rejected — the missing piece
  is a domain field plus a roster surface, not a fold.

## Consequences

- A peer's deletion leaves the roster on the event, and a working session
  re-sorts on its activity tick, rather than both waiting for a pull.
- A removed root session's manager-level mirrors go with it
  (`_releaseSessionMirrors`): the six projection streams and their two seq
  guards, the buffered-frame list, the pending-interaction keys, and the
  running edge. Web `handleSessionRemoved`
  (`packages/api/session-controller/src/client/sessions/manager.ts:729-757`)
  deletes the same session's projection store, queue mirror and per-session
  job list. Keeping them here would let a re-used id inherit a dead session's
  plan or its answerable-looking approval, and the retained running edge would
  arm a completion reminder for work the user never saw start. `_sessionStates`
  and `_sessionCursors` stay, matching the resident Session object the web
  manager keeps and only flags `removed`; a re-open reuses the reducer's queue
  mirror instead of rebuilding it. A subagent child returns before the release,
  so it keeps both its row and its mirrors.
- `forwarded_session_events_test.dart` pins both folds through the real
  repository, the real `SessionWire` decoder and the `$events` `emit` path: a
  root session leaves the roster, a subagent child survives with `running`
  cleared, and an activity tick advances the row's time without a pull. It also
  drives a `plan` projection frame and an `approval/requested` frame for a
  session it then removes and re-adds, and reads both mirrors back clean.
