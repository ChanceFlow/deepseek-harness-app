/// Unit tests for [ConnectionDiagnosticLog]: the throttle in front of the two
/// connection-diagnostics sinks. The clock is injected, so a 60 s window is
/// crossed without waiting; the collector is temp-dir-backed so the folded
/// captures go through the real persistence scheduling path.
library;

import 'dart:async';
import 'dart:io';

import 'package:app/di/connection_diagnostics.dart';
import 'package:app/logging/error_log_collector.dart';
import 'package:app/logging/error_log_entry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tempDir;
  late File logFile;
  late ErrorLogCollector collector;
  late DateTime now;
  late List<String> telemetryLines;
  late ConnectionDiagnosticLog sink;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('connection_diagnostics_');
    logFile = File('${tempDir.path}/${ErrorLogCollector.errorLogsFileName}');
    collector = ErrorLogCollector();
    await collector.initialize(storageFile: logFile);
    now = DateTime.utc(2026, 11, 12, 10);
    telemetryLines = <String>[];
    sink = ConnectionDiagnosticLog(
      source: 'Connection',
      collector: collector,
      now: () => now,
      telemetry: (String message, {required String level}) =>
          telemetryLines.add('$level: $message'),
    );
  });

  tearDown(() async {
    // Let the collector's async persistence settle before the directory goes.
    await collector.flushPersistence();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  void recordDiagnostic({
    String backendId = 'backend-1',
    String? uri = 'http://127.0.0.1:3080',
    String? diagnosticContext = 'connection.negotiate',
    String message = 'Generation handshake failed',
    ConnectionDiagnosticLevel level = ConnectionDiagnosticLevel.error,
    Object? error,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    sink.record(
      backendId: backendId,
      uri: uri,
      context: diagnosticContext,
      message: message,
      level: level,
      error: error,
      metadata: metadata,
    );
  }

  test(
    'emits the first occurrence, suppresses in-window repeats, then one recap',
    () {
      recordDiagnostic(error: TimeoutException('Future not completed'));
      expect(collector.entries, hasLength(1));
      final ErrorLogEntry first = collector.entries.single;
      expect(first.level, ErrorLogLevel.error);
      expect(first.type, 'TimeoutException');
      expect(first.message, 'TimeoutException: Future not completed');
      expect(first.context?['backendId'], 'backend-1');
      expect(first.context?['uri'], 'http://127.0.0.1:3080');
      expect(first.context?['diagnostic_context'], 'connection.negotiate');
      expect(first.context?['suppressedRepeats'], isNull);

      now = now.add(const Duration(seconds: 10));
      recordDiagnostic(error: TimeoutException('Future not completed'));
      now = now.add(const Duration(seconds: 20));
      recordDiagnostic(error: TimeoutException('Future not completed'));
      expect(collector.entries, hasLength(1));
      expect(collector.breadcrumbs, hasLength(3));

      // Exactly one window boundary later, one recap names the two folds.
      now = now.add(const Duration(seconds: 30));
      recordDiagnostic(error: TimeoutException('Future not completed'));
      expect(collector.entries, hasLength(2));
      final ErrorLogEntry recap = collector.entries.first;
      expect(recap.level, ErrorLogLevel.error);
      expect(recap.type, 'TimeoutException');
      expect(
        recap.message,
        'TimeoutException: Future not completed (2 repeats suppressed)',
      );
      expect(recap.context?['suppressedRepeats'], 2);

      // The recap restarts the window: the next occurrence is folded again.
      recordDiagnostic(error: TimeoutException('Future not completed'));
      expect(collector.entries, hasLength(2));
    },
  );

  test('a warning carrying an error keeps warning level and its message', () {
    recordDiagnostic(
      level: ConnectionDiagnosticLevel.warning,
      message: 'event stream /api/remote.mux failed',
      error: TimeoutException('reconnect'),
    );
    expect(collector.entries, hasLength(1));
    final ErrorLogEntry first = collector.entries.single;
    expect(first.level, ErrorLogLevel.warning);
    expect(first.message, 'TimeoutException: reconnect');
    expect(
      first.context?['diagnostic_message'],
      'event stream /api/remote.mux failed',
    );

    recordDiagnostic(
      level: ConnectionDiagnosticLevel.warning,
      message: 'event stream /api/remote.mux failed',
      error: TimeoutException('reconnect'),
    );
    expect(collector.entries, hasLength(1));

    now = now.add(const Duration(seconds: 60));
    recordDiagnostic(
      level: ConnectionDiagnosticLevel.warning,
      message: 'event stream /api/remote.mux failed',
      error: TimeoutException('reconnect'),
    );
    expect(collector.entries, hasLength(2));
    expect(collector.entries.first.level, ErrorLogLevel.warning);
    expect(collector.entries.first.message, endsWith('(1 repeats suppressed)'));
    expect(collector.entries.first.context?['suppressedRepeats'], 1);
  });

  test('a warning without an error stays breadcrumb-only', () {
    recordDiagnostic(
      level: ConnectionDiagnosticLevel.warning,
      message: 'socket closed without an exception',
    );
    expect(collector.entries, isEmpty);
    expect(collector.breadcrumbs, hasLength(1));
    expect(telemetryLines, hasLength(1));
  });

  test('breadcrumbs and telemetry are never suppressed', () {
    for (int i = 0; i < 5; i++) {
      recordDiagnostic(error: TimeoutException('same failure'));
      now = now.add(const Duration(seconds: 1));
    }

    expect(collector.entries, hasLength(1));
    expect(collector.breadcrumbs, hasLength(5));
    for (final String line in collector.breadcrumbs) {
      expect(line, contains('[Connection ERROR]'));
      expect(line, isNot(contains('repeats suppressed')));
    }
    expect(telemetryLines, hasLength(5));
    expect(telemetryLines.first, startsWith('error: connection.negotiate: '));
  });

  test('distinct backends, contexts and error types never share a gate', () {
    void recordAll() {
      recordDiagnostic(backendId: 'a', error: TimeoutException('same'));
      recordDiagnostic(backendId: 'b', error: TimeoutException('same'));
      recordDiagnostic(
        backendId: 'a',
        diagnosticContext: 'connection.close',
        error: TimeoutException('same'),
      );
      recordDiagnostic(backendId: 'a', error: _AlphaFailure());
      recordDiagnostic(backendId: 'a', error: _BetaFailure());
    }

    recordAll();
    expect(collector.entries, hasLength(5));

    recordAll();
    expect(collector.entries, hasLength(5));

    now = now.add(const Duration(seconds: 60));
    recordAll();
    expect(collector.entries, hasLength(10));
    expect(
      collector.entries
          .take(5)
          .every(
            (ErrorLogEntry entry) => entry.context?['suppressedRepeats'] == 1,
          ),
      isTrue,
    );
    expect(
      collector.entries
          .take(5)
          .every(
            (ErrorLogEntry entry) =>
                entry.message.endsWith('(1 repeats suppressed)'),
          ),
      isTrue,
    );
    expect(
      collector.entries
          .skip(5)
          .every(
            (ErrorLogEntry entry) =>
                !entry.message.contains('repeats suppressed'),
          ),
      isTrue,
    );
  });

  test('only whitespace folds in the gate key', () {
    recordDiagnostic(
      message: 'Generation  handshake\nfailed',
      error: TimeoutException('x'),
    );
    recordDiagnostic(
      message: 'Generation handshake failed',
      error: TimeoutException('x'),
    );
    expect(collector.entries, hasLength(1));

    // A meaningful token stays a distinct failure.
    recordDiagnostic(
      message: 'Generation handshake failed: 401',
      error: TimeoutException('x'),
    );
    recordDiagnostic(
      message: 'Generation handshake failed: 500',
      error: TimeoutException('x'),
    );
    expect(collector.entries, hasLength(3));
  });

  test('telemetry keeps the fallback label and the warn mapping', () {
    recordDiagnostic(
      level: ConnectionDiagnosticLevel.info,
      diagnosticContext: null,
      message: 'connected',
    );
    recordDiagnostic(
      level: ConnectionDiagnosticLevel.debug,
      diagnosticContext: null,
      message: 'frame dropped',
    );
    expect(collector.entries, isEmpty);
    expect(collector.breadcrumbs, hasLength(2));
    expect(telemetryLines, <String>[
      'warn: connection: connected',
      'warn: connection: frame dropped',
    ]);
  });

  test('an operation diagnostic goes to the operations ring only', () {
    // An operation phase is evidence, not a failure, even when it arrives as
    // an error: routing is by context alone, before level and the gate.
    sink.record(
      backendId: 'backend-1',
      context: 'operation',
      message: 'resync begin',
      level: ConnectionDiagnosticLevel.error,
      error: TimeoutException('phase timing only'),
    );

    expect(collector.operations, hasLength(1));
    expect(collector.operations.single, contains('[OP] resync begin'));
    // No entry, no breadcrumb, no telemetry line: the error evidence lives in
    // the operation trail, not the error log.
    expect(collector.entries, isEmpty);
    expect(collector.breadcrumbs, isEmpty);
    expect(telemetryLines, isEmpty);
  });
}

/// Two failures that print identically but are different exception types.
final class _AlphaFailure {
  @override
  String toString() => 'event stream failed';
}

final class _BetaFailure {
  @override
  String toString() => 'event stream failed';
}
