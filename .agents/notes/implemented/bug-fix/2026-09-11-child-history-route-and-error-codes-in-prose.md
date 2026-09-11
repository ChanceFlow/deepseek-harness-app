# Agent Note: Child history is `session/page`, and its guards are slash-coded

Status: implemented

## Problem

Two names the client's prose still used describe nothing on the pinned host
(`dsh-v0.1.5-rc.2`, `fb2c4b9e698e30edb738bca4cf0618587db7d203`):

- **`subagent.history`** is not the route a child transcript comes from. 0.1.5
  reads it through `session/page` with a `subagent` address
  (`{kind: 'subagent', parentSessionId, childSessionId, mode}`;
  `packages/api/session-controller/src/history.ts`), which is what
  `HarnessRepositoryImpl.loadSubagentHistory` already sends. The endpoint
  registry keeps `subagent/history` as a declared-only constant with no call
  site, and the `wire-pin` gate's allowlist
  ([note](../process/2026-09-11-wire-pin-gate.md)) names it as such — but four `app`
  files, three `domain` members, the adapter's own comment, two
  `docs/spec*.md` bullets and five test names still pointed a reader at it.
- **`subagent-not-found`** is not a code the host ever answers. The address
  guards throw `subagent/unauthorized` for a mode or ownership mismatch
  (`history.ts` `validateAddress`), `subagent/not-found` for a child the
  catalog no longer lists (`rejectNotFound`), `subagent/catalog-diagnostic`
  for a corrupt descriptor, and `session/agent-busy` for a bare session
  address naming a subagent. A mode-mismatch prose that named
  `subagent-not-found` sent a reader looking for a code the server has no
  branch for.

The adapter's fold already reported the right codes
([note](2026-09-11-forwarded-session-lifecycle-events.md) corrected the
adapter comment); the `app` tree and the route name were recorded there as out
of scope, so this is that follow-up.

## Decision

Every one of those sites now names the route the client actually calls and the
codes the host actually throws:

- the child-history read is written as `session/page` with a `subagent`
  address, and `subagent/history` is named only where it is being retired (the
  registry constant and `docs/spec*.md`);
- a mode or ownership mismatch is `subagent/unauthorized`; an unavailable
  child is `subagent/not-found`; `subagent/prompt` and `subagent/interrupt`
  reject a misaddressed row with `subagent/unauthorized`, not with a
  history code.

No behavior changed: the prose was wrong, the traffic was not. The affected
test names and the controller test's injected host error were moved to the
real code so the fiction matches the wire.

## Alternatives considered

- **Rename the domain verb `loadSubagentHistory`** to match the route:
  rejected — the member names the capability the UI asks for, and the route is
  the adapter's business; a route-named domain API would drag wire vocabulary
  across the boundary the import gate and the package contract protect.
- **Delete the declared-only `subagentsHistory` constant**: rejected — the
  wire-pin allowlist documents why it stays
  ([note](../process/2026-09-11-wire-pin-gate.md)); removing it is a separate call.
- **Leave the historical notes alone**: rejected for the four sentences that
  state a live contract (a reader greps a code name and acts on it); the
  narrative elsewhere in those notes is untouched.

## Consequences

- One route name and one error-code family across `app`, `domain`, the
  adapter's comments and `docs/spec*.md`.
- `subagent/not-found` and `subagent/unauthorized` are now distinguishable in
  prose, which is what the roster's error banner shows a user.
