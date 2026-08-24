# Agent Note: Streaming reply re-parse and re-copy made linear

Status: implemented

## Problem

A long conversation whose agent emitted a huge, repetitive block (the
easytile sessions) crashed the phone client while the web client on the
same host stayed responsive. Three quadratic behaviors compounded on the
phone, none of which the reference web client has:

1. **`MarkdownText` re-parsed its whole text on every build.** The widget
   was stateless: every timeline publish — every `assistant/chunk` delta —
   rebuilt every visible row, and each rebuild ran
   `MarkdownParser.parse` over each message's full accumulated text, then
   rebuilt every block's widget subtree and re-laid-out the text. Cost per
   delta grew with the message; cumulative cost grew quadratically.
2. **The reducer concatenated an immutable string per delta**
   (`text += delta`), re-copying the whole accumulated message on every
   chunk.
3. **Every publish rebuilt the whole screen.** The web publishes a
   streaming session at animation-frame cadence (one React commit per
   frame regardless of chunk count) and renders per-node subscriptions
   (`ChatNodeSeat` memo per key), so one chunk re-renders exactly one row.

On a phone the per-delta work (parse with inline regexes + full widget
tree + full text layout) saturates the UI thread; the frame backlog and
the parse-tree allocations balloon memory until the OS kills the app.
The web survives on three layers the phone client lacked: frame-batched
notification
([notifier.ts](../../../../reference/deepseek-harness/packages/client/runtime/src/client/sessions/notifier.ts)
`markFrameDirty`; the assistant node publishes every chunk at
`'animation-frame'` cadence), memoized per-block rendering
([AssistantMarkdown.tsx](../../../../reference/deepseek-harness/packages/client/ui-conversation/src/client/chat/AssistantMarkdown.tsx)),
and an incremental markdown parser that freezes every block behind the
trailing two and re-parses only the tail
([incremental.ts](../../../../reference/deepseek-harness/packages/client/ui-primitives/src/markdown/incremental.ts)
— its header states the exact quadratic this note's item 1 reintroduced).

## Decision

Port the web's per-message economics, then its frame-cadence publishing:

- **Incremental parse.**
  [markdown_parser.dart](../../../../flutter/app/lib/ui/chat/markdown/markdown_parser.dart)
  now exposes `parseSpanned` — the same block parse with each block's
  source character span (`linesWithStarts` splits lines with offsets) —
  and [incremental.dart](../../../../flutter/app/lib/ui/chat/markdown/incremental.dart)
  ports the reference `IncrementalMarkdownParser` verbatim: append-only
  input freezes all but the trailing two blocks and re-parses only the
  tail behind the last frozen block's end offset; non-append input resets.
- **Cached block widgets.** `MarkdownText` is stateful: a block whose
  instance survived the freeze (or whose value is deep-equal, for the
  unstable tail's settled blocks) reuses its built widget instance, which
  Flutter skips wholesale (`Element.updateChild` short-circuits identical
  widgets), so a delta re-builds only the tail. Theme/locale dependency
  changes discard the widget cache and rebuild.
- **Buffered accumulation.** The timeline reducer's streaming partial
  accumulates into `StringBuffer`s; one delta is one O(delta) append and
  the `ChatMessage` string materializes only when `snapshot()` reads it
  (`_materializePartial`), pairing with the render-side freeze.
- **Frame-cadence publishing** (web layer 1, `markFrameDirty` /
  `'animation-frame'` publication rank).
  [harness_repository_impl.dart](../../../../flutter/packages/harness_adapter/lib/src/harness_repository_impl.dart)
  `_SessionState` coalesces streaming token chunks — every
  `assistant/chunk` except `finish`/`usage` — into one timeline-window
  publish per 16ms window (`kStreamPublishWindow`), capping the publish
  rate at frame cadence no matter how fast the host flushes chunks. All
  other frames (turn boundaries, tool calls, approvals, queue, jobs)
  publish immediately, and an immediate publish flushes chunks still
  waiting on the timer, so structural events never wait a frame behind
  streaming. Repository `dispose()` cancels a still-pending publish.

## Alternatives considered

- **Frame-coalesced publishing in the controller instead of the
  adapter**: rejected — the adapter is where the publication rank lives
  (the web classifies in the conversation assembler under the Session),
  and coalescing after the controller would still pay the window-stream
  fan-out per chunk.
- **Virtualization / per-row subscriptions** (web layer 2): deferred —
  the transcript is already a lazy `ListView.builder` and only visible
  rows build; the multi-backend slice watch in `ChatRoute` is the
  remaining O(all backends) per-publish cost.
- **Porting micromark/CommonMark**: rejected — the hand-written parser is
  the repo's standing decision, and spans give the freeze scheme
  everything it needs.

## Consequences

- Per-chunk work now tracks the unstable tail (≤2 blocks), not the
  message; a settled message costs zero parse on any later publish, so
  the easytile shape (giant repetitive output into one long conversation)
  renders at the same cost as the web's streaming path.
- Property tests pin the invariant: incremental appends equal a full
  parse at every prefix (per-line and per-word corpora), frozen blocks
  keep their instances, non-append input resets, and `linesWithStarts`
  matches `LineSplitter`'s boundary semantics.
- Two integration tests pin the coalescing: five chunks inside one window
  produce exactly one window publish carrying the accumulated partial,
  and a structural frame publishes immediately while flushing chunks
  still waiting on the timer.
- Known shared deviation (inherited from the reference design): a
  reference-style link whose definition lands across the freeze boundary
  renders literally until the settled full parse self-heals it — our
  grammar has no reference links, so the deviation is vacuous here.
- `_framesAfterOpen` retains every live frame's raw JSON for the
  session's lifetime — the reference `Session` does the same with its
  `events` array (the window pages only toward older history), so this is
  parity, not a deviation.
