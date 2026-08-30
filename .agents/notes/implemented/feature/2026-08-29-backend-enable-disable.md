# Agent Note: Backend enable/disable — switch any configured host off

Status: implemented

## Problem

The registry connects every configured backend for the app's lifetime
([the multi-backend note](2026-08-20-multi-backend-registry.md)); the
only way to stop talking to a host was to remove it and re-add it (with
a fresh id, losing per-backend local keys). The requirement: enable or
disable any configured host in place — a disabled host keeps its config
and id, but the client holds no connection, controllers, sidebar slice,
or switcher entry for it.

## Decision

### Model and format

`BackendConfig` carries `final bool enabled` (default true; part of
`copyWith`/`==`/`hashCode`), and `BackendRegistryState` (plus
`BackendStoreData`) expose `enabledBackends`. This is an on-disk format
change to `backends.json`: `save` always writes `"enabled"` per entry;
`load` treats an absent key as enabled (pre-feature documents), and a
non-bool value fails loud as a malformed entry.

### Registry

`SetBackendEnabled(id, enabled)` joins the guarded mutations. Disabling
is always allowed (unlike removal: the list may hold disabled entries);
disabling the active backend moves `activeId` to the first enabled
backend in list order, and disabling the last enabled one leaves
`activeId` null — every route's empty-backend state catches it (the
loading-spinner placeholders for chat/models/goal/subagents; Settings
renders its host card without a scope). Enabling while no backend is
active activates the enabled one (a disabled list has no chat surface to
preserve); selecting a disabled backend is refused on
`errorMessage` ("Enable the backend before activating it"). Load
reconciles a persisted active id that points at a disabled backend onto
the first enabled entry, or null when none remains.

### Release and rebind

Disabling reuses the existing family + keep-alive machinery:
`allBackendConnectionsProvider`, `backendSessionSlicesProvider`, and
`foregroundNotificationEventsProvider` watch the `enabledBackends` set,
so a disabled backend simply leaves the watch sets. Riverpod 3's
default auto-disposal then tears the chain down — chat UI state → chat
controller → repository → `(id, uri)` connection member →
`DshConnectionManager.stop` (event-socket subscriptions cancelled).
Re-enabling rebuilds the chain lazily through the same families; the
rebuild carries fresh state (sessions reload), the accepted cost of
"off means off". Nothing calls `invalidate`. Two guards keep released
backends released: the Settings scope resets to follow-active when the
pinned backend is disabled (the host pages keep whatever they describe
connected), and the app root drops notification taps targeting a
disabled or removed backend (the controller read would reconnect).

### Surfaces

- **Settings host sheet**: every backend row gains a stock M3 `Switch`
  (tooltip `backendEnableTooltip`/`backendDisableTooltip`); edit/remove
  verbs keep their seats. A disabled row rides `StateDotState.disabled`
  — the `onSurfaceVariant` grey added to the StateDot vocabulary — plus
  a `backendStatusDisabled` badge, never the offline error red (the host
  is off by choice, not unreachable); its version tail drops. Row taps
  (scope pin) are inert while disabled, and the edit sheet hides "Set as
  chat host" for a disabled backend. All backends, enabled or not, stay
  listed — this sheet is the way back from an all-disabled state.
- **Sidebar and Workspaces**: slices and aggregate sections are built
  from `enabledBackends`, so a disabled host's session tree, group
  headers, and start-a-session/switch entries vanish; the active
  backend is always enabled, so the grouped sidebar never renders a
  disabled slice.

## Alternatives considered

- **Grey out the row but keep the connection**: rejected — a
  "disabled" host still holding a WebSocket, live session rosters, and
  background notifications contradicts the verb; the resource and
  battery cost the switch exists to stop would continue.
- **Hide disabled backends from all UI**: rejected — the enable switch
  lives on the host sheet row; hiding the row would make a disabled
  backend (or an all-disabled registry) unreachable, with no way back
  short of reinstall.
- **Refuse disabling the last enabled backend (mirror the removal
  floor)**: rejected by the requirement — the user must be able to
  switch everything off; the null-active surfaces already exist and the
  host sheet stays reachable.

## Consequences

`backends.json` entries gained `enabled`; old documents decode as
all-enabled and any save rewrites them with the key present. The
active-backend invariant is now "active exists iff at least one backend
is enabled, and the active backend is enabled"; removal guards and
`backendStatusStandby` pill semantics are unchanged. Disabling a backend
discards its in-memory browsing state (controller disposed); re-enable
refetches. The Workspaces tab, sidebar, and switchers enumerate enabled
backends only; Settings' host sheet enumerates all. Tests: controller
(relocate, all-disabled null, re-enable-activates, select refusal, load
reconcile, round-trip persisting the flag), store (enabled round-trip,
legacy missing-key decode, non-bool refusal), slices provider (disabled
slice drops and returns), Settings widget through the real registry
chain (switch flip relocates Active, disabled badge and grey dot, inert
scope tap, hidden chat-host verb, all-disabled fallback keeps the
manage sheet reachable), scope notifier (disabled-pin reset), and
providers through the real store/controller with per-URL transport
fakes (disable stops the manager's socket subscriptions and leaves the
other backend untouched; re-enable reconnects a fresh member).
