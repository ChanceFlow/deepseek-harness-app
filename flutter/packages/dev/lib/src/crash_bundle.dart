/// Crash bundle payload — the wire contract with the pi-crash-intake server.
///
/// Field names and shapes mirror `src/triage-context.ts` (CrashBundle) in
/// the pi-crash-intake repository, one-to-one; change either side only
/// together (dual-provider symmetry applies to the intake server, this file
/// is the app-side producer of the same shape).
library;

import 'package:flutter/foundation.dart' show FlutterErrorDetails;

/// Build-time provenance of the running binary, injected at build time via
/// `--dart-define`; see [CrashBundleSource] for the intake `source` block.
class CrashBuildInfo {
  const CrashBuildInfo({
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
  factory CrashBuildInfo.fromEnvironment() => const CrashBuildInfo(
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
}

/// One Flutter error as captured by the crash hooks.
class CapturedCrash {
  const CapturedCrash({
    required this.kind,
    required this.type,
    required this.message,
    this.stackFrames = const [],
    required this.occurredAt,
  });

  /// Free-text classifier, e.g. `FlutterError`, `uncaught-async`.
  final String kind;
  final String type;
  final String message;
  final List<String> stackFrames;
  final DateTime occurredAt;

  factory CapturedCrash.fromFlutterError(FlutterErrorDetails details, {required DateTime occurredAt}) {
    final stack = details.stack?.toString().split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).take(20).toList() ?? const [];
    return CapturedCrash(
      kind: details.context == null ? 'FlutterError' : 'FlutterError:${details.context!.name}',
      type: details.exception.runtimeType.toString(),
      message: details.exceptionAsString(),
      stackFrames: stack,
      occurredAt: occurredAt,
    );
  }

  factory CapturedCrash.fromAsyncError(Object error, StackTrace? stack, {required DateTime occurredAt}) {
    final stackLines = stack?.toString().split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).take(20).toList() ?? const [];
    return CapturedCrash(
      kind: 'uncaught-async',
      type: error.runtimeType.toString(),
      message: error.toString(),
      stackFrames: stackLines,
      occurredAt: occurredAt,
    );
  }
}

/// The full JSON body sent to the intake server — the intake `CrashBundle`
/// wire contract (see `src/triage-context.ts` in pi-crash-intake).
class CrashBundleWire {
  const CrashBundleWire({
    required this.app,
    required this.version,
    required this.build,
    required this.platform,
    required this.device,
    required this.dshBaseUrl,
    required this.sessionId,
    required this.sourceRepo,
    required this.sourceCommit,
    required this.crash,
    required this.logs,
  });

  factory CrashBundleWire.fromJson(Map<String, Object?> json) {
    // jsonDecode produces _Map<dynamic, dynamic>; read through a tolerant
    // helper instead of casting subtrees.
    Map<String, Object?>? sub(Object? value) =>
        value is Map ? value.map((k, v) => MapEntry('$k', v as Object?)) : null;
    List<String> strs(Object? value) =>
        value is List ? value.whereType<String>().toList() : const <String>[];
    final source = sub(json['source']) ?? const {};
    final crashJson = sub(json['crash']) ?? const {};
    return CrashBundleWire(
      app: json['app'] as String? ?? 'dsh-android',
      version: json['version'] as String? ?? '',
      build: json['build'] as String? ?? '',
      platform: json['platform'] as String? ?? 'android',
      device: json['device'] as String? ?? '',
      dshBaseUrl: json['dshBaseUrl'] as String? ?? '',
      sessionId: json['sessionId'] as String? ?? '',
      sourceRepo: source['repo'] as String? ?? 'Chance/deepseek-harness-android',
      sourceCommit: source['commit'] as String? ?? '',
      crash: CapturedCrash(
        kind: crashJson['kind'] as String? ?? '',
        type: crashJson['type'] as String? ?? '',
        message: crashJson['message'] as String? ?? '',
        stackFrames: strs(crashJson['stackFrames']),
        occurredAt:
            DateTime.tryParse(crashJson['occurredAt'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
      ),
      logs: strs(json['logs']),
    );
  }

  final String app;
  final String version;
  final String build;
  final String platform;
  final String device;
  final String dshBaseUrl;
  final String sessionId;
  final String sourceRepo;
  final String sourceCommit;
  final CapturedCrash crash;
  final List<String> logs;

  Map<String, Object?> toJson() => {
    'app': app,
    'version': version,
    'build': build,
    'platform': platform,
    'device': device,
    'dshBaseUrl': dshBaseUrl,
    'sessionId': sessionId,
    'source': {'repo': sourceRepo, 'commit': sourceCommit},
    'crash': {
      'kind': crash.kind,
      'type': crash.type,
      'message': crash.message,
      'stackFrames': crash.stackFrames,
      'occurredAt': crash.occurredAt.toUtc().toIso8601String(),
    },
    'logs': logs,
  };
}