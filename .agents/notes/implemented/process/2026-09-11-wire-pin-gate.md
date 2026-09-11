# Agent Note: A gate for the wire pin

Status: implemented

## Problem

`flutter/packages/harness_adapter/lib/src/rpc_map.dart` (`DshRpcEndpoints`)
declares the wire names this client calls; `reference/deepseek-harness/`
pinned at `reference/README.md` is the contract those names must match. No
check compared them. The adapter's fake-host suite derives its accepted set
from the same registry it should police — the removed
`_testLegacyToCanonicalMap` folded `skill/list`, `skill.list`, and
`skills/list` onto one constant — so a renamed wire name kept the suite
green. The client drifted about four minor versions ahead of its own source
of truth, and the re-pin procedure claimed a wire-parity test that never
existed.

## Decision

[scripts/verify_wire_pin.py](../../../../scripts/verify_wire_pin.py) joins
`verify_all.py`'s `docs` group behind the usual submodule guard. Python-only
and sub-second, it is the fast joint's job: the failure it prevents is a
process/contract drift, not Flutter behavior.

- **The registered surface is derived from declaration sites.** 0.1.2 deleted
  the static `packages/host/apiproxy/src/api/rpc-map.ts`; 0.1.5 registers
  `@Remote` methods on `TypertRemoteService` subclasses and composes
  `<namespace>/<exportName>` at build time, so no committed file holds the
  endpoint literals. The gate scans `class … extends TypertRemoteService`,
  the `super(ctx, '<key>'[, { namespace }])` binding, and each line-anchored
  `@Remote` decorator, plus the Gateway's `REMOTE_EVENT_RESULT_ENDPOINT`.
  `fixture.ts` was rejected — it is the upstream client's fake and omits
  endpoints the 0.1.5 host registers (`workspaceFiles/readBytes`, `readAll`)
  — and the bundle patch was rejected as an overlay parse with no stdlib
  reader. An unparsable declaration fails the gate loudly; nothing is dropped.
- **One normalisation, then a reviewed declared-only allowlist.** Comparison
  trims whitespace and stays case- and separator-significant, so variant
  folding cannot pass. The names the client declares that 0.1.5 does not
  register (`session/history`, `subagent/history`) live in
  [gates_manifest.json](../../../../scripts/gates_manifest.json)
  (`wire_pin.declared_only_allowlist`) with one reason each. The list excuses
  a *declaration* only: an entry must have no call site under
  `flutter/packages/harness_adapter/lib/src`, and one that is invoked fails
  the gate naming the call site. It is closed three ways: an unlisted client
  endpoint fails, an allowlisted name the pin later registers fails until the
  entry is deleted, and an allowlisted name the wire layer calls fails
  ([decision](../bug-fix/2026-09-11-drops-routes-the-pinned-host-does-not-register.md)).
- **Pin identity is two facts.** The gate parses the pinned commit and a new
  registration-source digest from `reference/README.md`, compares the commit
  with the submodule's checked-out HEAD, and recomputes the digest over the
  contributing files. `--print-digest` regenerates the record, so the re-pin
  procedure names the exact commands.
- **Privileged methods are asserted, not skipped.** 0.1.5 removed
  `PRIVILEGED_METHODS`; the browser-trust fence and signed cookie now apply to
  every `/api` method, and `connection.isLoopback` is the surviving concept.
  The gate asserts that shape and fails loudly if a privileged set reappears
  without the gate being extended, while validating the client's own
  out-of-scope list from the machine-readable coverage block in
  [docs/spec.md §4.6](../../../../docs/spec.md#46-wire-coverage).
- **Counts are derived, recorded twice, and compared.** The block records
  declared 54 / upstream 84 / identical 52 / missing 32 / client-only 2; the
  [README](../../../../README.md) coverage sentence and the block must agree
  with the registries on every run.
- **The fake host stays honest.** The gate fails on a reintroduced
  name-folding map, map literal, or switch case that mixes `DshRpcEndpoints`
  constants with wire-name string literals.

## Alternatives considered

- **A generated `rpc-map.ts`-style registry.** Rejected: upstream owns that
  file's absence; regenerating a shadow registry adds a second source of
  truth that can rot exactly as this one did.
- **Read the surface from `fixture.ts`.** Rejected: it omits host endpoints
  and would fail the client on drift that does not exist.
- **Derive the loaded set from `packages/bundle/*/cordis.patch.yml`.**
  Rejected: correct for one deployment, but a patch-overlay parse that would
  need its own tests; the tree-wide scan is a documented superset.
- **Hard-code the expected commit in the script.** Rejected: a second copy
  that can disagree with the record; the gate parses `reference/README.md`.
- **Put the allowlist in the script.** Rejected: the manifest already owns
  every exception, so reviewers see it beside the other ceilings.

## Consequences

- A re-pin, a `rpc_map.dart` rename, or an upstream method rename fails one
  gate with `file:line`; the counts in `README.md`, `README.zh.md`, and
  `docs/spec.md` can no longer rot silently.
- Documented limits: the scan is a superset of any one deployment's mounted
  plugins, so a method served only by an unmounted package could pass; a
  runtime-built binding is invisible; the parent's recorded gitlink is not
  checked, only the checked-out HEAD.
- The first run corrected three stale surfaces: the README coverage count, the
  §5 claim that 0.1.5 registers only `session`, `settings`, and `workspace`,
  and §15's `agentPreset.*` names. Sections outside this gate's scope (for
  example §11's `subagent.list`) still carry pre-0.1.5 dot names.
