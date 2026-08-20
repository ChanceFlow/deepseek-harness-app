# Agent Note: Connection status lives in Settings, not the chat surface

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
rows; the chat surface no longer renders any persistent connection
line.

- The `ConnectionBanner` widget is deleted and the compact-layout body
  drops it.
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

## Consequences

The Settings Backends rows are the only surface naming the host version;
the chat screen keeps its title and the sidebar's per-backend headers.
`backendConnectionStateProvider` is `autoDispose` per backend, so a row
watches only while its backend page is visible, and it keeps that
backend's connection alive only during that window (the Settings page's
existing keep-alive watch covers the whole page). The chat controller no
longer observes connection state, so connection phase changes never
trigger a chat UI rebuild. Tests updated accordingly: the chat tests
assert the absence of any connection/version text, and the Settings
tests assert the version rides the backend rows' endpoint lines.
