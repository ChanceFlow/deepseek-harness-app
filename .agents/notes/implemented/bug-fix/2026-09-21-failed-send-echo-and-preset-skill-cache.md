# Agent Note: A refused send's echo, and the preset's stale skill cache

Status: implemented

## Problem

Two small pieces of client state outlived the fact that produced them.

**A refused prompt stayed on screen.** `_sendPrompt` appends a local
`optimistic-<micros>` user message for immediate feedback, and nothing removed
it: the host's durable `user/message` was expected to supersede it, so a send
the host refused left the reader's own words in the transcript as if they had
been delivered. The reference retires a failed submission explicitly
(`Session.retireFailedSubmission`,
`api/session-controller/src/client/sessions/session.ts:764-769`).

**A preset switch kept the old catalog.** `_skillsBySession` caches each
session's `/`-menu skill candidates; `_selectAgentPreset` fired the switch and
never invalidated the cache. A preset decides which skill providers the agent
reads, so after switching the composer kept offering the previous preset's
skills indefinitely — the web client invalidates one key on
`agent-preset/selected` for exactly this reason
(`client/ui-skill/src/client/index.ts:122-132,188`).

## Decision

`_withdrawOptimistic(id)` removes the row whose id the send minted, and the
failure branch calls it before its telemetry. The helper is a no-op when the
row is already gone, so a window that refreshed first cannot make a late
failure delete a message the host did accept. Success is unchanged: the
durable message still replaces the echo when it arrives.

`_selectAgentPreset` now awaits the host's answer and, **only on success**,
drops that session's cache entry and re-reads the catalog when that session is
selected. A refusal keeps the cache, because a refused switch changed nothing
about which providers the agent reads.

## Alternatives considered

- **Match the durable message by `rpcId` and retire the echo on arrival.**
  Rejected for this pass: the reference pairs them that way, but our
  `SendMessageRequest` does not carry a client-generated request id end to
  end, so the pairing would need a wire change; withdrawal on failure fixes
  the visible defect without inventing an identity the host does not echo.
- **Clear the whole skill cache on preset select.** Rejected: the cache is
  per session on purpose (one fetch per session), and only the switched
  session's providers changed.
- **Invalidate on the `agent-preset/selected` forwarded event instead.**
  Rejected for now: the controller does not observe that event, and its own
  successful call is the same fact at the same moment.

## Consequences

- A prompt the host refuses leaves no phantom message; the composer's error
  strip is the surface that reports it.
- A successful preset switch costs one extra `skills/list` for the selected
  session.
- Known remaining gap in the same area, from the parity audit and not fixed
  here: the skill cache is still not cleared on a connection generation reset,
  so a host that changes its providers restarts with a stale catalog until the
  app restarts.
