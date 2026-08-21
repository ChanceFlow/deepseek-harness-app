/// Build-time configuration injected via `--dart-define`.
///
/// Mirrors the legacy `-PDSH_BASE_URL` Gradle property: pass
/// `--dart-define=DSH_BASE_URL=http://192.168.1.10:3080` to override the
/// emulator-loopback default.
library;

/// dsh backend base URL (unchanged legacy contract).
const String kDshBaseUrl = String.fromEnvironment(
  'DSH_BASE_URL',
  defaultValue: 'http://10.0.2.2:3080',
);

/// pi-crash-intake endpoint base; only used by debug crash capture.
const String kPiCrashIntakeUrl = String.fromEnvironment(
  'PICRASH_INTAKE_URL',
  defaultValue: 'http://10.0.2.2:9876',
);

/// Git commit (short or full) this build was compiled from. Injected by the
/// dev build command (`--dart-define=DSH_SOURCE_COMMIT=$(git rev-parse
/// HEAD)`); the intake server pins the exact source from this for the
/// self-fix loop.
const String kDshSourceCommit = String.fromEnvironment(
  'DSH_SOURCE_COMMIT',
  defaultValue: 'unknown',
);

/// Source repo owning [kDshSourceCommit]; matches the intake default.
const String kDshSourceRepo = String.fromEnvironment(
  'DSH_SOURCE_REPO',
  defaultValue: 'Chance/deepseek-harness-android',
);

/// Human-readable app version reported in crash bundles.
const String kDshAppVersion = String.fromEnvironment(
  'DSH_APP_VERSION',
  defaultValue: '0.0.0-dev',
);

/// Build number reported in crash bundles.
const String kDshBuildNumber = String.fromEnvironment(
  'DSH_BUILD_NUMBER',
  defaultValue: '0',
);