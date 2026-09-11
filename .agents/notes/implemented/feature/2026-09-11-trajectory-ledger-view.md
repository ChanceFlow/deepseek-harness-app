# Agent Note: Trajectory ledger view

Status: implemented

## Problem

The reference web client ships two conversation views over one session: the
chat transcript and a turn-aware **Trajectory** ledger
(`reference/deepseek-harness/packages/client/ui-trajectory/`). The ledger
shows a thick rule at every turn, inline step markers, selectable
User/Assistant/Tool/Sub-tool records, a per-record inspector of token usage
and timing, local search over the ledger, and older-history paging
(`TrajectoryTable.tsx:1-1588`, `TrajectoryToolbar.tsx:114-126`,
`trajectory-search-index.ts:124-132`). The phone client has neither the view
nor the per-record facts behind it.

The reference assembles the ledger client-side from the session event stream
and `session/history`; it needs no RPC. The phone client already decodes both
— `TimelineReducer` folds the same events and `ChatRepository` already pages
— but the fold discarded three facts the ledger's inspector states:
`step/start` boundaries, `assistant/message.usage`, and the recorded
assistant stream's first-token time.

## Decision

**The ledger reads the existing `domain` timeline window; no new RPC.** The
new `app/lib/ui/trajectory/` package owns `TrajectoryController`,
`TrajectoryScreen`, and the entry route. The controller subscribes to
`observeTimelineWindow` — the same window the chat surface renders — folds it
into turn sections with inline step markers, indexes the loaded window for a
local AND-term search, and pages older history through
`loadOlderHistory`. Selection opens a modal inspector.

**Expose the missing facts in `domain`; decode them in the adapter.** Three
additions, each from the submodule rather than inferred:

- `TimelineMessage.step`, `TimelineToolCall.step` — from `step/start`
  (`packages/core/session/src/types.ts:287`). The wire already carries the
  step on `assistant/message`, `tool/call`, and `tool/result`; `step/start`
  supplies it for code-dispatch sub-calls, whose payload
  (`packages/core/tools/src/types.ts:11-23`) has no step.
- `TimelineMessage.usage` and `TimelineTurnBoundary.usage` — from
  `assistant/message.usage`, a `TokenUsage` whose counts are disjoint
  (`packages/llm/llm/src/types.ts:149-163`). `TokenUsage` is a new `domain`
  value type; billed input is the sum of the three input buckets, never a
  provider total.
- `TimelineMessage.firstTokenAtEpochMs`, `TimelineToolCall.startedAtEpochMs`
  — the recorded stream's first token (`assistantStreamFirstTokenTime`,
  `packages/llm/llm/src/assistant-stream.ts:333`) and the `tool/call` or
  dispatch-start event time. Both are decoded in `dsh_wire_types.dart` with
  fixture and negative tests.

**Nested sub-calls nest by their own pairing ids.** `tool/ptc-dispatch-start`
/ `tool/ptc-dispatch` (`packages/core/tools/src/types.ts:40-56`) fold into
`TimelineToolCall.children` under the parent call, matched by `subCallId`. A
dispatch whose start fell outside the folded window still publishes its
settled outcome as a row rather than vanishing.

**A figure the log does not carry is stated, not estimated.** The inspector
renders turn, step, kind, status, start time, first-token time, and the token
buckets. It states **unavailable / not recorded** for a record's own duration
and throughput: the log has no `tool/result` timestamp and no recorded
`step/start` on the tool path, so `total − first token` would be invention.
Nothing in the view computes a number the host never sent.

Density decisions on a 360dp phone: 12sp content on the smallest M3 text
roles, one ellipsized scan line per record; a 2dp `primary` rule at a turn and
a `Step {n}` chip at a step instead of cards; a 16dp indent over a hairline
`outlineVariant` rule per nesting depth; the inspector is a modal sheet, since
a phone has no room for the reference's side-by-side split.

## Alternatives considered

- **A new RPC returning the projected ledger.** Rejected: the reference
  assembles it client-side from events the client already decodes, and a new
  verb would duplicate the fold on both sides of the wire.
- **A `TimelineStepBoundary` item.** Rejected: `timeline_folding.dart` and
  `chat_screen.dart` switch `TimelineItem` exhaustively, so a new variant
  forces edits inside another owner's files for no reader benefit. A step is a
  fact of the rows inside it, so it rides those rows.
- **Fold the token total on `ChatMessage`.** Rejected: the turn's total is a
  boundary fact, and the chat transcript renders no per-message accounting.
- **Derive duration from `assistant/message` time minus `step/start`.** The
  tool path logs no result timestamp, so the metric would be absent for
  exactly the rows the reference shows it on; recording it as unavailable is
  the honest output.
- **A side-by-side inspector.** Rejected at 360dp; the sheet keeps the
  ledger visible underneath and needs no layout state.

## Consequences

- The chat header needs one mount:
  `TrajectoryEntryButton(backendId: …, sessionId: …)` in the AppBar `actions`.
  The widget carries its own route and `ProviderScope` override, so no other
  chat edit is required.
- `ChatRepository.loadOlderHistory` is now driven by two views over one
  shared session state; the repository's `_loadingOlder` guard keeps the two
  from racing.
- The adapter decodes four previously ignored wire facts, so adapter fixture
  coverage grows with the view.
- Per-record duration and decode throughput remain absent from the phone
  ledger until the contract carries a settle timestamp.
