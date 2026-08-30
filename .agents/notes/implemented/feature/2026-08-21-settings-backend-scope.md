# Agent Note: Settings backend scope — which host the settings pages describe

Status: implemented

## Problem

With more than one configured backend, the Settings tab's host pages
(General, Models, Plugins, Agent presets) silently described whatever
backend was chat-active at the moment. Reading or editing a setting
gave no indication which host it touched, and switching the chat-active
backend on the Backends page rebinding all host pages underneath a user
mid-edit — the operation implied one thing (which host chat uses) and
did another (which host the settings pages describe).

## Decision

### The scope

`SettingsBackendScope` (`flutter/app/lib/ui/settings/settings_backend_scope.dart`)
is a Riverpod `Notifier<String>` holding the backend id the Settings
host pages describe — session-scoped, device-local, independent of the
chat-active backend:

- **Follow-active default.** Until the user pins a backend, the scope
  tracks the chat-active backend id (the single-backend-era behavior:
  settings describe what chat uses).
- **Pin.** Selecting a backend in the scope picker pins the scope to it;
  chat-active switches no longer move it.
- **Follow-active entry.** While pinned, the picker offers "Follow the
  active backend", which clears the pin.
- **Gone pin resets.** A pinned backend that leaves the registry or gets
  disabled (on any surface) resets the scope to follow-active; the
  registry's guards keep the active backend removable-proof and always
  enabled, so the fallback target is a configured backend or empty
  (every backend disabled — see
  [enable/disable](2026-08-29-backend-enable-disable.md)).
- **Session-scoped.** The pin lives in memory only; the app restarts to
  follow-active. Persisting it would imply the settings scope is a
  durable preference when it is a navigation aid.

The scope rides the real registry chain: its build watches
`activeBackendIdProvider` and `backendRegistryStateProvider` (both
stream providers over the registry controller's UDF stream), so it
tracks every registry mutation through the same path the UI uses.

### The surface

`settings_screen.dart` gains a `_ScopeBar` above the section nav,
rendered only when more than one backend is configured (a single backend
is unambiguous; single-backend installs render the pre-refactor layout).
The bar shows the live connection dot, "Configuring: {label}" over
`host:port`, and the chat-active mark when the scoped backend is also
chat-active; tapping it opens the scope picker — a menu-surface sheet
listing every configured backend (the current scope checked, the
chat-active one badged) plus the follow-active entry while pinned.
`SettingsRoute` resolves its controller family parameter from the scope
instead of the active backend, so the host pages rebind as a unit when
the scope changes.

## Alternatives considered

- **Keep following the chat-active backend, show its identity**: rejected
  — it improves visibility without fixing the rebinding problem; the
  user asked specifically that editing target be explicit and stable.
- **Chat-active switches rebind with a confirmation**: rejected — the
  confirmation is noise on every switch, and the underlying coupling
  stays; the user's requirement is an explicit, stable editing target.
- **Per-page backend selectors**: rejected — the scope is a surface-level
  fact (which host this tab describes), not per-page state; one bar
  above the sections states it once.
- **Persist the pin (shared store)**: rejected — the follow-active
  default is the normal state; a pin is a navigation aid that survives
  active switches within a session, and persisting it would surprise
  after reinstall where backend ids are device-local.
- **UDF controller (stream of pins) instead of a Notifier**: rejected —
  the scope has no async work, no I/O, and exactly one consumer (the
  Settings surface); the Notifier's direct state transitions are the
  simplest expression of a session-scoped selection. The registry itself
  stays the UDF controller; the scope only derives from it.

## Consequences

- The Settings tab states which backend it describes, and that choice is
  stable across chat-active switches. Removing a pinned backend snaps
  the scope back to following the active one without exposing a dead
  selection.
- The Backends page keeps describing the chat-active backend with its
  Active/Standby badges; the scope bar's Active mark is the same fact
  mirrored on the currently-scoped backend.
- Single-backend installs render exactly the pre-refactor layout — the
  scope bar does not exist with one backend, so the single-backend
  widget tests pass unchanged. Multi-backend Settings tests scope their
  badge assertions to the backend rows (the scope bar carries its own
  Active mark).
- Tests: notifier behavior through the real store/registry/provider
  chain (`settings_backend_scope_test.dart` — follow, pin, pin-across-
  switches, unpin, removal reset), scope-bar widget tests (pin/unpin/
  follow, single-backend hidden), and a SettingsRoute-level test proving
  the host pages rebind to the pinned backend's data while the
  chat-active backend differs (per-backend repository doubles, real
  registry chain).