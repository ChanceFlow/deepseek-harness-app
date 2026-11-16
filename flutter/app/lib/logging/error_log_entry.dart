/// Error log entry models for the in-app error log collection system.
library;

import 'package:flutter/foundation.dart' show FlutterErrorDetails;

/// Hard cap on the characters of an [ErrorLogEntry.trace] a report renders.
const int kMaxTraceChars = 64 * 1024;

/// The line appended when a trace is cut at [kMaxTraceChars]. It repeats the
/// words `DiagnosticsBridge.kt` uses when the platform stream is cut, so a
/// report states truncation in one vocabulary.
const String kTraceTruncationMarker =
    '[... trace truncated at 65536 bytes ...]';

/// The readable form of a system [trace]: trimmed, and cut at [kMaxTraceChars]
/// with [kTraceTruncationMarker] appended when it is longer.
///
/// Idempotent: a trace that already carries the marker (or fits the cap) is
/// returned trimmed but otherwise unchanged, so persisting this form and
/// rendering it again cannot double the marker.
String renderableTrace(String trace) {
  final String trimmed = trace.trim();
  if (trimmed.length <= kMaxTraceChars) return trimmed;
  final String head = trimmed.substring(0, kMaxTraceChars);
  return head.contains(kTraceTruncationMarker)
      ? head
      : '$head\n$kTraceTruncationMarker';
}

/// Whether [trace] already lost evidence: the platform stream was cut at its
/// byte cap, or the text is longer than a report renders.
bool isTraceTruncated(String trace) =>
    trace.length > kMaxTraceChars || trace.contains(kTraceTruncationMarker);

/// Severity levels for captured errors and diagnostics.
enum ErrorLogLevel {
  fatal,
  error,
  warning,
  info;

  String get label => switch (this) {
    ErrorLogLevel.fatal => 'FATAL',
    ErrorLogLevel.error => 'ERROR',
    ErrorLogLevel.warning => 'WARN',
    ErrorLogLevel.info => 'INFO',
  };

  static ErrorLogLevel parse(String? raw) => switch (raw?.toLowerCase()) {
    'fatal' || 'crash' => ErrorLogLevel.fatal,
    'warn' || 'warning' => ErrorLogLevel.warning,
    'info' => ErrorLogLevel.info,
    _ => ErrorLogLevel.error,
  };
}

/// A structured error record captured by [ErrorLogCollector].
class ErrorLogEntry {
  const ErrorLogEntry({
    required this.id,
    required this.timestamp,
    required this.level,
    required this.type,
    required this.message,
    this.stackTrace,
    this.context,
    this.breadcrumbs = const <String>[],
    this.trace,
  });

  /// Unique identifier, e.g. `err_1724123456789_1`.
  final String id;

  /// Time the error occurred.
  final DateTime timestamp;

  /// Severity level.
  final ErrorLogLevel level;

  /// Error classifier (e.g. `FlutterError`, `uncaught-async`, `SocketException`).
  final String type;

  /// Human-readable error message.
  final String message;

  /// Stack trace if captured.
  final String? stackTrace;

  /// Diagnostic metadata snapshot (active backend, session, route, etc.).
  final Map<String, Object?>? context;

  /// Ring buffer of recent breadcrumbs leading up to this error.
  final List<String> breadcrumbs;

  /// The bounded system trace captured for this entry, if any.
  ///
  /// Process-exit entries carry the previous process's ANR or crash trace here
  /// ([kProcessExitTypePrefix] records); a report renders it as a fenced
  /// `System Trace` block. Null when no trace was available.
  final String? trace;

  /// Formatted clock timestamp `YYYY-MM-DD HH:mm:ss.SSS`.
  String get formattedTimestamp {
    String two(int n) => n.toString().padLeft(2, '0');
    final String y = timestamp.year.toString();
    final String m = two(timestamp.month);
    final String d = two(timestamp.day);
    final String h = two(timestamp.hour);
    final String min = two(timestamp.minute);
    final String s = two(timestamp.second);
    final String ms = timestamp.millisecond.toString().padLeft(3, '0');
    return '$y-$m-$d $h:$min:$s.$ms';
  }

