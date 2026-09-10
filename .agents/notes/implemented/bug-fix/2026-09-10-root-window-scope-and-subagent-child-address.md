# Agent Note: Reconnect resync rebuilds only opened root-session windows

Status: implemented

## Problem

One reconnect generation reported by a phone build (host
`dsh.qs.geekcat.site:3083`) split its `resync.session` warnings into two
classes:

1. `DshBusinessException: session/agent-busy: subagent Sessions require their
   durable parent address` for six sessions whose ids are bare UUIDs — the
   shape [continuation.ts](../../../../reference/deepseek-harness/packages/subagent/subagent/src/continuation.ts)
   mints for an in-process continuable child
   (`SessionId(randomUUID())`), never the `session-<n>` a root gets.
   `_resync` fired `ensureLoaded` for every instantiated `_SessionState`, not
   only the opened ones, and
   [harness_repository_impl.dart](../../../../flutter/packages/harness_adapter/lib/src/harness_repository_impl.dart)
   `_loadHistory` addressed each one as `{kind: 'session', sessionId}`. A child
   transcript is addressable only as `{kind: 'subagent', parentSessionId,
   childSessionId, mode}`, so the host rejects the ordinary address.
2. `HTTP 504 for api/session/page` on eighteen root sessions, with
   `HTTP 502 for api/session/list` and a refused `/api/events.host` upgrade in
   the same window — an upstream outage. The adapter multiplied it: one tail
   page per remembered session, all in flight together, so every remembered
   session logged its own failure.

The reference web client gates that rebuild twice, and the adapter matched
neither: `Session.resync()` returns early on `openState === 'cold'` ("never
opened: no window to rebuild"), and a child window carries its catalog
address, so its history reads route through `subagents.history({...address})`
(see
[session.ts](../../../../reference/deepseek-harness/packages/client/runtime/src/client/sessions/session.ts)).

## Decision

Three gates, mirroring the web:

1. `_resync` rebuilds only states that are opened (`_SessionState.isOpened`,
   set by `openSession` before its first load) **and** whose `session/list`
   row is a root — no `parentSessionId` and `origin != 'subagent'`
   ([sessions.ts](../../../../reference/deepseek-harness/packages/host/apiproxy/src/api/sessions.ts)
   row fields).
2. `_loadHistory` throws instead of paging a subagent id with the ordinary
   address, so no future caller can reintroduce the rejection.
3. `openSession` refuses a subagent id with a `session.open` warning naming
   `loadSubagentHistory`, because a child transcript rides the subagent view's
   addressed route.

Context pressure and breakdown left `_SessionState` for per-session fact
streams keyed by session id (`_contextPressureProjections`,
`_contextBreakdownProjections`, each with its own seq guard reset per
generation), so a child's projection frames land — and stay observable —
without allocating a history window.

## Alternatives considered

- **Cap the resync fan-out concurrency**: rejected — the parallelism is
  deliberate web `handleConnected` parity
  ([resync-concurrent-publish-coalesced](2026-08-29-resync-concurrent-publish-coalesced.md)),
  and the 502/504s are upstream availability. The wasted requests to remove
  are the ones for windows nobody opened, not the ones that are needed.
- **Rebuild children through `session/page` with a subagent address**:
  rejected — a root window's reducer, queue mirror and pending-interaction
  replay are root-session contracts; the addressed route already exists as
  `loadSubagentHistory`
  ([nested-subagent-direct-parent-addressing](2026-08-30-nested-subagent-direct-parent-addressing.md)).
- **Redirect `openSession(childId)` to the child's durable parent**: rejected
  — it renders one session's transcript under another's id and hides which
  row was tapped.
- **Leave projections on `_SessionState`**: rejected — a consumer that reads
  one fold (`observeContextPressure(childId)`) would instantiate a window and
  with it a history load.

## Consequences

- A reconnect generation issues `session/page` only for opened root sessions;
  children and never-opened states are skipped, so the durable-parent
  rejection leaves the warning stream.
- Subagent children still publish context pressure and breakdown to observers
  without a window, which the subagent view reads on demand.
- `openSession` on a child is a warning-level no-op instead of a host error:
  no shipped path selects a child as the root chat session, because the shared
  session tree filters `origin == 'subagent'`.
- Upstream 502/504s still log one `resync.session` warning per affected opened
  root session, and the next generation retries those windows.
- Adapter tests pin a generation holding a child, a never-opened root and an
  opened root: only the opened root is paged, and `openSession(childId)` warns
  without issuing `session/page`.
