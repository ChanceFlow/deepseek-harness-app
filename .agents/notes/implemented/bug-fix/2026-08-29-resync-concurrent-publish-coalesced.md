# Agent Note: Resume freeze cured by concurrent resync and coalesced publishes

Status: implemented

## Problem

Returning the app to the foreground after a disconnect gap froze the chat
for seconds, then flooded the transcript back in one burst. Three layers
compounded the same delay, none of them present in the reference web
client:

1. `harness_repository_impl.dart:1488` `_resync` (the connection listener's
   recovery entry) serialized all recovery inside the resync mutex: await
   `refreshSessions()`, then `refreshWorkspaces()`, then per-session
   `ensureLoaded` one at a time. The web
   [manager.ts](../../../../reference/deepseek-harness/packages/client/runtime/src/client/sessions/manager.ts)
   `handleConnected` fires the list pull and every `session.resync()` in
   parallel. While the chain ran, every session stayed `_ready = false`,
   arriving frames parked in `_pending`, and nothing published — the
   multi-second hold followed by the flood.
2. `chat_controller.dart:156-217` rebuilt the whole `ChatUiState` once per
   upstream stream event: one wire frame fans out over the window, stats,
   pressure, plan, goal, permissions and roster listeners, and the roster
   was subscribed twice (a second chain only watching the selected
   session's removal), so a frame cost 6–8 full rebuilds, each including
   a `_timelineJobs()` scan of every timeline item.
3. `harness_repository_impl.dart:2063-2068` re-assigned
   `contextPressure`/`contextBreakdown`/`sessionStats` on every
   `session/event` frame, and the adapter
   [state_stream.dart](../../../../flutter/packages/harness_adapter/lib/src/state_stream.dart)
   setter published unconditionally: folds re-minting an equal value still
   republished and fed the rebuild storm of item 2.

## Decision

Mirror the web's recovery parallelism in the adapter, and its frame-cadence
notification batching on the app side (the web Notifier batches at
microtask rank right after the assembly flush; the app already publishes
streaming windows at 16ms, so the controller folds at the same frame
window):

- **Concurrent resync.** `_resync` still runs the synchronous generation
  prep (window re-arms; the pending-interaction mirror drop and queue-frame
  buffer truncation it also carried moved in-band to the
  `session/subscribed` frame — see
  [queue-rebaseline-in-band](2026-08-29-queue-rebaseline-in-band.md)) inside
  the resync mutex, then fires the
  list/workspaces pull and every opened session's `ensureLoaded` together
  via `Future.wait` — the web `handleConnected` parity. Recovery is
  first-settled-first-published: each session releases its `_pending`
  frames when its own history lands; the selected session needs no special
  scheduling. The session-states collection is snapshotted before firing.
  The resync mutex keeps serializing generations (the action awaits the
  whole batch); each session's own `_mutex` keeps serializing its window.
  Per-session history failures stay swallowed (retried next generation)
  and a list failure still never blocks timeline recovery — existing
  semantics, unchanged. The buffered-frame replay of
  [question-frame-buffering](2026-08-22-question-frame-buffering.md)
  keeps its ordering: buffers replay through the same `handleFrame` path.
- **Controller publish window.** Every repository-stream listener feeds
  `_publishUpstream()`: the first event of a burst arms a 16ms
  trailing-edge timer (app-local `kUiPublishWindow`, restating the
  adapter's `kStreamPublishWindow` because the import gate keeps `app`
  off the adapter package), so upstream jitter folds into one
  [ChatUiState](../../../../flutter/app/lib/ui/chat/chat_ui_state.dart)
  publish per window. No state is lost — the flush rebuilds from the
  current fields — so approval, question and plan reach `uiState` within
  one window of arrival (a widget test pins the boundary, and
  `dispose()` cancels the timer). Action-driven and one-shot RPC
  completions keep publishing immediately. The duplicate roster chain
  folds into the baseline `observeSessions()` listener.
- **Equality gate and scan memo.** The `StateStream.value` setter drops
  value-equal (`==`) writes. The three folded types
  ([session_window_stats.dart](../../../../flutter/packages/domain/lib/model/session_window_stats.dart),
  [context_pressure.dart](../../../../flutter/packages/domain/lib/model/context_pressure.dart))
  already carry value equality; domain tests pin it. Identity-compared
  lists (timelines, rosters) keep publishing on every fresh instance.
  `_timelineJobs()` memoizes its scan on the timeline list instance, so a
  publish driven by another field reuses the roster.

## Alternatives considered

- **Move history decoding off the UI isolate**: deferred — the freeze was
  serialization and republish, not decode; decode cost is unmeasured on a
  phone, so isolate work waits for real-device frame stats.
- **A WS-level ping/pong to shorten detection of dead connections**: the
  reference protocol carries no such contract; out of parity scope, a
  separate proposal if resume latency still dominates.
- **Per-widget selector subscriptions instead of one ChatUiState**:
  touches every chat surface's provider wiring; unnecessary once the
  publish rate is frame-bounded.

## Consequences

- Foreground resume now republishes each opened session as its own history
  lands instead of after the whole serial chain; the "hold seconds, then
  flood" pattern is gone at both layers. Integration tests pin the mutual
  in-flight overlap (cross-gated list/history responses), generation
  serialization across back-to-back resyncs, and the equality gate's
  silence on unchanged folds.
- This note complements
  [the streaming-render reparse fix](2026-08-24-streaming-render-quadratic-reparse.md)
  (adapter-side chunk coalescing) rather than superseding it: that note
  caps publishes per chunk, this one parallelizes recovery and caps the
  controller's rebuilds per stream fan-out.
- Known gap, unchanged behavior: a failed resync history load stays
  silent (stale content until the next generation retries it) — the
  existing documented deviation.
- On-device validation pending: resume a streaming host and an idle host,
  compare post-resume fps/jank in the debug frame stats against a build
  without this change, and confirm the transcript paints incrementally;
  the two hosts separate client-side coalescing effects from host-side
  response latency.
