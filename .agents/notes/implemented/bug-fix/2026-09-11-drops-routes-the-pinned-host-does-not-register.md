# Agent Note: The client stops calling three routes the pinned host does not register

Status: implemented

## Problem

The owner reported three wire names the client called that exist on neither
the pinned `dsh-v0.1.5-rc.2` tree nor the running `0.1.5-rc.1-chance.0` fork
(live probes against the gateway on `127.0.0.1:8102`):

- `host/describe`. 0.1.5 registers no `host` Remote namespace;
  `POST /api/host/describe` answers `404 not found`. `DshConnectionManager`
  called it on every connect through `invokeOrNullOnNotFound` and fell back to
  a hard-coded `HostDescription` (`version: '0.1.2'`, empty `cwd`, zero
  `attachedSessions`), so the handshake 404'd every generation and the
  fallback silently replaced real facts with fabricated ones.
- `workspace/list`. The workspace controller registers create, rename, delete,
  insertBefore, insertSessionBefore, archiveSession, and one stream
  (`packages/api/workspace-controller/src/index.ts`) — no unary list; the
  route answers `404`. The roster already arrives on the `workspace/follow`
  stream the client folds, so the call was dead.
- `/api/events.host`. No downlink route: the upgrade hangs and the gateway
  answers `502`. The optional leg spent one upgrade and one subscription per
  generation and decoded no frames.

The `verify_wire_pin` allowlist framed all three as acceptable "client-only"
names, the same as two genuinely unused declarations, so the gate blessed a
live call to a non-existent route.

## Decision

**Readiness is the `$events` ready frame.** The gateway answers the `$events`
open with `{type: 'item', streamId: 'remote-events', value: {type: 'ready',
clientId, host: {home}}}` (`packages/api/gateway/src/stream-protocol.ts`
`RemoteEventReadyFrame`) — the reference client's own generation handshake
(`packages/api/gateway/src/client/remote-events.ts` `ready(opening.host)`,
published as `ConnectionHostInfo`).
[DshConnectionManager](../../../../flutter/packages/harness_adapter/lib/src/dsh_connection_manager.dart)
publishes CONNECTED once the mux `onOpen` and that frame hold, and fails the
generation on a frame missing `host.home`, a stream that closes first, or a
30 s miss. `settings/describe` was rejected as the probe: it couples readiness
to the settings plane and still carries no host facts. `session/list` was
rejected: it needs session context and duplicates the resync pull.

**`HostDescription` keeps only real facts.** It carries the ready frame's
`home`, plus a `version` that stays null — no pinned route publishes a host
version, and a fabricated default is the defect this change removes. The other
0.1.1 probe fields are deleted: `cwd`, `provider`, and `model` are per-session
facts (`session/list` rows, `session/modelCatalog`), and `attachedSessions`
and `canOpenPath` are published nowhere.

**`workspace/list` is deleted with `_loadWorkspaceListing`.** Create, rename,
and delete keep their locally applied response rows; the `workspace/follow`
stream's baseline and `upsert`/`remove`/`order` frames stay authoritative.
`refreshWorkspaces` settles without a pull because the pinned namespace has
none.

**The `/api/events.host` leg, its `hostFrames` seam, and the repository's
host-frame folds are deleted.** `host/session-removed` re-pulled the roster;
its live successor `api-session/removed` is forwarded with no fold, so a
peer removal lands on the next `session/list` pull.

**The gate separates a declaration from a call.**
[verify_wire_pin.py](../../../../scripts/verify_wire_pin.py) excuses a
`wire_pin.declared_only_allowlist` name only while it is declared and not
invoked under `flutter/packages/harness_adapter/lib/src`; an allowlisted name
with a call site fails as a defect to remove.

## Alternatives considered

- **Keep `host/describe` behind a version check** — rejected: no supported
  revision registers it, so the branch would be dead on every host the client
  claims to support.
- **Keep `workspace/list` for a named pre-0.1.5 revision** — rejected: the
  client pins one contract and carries no other revision's surface.
- **Read host facts from a `session/list` row** — rejected: cwd, provider, and
  model are per-session facts; promoting one row's values to host facts
  invents a fact the host never published.
- **Keep the bounded `/api/events.host` leg** — rejected: nothing serves it,
  so the 500 ms grace and its subscription bought no frames.
- **Source `version` from the running dsh build** — rejected: no client route
  exposes it; the field stays null rather than being guessed.

## Consequences

- A generation is ready when the `$events` stream is actually delivering, not
  when a socket merely opened, and the fabricated host facts are gone.
- `/api/events.host` is never dialed; one upgrade per generation is saved.
- `HostDescription.version` is null on every generation, so the settings
  surface's versioned backend subtitle has no source and stays unrendered
  until its owner removes the read.
- [docs/spec.md](../../../../docs/spec.md) §4.2, §4.5, §4.6, and §5 state the
  revised contract and the new coverage counts (declared 54, client-only 2).
- Adapter fakes answer the ready frame; the fake host's undeclared-name guard
  now covers the connection path.
