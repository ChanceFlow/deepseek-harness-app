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
///
/// The collector also keeps a bounded ring of recent operations
/// ([addOperation], [operations]) and persists it to
/// [operationsFileName] through a second loop of the same shape. The run after
/// this one reads that file once in [initialize] into [previousOperations] and
/// deletes it, so the next `process-exit:` entry can carry the phases the dead
/// process reached — evidence that survives stripped Dart symbols.
class ErrorLogCollector {
  ErrorLogCollector({
    this.maxEntries = 100,
    this.maxBreadcrumbs = 30,
    this.maxOperations = 32,
  });

  /// The global singleton instance.
  static final ErrorLogCollector instance = ErrorLogCollector();

  final int maxEntries;
  final int maxBreadcrumbs;
  final int maxOperations;

  final List<ErrorLogEntry> _entries = <ErrorLogEntry>[];
  final List<String> _breadcrumbs = <String>[];
  final List<String> _operations = <String>[];

  /// The previous process's operations, loaded once by [initialize].
  List<String> _previousOperations = const <String>[];

  final StreamController<List<ErrorLogEntry>> _controller =
      StreamController<List<ErrorLogEntry>>.broadcast();

  File? _storageFile;
  File? _operationsFile;
  bool _hooksInstalled = false;
  FlutterExceptionHandler? _previousOnError;
  ErrorCallback? _previousPlatformError;

  /// The write loop currently draining the dirtied state, if any.
  Future<void>? _pendingPersist;

  /// The operations write loop currently draining the dirtied ring, if any.
  Future<void>? _pendingOperationsPersist;

  /// Whether memory holds entries newer than the last write the loop started.
  bool _persistDirty = false;

  /// Whether memory holds operations newer than the last write the loop
  /// started.
  bool _operationsDirty = false;

  /// Bumped by [clear] so an in-flight entry or operations write cannot
  /// resurrect the old state.
  int _persistGeneration = 0;

  /// Stream of error log snapshots (newest first).
  Stream<List<ErrorLogEntry>> get stream => _controller.stream;

  /// Current snapshot of captured error logs (newest first).
  List<ErrorLogEntry> get entries => List<ErrorLogEntry>.unmodifiable(_entries);

  /// Recent operation breadcrumbs.
  List<String> get breadcrumbs => List<String>.unmodifiable(_breadcrumbs);

  /// This run's recent operations, oldest first.
  List<String> get operations => List<String>.unmodifiable(_operations);

  /// The previous run's operations, oldest first.
  ///
  /// [initialize] fills this from [operationsFileName] and deletes the file, so
  /// only the first launch after an abnormal exit sees it; [clear] empties it.
  List<String> get previousOperations =>
      List<String>.unmodifiable(_previousOperations);

  /// Whether hooks are currently installed.
  bool get areHooksInstalled => _hooksInstalled;

  /// Name of the persistent error logs file.
  static const String errorLogsFileName = 'error_logs.json';

  /// Name of the persistent recent-operations file, beside
  /// [errorLogsFileName].
  static const String operationsFileName = 'last_operations.json';

