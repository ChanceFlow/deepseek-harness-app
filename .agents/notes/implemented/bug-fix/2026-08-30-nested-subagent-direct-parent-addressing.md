# Agent Note: Direct-parent addressing for nested subagents

Status: implemented

## Problem

The Subagents screen renders a recursive nested catalog tree
(`_CatalogBranch` in
[subagent_screen.dart](../../../../flutter/app/lib/ui/subagents/subagent_screen.dart)).
When tapping a row, the screen dispatched `OpenChild(entry.id, mode)`
([subagent_ui_state.dart](../../../../flutter/app/lib/ui/subagents/subagent_ui_state.dart))
without parent attribution.
`SubagentController` addressed `loadSubagentHistory(parentId, child, mode)`,
`sendSubagentPrompt(parentId, child, ...)`, and `interruptSubagent(parentId, child)`
using `_selectedParentId` — the root parent selected in the parent picker.

For depth≥2 rows (grandchildren and deeper descendants), the host expects the
direct parent session id (`SubagentAddress = { parentSessionId, childSessionId }`,
as defined in
[subagents.ts](../../../../reference/deepseek-harness/packages/host/apiproxy/src/api/subagents.ts):49-57
and wired in
[SubagentHeaderLineage.tsx](../../../../reference/deepseek-harness/packages/client/ui-subagent/src/client/SubagentHeaderLineage.tsx):324-327).
Passing the tree root instead of the direct parent caused history load, prompt send,
and interrupt to target the wrong session and fail with `subagent-not-found`.

## Decision

1. **Direct parent in actions.** `OpenChild` and `InterruptSubagent` carry the
   row's direct parent session id (`parentSessionId`). `_CatalogBranch` passes
   `catalog.parentSessionId` — the session id of the catalog level that produced
   the entry. Depth-1 rows keep identical behavior where direct parent equals the
   root parent.
2. **Controller rebinding.** `SubagentController` records `_selectedChildParentId`
   alongside `_selectedChildId` when opening a child, and passes that direct parent
   id to `loadSubagentHistory`, `sendSubagentPrompt`, and `interruptSubagent`.
   Opening a different child rebinds both fields; closing or switching root parent
   resets both.
3. **State exposure.** `SubagentUiState` exposes `selectedChildParentId`, and
   `selectedChildCatalog` verifies entry containment within the direct parent's
   catalog or branch.

## Alternatives considered

- **Resolve parent solely by walking loaded catalogs on demand**: rejected —
  a direct parent carried explicitly in `OpenChild` mirrors the web client contract
  (`openChild({ parentSessionId, childSessionId, mode })`) and avoids ambiguous
  tree lookups during branch catalog refreshes.
- **Flatten nested subagents into a single-level list**: rejected — the host
  wire protocol and web client represent subagents as an arbitrary-depth hierarchy
  where each branch represents a subagent session.

## Consequences

- Depth≥2 nested subagent rows correctly load transcripts, accept continuable
  prompts, and receive interrupt cancellations addressed to their direct parent.
- Unit and widget tests in
  [subagent_controller_test.dart](../../../../flutter/app/test/ui/subagents/subagent_controller_test.dart)
  and
  [subagent_screen_test.dart](../../../../flutter/app/test/ui/subagents/subagent_screen_test.dart)
  pin that grandchild row taps dispatch direct-parent `OpenChild`, history loads
  receive `(directParentId, grandchildId)`, and prompts/interrupts target the direct
  parent.
- Complements
  [subagent lineage events, typed history mode, and sheet visibility](2026-08-29-subagent-lineage-events-typed-mode-and-sheet-visibility.md).
