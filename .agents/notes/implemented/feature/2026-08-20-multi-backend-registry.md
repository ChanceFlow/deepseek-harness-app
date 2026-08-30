# Agent Note: Multi-backend registry — configure, aggregate, switch

Status: implemented

## Problem

The client was compiled against exactly one dsh host (`DSH_BASE_URL`
dart-define). The requirement: configure several backends in the app,
keep connections to ALL of them alive, browse every host's workspaces
and sessions, and switch which one the chat surface presents. The
Workspaces tab must aggregate all backends (not switch), Settings owns
backend configuration (device-local — no host can own the list that
decides which host to talk to), and the sidebar groups sessions by
backend.

## Decision

### Registry

`BackendConfig` and `BackendRegistryState` live in
`flutter/packages/domain/lib/model/backend.dart` (neutral vocabulary).
The device-local store (`flutter/app/lib/backends/backend_store.dart`)
owns a JSON document in the documents directory, written atomically
(temp + rename); an absent file yields the seed document (build-time
URL, id `default`) so a fresh install behaves like the single-backend
build. Corrupt documents fail loud as `BackendStoreException`; the
controller falls back to `seedDocument()` with the corruption on the
state (re-reading the same file would throw again — the fallback's
fixed dead loop).

`BackendRegistryController` is the UDF stream over the store:
Add/Rename/UpdateUrl/Remove/Select/SetBackendEnabled, all guarded — the
active backend cannot be removed, the list never drops below one,
labels non-empty, URLs http(s) with a host, disabled backends
unselectable. Refusals ride
`BackendRegistryState.errorMessage`; the next successful mutation
clears them. Details: [enable/disable](2026-08-29-backend-enable-disable.md).

### DI: everything backend-dependent is a family

`flutter/app/lib/di/providers.dart` keys the connection manager by
`(id, url)` (a URL edit reconnects; reads create running connections),
the repository, and the six UI controllers by backend id.
`allBackendConnectionsProvider` is the keep-alive watching every
enabled backend's connection — all stay connected; disable/removal
stops it. The chat sidebar additionally watches each backend's
`chatUiStateProvider`, keeping every connected backend's chat
controller alive: live session lists everywhere, browsing state
surviving switch-back.

### Surfaces

- **Workspaces — aggregate.** One section per enabled backend: live
  connection dot + label + host + Active marker over that backend's
  embedded browsing region. Tapping a header or starting a session in a
  non-active backend selects it.
- **Settings — the Backends page.** A mobile-only section ahead of the
  web nav order: one row per backend (live dot, label, `host:port`,
  Active/Standby pill, enable switch), an add/edit bottom sheet (label +
  base URL with the registry validation mirrored inline; the controller
  re-checks), and removal guards stated as visible copy instead of dead
  controls.
  The section stays reachable when the active host is not — host pages
  gate behind a snapshot placeholder that routes to Backends (repointing
  the unreachable host must not dead-end).
- **Chat sidebar — grouped by backend.** With >1 backend the browsing
  region renders per-enabled-backend sections (the Workspaces header
  vocabulary) over each backend's own workspace-grouped tree. The
  active slice keeps raw group keys
  (single-backend-era persisted overrides stay valid);
  others namespace keys under their backend id and default collapsed.
  Tapping another backend's header or session dispatches `SelectBackend`
  on the registry AND `SelectSession` on the target backend's own
  controller — the surface rebinds with the session chosen, no
  active-closure race.
- **App-bar subtitle.** >1 backend prefixes the active label
  (`Laptop · connected 1.2.3`); single-backend keeps the bare line.

The live dot is shared vocabulary
(`flutter/app/lib/ui/shared/backend_connection_dot.dart`): connection
phases mapped onto the StateDot vocabulary.

### Tests

Store round-trips and malformed-document failures; controller guards,
persistence, replay stream, corrupt fallback; the Settings Backends page
and unreachable-host gate; sidebar grouping, callbacks, subtitle, and a
registry-level switch through the real provider chain (ChatRoute). Real entry paths throughout: real store, real registry,
per-URL transport fakes (an unfaked URL attempts a real connection).
Fake-async harnesses advance real dart:io chains one IO turn per
`runAsync` round + pump; controller round-trips poll the document until
the atomic write lands.

## Alternatives considered

- **Registry in the shared LocalStateStore**: rejected — the backend
  list should not ride the chat cache's whole-document flushes; a
  dedicated document with its own atomic-write contract is separable.
- **Switch-only Workspaces tab**: rejected by the requirement — the tab
  aggregates; switching is a side-effect of tapping a header or starting
  a session there.
- **Disposing non-active chat controllers on switch**: rejected once the
  sidebar watched every backend's chat state — live rosters and
  switch-back state are worth one bounded state per backend.
- **Multi-host sidebar search**: deferred — search dispatches to the
  active backend's controller; a host fan-out wants a wire contract the
  protocol does not offer.

## Consequences

A build targets any number of hosts; `DSH_BASE_URL` becomes the seed
backend's URL only. All enabled backends stay connected for the
app's lifetime. Backend ids are device-local; non-active backends'
sidebar toggles key on them, so a reinstall resets those (the active
backend's raw keys survive). Settings' host pages render inside a
snapshot gate — an unreachable host no longer blanks the tab. Every
multi-backend surface activates only with >1 backend configured; a
single-backend install renders exactly the pre-multi-backend layouts,
which is also why legacy widget tests pass unchanged.
