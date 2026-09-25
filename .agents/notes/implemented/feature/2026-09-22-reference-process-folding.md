# Agent Note: The transcript folds process the way the reference does

Status: implemented

## Problem

The transcript's folding was our own design. The pinned reference client
(`reference/deepseek-harness/packages/client/ui-chat/`) folds the same
material in two levels, and the readings had drifted:

- The reference has a **Turn-level control** per Turn
  (`conversation-nodes/turn-process.ts`, `chat/TurnProcessNodeView.tsx`):
  `Deep diving for 8s` while it runs, `Took 2m 03s`, `Stopped`, `Failed` or
  `Worked` once it ends, and one chevron over everything the agent did before
  its finalized answer. We had no such row.
- Its **group header** carries a category icon and a label built from the
  group's **top three ranked categories** without counts (`processTitle`:
  `Searched code and read files`), and while the group runs it shows the live
  label plus a **one-line running detail** taken from the running tool's own
  arguments (`process-activity.ts`, 160 graphemes, falling back to the newest
  reasoning paragraph). Ours built a bespoke sentence (`Explored 3 files, 2
  searches`) with eight coarse variants, no icons and no detail, and chose its
  subtitle by testing whether the title contained the English or Chinese word
  for "operation" — copy sniffing that also put user-visible strings at the
  call site instead of in the ARB.
- A reply-bearing step whose reasoning is non-empty contributes that reasoning
  to the phase **and** renders its reply as a row (`process-groups.ts`); ours
  dropped the reasoning when the step had text.
- A phase is live only while it is the Turn's **trailing** one; any node after
  it closes it (`flush`). Ours read liveness off the whole Turn, so a live
  Turn's finished phases all wore a running label.

## Decision

Port the model and its chrome, with every string from the reference's own
locale table:

- `process_activity.dart` ports `process-activity.ts`: the 14 categories in
  the reference's probe order, ranked counts with explicit first-appearance
  ties (Dart's `sort` is not stable), the live detail's argument-key priority,
  whitespace collapse, the 160-**grapheme** cap (hence the `characters`
  dependency) and its reasoning fallback. Its `preparing` phase is read off the
  payload — arguments absent or not yet parseable — because a durable tool call
  carries no phase frame, and its detail falls back to the phase's newest
  thought rather than to a still-running step.
- `turn_process.dart` derives one Turn's facts from its boundary and splits
  its rows into `TurnProcessMember`s that keep the transcript order and carry a
  `folds` flag. The answer — the Turn's last reply-bearing assistant message,
  and only when no tool call follows it, phases' own members included — and
  every row after it never fold, so collapsing hides work without moving the
  reader's message or the reply. A Turn with nothing foldable cannot collapse
  (`hasContent`).
- `process_disclosure.dart` renders both controls in stock Material chrome: the
  Turn control is a full-width row under a hairline rule whose chevron rotates
  180°; the group header is a 16px box where the category icon and the chevron
  cross-fade, over a body capped at `min(400, 50vh)` with 24px edge fades.
  `processActivityIcon` and `processActivityIconSize` follow the glyph the
  reference draws — including its reuse of one document glyph for `read`,
  `readImage` and `webFetch` — not the label beside it.
- `timeline_folding.dart` ports the reply/phase split: a step with both
  reasoning and text puts the reasoning in the phase and emits its reply
  through `_replyOnly`, and a phase is closed unless it is the Turn's trailing
  one.

## Alternatives considered

Keep our summary and only add icons: rejected — the labels are what a reader
reads, and a bespoke sentence keeps diverging from the client the user compares
us against. Implement the four work-details modes
(`compact`/`standard`/`detailed`/`verbose`): deferred, not rejected; the app
has no such setting and the reference's `standard` policy is what this ports.
Render the Turn control without folding: rejected, a finished Turn collapsing
to one line is the behavior the user asked for. Keep the interactive cards
inside the fold: rejected, the reference renders approvals and questions
through a slot outside the transcript while here they are rows, and hiding a
blocking prompt would remove the reader's only way to answer it.

## Consequences

A finished Turn reads as one line plus its answer; a running, stopped, failed
or human-interrupted Turn never folds. Deliberate departures: slash-command
cards, compaction markers, approval and question cards, and
`TimelineHookAudit`/`TimelineWorkflowRun` rows stay outside the fold; the
answer is read by position because a `TimelineItem` carries no step, where the
reference reads per-step Node data; there is no `turn-trigger` or `model-retry`
row here. The group header's chevron appears only on hover or while open,
faithful to `ChatGroupSeat.module.css`, so on a touch screen the header reads as
a plain label — the one desktop affordance this port copies. The child-session
record on the subagents screen is still unfolded: it renders raw rows through
`TimelineRow`. Six old copy keys for the replaced summary were deleted from both
locales.
