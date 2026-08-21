# AGENTS.md — packages/dev (debug-build tooling)

Supplements the [root conventions](../../../AGENTS.md#conventions) and the
[workspace file](../../AGENTS.md). This package is the debug-build tooling
home: telemetry facade (log / event / metric), frame-rate tracking, and the
crash capture chain (ring log buffer, crash marker, restart detection,
fatal-log reporting).

## Who runs it

One compile-time gate decides, in `app/lib/main.dart`: debug builds always
report; a release build reports only when the release pipeline passed
`--dart-define=DSH_TELEMETRY_ENABLED=true`, which it does for prerelease
versions (`-alpha/-beta/-rc`). A stable release folds `kReleaseMode &&
!kDebugTelemetryEnabled` to `return` and AOT tree-shakes the whole chain out
of the APK. Widget tests skip the chain on `FLUTTER_TEST`. A local
`flutter build apk --release` without the define reports — the gate errs
toward observability.

## Contract and boundaries

- **Transport is OTLP/HTTP to SigNoz.** All signals ride the OpenTelemetry
  SDK (`dartastic_opentelemetry`, Apache-2.0 — the official
  `opentelemetry_otlp` package does not resolve on Dart 3, see the telemetry
  decision note). The endpoint arrives via `DSH_DEBUG_OTLP_URL` (app
  `config.dart`; default `http://10.0.2.2:4318` — the emulator's route to
  the host's SigNoz; LAN address for real devices).
- **No fixed wire contract with any external server.** The crash marker is
  a self-contained record (`CrashRecord` JSON) with no server-side schema;
  crashes and telemetry go to SigNoz as OTel log records / metrics. Backend
  swaps require no client payload changes beyond the endpoint.
- **Zero internal coupling.** This package must not import `domain`,
  `network`, or `harness_adapter`; it depends on `flutter` and
  `dartastic_opentelemetry` only. The app feeds build provenance through
  dart-defines (`config.dart`), never through the domain model.
- **Telemetry must never break the app.** All facade emit paths, marker
  writes, and bootstrap init failures are swallowed (best-effort by
  design). The dying-process case is why the marker is written
  SYNCHRONOUSLY; the OTel emit at capture time is a best-effort bonus on top
  of the durable marker.
- **Hooks chain, never replace.** `FlutterError.onError` and
  `PlatformDispatcher.instance.onError` must delegate to the previous
  handler after capturing; the app's own error behavior is unchanged.
- **Compile-time injection only.** Build provenance
  (`DSH_SOURCE_COMMIT`/`DSH_APP_VERSION`/...) arrives via
  `String.fromEnvironment` and becomes OTel resource attributes; there is
  no runtime settings channel. A build without `DSH_SOURCE_COMMIT` reports
  `unknown` — SigNoz just cannot pin the source.
- **Frame tracking uses the framework's own timings stream.**
  `WidgetsBinding.addTimingsCallback` feeds `app.frame.total_ms`
  (histogram), `app.frame.jank_total` (counter, > 16.7 ms), and
  `app.frame.fps` (gauge); no third-party instrumentation.
- **Facade methods are the app's only surface** (`DebugTelemetry`:
  `log`/`event`/`count`/`record`/`setGauge`/`reportCrash`), with a
  `TelemetrySettings.enabled` master switch and a per-second event rate cap.