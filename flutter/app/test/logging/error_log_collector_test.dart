import 'dart:io';

import 'package:app/logging/error_log_collector.dart';
import 'package:app/logging/error_log_entry.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('error_log_test_');
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('ErrorLogEntry', () {
    test('round-trips through JSON serialization', () {
      final DateTime now = DateTime.utc(2026, 8, 20, 14, 30, 45, 123);
      final ErrorLogEntry entry = ErrorLogEntry(
        id: 'err_test_1',
        timestamp: now,
        level: ErrorLogLevel.fatal,
        type: 'TestCrashException',
        message: 'Something crashed fatally',
        stackTrace: '#0 main.dart:42',
        context: <String, Object?>{
          'sessionId': 'sess_123',
          'host': '127.0.0.1',
        },
        breadcrumbs: <String>[
          '14:30:40 [INFO] app start',
          '14:30:44 [WARN] slow query',
        ],
      );

      final Map<String, Object?> json = entry.toJson();
      final ErrorLogEntry restored = ErrorLogEntry.fromJson(json);

      expect(restored.id, 'err_test_1');
      expect(restored.timestamp, now);
      expect(restored.level, ErrorLogLevel.fatal);
      expect(restored.type, 'TestCrashException');
      expect(restored.message, 'Something crashed fatally');
      expect(restored.stackTrace, '#0 main.dart:42');
      expect(restored.context?['sessionId'], 'sess_123');
      expect(restored.context?['host'], '127.0.0.1');
      expect(restored.breadcrumbs, hasLength(2));
    });

    test('fromFlutterError captures details and context', () {
      final FlutterErrorDetails details = FlutterErrorDetails(
        exception: const FormatException('Bad JSON format'),
        stack: StackTrace.fromString('#0 parser.dart:10'),
        context: DiagnosticsNode.message('during layout'),
      );

      final ErrorLogEntry entry = ErrorLogEntry.fromFlutterError(
        details,
        id: 'err_flt',
        breadcrumbs: <String>['14:00:00 [INFO] step 1'],
        context: <String, Object?>{'screen': 'Chat'},
      );

      expect(entry.id, 'err_flt');
      expect(entry.level, ErrorLogLevel.fatal);
      expect(entry.type, contains('FlutterError'));
      expect(entry.message, contains('Bad JSON format'));
      expect(entry.stackTrace, contains('#0 parser.dart:10'));
      expect(entry.context?['screen'], 'Chat');
      expect(entry.breadcrumbs, <String>['14:00:00 [INFO] step 1']);
    });

    test('toMarkdown produces readable formatted markdown', () {
      final ErrorLogEntry entry = ErrorLogEntry(
        id: 'err_md',
        timestamp: DateTime(2026, 8, 20, 12, 0, 0),
        level: ErrorLogLevel.error,
        type: 'HttpException',
        message: '404 Not Found',
        stackTrace: '#0 client.dart:99',
        context: <String, Object?>{'url': 'http://example.com'},
        breadcrumbs: <String>['request started'],
      );

      final String md = entry.toMarkdown();
      expect(md, contains('### [ERROR] HttpException'));
      expect(md, contains('- **Message**: 404 Not Found'));
      expect(md, contains('`url`: http://example.com'));
      expect(md, contains('request started'));
      expect(md, contains('#0 client.dart:99'));
    });
  });

  group('ErrorLogCollector', () {
    test('captures error and prepends newest first', () {
      final ErrorLogCollector collector = ErrorLogCollector(maxEntries: 10);
      collector.captureError(
        'First error',
        level: ErrorLogLevel.error,
        type: 'ErrorA',
      );
      collector.captureError(
        'Second error',
        level: ErrorLogLevel.fatal,
        type: 'ErrorB',
      );

      expect(collector.entries, hasLength(2));
      expect(collector.entries.first.message, 'Second error');
      expect(collector.entries.first.level, ErrorLogLevel.fatal);
      expect(collector.entries.last.message, 'First error');
    });

    test('respects maxEntries capacity limit by dropping oldest', () {
      final ErrorLogCollector collector = ErrorLogCollector(maxEntries: 3);
      for (int i = 1; i <= 5; i++) {
        collector.captureError('Error $i');
      }

      expect(collector.entries, hasLength(3));
      expect(collector.entries[0].message, 'Error 5');
      expect(collector.entries[1].message, 'Error 4');
      expect(collector.entries[2].message, 'Error 3');
    });

    test('records and trims breadcrumbs', () {
      final ErrorLogCollector collector = ErrorLogCollector(
        maxEntries: 10,
        maxBreadcrumbs: 3,
      );
      collector.addBreadcrumb('action 1');
      collector.addBreadcrumb('action 2');
      collector.addBreadcrumb('action 3');
      collector.addBreadcrumb('action 4');

      expect(collector.breadcrumbs, hasLength(3));
      expect(collector.breadcrumbs.any((b) => b.contains('action 1')), isFalse);
      expect(collector.breadcrumbs.any((b) => b.contains('action 4')), isTrue);

      collector.captureError('Error with breadcrumbs');
      expect(collector.entries.first.breadcrumbs, hasLength(3));
    });

    test('persists to file and initializes from existing file', () async {
      final File logFile = File('${tempDir.path}/error_logs.json');
      final ErrorLogCollector collector1 = ErrorLogCollector(maxEntries: 50);
      await collector1.initialize(storageFile: logFile);

      collector1.captureError(
        'Persisted error 1',
        level: ErrorLogLevel.warning,
        type: 'WarnType',
      );
      collector1.captureError(
        'Persisted error 2',
        level: ErrorLogLevel.error,
        type: 'ErrType',
      );

      expect(logFile.existsSync(), isTrue);

      // Create a fresh collector instance reading from the same file
      final ErrorLogCollector collector2 = ErrorLogCollector(maxEntries: 50);
      await collector2.initialize(storageFile: logFile);

      expect(collector2.entries, hasLength(2));
      expect(collector2.entries.first.message, 'Persisted error 2');
      expect(collector2.entries.last.message, 'Persisted error 1');
    });

    test('clear() wipes memory and deletes persistent file', () async {
      final File logFile = File('${tempDir.path}/error_logs.json');
      final ErrorLogCollector collector = ErrorLogCollector(maxEntries: 10);
      await collector.initialize(storageFile: logFile);

      collector.captureError('Will be cleared');
      expect(collector.entries, hasLength(1));
      expect(logFile.existsSync(), isTrue);

      collector.clear();
      expect(collector.entries, isEmpty);
      expect(logFile.existsSync(), isFalse);
    });

    test('formatExportReport generates comprehensive markdown report', () {
      final ErrorLogCollector collector = ErrorLogCollector();
      collector.captureError(
        'Database locked',
        level: ErrorLogLevel.error,
        type: 'SqliteException',
      );

      final String report = collector.formatExportReport(
        activeBackendUrl: 'http://127.0.0.1:3080',
      );

      expect(report, contains('# DSH Mobile Error & Diagnostic Report'));
      expect(report, contains('## System Information'));
      expect(report, contains('**Active Host**: http://127.0.0.1:3080'));
      expect(report, contains('**Total Recorded Errors**: 1'));
      expect(report, contains('Database locked'));
    });

    test('installHooks and dispose toggle hook status safely', () {
      final ErrorLogCollector collector = ErrorLogCollector();
      expect(collector.areHooksInstalled, isFalse);

      collector.installHooks();
      expect(collector.areHooksInstalled, isTrue);

      // Idempotent
      collector.installHooks();
      expect(collector.areHooksInstalled, isTrue);

      collector.dispose();
      expect(collector.areHooksInstalled, isFalse);
    });
  });
}
