# Agent Note: Multi-backend registry — configure, aggregate, switch

Status: implemented

## Problem

The client was compiled against exactly one dsh host (`DSH_BASE_URL`
dart-define): every surface — Chat, Workspaces, Settings, session tools —
bound to one connection at build time. The requirement: configure several
backends in the app, keep connections to ALL of them alive at once, browse
every host's workspaces/sessions, and switch which one the chat surface
presents freely. The Workspaces tab must be an aggregate grouped by
backend (not a switcher), the Settings tab owns backend configuration
(device-local — no host can own the list that decides which host to talk
to), and the chat sidebar groups sessions by backend with taps on another
backend's rows switching there.

## Decision

### Registry (domain + app)

`BackendConfig {id, label, baseUri}` and
`BackendRegistryState {backends, activeId, errorMessage}` live in
`flutter/packages/domain/lib/model/backend.dart` — neutral vocabulary, no
wire knowledge. The device-local store
(`flutter/app/lib/backends/backend_store.dart`) owns a JSON document in
the app documents directory (`{"backends": [...], "activeId": ...}`),
written atomically (temp file + rename); an absent file yields the
seed-only document (build-time base URL, id `default`, label `host:port`)
so a fresh install behaves exactly like the single-backend build. A
corrupt document fails loud as `BackendStoreException` naming the field;
the controller falls back to the store's `seedDocument()` (re-reading the
same corrupt file would throw again) with the corruption reported on the
state.

`BackendRegistryController`
(`flutter/app/lib/backends/backend_registry_controller.dart`) is a UDF
stream controller over the store: Add/Rename/UpdateUrl/Remove/Select, all
guarded — the active backend cannot be removed (switch first), the list
never drops below one entry, labels must be non-empty, base URLs must
parse with an http(s) scheme and a host. Refusals fail loud: the message
rides `BackendRegistryState.errorMessage` (rendered by the Backends page
and cleared by the next successful mutation — a mutation that succeeds
describes the current list, not the refusal before it).

### DI: everything backend-dependent is a family

`flutter/app/lib/di/providers.dart` keys every backend-dependent provider
by backend id: the connection manager (`backendConnectionProvider`,
keyed `(id, url)` — a URL edit reconnects cleanly, the old member stops),
the repository, and the six UI controllers. `allBackendConnectionsProvider`
is the keep-alive: it watches every configured backend's connection, so
all of them stay connected simultaneously; a removed backend drops out of
the watch set and its connection stops. Connections are created running —
every read of a configured backend starts its connection.

Watching each backend's `chatUiStateProvider` from the chat sidebar keeps
every backend's chat controller alive: every host's session list stays
live in the sidebar and its browsing state survives switching back (the
controllers no longer dispose on switch while the chat tab is mounted;
the cost is one ChatUiState per backend, bounded by what was browsed
there).

### Surfaces

- **Workspaces tab — aggregate, not a switcher.** `WorkspaceRoute`
  renders one `_BackendWorkspaceSection` per backend: live connection
  dot + label + host + Active marker over that backend's embedded
  browsing region. Tapping a header selects that backend; starting a
  session in a non-active backend's workspace selects it first so the
  chat surface follows.
- **Settings tab — the Backends page (device-local).** A mobile-only
  section ahead of the web nav order: one row per backend (live dot +
  label + `host:port` + Active/Standby pill), an add/edit bottom sheet
  (label + base URL with the registry's validation mirrored as inline
  feedback; the controller re-checks on dispatch), and removal guards
  stated as visible copy instead of dead controls. The section stays
  reachable when the active host is not: the host-settings pages gate
  behind a snapshot placeholder that routes to Backends (repointing the
  unreachable host is exactly the flow that must not dead-end).
