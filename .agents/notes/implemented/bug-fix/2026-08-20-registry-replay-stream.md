# Agent Note: Registry replay stream and shell test entry path

Status: implemented

## Problem

The app shell could sit on `ChatRoute`'s loading spinner forever:
`BackendRegistryController` published state on a raw broadcast stream, and
`backendRegistryStateProvider` yielded `controller.state` (read before the
async store load landed) before subscribing — an emission published between
the controller's construction and the provider's subscription was dropped,
so the first-yielded empty state could be the last one anyone saw. On top of
that, `activeBackendIdProvider` was a FutureProvider awaiting the state
stream's future, which latches the first (possibly empty) value and never
recomputes when the stream later emits the loaded registry. Widget tests
additionally pumped `ChatScreen` bare: the sidebar's footer and the composer
persistence resolve providers, so every real-entry pump now requires a
`ProviderScope`.

## Decision

- The registry's `uiState` is now the app's replay-seeded
  [AppStateStream](../../../../flutter/app/lib/ui/state_stream.dart): every
  subscriber first receives the current state, then live updates, so a load
  that completes before or after a consumer attaches is always observed
  exactly once. `_publish` writes through the holder.
- `activeBackendIdProvider` is a `StreamProvider` that maps
  `controller.uiState` emissions (the same shape as the neighboring
  `backendByIdProvider`); consumers keep their `ref.watch(...).value` reads.
- Widget tests that pump the shell follow the real entry path: a
  `ProviderScope`, plus one `tester.runAsync` settle so the backend store's
  real `dart:io` read can complete — fake-async zones never complete real
  file IO, so without that beat the registry stays empty and the shell stays
  on its spinner.

## Alternatives considered

Buffering emissions in each provider with a stream controller duplication of
what AppStateStream already provides; and seeding tests with a loaded store
by writing the file synchronously first, which still loses to the
fake-async/real-IO split and hides the loading transition the shell must
survive.

## Consequences

The registry's state stream is safe for any attach timing; the shell mounts
`ChatScreen` as soon as the registry's loaded state arrives. Bare
`MaterialApp(home: ChatScreen(...))` pumps are no longer a valid test shape —
`ChatScreen` surfaces resolve shared providers (persistence, destination)
that require a scope, matching production where the app root always provides
one.

## Testing

`flutter test` (full suite, 294 tests) covers the shell through
`app/test/widget_test.dart` (destinations, tab switches, draft survival) and
the chat/settings/sidebar surfaces through their per-screen suites;
`verify_all.py` aggregate is green.
