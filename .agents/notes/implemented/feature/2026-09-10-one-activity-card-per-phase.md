# Agent Note: One activity card per execution phase

Status: implemented

## Problem

A phase that reasoned, was handed context and then ran tools rendered as a
stack of separate folds: a `Thought` row, the `ToolGroupRow` action chip, and
one `ExpansionTile` per injected-context row. The reader tapped three places to
read one step, and an injection — a step in the run like any other — also cut
the tool run in half, because `foldTimelineActivities` treated
`TimelineContextInjection` as a phase boundary.

## Decision

1. **One card per phase.** `TimelineToolGroup` becomes
   [TimelineActivityGroup](../../../../flutter/app/lib/ui/chat/timeline_folding.dart),
   holding the phase's members in transcript order: the merged thought, the
   injected-context rows and the tool calls. A phase of one member keeps its own
   row — a lone tool call, a lone thought and a lone injection all render
   exactly as before.
2. **Injections are steps, not boundaries.** An injection joins the phase
   instead of flushing it, so tool runs on either side of a recall stay one
   card.
3. **The card owns the phase's only disclosure.** Its members render inline
   when it opens: `ReasoningRow` and `ContextInjectionRow` gained an `inline`
   mode that drops their own chevron and fold, and `ToolCallRow` keeps the
   expansion it already had.
4. **The collapsed header names the phase.** Tool calls present → the semantic
   tool summary (`Explored 3 files, 2 searches`), with the phase's thinking time
   appended (`· Thought 10s`) so a phase that both thought and worked keeps both
   facts; no tool calls → the thought label or the injection's role. The leading
   glyph follows: activity dot, success check, psychology for a thought-only
   phase, travel_explore for context.
5. **A phase's thoughts still merge into one block**, at the position of the
   first thought, so the `Thought 10s` total survives — but the card is keyed on
   its *first* member's id, because the merged message borrows the newest
   chunk's id while it streams and would remount the card on every chunk.

## Alternatives considered

- **Keep the thought row outside the card and fold only injections**: rejected
  — the reader asked for one card per phase; the thought is the phase's own
  reasoning, and its duration rides the header instead.
- **Merge every phase's thought block to the card's end**: rejected — the
  merged thought belongs where the thinking happened, and tools that ran before
  it must not read as having run after it.
- **Nest each member's own disclosure inside the card**: rejected — a card full
  of folded rows is the stack this change removes.
- **Fold consecutive injections into their own card when no tools ran**:
  rejected — the phase rule stays uniform; a run of injections is one card,
  headed by the role of its first member.

## Consequences

- A phase reads as one line (`Explored 3 files, 2 searches · Thought 10s`) that
  opens into the reasoning, the injected context and every tool row in order.
- `ActivityGroupRow` replaced `ToolGroupRow`; folding tests, the Cursor-style
  transcript test and the injection test were rewritten against the card, and
  the design fixture gained a phase that reasons, is handed a recall and then
  reads files.
- Partially supersedes
  [cursor-style timeline folding](2026-09-08-cursor-style-timeline-folding.md):
  its semantic summaries, thought durations and phase extraction stand, while
  its two-fold phase shape does not.