- **Chat sidebar — grouped by backend.** With more than one backend
  configured, the browsing region renders per-backend sections: the same
  header vocabulary as the Workspaces tab over each backend's own
  workspace-grouped tree. The active backend's group keys stay raw
  (persisted expansion overrides from the single-backend era remain
  valid); other backends namespace group keys under their backend id and
  default collapsed. Tapping another backend's header or one of its
  sessions makes it active — ChatRoute dispatches `SelectBackend` on the
  registry AND `SelectSession` on the target backend's own controller
  (family member), so the surface rebinds with the session already
  chosen; no race with the active-controller closure.
- **Chat app-bar subtitle.** With more than one backend the subtitle
  prefixes the active backend's label (`Laptop · connected 1.2.3`);
  single-backend builds keep the bare connection line.

The live connection dot is shared vocabulary
(`flutter/app/lib/ui/shared/backend_connection_dot.dart`): the
connection-state phases map onto the StateDot vocabulary (connected =
done, connecting/reconnecting = ongoing, disconnected = error), used by
the Workspaces headers, the Settings Backends rows, and the sidebar
section headers.

### Tests

Store round-trips and malformed-document failures
(`flutter/app/test/backends/backend_store_test.dart`); controller guards,
persistence round-trips, replay stream, corrupt fallback
(`backend_registry_controller_test.dart`); the Settings Backends page and
the unreachable-host gate (`flutter/app/test/ui/settings/
settings_screen_test.dart`); the sidebar grouping, callbacks, subtitle,
and the registry-level switch through the real provider chain
(`flutter/app/test/ui/chat/session_panel_backend_test.dart`).

The fake-async constraint shapes the harnesses: real dart:io chains
(store load: exists → readAsString → decode) advance one IO turn per
`runAsync` round + pump, so registry-backed pumps loop several rounds; a
seeded two-backend document needs the rounds, a fresh store settles in
the first. Per-backend transport fakes are keyed per URL (second port on
the emulator-loopback host) — an unfaked URL would attempt a real
connection. The connection handshake fake answers a valid `host.describe`
so every generation reaches CONNECTED and the retry loop sits quiescent
(no backoff timers for pumpAndSettle to trip over). Controller
round-trips poll the document until the mutation's bytes are on disk (the
atomic write is several IO turns; `Duration.zero` is not enough), and the
poll string matches `jsonEncode`'s no-space form.

## Alternatives considered

- **Store the registry in the shared LocalStateStore**: rejected — the
  backend list decides which host to talk to, so no host can own it, but
  neither should it ride the chat-surface cache's whole-document flushes;
  a dedicated document with its own atomic-write contract is separable
  and self-describing.
- **Switch-only Workspaces tab**: rejected by the requirement — the tab
  aggregates all connected backends' workspaces; switching is a
  side-effect of tapping a backend header or starting a session there.
- **Dispose non-active chat controllers on switch**: rejected once the
  sidebar began watching every backend's chat state — live rosters on
  every backend and state surviving switch-back are worth one bounded
  ChatUiState per backend; the connections were already keep-alive.
- **A `Notifier` for the registry**: rejected — the registry is a
  controller with a UDF stream like every other app state owner; the
  replay-seeded `AppStateStream` fixes the late-subscriber race the
  async load creates.
- **Backend-scoped search across all hosts in the sidebar**: deferred —
  search dispatches to the active backend's controller (the web sidebar
  searches its one host); multi-host search wants a host-fanout contract
  the wire does not offer.

## Consequences

A build targets any number of hosts; the build-time `DSH_BASE_URL`
becomes the seed backend's URL only. All configured backends stay
connected for the app's lifetime (any surface reading them pins them);
per-backend controllers stay alive while the chat tab is mounted.
Backend ids are device-local and unstable across devices; the sidebar's
per-backend browsing toggles for non-active backends key on those ids, so
a reinstall resets them (the active backend's raw keys survive from the
single-backend era). Settings' host pages now render inside a snapshot
gate: an unreachable host no longer blanks the whole tab. The
multi-backend surface set (aggregate Workspaces, Backends page, grouped
sidebar, labeled subtitle) activates only with >1 backend configured — a
single-backend install renders exactly the pre-multi-backend layouts,
which is also why every legacy widget test passes unchanged.
