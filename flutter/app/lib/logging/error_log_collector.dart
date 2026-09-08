/// Central error log collection and diagnostic reporting service.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show ErrorCallback;

import 'package:flutter/foundation.dart';

import '../config.dart';
import 'error_log_entry.dart';

class ErrorLogCollector {
  ErrorLogCollector({this.maxEntries = 100, this.maxBreadcrumbs = 30});

  /// The global singleton instance.
  static final ErrorLogCollector instance = ErrorLogCollector();

  final int maxEntries;
  final int maxBreadcrumbs;

  final List<ErrorLogEntry> _entries = <ErrorLogEntry>[];
  final List<String> _breadcrumbs = <String>[];
  final StreamController<List<ErrorLogEntry>> _controller =
      StreamController<List<ErrorLogEntry>>.broadcast();

  File? _storageFile;
  bool _hooksInstalled = false;
  FlutterExceptionHandler? _previousOnError;
  ErrorCallback? _previousPlatformError;

  /// Stream of error log snapshots (newest first).
  Stream<List<ErrorLogEntry>> get stream => _controller.stream;

  /// Current snapshot of captured error logs (newest first).
  List<ErrorLogEntry> get entries => List<ErrorLogEntry>.unmodifiable(_entries);

  /// Recent operation breadcrumbs.
  List<String> get breadcrumbs => List<String>.unmodifiable(_breadcrumbs);

  /// Whether hooks are currently installed.
  bool get areHooksInstalled => _hooksInstalled;

  /// Name of the persistent error logs file.
  static const String errorLogsFileName = 'error_logs.json';

  /// Initialize persistence from [storageDir] or specific [storageFile].
  Future<void> initialize({Directory? storageDir, File? storageFile}) async {
    try {
      if (storageFile != null) {
        _storageFile = storageFile;
      } else if (storageDir != null) {
        _storageFile = File('${storageDir.path}/$errorLogsFileName');
      }

      final File? file = _storageFile;
      if (file != null && file.existsSync()) {
        final String raw = await file.readAsString();
        if (raw.trim().isNotEmpty) {
          final Object? decoded = jsonDecode(raw);
          if (decoded is List) {
            _entries.clear();
            for (final Object? item in decoded) {
              if (item is Map<String, Object?>) {
                _entries.add(ErrorLogEntry.fromJson(item));
              } else if (item is Map) {
                _entries.add(
                  ErrorLogEntry.fromJson(item.cast<String, Object?>()),
                );
              }
            }
            if (_entries.length > maxEntries) {
              _entries.removeRange(maxEntries, _entries.length);
            }
            _controller.add(entries);
          }
        }
      }
    } catch (_) {
      // Best-effort: initialization failure never breaks the app.
    }
  }

  /// Install Flutter framework and platform-level unhandled error hooks.
  /// Hooks are chained so previous handlers (e.g. debug telemetry or tester)
  /// remain active.
  void installHooks() {
    if (_hooksInstalled) return;

    _previousOnError = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      captureFlutterError(details);
      _previousOnError?.call(details);
    };

