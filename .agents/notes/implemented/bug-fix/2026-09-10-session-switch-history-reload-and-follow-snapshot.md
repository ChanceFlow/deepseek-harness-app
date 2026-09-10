# Agent Note: Session switch reloads history and ingests follow snapshots

Status: implemented

## Problem

When switching between sessions on the mobile client, messages that landed in a
session while the user was viewing another session (for example, driven by
concurrent turns on the desktop web client) failed to display in real time upon
switching back.

Two defects caused this freeze:

1. `openSession` in
   [harness_repository_impl.dart](../../../../flutter/packages/harness_adapter/lib/src/harness_repository_impl.dart)
   gated history pulls behind `state.ensureLoaded()`, which checked
   `if (_ready) return;`. Once a session had loaded its initial history,
   `_ready` remained true across later session switches, so re-opening the
   session skipped `_loadHistory` entirely.
2. `_followSession` re-opened `session/follow` for the newly selected session,
   receiving the host's opening `type: 'snapshot'` frame containing `records`
   (the recent message window), `cursor`, and `projections`. The mux frame
   collector in `HarnessRepositoryImpl` extracted the cursor and projections,
   but completely discarded `records` and returned immediately. Any messages
   appended while the follow stream was closed never reached the timeline
   reducer.

## Decision

1. **Re-opening an opened session calls `reload`**:
   `openSession` checks `state.isOpened`. If the session was already opened, it
   calls `state.reload((beforeSeq) => _loadHistory(sessionId, beforeSeq))`,
   pulling the latest tail page from the server and updating the timeline
   reducer.
2. **`session/follow` snapshots are installed into session state**:
   When a `type: 'snapshot'` frame arrives on `session-follow-$sessionId`, its
   `records` are decoded via `SessionHistoryValueWire` and handed to
   `_SessionState.installSnapshot()`. The reducer and window stats fold the
   fresh records and publish the updated timeline immediately.

## Alternatives considered

- **Keep all session follow streams open concurrently**: rejected — opening
  persistent WebSocket follow streams for every session in a workspace wastes
  battery, bandwidth, and host resources on mobile; on-demand following with
  snapshot ingestion preserves the lightweight single-stream model while
  guaranteeing fresh data.
- **Rely solely on `openSession` reload without snapshot handling**: rejected —
  the follow stream's opening snapshot is authoritative from the host and arrives
  in-band with the live follow channel; discarding its records violated the
  Gateway protocol contract.
- **Clear `_ready` on every switch**: rejected — a session should retain its
  cached window in memory so navigation does not flicker with an empty screen
  while the reload is in flight.

## Consequences

- Switching back to a session immediately renders messages and turns completed
  on other clients or background agents.
- The `session/follow` opening snapshot synchronizes the local transcript before
  subsequent live events stream in.
- Integration tests pin both the re-open reload behavior and follow snapshot
  ingestion.
