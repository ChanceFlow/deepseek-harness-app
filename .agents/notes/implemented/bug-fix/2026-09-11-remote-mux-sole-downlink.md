# Agent Note: Remote mux is the sole downlink

Status: implemented

## Problem

`DshConnectionManager` dialed two downlink WebSockets per generation and
treated both `onOpen` events as readiness facts
([dsh_connection_manager.dart](../../../../flutter/packages/harness_adapter/lib/src/dsh_connection_manager.dart)).
Probing the live stack — `dsh web` on `127.0.0.1:3080` behind a
`dsh-go-gateway` on `127.0.0.1:8102` — showed that contract was wrong in
three ways:

- `/api/remote.mux` is the only downlink the host serves. It answers the
  upgrade immediately (`101 Switching Protocols` through the gateway; a
  direct, cookie-less `401 Unauthorized`), while `/api/events.mux` and
  `/api/events.host` never return an HTTP status line at all: a raw upgrade
  direct to `3080` hangs until the probe's own timeout, across three Host
  header variants. Through the gateway the relay's upstream dial times out
  and it answers `502 Bad Gateway`.
- The client's fallback from `remote.mux` to `events.mux` fired only when the
  error text contained `404`. The real failure is a hang, so the fallback was
  dead code and `_legacyEventsMuxPath` was never dialed.
- Because readiness awaited the optional host leg with the same 3 s timeout as
  the required mux, every generation stalled the full 3 s before publishing
  CONNECTED.

## Decision

`/api/remote.mux` is the sole mux path and — since
[the route-removal decision](2026-09-11-drops-routes-the-pinned-host-does-not-register.md)
— the only downlink the client dials.

- Removed the 404 fallback and the `_legacyEventsMuxPath` constant; `_pump`
  dials one path and no longer carries a reconnect closure.
- `/api/events.host` is deleted, not bounded: no supported revision serves it,
  so its 500 ms open grace, its `hostFrames` seam, and the repository's
  host-frame folds bought no frames. Generation readiness is the mux `onOpen`
  plus the `$events` ready frame, and any required-stream loss still fails the
  generation into the backoff.
- Diagnostics keep the required mux leg's warning and its real error text; the
  per-leg debug lines for the optional leg are gone with it.

## Alternatives considered

- **Keep the fallback and key it on the hang/timeout** — rejected: no known
  host revision serves `events.mux`, and reactivating a path the host does not
  answer would add another 3 s stall, not remove one.
- **Bound the optional leg instead of deleting it** — adopted first, then
  superseded: a 500 ms grace removed the stall but delivered no frames on any
  supported host, so the leg, its seam, and its folds were deleted.
- **Await the optional leg with no timeout** — rejected: that is the shipped
  stall.
- **Fail the generation when the optional leg does not open** — rejected: it
  never opens on any supported host, so that rule would keep the client off
  every one of them.

## Consequences

- A connect or reconnect reaches CONNECTED after the mux open plus the
  `$events` ready frame; one upgrade attempt and one subscription per
  generation are saved.
- Tests pin the removal: a non-404 mux failure and a 404-shaped mux failure
  each dial only the failed generation's path, never `events.mux` or
  `events.host`, and the ready-frame handshake is asserted in virtual time in
  [dsh_connection_manager_test.dart](../../../../flutter/packages/harness_adapter/test/dsh_connection_manager_test.dart).
- [docs/spec.md](../../../../docs/spec.md) states the revised contract.
