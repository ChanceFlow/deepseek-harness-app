# Agent Note: Message feedback on the phone

Status: implemented

## Problem

dsh keeps human feedback beside the Session log:
`messageFeedback/{list,put,delete}` read and mutate one durable judgment per
finalized assistant message (`packages/feedback/message-feedback/src/index.ts`),
and `sessionFeedback/record` appends one free-text remark about a Session
(`packages/feedback/command-feedback/src/index.ts`). The web client renders the
message half as the Like/Dislike pair inside the assistant message's
assistant-actions strip, between copy and branch
(`packages/client/ui-message-feedback/src/client/{MessageFeedbackActions.tsx,controller.ts}`).

The phone carried none of it: no feedback endpoint in `DshRpcEndpoints`, no
repository verb, no decoder, and a reply footer offering only copy, fork, and a
clock. A judgment recorded from another client was invisible here, and a phone
reader could not record one.

## Decision

- **All four methods join the wire registry, with refusals as values.** `list`
  returns the message items; `put`/`delete` answer `MessageFeedbackCommitted` or
  `MessageFeedbackRefused(code, current)` — the Host's own success-branch
  business result, never an exception. `sessionFeedback/record` is a plain verb.
- **The Host owns compare-and-set.** Every mutation sends the version this
  controller last observed (`ifVersion: null` requires that no item exists), and
  a `version-conflict` refusal carries the authoritative item, which the
  controller commits before it states the reason. A lost race reconciles from
  the refusal instead of refetching the Session.
- **One list read per backend + Session seeds every row.**
  `MessageFeedbackController` (a `Provider.family` over `(backendId,
  sessionId)`) reads once on construction; every assistant footer of that
  Session renders from its published view, and a Session switch binds its own
  controller.
- **The footer owns the pair, the row owns the reason.** `MessageIconActions`
  takes a `feedback` seat between copy and fork; `MessageFeedbackActions` draws
  the thumbs and `MessageFeedbackNotice` draws the load failure or the write's
  reason on its own line under the footer — a narrow phone cannot spend a
  caption row inside the icon strip without pushing the footer out of shape.- **A recorded judgment stays visible and retracts on tap.** The stored thumb
  fills its glyph and takes the `primary` role; tapping it deletes, tapping the
  other records the replacement. On a cold row the pair is inert until the seed
  lands, because a tap before it cannot know whether it records or retracts.
- **The reference has no feedback list surface.** `messageFeedback/list` exists
  only to seed the per-message controls (`controller.ts` `load`), so no Settings
  page mirrors it; the stored records are the filled thumbs themselves.
- **No note/category dialog on the phone.** The DTOs decode a note and category
  another client stored, and `put` accepts both, but the phone records the bare
  judgment; the web's dialog buys a category picker no phone reader has asked
  for.
- **Session-level feedback stays wire-only here, and is reachable another way.**
  The Host registers the global `/feedback <text>` command
  (`command-feedback/src/index.ts`), which the phone's existing command roster
  already lists and executes through `commands/execute`; the phone has no
  dedicated session-feedback UI.
- **A write that never reached a Host verdict states a generic reason.** A
  transport failure publishes a local refusal code, records the raw error for
  diagnostics, and leaves the row as it was.

## Alternatives considered

- **A Settings page listing stored feedback records** — rejected: the reference
  has no such surface. Its single list read seeds the controls; a phone list page
  would invent a surface and a second source of truth for the same records.
- **Optimistically painting the chosen rating before the reply** — rejected: the
  refusal's authoritative `current` is the point of the Host's compare-and-set,
  and an optimistic row would briefly show a judgment the Host never stored.
- **Raising refusals as exceptions behind a generic error strip** — rejected: the
  Host answers them on the success branch, and the reason belongs on the row that
  raised it, which stays unrated.
- **Porting the note/category dialog** — rejected for now: it is the web's
  wide-surface form, and the wire fields stay available to another client.

## Consequences

The four constants move the wire-pin counts, so `docs/spec.md`'s coverage block
and the README's coverage sentence are updated in the same change. A Host that
composes no feedback plugin answers a 404 for the three message methods: the
footer states its load failure, and a tap still attempts a write, which then
states its own reason. Note and category are not settable from the phone, so a
judgment recorded there is uncategorized until another client edits it. The
controller resyncs nothing on reconnect: a stale version resolves through the
Host's `version-conflict` reply rather than a refetch.

## Testing

`packages/domain/test/model/message_feedback_test.dart` covers the model, the
wire parsers' loud failure, and both write outcomes.
`packages/harness_adapter/test/harness_repository_integration_test.dart` covers
the four payloads, the list value, the committed put, the refusal's `current`,
and the delete ack. `app/test/ui/chat/message_feedback_actions_test.dart` drives
the real strip and controller: seed, put, replace, retract, the filled glyph
under both themes, the pre-seed pair, a refused write, the conflict's
reconciliation, a transport failure, and a backend-less transcript.
