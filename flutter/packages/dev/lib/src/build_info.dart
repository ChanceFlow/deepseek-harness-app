/// Build-time provenance of the running binary, injected at build time via
/// `--dart-define`. Feeds both the crash record and the OTel resource
/// attributes so the SigNoz backend can pin the exact source commit.
library;

/// Build provenance for a debug build.
class DebugBuildInfo {
  const DebugBuildInfo({
    this.app = 'dsh-android',
    this.version = '0.0.0-dev',
    this.build = '0',
    this.platform = 'android',
    this.sourceRepo = 'Chance/deepseek-harness-android',
    this.sourceCommit = 'unknown',
  });

  final String app;
  final String version;
  final String build;
  final String platform;
  final String sourceRepo;
  final String sourceCommit;

  /// Reads the standard dart-define keys; defaults keep the payload
  /// well-formed when a dev build forgets the defines.
  factory DebugBuildInfo.fromEnvironment() => const DebugBuildInfo(
    app: String.fromEnvironment('DSH_APP_NAME', defaultValue: 'dsh-android'),
    version: String.fromEnvironment('DSH_APP_VERSION', defaultValue: '0.0.0-dev'),
    build: String.fromEnvironment('DSH_BUILD_NUMBER', defaultValue: '0'),
    platform: 'android',
    sourceRepo: String.fromEnvironment(
      'DSH_SOURCE_REPO',
      defaultValue: 'Chance/deepseek-harness-android',
    ),
    sourceCommit: String.fromEnvironment('DSH_SOURCE_COMMIT', defaultValue: 'unknown'),
  );

  /// Resource attributes shared by every telemetry signal of this build.
  Map<String, Object> toResourceAttributes() => {
    'service.name': app,
    'service.version': version,
    'deployment.environment': 'dev',
    'build.number': build,
    'device.platform': platform,
    'source.repo': sourceRepo,
    'source.commit': sourceCommit,
  };
}