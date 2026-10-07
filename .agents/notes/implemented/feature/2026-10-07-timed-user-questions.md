# Agent Note: Answering a timed question after the wait ended

Status: implemented

## Problem

The 0.2.0 pin registers a second way to ask the reader a question, and the
client could not answer it. `tool-ask-user` may run `mode: timed`, where the
call carries a foreground wait; when the wait ends the host continues the turn
and the call's own result records the timeout. The still-answerable calls are
published as the `userQuestions` session projection, and a late reply travels
through `userQuestions/answer`.

Both halves were invisible here. The adapter forwarded only the waterfall
request's `questions`, so the `wait` identity never reached the client, and the
projection key was not folded: `_projectionKeys` did not name it and
`_handleProjection` reported it as unhandled. A reader who answered a question
after its window had closed therefore sent `$events/result` for a waterfall the
host had already released, and the answer went nowhere — the failure mode with
no error in it. No shipped bundle enables `mode: timed` yet, so this is the
contract being ready before the host that needs it, not a live outage.

## Decision

Wire the late-answer half of the feature, and name the half that stays out.

- `DshRpcEndpoints.userQuestionsAnswer` declares `userQuestions/answer`; the
  agent address is the `agentId` every other agent-scoped verb already uses
  (`packages/interaction/user-questions/src/index.ts` `@Remote answer`).
- `PendingUserQuestion` / `UserQuestionState` are domain vocabulary
  (`packages/interaction/user-questions/src/types.ts`), and
  `ChatRepository.observePendingUserQuestions` plus `answerContinuedQuestion`
  carry them across the boundary.
- The adapter folds the `userQuestions` projection through the same
  newer-seq-wins path every other projection takes: a baseline block claims it,
  a live frame claims it, a complete block that omits it clears it, and a
  session that leaves the window drops it. The `active` half is decoded; a row
  without a `callId` fails loud with a diagnostic rather than defaulting.
  `settled` is left to the transcript work it belongs to.
- `TimelineReducer.toQuestionItem` became the top-level `decodeQuestionItem` so
  the projection and the waterfall decode one shape.
- The chat screen gives a `continued` call the composer seat through the
  existing `QuestionRow`, and the controller routes that request id to
  `answerContinuedQuestion`. Dismissal drops the card locally: the host keeps
  holding the call, and there is no waterfall left to refuse.

## Alternatives considered

Hold the wait with `userQuestions/attachWait` and render the reference's
countdown: rejected for now — it is a second stream, a timer, and a claim the
shipped composition never asks for, and the answer path is worth landing without
it. Answer a continued call through the same `$events/result` outcome: rejected
— the waterfall is released at the timeout, so the outcome has no listener and
the answer is lost silently, which is the defect this change exists to remove.
Decode `settled` too and render the reference's late-reply row: rejected as a
separate unit — it is transcript presentation, it needs the steered
`user-question-reply` message, and folding it here would put two features in one
change. Invent a local `dismissed` set so a dropped card stays dropped: rejected
— the projection is the host's fact, and a local veto would fight the next
publish for no user-visible gain.

## Consequences

A reader can answer a question the host continued, and the reply lands as a new
turn instead of vanishing; against a host that never enables `mode: timed`
nothing changes, because the projection stays empty. Coverage moves to
`declared 54, upstream 128, identical 52, missing 76, client-only 2`. The
countdown and the `settled` transcript row are stated as deferred in
[docs/spec.md §10](../../../../docs/spec.md), so the omission is a recorded
boundary rather than an assumption.
