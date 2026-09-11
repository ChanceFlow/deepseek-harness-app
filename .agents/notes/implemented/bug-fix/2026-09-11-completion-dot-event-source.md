# Agent Note: Completion dot rides api-session/status, not the dead host frame

Status: implemented

## Problem

The sidebar's finished-but-unviewed dot (a session finished while the reader
was looking elsewhere) folds a per-session `running` edge
(`harness_repository_impl.dart` `_prevRunningBySession`); the fold's own
semantics stay owned by
[sidebar activity, pending dot and completion dot](../feature/2026-08-20-sidebar-archive-priority-pending.md).
Its only live frame source was the `host/session-status` host frame on the
optional `/api/events.host` downlink.

On the pinned backend (`dsh-v0.1.5-rc.2`,
`fb2c4b9e698e30edb738bca4cf0618587db7d203`) that source cannot fire:

- `git grep "host/session-status" dsh-v0.1.5-rc.2 -- packages` is empty; the
  frame disappears at `dsh-v0.1.2-alpha.1`, and the client targets 0.1.2+ only.
- `/api/events.host` is registered nowhere in the pinned sources and is no
  longer dialed, so the host-frame vocabulary has no delivery path at all
  ([remote mux is the sole downlink](2026-09-11-remote-mux-sole-downlink.md),
  [the route-removal decision](2026-09-11-drops-routes-the-pinned-host-does-not-register.md)).

The dot therefore armed only through the `session/list` pull fold: a session
finishing while the stream was up and the reader was elsewhere lit nothing
until an unrelated refresh pulled the list.

## Decision

The forwarded Remote Event `api-session/status` is the live frame source.

- The host event `'api-session/status'(sessionId: SessionId, running: boolean)`
  (`packages/api/session-controller/src/types.ts:592`) is allowlisted for
  forwarding as `{event: 'api-session/status', mode: 'emit'}`
  (`packages/api/remotes/src/remote-events.ts:23`). The client receives it as a
  `$events` `emit` item `{type: 'emit', event, args: [sessionId, running]}` on
  `/api/remote.mux` — the stream it already opens for interactive waterfalls
  (fixture shape: `packages/client/connection/tests/fixture.client.spec.ts:1027`).
- `_applyForwardedEvent` dispatches it to a private `_applySessionStatusEvent`,
  which decodes the positional args and calls `_foldSessionRunning`. That
  helper is the one home of the web `syncCompletedNotifications` edge fold
  (seed, arm on true→false while unviewed, clear on running); the
  `session/list` pull fold feeds the same helper, so no edge logic is
  duplicated.
- The dead `host/session-status` arm is deleted. It never fired on the pinned
  contract and its decode duplicated no logic: `_foldSessionRunning` is the one
  home of the edge, fed by the live `api-session/status` item and the
  `session/list` pull fold. The integration tests that pinned the frame now
  drive the live item, so no behavior lost coverage.

## Alternatives considered

- **Keep the `host/session-status` arm as a tolerant decode** — rejected: it is
  dead on every supported host (`/api/events.host` never answers the upgrade),
  and once the integration tests drive the live item the arm has no reason to
  exist; dead code carrying a reason is worse than no code.
- **Add `api-session/status` to the host-frame vocabulary too** — rejected:
  those arms rode the retired `/api/events.host` leg, so it would have been a
  second dead path.
- **Keep the pull-only fold** — rejected: the edge is event-shaped, and a pull
  fires only for the open session's own turn end (plus reconnect), so a
  background finish stays invisible until an unrelated refresh.

## Consequences

- The completion dot arms live for a finished background session; running
  again or opening the session clears it (unchanged semantics).
- The `$events` stream is load-bearing for both interactive decisions and
  session status; a `$events` outage degrades to the pull fold, which still
  arms on the next list refresh.
- `session_status_event_test.dart` drives the real repository entry path (real
  `DshConnectionManager`, an `api-session/status` `emit` item) and pins the
  true→false arming, running-again clearing, and first-observation seeding; the
  three integration tests that used the deleted frame drive the same live item.