    _previousPlatformError = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      captureError(
        error,
        stackTrace: stack,
        level: ErrorLogLevel.fatal,
        type: 'uncaught-async:${error.runtimeType}',
      );
      return _previousPlatformError?.call(error, stack) ?? true;
    };

    _hooksInstalled = true;
  }

  /// Capture a generic error or caught exception.
  void captureError(
    Object error, {
    StackTrace? stackTrace,
    ErrorLogLevel level = ErrorLogLevel.error,
    String? type,
    Map<String, Object?>? context,
  }) {
    try {
      final DateTime now = DateTime.now();
      final ErrorLogEntry entry = ErrorLogEntry(
        id: 'err_${now.microsecondsSinceEpoch}',
        timestamp: now,
        level: level,
        type: type ?? error.runtimeType.toString(),
        message: error.toString(),
        stackTrace: stackTrace?.toString(),
        context: context,
        breadcrumbs: List<String>.unmodifiable(_breadcrumbs),
      );

      _insertEntry(entry);
    } catch (_) {
      // Error capture must never throw.
    }
  }

  /// Capture a [FlutterErrorDetails] framework error.
  void captureFlutterError(
    FlutterErrorDetails details, {
    Map<String, Object?>? context,
  }) {
    try {
      final ErrorLogEntry entry = ErrorLogEntry.fromFlutterError(
        details,
        breadcrumbs: List<String>.unmodifiable(_breadcrumbs),
        context: context,
      );
      _insertEntry(entry);
    } catch (_) {
      // Framework error capture must never throw.
    }
  }

  /// Append a breadcrumb message to the in-memory ring buffer.
  void addBreadcrumb(String message, {String level = 'info'}) {
    try {
      final DateTime now = DateTime.now();
      String two(int n) => n.toString().padLeft(2, '0');
      final String ms = now.millisecond.toString().padLeft(3, '0');
      final String time =
          '${two(now.hour)}:${two(now.minute)}:${two(now.second)}.$ms';
      final String line = '$time [${level.toUpperCase()}] $message';

      _breadcrumbs.add(line);
      if (_breadcrumbs.length > maxBreadcrumbs) {
        _breadcrumbs.removeRange(0, _breadcrumbs.length - maxBreadcrumbs);
      }
    } catch (_) {
      // Swallowed.
    }
  }

  void _insertEntry(ErrorLogEntry entry) {
    _entries.insert(0, entry);
    if (_entries.length > maxEntries) {
      _entries.removeRange(maxEntries, _entries.length);
    }
    _persistSync();
    _controller.add(entries);
  }

  void _persistSync() {
    final File? file = _storageFile;
    if (file == null) return;
    try {
      file.parent.createSync(recursive: true);
      final List<Map<String, Object?>> jsonList = _entries
          .map((ErrorLogEntry e) => e.toJson())
          .toList();
      file.writeAsStringSync(jsonEncode(jsonList), flush: true);
    } catch (_) {
      // Swallowed: disk persistence failure must never crash the caller.
    }
  }

  /// Clear all stored error logs in memory and on disk.
  void clear() {
    try {
      _entries.clear();
      final File? file = _storageFile;
      if (file != null && file.existsSync()) {
        file.deleteSync();
      }
      _controller.add(entries);
    } catch (_) {
      _controller.add(entries);
    }
  }

  /// Format all or given error entries into a Markdown diagnostic report.
  String formatExportReport({
    List<ErrorLogEntry>? entries,
    String? activeBackendUrl,
  }) {
    final List<ErrorLogEntry> list = entries ?? _entries;
    final StringBuffer sb = StringBuffer();

    sb.writeln('# DSH Mobile Error & Diagnostic Report');
    sb.writeln();
    sb.writeln('## System Information');
    sb.writeln(
      '- **Report Generated**: ${DateTime.now().toUtc().toIso8601String()}',
    );
    sb.writeln('- **App Version**: $kDshAppVersion ($kDshBuildNumber)');
    sb.writeln('- **Source Commit**: $kDshSourceCommit');
    sb.writeln('- **Source Repo**: $kDshSourceRepo');
    sb.writeln('- **Default Base URL**: $kDshBaseUrl');
    if (activeBackendUrl != null && activeBackendUrl.isNotEmpty) {
      sb.writeln('- **Active Host**: $activeBackendUrl');
    }
    sb.writeln(
      '- **Operating System**: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
    );
    sb.writeln('- **Total Recorded Errors**: ${list.length}');
    sb.writeln();

    if (list.isEmpty) {
      sb.writeln('*(No error logs recorded)*');
      return sb.toString();
    }

    sb.writeln('## Error Log Records');
    sb.writeln();
    for (int i = 0; i < list.length; i++) {
      sb.writeln('---');
      sb.writeln(list[i].toMarkdown());
    }

    return sb.toString();
  }

  /// Teardown hooks (useful for testing).
  void dispose() {
    if (_hooksInstalled) {
      FlutterError.onError = _previousOnError;
      PlatformDispatcher.instance.onError = _previousPlatformError;
      _hooksInstalled = false;
    }
  }
}
