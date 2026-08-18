/// Base-URL configuration injected at build time.
///
/// Mirrors the legacy `-PDSH_BASE_URL` Gradle property: pass
/// `--dart-define=DSH_BASE_URL=http://192.168.1.10:3080` to override the
/// emulator-loopback default.
library;

const String kDshBaseUrl = String.fromEnvironment(
  'DSH_BASE_URL',
  defaultValue: 'http://10.0.2.2:3080',
);