  /// Create an [ErrorLogEntry] from a framework [FlutterErrorDetails].
  factory ErrorLogEntry.fromFlutterError(
    FlutterErrorDetails details, {
    String? id,
    DateTime? at,
    List<String> breadcrumbs = const <String>[],
    Map<String, Object?>? context,
  }) {
    final DateTime now = at ?? DateTime.now();
    final String entryId = id ?? 'err_${now.microsecondsSinceEpoch}';
    final String ctx =
        details.context?.toString().trim().split('\n').first ?? '';
    final String typeName = ctx.isEmpty
        ? 'FlutterError:${details.exception.runtimeType}'
        : 'FlutterError:$ctx';

    return ErrorLogEntry(
      id: entryId,
      timestamp: now,
      level: ErrorLogLevel.fatal,
      type: typeName,
      message: details.exceptionAsString(),
      stackTrace: details.stack?.toString(),
      context: context,
      breadcrumbs: breadcrumbs,
    );
  }

  /// Create an [ErrorLogEntry] from an async unhandled error.
  factory ErrorLogEntry.fromAsyncError(
    Object error,
    StackTrace? stack, {
    String? id,
    DateTime? at,
    ErrorLogLevel level = ErrorLogLevel.fatal,
    List<String> breadcrumbs = const <String>[],
    Map<String, Object?>? context,
  }) {
    final DateTime now = at ?? DateTime.now();
    final String entryId = id ?? 'err_${now.microsecondsSinceEpoch}';

    return ErrorLogEntry(
      id: entryId,
      timestamp: now,
      level: level,
      type: 'AsyncError:${error.runtimeType}',
      message: error.toString(),
      stackTrace: stack?.toString(),
      context: context,
      breadcrumbs: breadcrumbs,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'timestamp': timestamp.toIso8601String(),
    'level': level.name,
    'type': type,
    'message': message,
    if (stackTrace != null) 'stackTrace': stackTrace,
    if (context != null) 'context': context,
    if (breadcrumbs.isNotEmpty) 'breadcrumbs': breadcrumbs,
    if (trace != null) 'trace': trace,
  };

  factory ErrorLogEntry.fromJson(Map<String, Object?> json) {
    final String id = json['id'] as String? ?? 'err_unknown';
    final String timeStr = json['timestamp'] as String? ?? '';
    final DateTime time = DateTime.tryParse(timeStr) ?? DateTime.now();
    final ErrorLogLevel level = ErrorLogLevel.parse(json['level'] as String?);
    final String type = json['type'] as String? ?? 'Unknown';
    final String message = json['message'] as String? ?? '';
    final String? stackTrace = json['stackTrace'] as String?;
    final Map<String, Object?>? context = json['context'] is Map
        ? (json['context'] as Map).cast<String, Object?>()
        : null;
    final List<String> breadcrumbs = json['breadcrumbs'] is List
        ? (json['breadcrumbs'] as List).whereType<String>().toList()
        : const <String>[];
    final String? trace = json['trace'] as String?;

    return ErrorLogEntry(
      id: id,
      timestamp: time,
      level: level,
      type: type,
      message: message,
      stackTrace: stackTrace,
      context: context,
      breadcrumbs: breadcrumbs,
      trace: trace,
    );
  }

  /// Formatted single-entry markdown block for copying.
  String toMarkdown() {
    final StringBuffer sb = StringBuffer();
    sb.writeln('### [${level.label}] $type');
    sb.writeln('- **Time**: $formattedTimestamp');
    sb.writeln('- **Message**: $message');
    if (context != null && context!.isNotEmpty) {
      sb.writeln('- **Context**:');
      for (final MapEntry<String, Object?> entry in context!.entries) {
        sb.writeln('  - `${entry.key}`: ${entry.value}');
      }
    }
    if (breadcrumbs.isNotEmpty) {
      sb.writeln('- **Recent Breadcrumbs**:');
      for (final String line in breadcrumbs) {
        sb.writeln('  - `$line`');
      }
    }
    if (stackTrace != null && stackTrace!.trim().isNotEmpty) {
      sb.writeln('- **Stack Trace**:');
      sb.writeln('```');
      sb.writeln(stackTrace!.trim());
      sb.writeln('```');
    }
    if (trace != null && trace!.trim().isNotEmpty) {
      sb.writeln('- **System Trace**:');
      sb.writeln('```');
      sb.writeln(renderableTrace(trace!));
      sb.writeln('```');
    }
    return sb.toString();
  }
}
