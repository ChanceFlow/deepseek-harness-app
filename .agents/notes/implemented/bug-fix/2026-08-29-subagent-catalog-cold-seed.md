# Agent Note: Subagent catalog cold seed from the host-reported tree

Status: implemented

## Problem

Opening the Subagents screen from a chat session that had subagents
rendered the "No subagents" empty state even though the host had a full
child tree to report; only the app-bar refresh made rows appear, and
re-selecting the already-pre-selected parent in the sheet was a no-op.
Root cause: the chat route pre-selects the parent via
`SubagentController(initialSessionId:)`, but the catalog was fetched only
from the `SelectParent` action — construction never requested it.

The originating diagnosis claimed the fix was to decode a per-session
`subagentSummary` field off the `sessions/list` response and cold-seed a
live-event projection from it. Re-verification rejects both premises
against this repo's pinned contract
(`dsh-v0.1.1-rc.2`): the method is `session.list`, its row schema
([sessions.schema.ts](../../../../reference/deepseek-harness/packages/host/apiproxy/src/api/sessions.schema.ts)
`sessionSummarySchema`) carries no `subagentSummary`, no `AgentRef` type
exists, no `agent/list` RPC exists, and a whole-disk search finds zero
hosts on this machine publishing the field. `subagent_store.dart` and
`subagent_projection.dart` are deleted legacy-Kotlin files; the Dart
rewrite already replaced that event projection with the `subagent.list`
RPC catalog ([subagents.schema.ts](../../../../reference/deepseek-harness/packages/host/apiproxy/src/api/subagents.schema.ts)
`subagentListValueSchema`), which reads durable state and answers the
parent's complete child tree — settled children included — from a cold
host. Decoding the claimed field would have meant inventing a fixture
payload, which [docs/testing.md](../../../../docs/testing.md) rule 3
forbids.

## Decision

The fact source for the subagent list is the host's `subagent.list`
report, cold-seeded into the screen state:
[subagent_controller.dart](../../../../flutter/app/lib/ui/subagents/subagent_controller.dart)
requests the pre-selected parent's catalog the first time a
`session.list` publication contains that session (host reachability and
a fresh parent row are proven by that point; an offline launch shows no
spurious failure). Merge policy: each landed snapshot replaces the
parent's tree wholesale — the host re-reads durable state per call, so
there is nothing client-side to merge row-by-row — and live session
events never merge catalog rows; catalog upkeep flows through the
child-membership re-pulls and post-action reloads of
[subagent lineage events, typed history mode, and sheet visibility](2026-08-29-subagent-lineage-events-typed-mode-and-sheet-visibility.md),
plus the explicit refresh action (the interrupt path already reloads).
The screen's `SubagentRoute` already streams `controller.uiState`, so no
subscription change was needed.

## Alternatives considered

- **Decode `subagentSummary` from `session.list` rows, as diagnosed**:
  rejected — the field does not exist in the pinned wire contract; the
  adapter may only decode what the submodule defines.
- **Poll an `agent/list` RPC**: not applicable — no such method exists in
  the pinned contract (`subagent.list` is the roster RPC).
- **Keep catalog loading gesture-only**: rejected — a cold open with
  host-reported children renders empty until the user discovers the
  refresh button; that is the user-visible defect.
- **Fetch in the constructor unconditionally**: rejected — races
  connection readiness and spends a failure banner on launches before
  the host is reachable.

## Consequences

- One `subagent.list` call per cold open of the page, and none until the
  host has answered `session.list`.
- Three new regression tests pin the chain through real entry paths:
  `subagent.list` decode with rows / without rows / a fail-loud negative
  in
  [harness_repository_integration_test.dart](../../../../flutter/packages/harness_adapter/test/harness_repository_integration_test.dart),
  controller cold-seed behavior in
  [subagent_controller_test.dart](../../../../flutter/app/test/ui/subagents/subagent_controller_test.dart),
  and a route-level cold-open widget test; the contract bullet lives in
  [docs/spec.md](../../../../docs/spec.md) §11.
- Any future host that does fold the tree into `session.list` rows will
  re-pin the submodule first; until then this note owns the fact-source
  decision. The screen's catalog rendering and child-view semantics
  remain owned by
  [todos projection and subagent view](../feature/2026-08-19-todos-projection-subagent-view.md),
  which this note cross-links without superseding.
