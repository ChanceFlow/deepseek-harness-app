# Agent Note: Subagent lineage events, typed history mode, and sheet visibility

Status: implemented

## Problem

Three verified defects in the Subagents screen's data chain, all under the
catalog/child-view contract owned by
[todos projection and subagent view](../feature/2026-08-19-todos-projection-subagent-view.md)
and seeded by
[subagent catalog cold seed](2026-08-29-subagent-catalog-cold-seed.md):

1. **The catalog never refreshes after open.** The wire reports child
   spawns over `host/session-added` frames
   ([events.schema.ts](../../../../reference/deepseek-harness/packages/host/apiproxy/src/api/events.schema.ts),
   carrying `parentSessionId` + `origin: 'subagent'`) and `session.list`
   rows carry `parentSessionId`
   ([sessions.schema.ts](../../../../reference/deepseek-harness/packages/host/apiproxy/src/api/sessions.schema.ts)
   `sessionSummarySchema`). The adapter decoded `parentSessionId` in
   `SessionWire` but dropped it at the domain boundary, so
   `SubagentController` had no lineage to diff: a child spawned after the
   page opened never appeared, and a child whose session detached kept a
   lit status dot.
2. **A one-shot child's transcript never opens.** The adapter hardcoded
   `'mode': 'continuable'` on `subagent.history`, and the host's
   `catalogChild` guard answers a mode mismatch with
   `subagent-not-found`
   ([subagents.schema.ts](../../../../reference/deepseek-harness/packages/host/apiproxy/src/api/subagents.schema.ts)
   + api-proxy.ts). Every one-shot row tap died on the error banner plus a
   fake-empty transcript (`result ?? const []`). Companion bug: the
   read-only composer gate for a child opened inside an expanded branch
   evaluated the root catalog's `parentAvailable` instead of the branch's.
3. **The parent-picker sheet lists subagent children as selectable
   parents.** The sidebar hides them through the app-wide
   [`sessionVisible`](../../../../flutter/app/lib/ui/shared/session_tree.dart)
   rule; the controller's own visibility filter only dropped blank rows.

## Decision

**Lineage into the domain + debounced event refresh.** `SessionSummary`
carries a neutral `parentSessionId` field (constructor, `==`, `hashCode`;
the model has no props method);
[`_toDomainSession`](../../../../flutter/packages/harness_adapter/lib/src/harness_repository_impl.dart)
maps the already-decoded wire value, and the fold helpers
(`_copySession`, `_withPending`) preserve it. `SubagentController` diffs
attributed children of each watched parent — the selected root plus every
expanded branch — on each `session.list` publication: a child added or
removed schedules one `subagent.list` re-pull per parent after a 50 ms
window (web `scheduleCatalogRefresh` debounce in
[manager.ts](../../../../reference/deepseek-harness/packages/client/runtime/src/client/sessions/manager.ts));
a removal or a running-state flip first folds that row's activity in the
loaded catalogs (web `updateCatalogActivity`) so the dot tracks the live
session — dimming with it, relighting on a resumed child — before the pull
lands. Mutual exclusion with the cold seed: the seed
fires exactly once per parent through `_catalogRequestedFor`; the
membership baseline for a parent is established on the first publication
that carries that parent's own row — the same host-answered gate as the
seed — so the cold open never double-pulls, and every later membership
change re-pulls regardless of the seed gate.

**Typed mode end to end.** The domain gains the closed enum
`SubagentMode { oneShot, continuable }`;
[`SubagentEntry.mode`](../../../../flutter/packages/domain/lib/model/subagent.dart)
is that enum, and the adapter maps wire literals onto it, failing loud on
a child row with a missing or unknown mode (the schema requires it on
child rows). `ChatRepository.loadSubagentHistory` takes the row's own
`SubagentMode`; the `OpenChild` action carries it from the tapped row;
the controller keeps it for the post-prompt reload. `subagent.prompt` and
`subagent.interrupt` keep their signatures — the request schemas pin the
`'continuable'` literal — but the adapter now encodes that literal through
the enum instead of a bare string. A failed history load closes the child
view instead of leaving it open on a fake-empty transcript; the host
failure rides the existing error banner. `childReadOnlyReason` now gates
on the parent availability of the catalog owning the entry (root or
branch).

**Sheet visibility.** `SubagentController._publish` filters through
`sessionVisible`, the single home of the browsing rule.

## Alternatives considered

- **Read `parentSessionId`/`origin` off the host frame in the adapter and
  merge summaries** (the web's fast path): rejected — this client already
  repulls `session.list` on those frames; pulling lineage from the frame
  would add a second membership source racing the pull.
- **Poll or manual-refresh-only for catalog upkeep**: rejected — it is the
  defect itself; the cold seed deliberately answers only the open moment.
- **Keep `mode` a string and re-parse at request time**: rejected — the
  closed enum makes every mode decision an exhaustive switch and lets the
  decoder fail loud on contract violations.
- **Add a `childLoadFailed` transcript state**: rejected — closing the
  record on failure keeps the error banner honest with no new UI surface
  for the design-language pass to reconcile.

## Consequences

- One extra `subagent.list` pull per child spawn/detachment while a parent
  or branch is watched, merged inside the window; none on cold open.
- Wire evidence pins the chain:
  [harness_repository_integration_test.dart](../../../../flutter/packages/harness_adapter/test/harness_repository_integration_test.dart)
  covers lineage decode, `host/session-added` → stream, the one-shot mode
  on the request frame, `subagent-not-found` propagation, the
  continuable pin on prompt/interrupt, and the child-missing-mode
  negative;
  [subagent_controller_test.dart](../../../../flutter/app/test/ui/subagents/subagent_controller_test.dart)
  covers the debounced re-pull and burst merge, both fold paths, mode
  threading, fail-loud close, branch availability gating, and sheet
  visibility.
- The contract bullets live in
  [docs/spec.md](../../../../docs/spec.md) §11; the RPC method count is
  unchanged (field-level corrections to existing methods).
- The cold-seed note's refresh-flow sentence is superseded by this one and
  links here; child-view rendering semantics remain owned by the todos
  projection note.
