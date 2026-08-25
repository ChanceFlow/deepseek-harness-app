/// Crash record — the app-side shape of one captured crash.
///
/// No wire contract with any external server: the record is written to the
/// on-disk crash marker (dying-process path) and re-emitted as an OTel log
/// record (severity fatal) once the next launch reports the pending marker,
/// and best-effort at capture time. Keeping the shape self-contained means
/// the marker stays readable even when the telemetry backend changes.
library;

import 'package:flutter/foundation.dart' show FlutterErrorDetails;

import 'build_info.dart';

/// One Flutter error as captured by the crash hooks.
class CapturedCrash {
  const CapturedCrash({
    required this.kind,
    required this.type,
    required this.message,
    required this.occurredAt,
    this.stackFrames = const [],
  });

  /// Free-text classifier, e.g. `FlutterError`, `uncaught-async`.
  final String kind;
  final String type;
  final String message;
  final List<String> stackFrames;
  final DateTime occurredAt;

  factory CapturedCrash.fromFlutterError(
    FlutterErrorDetails details, {
    required DateTime occurredAt,
  }) {
    final stack =
        details.stack
            ?.toString()
            .split('\n')
            .map((l) => l.trim())
            .where((l) => l.isNotEmpty)
            .take(20)
            .toList() ??
        const [];
    final context = details.context?.toString().trim().split('\n').first;
    return CapturedCrash(
      kind: context == null || context.isEmpty
          ? 'FlutterError'
          : 'FlutterError:$context',
      type: details.exception.runtimeType.toString(),
      message: details.exceptionAsString(),
      stackFrames: stack,
      occurredAt: occurredAt,
    );
  }

  factory CapturedCrash.fromAsyncError(
    Object error,
    StackTrace? stack, {
    required DateTime occurredAt,
  }) {
    final stackLines =
        stack
            ?.toString()
            .split('\n')
            .map((l) => l.trim())
            .where((l) => l.isNotEmpty)
            .take(20)
            .toList() ??
        const [];
    return CapturedCrash(
      kind: 'uncaught-async',
      type: error.runtimeType.toString(),
      message: error.toString(),
      stackFrames: stackLines,
      occurredAt: occurredAt,
    );
  }
}

/// A full crash record: the captured crash plus build provenance, device
/// context, and the ring-buffer log tail. Serialized to the crash marker;
/// converted to an OTel log record by the telemetry facade.
class CrashRecord {
  const CrashRecord({
    required this.crash,
    required this.build,
    required this.device,
    required this.dshBaseUrl,
    required this.sessionId,
    required this.logs,
  });

  final CapturedCrash crash;
  final DebugBuildInfo build;
  final String device;
  final String dshBaseUrl;
  final String sessionId;
  final List<String> logs;

  Map<String, Object?> toJson() => {
    'app': build.app,
    'version': build.version,
    'build': build.build,
    'platform': build.platform,
    'device': device,
    'dshBaseUrl': dshBaseUrl,
    'sessionId': sessionId,
    'sourceRepo': build.sourceRepo,
    'sourceCommit': build.sourceCommit,
    'kind': crash.kind,
    'type': crash.type,
    'message': crash.message,
    'stackFrames': crash.stackFrames,
    'occurredAt': crash.occurredAt.toUtc().toIso8601String(),
    'logs': logs,
  };

  factory CrashRecord.fromJson(Map<String, Object?> json) {
    List<String> strs(Object? value) =>
        value is List ? value.whereType<String>().toList() : const <String>[];
    return CrashRecord(
      crash: CapturedCrash(
        kind: json['kind'] as String? ?? '',
        type: json['type'] as String? ?? '',
        message: json['message'] as String? ?? '',
        stackFrames: strs(json['stackFrames']),
        occurredAt:
            DateTime.tryParse(json['occurredAt'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
      ),
      build: DebugBuildInfo(
        app: json['app'] as String? ?? 'dsh-android',
        version: json['version'] as String? ?? '',
        build: json['build'] as String? ?? '',
        platform: json['platform'] as String? ?? 'android',
        sourceRepo: json['sourceRepo'] as String? ?? '',
        sourceCommit: json['sourceCommit'] as String? ?? '',
      ),
      device: json['device'] as String? ?? '',
      dshBaseUrl: json['dshBaseUrl'] as String? ?? '',
      sessionId: json['sessionId'] as String? ?? '',
      logs: strs(json['logs']),
    );
  }

  /// OTel attributes for the fatal log record that carries this crash.
  Map<String, Object> toTelemetryAttributes() => {
    'app': build.app,
    'version': build.version,
    'build': build.build,
    'platform': build.platform,
    'device': device,
    'dshBaseUrl': dshBaseUrl,
    'sessionId': sessionId,
    'source.repo': build.sourceRepo,
    'source.commit': build.sourceCommit,
    'crash.kind': crash.kind,
    'crash.type': crash.type,
    'crash.occurredAt': crash.occurredAt.toUtc().toIso8601String(),
  };
}
