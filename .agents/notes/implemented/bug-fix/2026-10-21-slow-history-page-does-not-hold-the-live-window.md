# Agent Note: A slow history page no longer holds the live window

Status: implemented

## Problem

Opening a session pulled its tail page (`session/page`, 30 s short-call
deadline) while holding the session's one mutex — the same mutex that
serializes the follow stream's opening snapshot and every live frame
(`_SessionState.handleFrame`). A cold or starved Host page therefore parked the
whole session generation: the reader sat on an empty, "loading" transcript
while the frames that would have filled it queued up behind the pull. When the
page hit its deadline they flushed in one burst (the report's warning arrived
with ~60 job events folded in the same 2 ms), and the client reported that
redundant page's timeout as a session-open failure even though the follow
snapshot had already delivered the window, its projections and its cursor.

## Decision

- **The pull is awaited outside the mutex.** `_pullOutsideMutex` marks the load
  (under the lock), pulls the page (without it), then installs or merges the
  result under the lock, so the settle point for window state stays one lock.
- **The follow snapshot opens the window on its own.** `installSnapshot` clears
  `_loading`: a session whose follow snapshot has arrived is not empty and
  loading. A page that lands afterwards merges into that window by sequence
  (`_installPage`) instead of replacing it, because the snapshot may be newer
  than the page's cursor.
- **A page failure is reported only when the session has no window.** With the
  snapshot present, the page is the redundant half of the open and its deadline
  is not an open failure. Without a snapshot the page is the only history
  source, so the `session.open` warning is unchanged
  ([the earlier open/reload decision](../bug-fix/2026-09-10-session-switch-history-reload-and-follow-snapshot.md)).
- **`reload` (re-opening an already-opened session) takes the same shape**: same
  pull outside the lock, same merge, same failure policy.

## Alternatives considered

**Lengthen the page deadline, or retry it** — rejected: the deadline is not the
defect, and either one keeps the live generation parked for longer; the window
is already in the snapshot. **Drop the page from the open and rely on the follow
snapshot alone** (how the reference browser client opens) — rejected: the page
is the fallback when a generation delivers no snapshot, and it is the only path
that fills `hasMore` and the projection block when the stream is cold. **Split
the mutex into an ingest lock and a load lock** — rejected: two locks around
one window invite exactly the interleavings the single mutex exists to prevent;
merging the page under that lock is the smaller, provable settlement. **Move
`loadOlder` out of the lock as well** — deferred: it is a reader-initiated page
taken while the transcript is already on screen, not the session-entry freeze
this change removes; it keeps its current shape and the lock hold is recorded
here rather than half-fixed.

## Consequences

- A cold or stalled first page no longer freezes a session: the transcript
  renders from the follow snapshot within a frame, and the page merges into it
  when it arrives (or never, if it times out — the window is already there).
- The reported warning disappears when the snapshot covered the open; a page
  failure with no snapshot still reports it, pinned by a test.
- The open's future still resolves when the page settles (up to its deadline),
  so callers that await it (session mint, fork, subagent open) are unchanged;
  the resync batch still awaits each session's page, but the frame pipeline no
  longer does.
- `session/page` keeps the 30 s deadline
  ([the deadline decision](../architecture/2026-09-11-rpc-call-deadline-and-passthrough-headers.md));
  what changed is what the client does with a page that does not answer in time.

Evidence: three tests in
[harness_repository_integration_test.dart](../../../../flutter/packages/harness_adapter/test/harness_repository_integration_test.dart)
pin the snapshot reaching the window while the page is still gated, the page
merging into the snapshot instead of replacing it, the failure being silent when
the snapshot covered it, and still reported when it did not. The first two fail
against the previous code.
