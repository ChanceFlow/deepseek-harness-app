# Agent Note: Todos projection, plan strip, and subagent child-view semantics

Status: implemented

## Problem

The `todos` projection (the standing `todo/write` list) never reached the
client — `todo_write` calls rendered as generic tool rows and no plan strip
existed above the composer. The Subagents screen was a debug-grade surface:
its child view showed a raw one-line-per-item timeline with a free-text
composer, ignoring the web's read-only semantics for one-shot and
parent-offline children, the read-only queue display, and the child's plan
chip.

## Decision

The adapter exposes `observeTodos(sessionId)` over the same channels as
plan: `session/projection` push frames (key `todos`) and the history tail
page's `projections.values` baseline. The domain carries
`TodoItem {content, status: pending|in_progress|completed}`
(`dsh-tool-todo` projection schema: the whole list, or null before the
first write / after a later `turn/start`). The chat controller subscribes
alongside plan and publishes `ChatUiState.todos`.

The plan strip (`todo_panel.dart`) ports the web `TodoPanel`: hidden while
empty, header = checklist glyph + "To-dos" + per-status counts
("·"-joined, zero-count segments dropped) + disclosure chevron; the
expanded body lists items with status glyphs (check ring / plain ring /
dashed ring on the figma 14×14 artboard). It mounts at input-dock order 0,
before the goal strip and queue dock.

The `todo_write` tool row ports the web `todo-row.tsx` + `plan-summary.ts`:
dedicated title "Update to-do list", checklist leading glyph, args-derived
plan summary "done/total completed · first active item" with the
parallel-active remainder as a non-shrinking "+N" suffix; malformed args
fall back to the generic row summary. The receipt stays in the expanded
output only.

The Subagents screen renders the web catalog form (StateDot, label +
`title · mode · activity` secondary, expandable branches, disabled
diagnostic rows) in the framework-row form componentized by
[subagent screen component pass](../simplification/2026-08-29-subagent-screen-framework-component-pass.md),
and its child view renders through the real `TimelineRow`
set with three read-only semantics: the read-only composer notice for
one-shot/parent-offline children (`SubagentReadOnlyComposer` copy — the
offline gate reads the availability of the catalog level owning the row,
see
[subagent lineage events](../bug-fix/2026-08-29-subagent-lineage-events-typed-mode-and-sheet-visibility.md)),
queued messages as read-only previews (`queueMutable = subagent === null`),
and a locked plan chip fed by `observePlan(childId)`.

## Alternatives considered

- **Fold todos client-side from `todo/write` events**: rejected — the host
  publishes a durable projection; refolding duplicates the turn/start
  clearing rule and desynchronizes from the web's value.
- **Keep the child view as a summary list**: rejected — the child's
  conversation is exactly what the web shows; real rows (messages, tool
  rows including the todo row, context injections) are the semantics.
- **Editable queue on the child view**: rejected — the web disables
  edit/steer/remove on subagent views; the parent owns queue mutations.

## Consequences

Plan/todo state is visible in every conversation surface including child
views; `turn/start` clears the strip through the host projection, not
client state. Web catalog token/duration metrics remain unported — the
domain model exposes no `tokenUsage`/`subagentTiming` projections (noted
at the secondary-line composition site).
