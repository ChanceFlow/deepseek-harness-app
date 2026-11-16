/// Central error log collection and diagnostic reporting service.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show ErrorCallback;

import 'package:flutter/foundation.dart';

import '../config.dart';
import 'error_log_entry.dart';

/// The app's error log: synchronous in-memory capture with asynchronous,
/// coalesced, atomic on-disk persistence.
///
/// Capture is synchronous in memory only: an entry is visible to [entries]
/// and [stream] immediately, while persistence is encoded and written by an
/// async, coalesced, atomic loop outside the capture call. A capture during a
/// write marks the state dirty and the single loop runs again with the newest
/// snapshot, so a connection storm costs one encode and one fsync per
/// event-loop turn instead of one blocking write per error. The trade-off is
/// a shorter durability window: a process kill within one event-loop turn of
/// a capture can lose the newest entry (the previous synchronous write
/// guaranteed it). No disk I/O runs on the capture caller's stack.
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

  /// The write loop currently draining the dirtied state, if any.
  Future<void>? _pendingPersist;

  /// Whether memory holds entries newer than the last write the loop started.
  bool _persistDirty = false;

  /// Bumped by [clear] so an in-flight write cannot resurrect the old entries.
  int _persistGeneration = 0;

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
  ///
  /// The read is asynchronous; a missing or unreadable file leaves whatever
  /// memory already holds and never breaks startup.
  Future<void> initialize({Directory? storageDir, File? storageFile}) async {
    try {
      if (storageFile != null) {
        _storageFile = storageFile;
      } else if (storageDir != null) {
        _storageFile = File('${storageDir.path}/$errorLogsFileName');
      }

      final File? file = _storageFile;
      if (file == null) return;

      // `readAsString` on an absent file raises [FileSystemException], so no
      // synchronous existence probe is needed.
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
    } on FileSystemException {
      // No persisted log yet (or it is unreadable): keep memory as captured.
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
  ///
  /// [trace] carries an optional bounded system trace (e.g. the exit trace of
  /// an ANR) straight onto the entry; capture does not read or parse it.
  void captureError(
    Object error, {
    StackTrace? stackTrace,
    ErrorLogLevel level = ErrorLogLevel.error,
    String? type,
    Map<String, Object?>? context,
    String? trace,
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
        trace: trace,
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
    _controller.add(entries);
    _schedulePersist();
  }

  /// Marks the in-memory log dirty and starts the write loop when idle.
  ///
  /// At most one write loop is in flight: a capture that lands while it runs
  /// sets the dirty flag, and the loop's next iteration snapshots the newest
  /// [entries] state. No timer is involved, so the durability window is one
  /// event-loop turn.
  void _schedulePersist() {
    final File? file = _storageFile;
    if (file == null) return; // Nothing to persist: flushPersistence settles.
    _persistDirty = true;
    if (_pendingPersist != null) return;
    _pendingPersist = _drainPersist(file);
  }

  /// Waits for the latest scheduled persistence write to finish.
  ///
  /// Capture never awaits disk I/O; tests call this to observe the file, and
  /// a lifecycle flush added later would await the same tracked write.
  /// Resolves immediately when no write is pending.
  Future<void> flushPersistence() async {
    for (;;) {
      final Future<void>? pending = _pendingPersist;
      if (pending == null) return;
      await pending;
    }
  }

  /// The single coalescing write loop.
  Future<void> _drainPersist(File file) async {
    // Yield once so a burst of captures in the same turn coalesces into one
    // encode, and so no encode or I/O runs on the capture caller's stack.
    await null;
    try {
      while (_persistDirty) {
        _persistDirty = false;
        final int generation = _persistGeneration;
        try {
          final List<ErrorLogEntry> snapshot = List<ErrorLogEntry>.unmodifiable(
            _entries,
          );
          final String payload = jsonEncode(<Map<String, Object?>>[
            for (final ErrorLogEntry entry in snapshot) entry.toJson(),
          ]);
          // A clear() landed while encoding: do not write the stale snapshot.
          if (generation != _persistGeneration) continue;
          await file.parent.create(recursive: true);
          final File temp = File('${file.path}.tmp');
          await temp.writeAsString(payload, flush: true);
          // A clear() landed while writing: drop the temp file and skip.
          if (generation != _persistGeneration) {
            await _deleteQuietly(temp);
            continue;
          }
          await temp.rename(file.path);
          // A clear() landed while renaming: the rename can complete after
          // clear deleted the target, so remove the file it re-created.
          if (generation != _persistGeneration) {
            await _deleteQuietly(file);
          }
        } catch (_) {
          // Best-effort: a disk failure must never surface on the caller.
        }
      }
    } finally {
      _pendingPersist = null;
    }
  }

  Future<void> _deleteQuietly(File file) async {
    try {
      await file.delete();
    } catch (_) {
      // Absent or undeletable: nothing to settle.
    }
  }

  /// Clear all stored error logs in memory and on disk.
  ///
  /// Bumps the persist generation first so any in-flight write is discarded
  /// instead of re-creating the file: the loop deletes its temp file, and a
  /// rename that lands after this call deletes the target it re-created.
  void clear() {
    try {
      _entries.clear();
      _persistGeneration++;
      _persistDirty = false;
      final File? file = _storageFile;
      if (file != null) {
        _deleteSyncQuietly(file);
        _deleteSyncQuietly(File('${file.path}.tmp'));
      }
      _controller.add(entries);
    } catch (_) {
      _controller.add(entries);
    }
  }

  void _deleteSyncQuietly(File file) {
    try {
      if (file.existsSync()) {
        file.deleteSync();
      }
    } catch (_) {
      // Swallowed: clear must never throw.
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
  ///
  /// Persistence is not cancelled: a scheduled write keeps running and its
  /// future stays tracked, so [flushPersistence] still awaits it.
  void dispose() {
    if (_hooksInstalled) {
      FlutterError.onError = _previousOnError;
      PlatformDispatcher.instance.onError = _previousPlatformError;
      _hooksInstalled = false;
    }
  }
}
