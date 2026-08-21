# AGENTS.md — packages/dev (debug crash capture)

Supplements the [root conventions](../../../AGENTS.md#conventions) and the
[workspace file](../../AGENTS.md). This package is the debug-build crash
capture chain: ring log buffer, crash marker, restart detection, intake
reporter. It is wired ONLY on debug builds (`kDebugMode` gate in
`app/lib/main.dart`); release builds never execute it.

## Contract and boundaries

- **Wire shape is the intake contract.** The JSON payload mirrors
  `src/triage-context.ts` (CrashBundle) in the pi-crash-intake repository
  one-to-one — `app/version/build/platform/device/dshBaseUrl/sessionId` +
  `source{repo,commit}` + `crash{type,message,stackFrames,occurredAt}` +
  `logs`. Change the shape only together with the intake server; the
  contract test (`../test/crash_bundle_test.dart`) pins every key.
- **Zero internal coupling.** This package must not import `domain`,
  `network`, or `harness_adapter`; it only depends on `flutter`, `http`,
  `path_provider`. The app feeds it build provenance through dart-defines
  (`config.dart`), never through the domain model.
- **Capture must never break the app.** Marker writes, reporter calls, and
  bootstrap init failures are all swallowed (best-effort by design). The
  dying-process case is why the marker is written SYNCHRONOUSLY.
- **Hooks chain, never replace.** `FlutterError.onError` and
  `PlatformDispatcher.instance.onError` must delegate to the previous
  handler after capturing; the app's own error behavior is unchanged.
- **Compile-time injection only.** Build provenance
  (`DSH_SOURCE_COMMIT`/`DSH_APP_VERSION`/...) arrives via
  `String.fromEnvironment`; there is no runtime settings channel. A build
  without `DSH_SOURCE_COMMIT` reports `unknown` and the intake skips the
  self-fix stage.