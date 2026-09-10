# Agent Note: Interactive decisions arrive as forwarded Remote Event waterfalls

Status: implemented

## Problem

On a live host (dsh `0.1.2-rc.1`), the composer-seat decision cards — the
`ask_user_question` card, its plan-review form and the tool-approval panel —
never appeared. The client built them from mux frames named
`question/requested` and `approval/requested`, and a 0.1.2 host never sends
those: the frame vocabulary the client was written against is the pinned
reference's 0.1.1. In 0.1.2 an interactive decision is an **Agent-scoped
waterfall on the forwarded Remote Event stream** — `user-questions/request`
and `approval/request` are entries of the host's
`API_REMOTE_FORWARDED_EVENTS` allowlist, and the client answers by returning
the listener's value. Nothing folded the waterfall, so no card was created,
the roster dot stayed dark, and the agent's question had no answerer at all.
`rpc_map.dart` already declared `$events/result` from an earlier attempt, but
nothing called it.

## Decision

1. **Open the forwarded-event stream.** `DshConnectionManager` opens the
   logical `remote-events` stream (`endpoint: $events`) on `/api/remote.mux`
   beside `workspace-follow` and `session/control`.
2. **Fold waterfalls into the existing request pipeline.** A `waterfall` item
   becomes the same internal request envelope the 0.1.1 mux frames produced
   (`question/requested` / `approval/requested`, keyed by the frame's
   `eventId`), then travels the one shared path — registry fold for the roster
   and alerts, live window when the session is instantiated, pre-instantiation
   buffer otherwise. The host projects the Agent out of `request`, and
   session-controller resolves an Agent identity to its session, so `agentId`
   files the request.
3. **Answer through `$events/result`.** `answerQuestions`, `cancelQuestions`
   and `respondToApproval` recognise a pending waterfall and send
   `{clientId, eventId, outcome}`: `{kind: 'result', value: {answers: […]}}`
   for a question, `{kind: 'result', value: 'allowed-once' | 'rejected'}` for
   an approval, and `{kind: 'rejected', error: {name: 'UserQuestionError',
   code: 'ASK_CANCELLED'}}` for a dismissal. A waterfall this client does not
   answer is delegated with `{kind: 'next'}` so the host's own answerer still
   sees it. The `ready` item binds the generation's `clientId`.
4. **End the card with the request.** A `cancel` item (the host dropped the
   request's lifetime) and the client's own answer both settle the local
   card; a new stream generation re-delivers every still-pending waterfall, so
   a reconnect restores the question. The 0.1.1 mux path stays as the legacy
   fallback and shares the same pipeline.

## Alternatives considered

- **Wait for a host-side bridge to the 0.1.1 frame names**: rejected — the
  deployed host is 0.1.2 and its allowlist is the contract; a client that only
  speaks retired frame names has no answer surface at all.
- **Drive the card from a client-side `$events` mirror instead of the timeline
  reducer**: rejected — the reducer already owns the request shape (intent
  classification, plan-review narrowing, dismissal), so reusing it keeps one
  decision surface and one classification.
- **Answer questions through `POST /api/respond` (the 0.1.1 carrier)**: not
  possible — a 0.1.2 waterfall is not an `rpcId` reply; it settles only through
  `$events/result`.
- **Treat every forwarded waterfall as answerable**: rejected — the allowlist
  is open, and an unknown event must delegate (`next`) rather than be claimed.

## Consequences

- Ask, plan-review and approval cards appear on a 0.1.2 host, and the roster's
  pending dot with them; the answer reaches the host as the decision it is.
- A reconnect re-delivers pending waterfalls, so a decision survives a
  generation loss without the buffer replay the mux path needed.
- The pinned reference submodule is 0.1.1 while the deployed host is 0.1.2, so
  this contract is sourced from the 0.1.2 tree the host is built from
  (`packages/api/gateway/src/stream-protocol.ts`,
  `packages/api/remotes/src/remote-events.ts`), not the pin. Raising the pin to
  a 0.1.2 revision is a separate decision.
- Adapter tests pin the whole path: a `ready` + two `waterfall` items (question
  and approval) open both cards and answer with the exact `$events/result`
  outcomes, and a `cancel` item withdraws the card.
