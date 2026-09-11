# Agent Note: Connection status lives in Settings; the chat surface shows host loss only

Status: implemented

## Problem

The chat screen persistently showed connection state and the host's dsh
version — a `ConnectionBanner` line in the compact layout and an app-bar
subtitle strip (label + `connected {version}`) in the wide layout. The
version number (`0.0.1` for the pre-release host) read as noise with no
meaning on the main surface, and the banner/strip consumed vertical
space on every screen. Connection state was already published per
backend, but the chat surface kept re-rendering a single global line.

## Decision

Connection status and host version appear only in the Settings Backends
rows; the chat surface renders no persistent connection line.

- The old persistent `ConnectionBanner` widget is deleted and the
  compact-layout body drops it.
- The wide-layout app bar loses its `bottom` strip and the
  `_activeBackendLabel` subtitle logic — the sidebar's per-backend
  headers already name each host and mark the active one, so the strip
  was redundant.
- `ChatUiState.connection` and the `ChatController` subscription to
  `observeConnectionState()` are removed — no surface reads them
  anymore. The adapter and repository still publish connection state
  (the lifecycle contract in `docs/spec.md` §5 is unchanged); Settings
  reads it through the manager directly.
- A new `backendConnectionStateProvider` (StreamProvider.family over the
  connection manager's state stream) feeds the Settings backend rows;
  each row's endpoint line appends the connected host's version
  (`host:port · v{version}`) via the `backendVersion` l10n key, beside
  the existing live connection dot.
- The nine now-dead connection l10n keys (`appBar*`, `connectionBanner*`)
  are removed from both arb files and the generated localizations.
- The one failure-only exception: `HostUnreachableBanner`
  (`flutter/app/lib/ui/chat/host_unreachable_banner.dart`) sits above the
  chat surface while the active backend's phase is `disconnected` or
  `reconnecting`. It names the host (its label, or the base URL authority
  when the label is blank), offers a manual reconnect, and dismisses for the
  current outage; a connected or connecting host renders nothing, so this is
  not the deleted status line returning. `ChatRoute` watches
  `backendConnectionStateProvider` for the phase and hands the widget a host
  label and a callback, so the UI never learns the adapter's
  `DshConnectionManager`; the callback invalidates
  `backendConnectionProvider((id, uri))`, the DI member that owns the
  manager's lifecycle, which rebuilds the member and dials a fresh
  generation immediately instead of waiting out the backoff loop. New keys:
  `connectionHostUnreachable(host)` and `reconnect`.

## Alternatives considered

- Keep a minimal app-bar strip naming only the active backend without
  the version — still duplicates the sidebar headers and reserves space
  for no added orientation; the sidebar already carries the Active
  marker, so the strip was deleted outright.
- Show the version only on the chat empty state or error banners —
  inconsistent with "Settings owns connection facts"; the backend rows
  are the single home.
- Leave `ChatUiState.connection` in place for hypothetical future
  surfaces — dead state against the no-dead-state convention; the
  repository still publishes it, so a future consumer re-adds the field
  trivially.
- **Put the unreachable banner in `AppRoot` so every tab shows it** —
  rejected: `AppRoot` is destination-agnostic and would have to pick one
  backend when several are enabled, while Workspaces and Settings already
  carry per-host dots and the chat tab owns the blocked conversation. The
  banner lives on the chat route, which already knows its backend.
- **Have the banner call `DshConnectionManager.start()`/`stop()`** —
  rejected: `stop()` latches `_stopped` and the manager exposes no retry
  verb, so the DI member's invalidation is the reconnect; it keeps the
  adapter type out of `lib/ui/**`.

## Consequences

The Settings Backends rows are the only surface naming the host version;
the chat screen keeps its title, the sidebar's per-backend headers, and a
failure-only host-unreachable banner. `backendConnectionStateProvider` is
`autoDispose` per backend, so a row watches only while its backend page is
visible, and it keeps that backend's connection alive only during that
window (the Settings page's existing keep-alive watch covers the whole
page). The chat controller no longer observes connection state, so
connection phase changes only rebuild the small banner, never the
transcript. Tests updated accordingly: the chat tests assert the absence of
any connection/version text while connected, and the Settings tests assert
the version rides the backend rows' endpoint lines;
`host_unreachable_banner_test.dart` pins the banner's name/reconnect/dismiss
behaviour and that a reconnect dials a fresh generation through the DI seam.
