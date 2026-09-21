# Agent Note: Live assistant streaming, and the subagent `delivery` field

Status: implemented

## Problem

Two asynchronous paths stopped working at the 0.1.5 wire pin, and neither
failed loudly.

**No token-by-token output.** The client's only producer of a streaming reply
was the durable `assistant/chunk` event, folded in `timeline_reducer.dart`.
That event is not in the current session vocabulary
(`packages/core/session/src/known-event-types.ts` lists `assistant/message` and
`assistant/attempt`, no `assistant/chunk`), so on a real host a reply appeared
whole when it committed and the streaming caret, the live cadence, and the
first-token figure never fired. The live text rides process-local
`assistant-stream` frames instead, which the host attaches only when the
follow request asks for them (`assistantStream: true`,
`packages/api/session-controller/src/history.ts:163`); the request carried only
`address`, and the frame vocabulary had no `assistant-stream` case.

**Every subagent prompt was refused.** `sendSubagentPrompt` sent
`mode: 'continuable'` and no `delivery`, but the control schema requires both
(`packages/subagent/subagent/src/control.ts`: `'subagent.prompt'` takes
`mode: z.literal('continuable')` **and** `delivery: z.enum(['queue','steer'])`).
The gateway rejected the call at its boundary
(`gateway/input-invalid … wire field "request" failed boundary validation`),
so the child composer could never deliver a message.

## Decision

**The follow asks for the live stream, and the reducer folds it.** `_followSession`
now sends `assistantStream: true` with the request. The repository routes
`assistant-stream` frames to `_SessionState.ingestAssistantStream`, which folds
them under the same mutex as the ordered events and publishes at frame cadence:
token deltas cannot wait for a durable event.

`TimelineReducer.ingestAssistantStreamFrame` handles the three frame kinds
(`SessionAssistantStreamFrame`): `start` records the attempt's
`attemptId`/`revision`/`turn`/`step`; `chunk` applies the payload through the
same `_applyChunk` the durable `assistant/chunk` path uses (one code path, two
sources, identical chunk vocabulary); `end` settles an **abandoned** attempt's
partial, because no durable event will ever arrive for it — a **committed**
attempt's text lands as the `assistant/message` or `assistant/attempt` that
follows, which replaces the partial on its own.

Continuity is the attempt cursor, not a sequence: a frame applies only while
`attemptId` and `revision` match the attempt being held, at the next dense
`index`, in increasing `ordinal`. A frame that fails any of those is dropped
rather than stitched into the wrong reply. The durable record never depends on
the live path, so a drop costs part of the preview, never a message.

**A mid-reply open renders what already streamed.** The follow opening's
snapshot carries `assistantStream`
(`SessionAssistantStreamBaseline`); `seedAssistantStreamBaseline` replays its
`activeAttempt.stream` into the partial and adopts its `nextIndex`, so a client
that opens during a long reply shows the text so far instead of an empty pane
until the commit. `reset` clears the live cursor with the window, since the
cursor is scoped to one follow generation.

**`delivery: 'queue'` on every subagent prompt.** The phone's child composer
has no steer seat, so it always appends after the child's current turn; the
field is now present, which is what the schema requires. The test asserts both
discriminants travel.

## Alternatives considered

- **Keep folding only the durable `assistant/chunk` and accept commit-time
  text.** Rejected: the event is not in the current vocabulary, so this is not
  a fallback but the broken state; the phone would show no live output at all.
- **Route live frames through `_ingestEvent` by inventing a seq.** Rejected:
  the frames are cursorless and parallel to the log; giving them synthetic
  seqs would corrupt the window cursor that paging (`throughSeq`) and the
  open snapshot depend on.
- **Drop a `revision` change and start a fresh partial.** Rejected for now:
  the host retires an accumulator across attempts, so a revision bump means
  the frames no longer belong to the partial being held; refusing them keeps
  the fold honest, and the next `start` frame re-bases it.
- **Send `delivery: 'steer'` for a running child.** Rejected: the phone offers
  no way for the reader to choose interruption, and a silent steer would cut
  the child's turn without the reader asking.
- **Wait for a live end-to-end streaming capture before landing this.**
  Rejected as a gate, recorded as a known limit: producing one requires
  prompting the host, and the frame shapes are pinned by the reference's own
  `SessionAssistantStreamFrame` union and follow-frame tests.

## Consequences

- `docs/spec.md` §6 names the live path and marks `assistant/chunk` as the v1
  log format rather than the live source.
- Live verification performed against the local 0.1.5 host: a `session/follow`
  opened with `assistantStream: true` is accepted and its snapshot carries
  `assistantStream` (e.g. `{"revision":48077}` between attempts); the frame
  fold itself is covered by six reducer tests.
- A prompt sent to a subagent now reaches the child instead of failing at the
  gateway boundary.
- Known gaps in this area, from the parity audit and not fixed here: child
  transcripts are a one-shot page with no follow and a stale cursor,
  `assistant/attempt` has no fold, and the remaining known-but-unhandled
  event types (`step/end`, `approval/asked`, `todo/write`, `model/selection`,
  `permission/preset`, `plan/mode`, `subagent/descriptor`, …) report a debug
  diagnostic instead of contributing a row.
