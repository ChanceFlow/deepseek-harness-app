/// Build-time configuration injected via `--dart-define`.
///
/// Mirrors the legacy `-PDSH_BASE_URL` Gradle property: pass
/// `--dart-define=DSH_BASE_URL=http://10.0.2.2:3080` to override the
/// loopback default. The default is the device loopback because `dsh web`
/// binds loopback-only by design (it rejects all-interfaces binding as a
/// remote-code-execution hazard); a phone reaches the backend through a
/// loopback forward such as `adb reverse tcp:3080 tcp:3080`.
library;

/// dsh backend base URL (unchanged legacy contract).
const String kDshBaseUrl = String.fromEnvironment(
  'DSH_BASE_URL',
  defaultValue: 'http://127.0.0.1:3080',
);

/// OTLP/HTTP collector base URL for debug telemetry (SigNoz otel receiver);
/// only used by debug-build tooling. Default is the emulator's route to the
/// host's SigNoz instance; point it at a LAN address for real devices.
const String kDshDebugOtlpUrl = String.fromEnvironment(
  'DSH_DEBUG_OTLP_URL',
  defaultValue: 'http://10.0.2.2:4318',
);

/// Git commit (short or full) this build was compiled from. Injected by the
/// dev build command (`--dart-define=DSH_SOURCE_COMMIT=$(git rev-parse
/// HEAD)`); reported as a telemetry resource attribute so SigNoz can pin
/// the exact source.
const String kDshSourceCommit = String.fromEnvironment(
  'DSH_SOURCE_COMMIT',
  defaultValue: 'unknown',
);

/// Source repo owning [kDshSourceCommit]; reported as a resource attribute.
const String kDshSourceRepo = String.fromEnvironment(
  'DSH_SOURCE_REPO',
  defaultValue: 'ChanceFlow/deepseek-harness-app',
);

/// Human-readable app version reported in telemetry and crash records.
const String kDshAppVersion = String.fromEnvironment(
  'DSH_APP_VERSION',
  defaultValue: '0.0.0-dev',
);

/// Build number reported in telemetry and crash records.
const String kDshBuildNumber = String.fromEnvironment(
  'DSH_BUILD_NUMBER',
  defaultValue: '0',
);
