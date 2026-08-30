# Agent Note: Queue and pending mirrors re-baseline in-band on session/subscribed

Status: implemented

## Problem

Foreground resume flashed the queue dock empty (and the sidebar's pending
dots dark) while the host's queue and waits were alive. `session/queue` is a
live authoritative snapshot with no durable history: at mux open the host
pushes every session's `session/subscribed` marker, then the still-pending
approval/question replays, then one queue snapshot per non-empty queue — and
resends none of them again in that generation
([api-proxy.ts](../../../../reference/deepseek-harness/packages/host/apiproxy/src/api-proxy.ts)
`events.mux`). `DshConnectionManager` forwards burst frames from socket open,
before the readiness-gated `connected` publish it drives
(dsh_connection_manager.dart:156-158, 188-198), so the burst can land while
the previous window is still ready. The repository hung every queue-related
re-baseline on that publish: `_resync` prep cleared `_pendingBySession` and
`_pendingInteractions`, truncated `session/queue` frames from
`_pendingBuffers`, and `prepareResync()` dropped `_framesAfterOpen` — wiping
baselines the burst had just delivered. An instantiated session lost its
swallowed queue with the replay list (the rebuilt history never carries it);
an unopened session's fresh baseline was truncated as stale, so its dock
opened empty. The web author documents exactly this trap: "The queue mirror
is NOT cleared here: onConnected … races the mux frames — the fresh
generation's baseline may have landed already, and the host never resends
it"
([session.ts:419-426](../../../../reference/deepseek-harness/packages/client/runtime/src/client/sessions/session.ts)).

## Decision

Port the web's in-band design: the `session/subscribed` frame is the
generation boundary, because the host's replay of everything it rebaselines
follows that frame on the same stream.

- **Queue mirror leaves the history-reset scope.** `TimelineReducer.reset`
  carries the `TimelineQueue` entry over a history rebuild, and
  `ingestFrame('session/subscribed')` drops it (web queueMirror parity,
  session.ts:482-490). The per-session `_SessionState` reducer is one
  persistent instance now, so a burst-outran baseline survives whichever
  path its frames took: live ingest or `_pending` replay.
- **`_pendingBuffers` truncation moves in-band.** `_dropGenerationMirrors`,
  called by the mux listener on every `session/subscribed`, removes that
  session's buffered queue snapshot — the host omits the baseline for an
  emptied queue, so a kept stale would replay phantom work on later
  instantiation (web manager.ts:714-732).
- **Pending dots move in-band the same way**: the same call drops the
  session's `_pendingBySession` keys; the generation's replayed requested
  frames re-track them right after.
- **Deleted out-of-band cleanings**: the `_pendingBySession`/
  `_pendingInteractions` clear and the `_pendingBuffers` queue filter in
  `_resync` prep, and the `_framesAfterOpen` clear in `prepareResync`
  (`ensureLoaded` replaces the list with the replayed generation's frames
  anyway). The remaining prep is the window re-arm only, and the concurrent
  `Future.wait` resync of
  [the resume-freeze note](2026-08-29-resync-concurrent-publish-coalesced.md)
  keeps its per-`_mutex` pending→reset→replay atomicity.
- **Fail loud**: `session/queue` frames missing `items`, and items missing
  `id`/`message`/`placement` or carrying an unknown placement value, throw
  `FormatException` with the field name (closed union, no silent fallback).

## Alternatives considered

- **Re-pull the queue over an RPC after connected**: rejected — the wire has
  no queue pull surface; the mux-open snapshot is the only baseline carrier.
- **Clear on connected and wait for the next queue-change broadcast**:
  rejected — that is the shipped bug's "resurrect on next change" experience.
- **A global drop on the RECONNECTING publish (web `handleDisconnected`,
  manager.ts:880-899)**: rejected — race-free here too, but it adds a second
  lifecycle owner; riding the same frame as the replay keeps one ordering
  point per session.

## Consequences

- Return-to-foreground keeps the dock and dots through the reconnect gap;
  on-device check: background with a live steer queue, resume across a gap,
  and the dock must never flash empty.
- This corrects in place
  [the question-buffering note](2026-08-22-question-frame-buffering.md): its
  "mux-open replay re-pushes pending frames so they survive" premise held
  only when the burst lost to the connected clear.
- Known, web-parity residual: an answerable card for an already-open window
  folds live, drops at the rebuild, and re-mints next generation (web
  `Session.resync`'s `pending.clear()` carries the same race); the dots,
  which drive alerts, now survive it. `session/jobs` keeps its rebuild-wipe
  behavior and shares the race.
