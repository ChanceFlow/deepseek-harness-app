# Agent Note: A subagent prompt refusal is not retried on a legacy route

Status: implemented

## Problem

`HarnessRepositoryImpl.sendSubagentPrompt` wrapped its `subagents/prompt` call
in an unbounded `catch (_)` and retried the payload on the raw literal
`subagent.prompt`. Two defects:

- The catch swallowed every failure. A legitimate business refusal — the host
  answers `subagent/unauthorized` when the address does not own the live target
  (`packages/subagent/subagent/src/index.ts`, `rejectPrompt` in
  `packages/subagent/subagent/src/control.ts`) — was retried, so the caller saw
  the fallback's failure code instead of the host's.
- `subagent.prompt` is not declared by `DshRpcEndpoints` and is not a route on
  the pinned contract. `packages/subagent/subagent/src/index.ts` registers
  `@Remote('prompt')` under the `subagents` namespace, so the wire name is
  `subagents/prompt`; the dotted string survives only as a control-schema key
  (`packages/subagent/subagent/src/control.ts:20`). The 0.1.5 fixture
  dispatches `subagents/prompt`
  (`packages/client/connection/src/client/fixture.ts`).

Reproduced against an honest fake host: the call journal was
`[subagents/prompt, subagent.prompt]` and the caller received `not-found`
instead of `subagent/unauthorized`.

## Decision

Delete the fallback. `sendSubagentPrompt` issues exactly one
`DshRpcEndpoints.subagentsPrompt` call and lets its `DshBusinessException`
propagate.

The legacy-name tolerance helper this file used to carry,
`DshRemoteInvoker.invokeOrNullOnNotFound`, is deleted: its two callers
(`host/describe`, `workspace/list`) were routes the pinned host does not
register
([decision](2026-09-11-drops-routes-the-pinned-host-does-not-register.md)),
and it never retried under a second name anyway. No call site retries an
endpoint under a legacy name, and `kDshEndpointFallbacks` has been empty since
the 0.1.2 lock.

## Alternatives considered

- **Wrap the canonical call in the 404-tolerant helper** (since deleted) —
  rejected: the method returns a message id, so null is not a tolerable
  absence, and a 404 is a real host mismatch the caller must see.
- **Keep the fallback but catch only 404** — rejected: `subagent.prompt` is
  undeclared on every pinned revision, so a 404 on `subagents/prompt` makes the
  fallback certain to fail too; that only changes which error is reported.
- **Declare `subagent.prompt` in `DshRpcEndpoints`** — rejected: the registry
  states the pinned contract, and the pinned tree registers no such route.

## Consequences

- A host refusal reaches the caller with its own code; the subagent composer
  surfaces the real reason instead of `not-found`.
- `test/subagent_prompt_refusal_test.dart` drives the real repository with a
  recording fake that answers `subagents/prompt` with `subagent/unauthorized`:
  exactly one canonical call, zero legacy calls, and the original code thrown.
