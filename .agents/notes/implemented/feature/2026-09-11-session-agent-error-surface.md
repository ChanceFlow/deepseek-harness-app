# Agent Note: An Agent-level failure reaches the session surface

Status: implemented

## Problem

`_applyForwardedEvent` enumerated `api-session/error` among the forwarded names
it deliberately left unfolded, with the reason recorded in the switch: the
event carries an Agent-level failure message that the web client puts on the
Session handle, and `domain.SessionSummary` had no field to hold it, so folding
it needed a model field and a surface rather than a switch arm.

The gap was user-visible. `'api-session/error'(sessionId: SessionId, message:
string)` (allowlisted as an `emit` item in
`packages/api/remotes/src/remote-events.ts`) is emitted by
`packages/api/session-controller/src/index.ts` from `agent/error` and from a
background activation that failed to resolve. Both are failures **with no turn
position**: no `session/event` carries them, so `TimelineReducer` folds nothing
and the session simply stopped with no reason on screen.

## Decision

`domain.SessionSummary` gains `agentError` (documented as the web
`SessionSnapshot.lastAgentError`), and `_applySessionErrorEvent` folds the
forwarded event onto the matching roster row.

- **It is a roster fact, and it survives the things that rebuild a row.** A
  `session/list` pull and an `api-session/added` upsert both rebuild the row
  from a wire summary that has no failure field, so both carry the held value
  forward; the web client's `lastAgentError` likewise outlives `refreshList`
  and `resync`. Without that, the next pull would erase the only account of why
  a session stopped.
- **A new prompt clears it.** `sendMessage` drops the session's
  `agentError` before the call, mirroring `ClientSession.prompt`, which clears
  `lastAgentError` (with `promptError`) before its first await: the attempt
  supersedes the failure.
- **The session surface renders it.** The chat screen shows it as the same
  error strip as a failed action, with the host message as the detail. That
  strip takes no dismiss action: the failure is the host's fact and clears on
  the next prompt, so a close button would hide something still true. Reusing
  the strip required making `ChatErrorBanner.onDismiss` optional.

## Alternatives considered

- **A synthetic timeline item**: rejected — the message has no turn position,
  so the transcript would invent one and show the failure in a place the host
  never put it.
- **A notification**: rejected for now — the host re-emits on each identical
  failure and the client has no dedupe policy for it; the notification layer
  already covers waiting-on-user and completion, and inventing a third alert
  class is its own design.
- **A warn glyph on the roster dot**: rejected — that dot has two meanings
  (waiting-on-user, finished-unviewed); an error is neither, and a third state
  in one slot would make all three unreadable.
- **A locally dismissible strip**: rejected — dismissal would diverge from the
  host, which still holds the failure and clears it only on the next prompt.

## Consequences

- An Agent-level failure is visible on the session the user is looking at; a
  failure on a session that is not selected is still held in the roster and
  appears when it is opened. A subagent child's failure is held the same way
  and shows when that child is opened in the chat surface; the subagent
  screen's transcript view does not render it, which stays a known gap.
- `forwarded_session_events_test.dart` drives the real repository through the
  `$events` `emit` path: the fold lands, a `session/list` pull keeps it, and a
  prompt clears it. `chat_screen_test.dart` pins the strip's copy and the
  absent dismiss affordance.
