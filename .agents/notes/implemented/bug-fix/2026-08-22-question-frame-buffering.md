# Agent Note: Buffering question/approval frames for unopened sessions

Status: implemented

## Problem

A session whose agent called `ask_user_question` before the phone app
instantiated that session's timeline never showed the question card. The
user saw the `ask_user_question` tool call spin forever with no card
(real sessions `session-25b13fe4…` recorded 7 unanswered asks; the web UI
answered the same kind of ask from `session-50a3fe03…`). Root cause is a
delivery hole, not a decode one:

- `question/requested` (and `approval/requested`, `session/queue`) are
  **live mux frames that never land in session history**. An open's
  `session.history` backfill shows only the still-running `tool/call`, so
  the card has no history source.
- The app instantiates a session's state lazily (`_sessionStateFor` on
  open/observe). `_collectMuxFrames` routed every mux frame through
  `_sessionStates[sessionId]` and **dropped the frame when the state did
  not exist yet** — a `question/requested` that arrived before the session
  was opened (agent asked mid-turn, user opens later; or a reconnect gap)
  was silently discarded. The pending-interaction fold
  (`_foldPendingFrame`) tracked the sidebar status but never the frame, and
  the mux-open replay only covers still-pending requests while connected.

## Decision

Mirror the web client's `pendingBuffers` (packages/client/runtime/src/
client/sessions/manager.ts): `HarnessRepositoryImpl` gains a per-session
frame buffer. `_collectMuxFrames` now routes an uninstantiated session's
`approval/requested`, `question/requested` and `session/queue` frames into
`_pendingBuffers` (compacting by stable key `a:<approvalId>` /
`q:<rpcId>` / `queue`), and drops their `* /resolved` counterparts from the
buffer so an answered request is never replayed. `_sessionStateFor` replays
the buffer into the newly created state through `handleFrame` — while the
state is not yet loaded these park in `_pending`, and `ensureLoaded`
replays them after the history reset, the same ordering as a live frame.
A session's buffered `session/queue` entry is truncated in-band by its new
generation's `session/subscribed` frame (the host pushes the fresh baseline
after it on the same stream, and omits it for an emptied queue); a
connected-time truncation raced the mux-open burst and is removed — see
[queue-rebaseline-in-band](2026-08-29-queue-rebaseline-in-band.md). Pending
approval/question frames survive the boundary because the burst re-pushes
them after that frame, and the replay is no longer out-ordered by an
out-of-band mirror clear.

## Alternatives considered

- **Eager instantiation**: create every listed session's state up front.
  Rejected — it loads history for sessions the user never opens and
  multiplies subscriptions; the web keeps lazy build and solves delivery
  with the buffer instead.
- **Reload history on session open with pending interactions**: fetch
  pending questions via an RPC on open. Rejected — no such host RPC exists;
  the host's recovery is the mux-open replay, which the buffer already
  covers while connected.

## Consequences

- The question/approval card now renders for a session opened after the ask
  was emitted, closing the spinner-without-card loop.
- Two integration tests pin the contract: a `question/requested` released
  before `openSession` renders after it, and a `question/resolved` before
  `openSession` compacts the buffer so the answered request never replays.
- The buffer is bounded by live pending requests (host replays already
  carry a stable identity), so no unbounded growth beyond what the host
  considers pending.