  /// Initialize persistence from [storageDir] or specific [storageFile].
  ///
  /// The read is asynchronous; a missing or unreadable file leaves whatever
  /// memory already holds and never breaks startup. An existing
  /// [operationsFileName] is loaded into [previousOperations] and then deleted:
  /// the ring belongs to the run that died, and one report consumes it.
  Future<void> initialize({Directory? storageDir, File? storageFile}) async {
    try {
      if (storageFile != null) {
        _storageFile = storageFile;
        _operationsFile = File(
          '${storageFile.parent.path}/$operationsFileName',
        );
      } else if (storageDir != null) {
        _storageFile = File('${storageDir.path}/$errorLogsFileName');
        _operationsFile = File('${storageDir.path}/$operationsFileName');
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

    await _loadPreviousOperations();
    // Operations captured before storage resolved are persisted now; without
    // this a run whose whole trail predates initialization would never write
    // the ring the next launch needs.
    if (_operations.isNotEmpty) _scheduleOperationsPersist();
  }

  /// Reads [operationsFileName] into [previousOperations], then deletes it.
  ///
  /// One-shot by design: the file describes the process that died, so the run
  /// that consumes it must remove it. An absent, unreadable, or malformed file
  /// leaves no previous operations rather than failing startup.
  Future<void> _loadPreviousOperations() async {
    final File? file = _operationsFile;
    if (file == null) return;
    List<String> restored = const <String>[];
    try {
      final String raw = await file.readAsString();
      final Object? decoded = raw.trim().isEmpty ? null : jsonDecode(raw);
      if (decoded is List) {
        final List<String> lines = decoded.whereType<String>().toList();
        restored = lines.length > maxOperations
            ? lines.sublist(lines.length - maxOperations)
            : lines;
      }
    } catch (_) {
      // Absence or damage is no evidence, not a startup failure.
    } finally {
      await _deleteQuietly(file);
    }
    _previousOperations = List<String>.unmodifiable(restored);
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
  /// [previousOperations] attaches the previous run's operation ring to the
  /// entry, as `recordProcessExitReasons` does for a `process-exit:` record.
  void captureError(
    Object error, {
    StackTrace? stackTrace,
    ErrorLogLevel level = ErrorLogLevel.error,
    String? type,
    Map<String, Object?>? context,
    String? trace,
    List<String> previousOperations = const <String>[],
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
        previousOperations: previousOperations,
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
      final String line = _timestampedLine(level.toUpperCase(), message);

      _breadcrumbs.add(line);
      if (_breadcrumbs.length > maxBreadcrumbs) {
        _breadcrumbs.removeRange(0, _breadcrumbs.length - maxBreadcrumbs);
      }
    } catch (_) {
      // Swallowed.
    }
  }

  /// Append an operation to the in-memory ring and schedule its persistence.
  ///
  /// The line is `HH:MM:SS.mmm [OP] <message>`, the breadcrumb clock with an
  /// `OP` tag. The call is synchronous in memory only; the write runs outside
  /// the caller on the coalescing operations loop, exactly as a capture does.
  void addOperation(String message) {
    try {
      _operations.add(_timestampedLine('OP', message));
      if (_operations.length > maxOperations) {
        _operations.removeRange(0, _operations.length - maxOperations);
      }
      _scheduleOperationsPersist();
    } catch (_) {
      // A diagnostic trail must never throw.
    }
  }

  /// `HH:MM:SS.mmm [<tag>] <message>`, the clock breadcrumbs and operations
  /// share.
  String _timestampedLine(String tag, String message) {
    final DateTime now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final String ms = now.millisecond.toString().padLeft(3, '0');
    final String time =
        '${two(now.hour)}:${two(now.minute)}:${two(now.second)}.$ms';
    return '$time [$tag] $message';
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

  /// Marks the operations ring dirty and starts its write loop when idle.
  ///
  /// The same shape as [_schedulePersist]: at most one loop is in flight and a
  /// later [addOperation] only sets the dirty flag, so a burst of operations
  /// costs one encode and one fsync per event-loop turn. The operations loop is
  /// separate from the entry loop, so a slow entry write never delays the ring.
  void _scheduleOperationsPersist() {
    final File? file = _operationsFile;
    if (file == null) return; // Nothing to persist: flushPersistence settles.
    _operationsDirty = true;
    if (_pendingOperationsPersist != null) return;
    _pendingOperationsPersist = _drainOperationsPersist(file);
  }

  /// Waits for both the latest entry write and the latest operations write.
  ///
  /// Capture and [addOperation] never await disk I/O; tests call this to
  /// observe the files, and a lifecycle flush awaits the same tracked writes.
  /// Resolves immediately when neither loop has work pending.
  Future<void> flushPersistence() async {
    for (;;) {
      final Future<void>? pendingEntries = _pendingPersist;
      final Future<void>? pendingOperations = _pendingOperationsPersist;
      if (pendingEntries == null && pendingOperations == null) return;
      if (pendingEntries != null) await pendingEntries;
      if (pendingOperations != null) await pendingOperations;
    }
  }

  /// The coalescing operations write loop, atomic via temp file and rename.
  Future<void> _drainOperationsPersist(File file) async {
    // Yield once so a burst of operations in the same turn coalesces into one
    // encode, and so no encode or I/O runs on the caller's stack.
    await null;
    try {
      while (_operationsDirty) {
        _operationsDirty = false;
        final int generation = _persistGeneration;
        try {
          final String payload = jsonEncode(List<String>.of(_operations));
          // A clear() landed while encoding: do not write the stale ring.
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
      _pendingOperationsPersist = null;
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

  /// Clear all stored error logs, breadcrumbs, and operations in memory and on
  /// disk.
  ///
  /// Bumps the persist generation first so any in-flight entry or operations
  /// write is discarded instead of re-creating a file: each loop deletes its
  /// temp file, and a rename that lands after this call deletes the target it
  /// re-created. [previousOperations] is dropped too: a cleared log has no
  /// previous run to report.
  void clear() {
    try {
      _entries.clear();
      _breadcrumbs.clear();
      _operations.clear();
      _previousOperations = const <String>[];
      _persistGeneration++;
      _persistDirty = false;
      _operationsDirty = false;
      final File? file = _storageFile;
      if (file != null) {
        _deleteSyncQuietly(file);
        _deleteSyncQuietly(File('${file.path}.tmp'));
      }
      final File? operationsFile = _operationsFile;
      if (operationsFile != null) {
        _deleteSyncQuietly(operationsFile);
        _deleteSyncQuietly(File('${operationsFile.path}.tmp'));
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
