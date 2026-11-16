/// The previous run's operation ring: timestamped in-memory capture, bounded
/// chronological persistence beside the error log, the one-shot restore that
/// hands it to the next `process-exit:` entry, and the JSON/Markdown round trip.
library;

import 'dart:convert';
import 'dart:io';

import 'package:app/logging/error_log_collector.dart';
import 'package:app/logging/error_log_entry.dart';
import 'package:app/logging/exit_reasons.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

final RegExp _operationLine = RegExp(r'^\d{2}:\d{2}:\d{2}\.\d{3} \[OP\] ');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late File logFile;
  late File opsFile;

  ErrorLogCollector newCollector({int maxOperations = 32}) =>
      ErrorLogCollector(maxOperations: maxOperations);

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('previous_ops_test_');
    logFile = File('${tempDir.path}/${ErrorLogCollector.errorLogsFileName}');
    opsFile = File('${tempDir.path}/${ErrorLogCollector.operationsFileName}');
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('operation ring', () {
    test('appends timestamped [OP] lines, oldest first', () {
      final ErrorLogCollector collector = newCollector();

      collector
        ..addOperation('network: GET /api/session/list')
        ..addOperation('adapter: decode session/list begin');

      expect(collector.operations, hasLength(2));
      final String first = collector.operations.first;
      expect(first, matches(_operationLine));
      expect(first, endsWith('[OP] network: GET /api/session/list'));
      expect(
        collector.operations.last,
        endsWith('[OP] adapter: decode session/list begin'),
      );
      expect(
        collector.breadcrumbs,
        isEmpty,
        reason: 'operations never crowd the breadcrumb ring',
      );
      expect(() => collector.operations.add('mutate'), throwsUnsupportedError);
    });

    test('keeps the newest maxOperations entries in chronological order', () {
      final ErrorLogCollector collector = newCollector(maxOperations: 3);
      for (int i = 1; i <= 5; i++) {
        collector.addOperation('op $i');
      }

      expect(collector.operations, hasLength(3));
      expect(collector.operations[0], endsWith('[OP] op 3'));
      expect(collector.operations[1], endsWith('[OP] op 4'));
      expect(collector.operations[2], endsWith('[OP] op 5'));
    });
  });

  group('persistence', () {
    test('defers the write off the caller and coalesces a burst', () async {
      final ErrorLogCollector collector = newCollector();
      await collector.initialize(storageFile: logFile);

      collector
        ..addOperation('op one')
        ..addOperation('op two');

      expect(
        opsFile.existsSync(),
        isFalse,
        reason: 'addOperation never runs disk I/O on the caller stack',
      );

      await collector.flushPersistence();

      expect(opsFile.existsSync(), isTrue);
      final List<Object?> raw =
          jsonDecode(await opsFile.readAsString()) as List<Object?>;
      expect(raw, hasLength(2));
      expect(raw.first, endsWith('[OP] op one'));
      expect(raw.last, endsWith('[OP] op two'));
      expect(
        File('${opsFile.path}.tmp').existsSync(),
        isFalse,
        reason: 'the temp file is renamed over the target',
      );
    });

    test('a new collector restores the ring and consumes the file', () async {
      final ErrorLogCollector writer = newCollector();
      await writer.initialize(storageFile: logFile);
      writer
        ..addOperation('op one')
        ..addOperation('op two');
      await writer.flushPersistence();

      final ErrorLogCollector reader = newCollector();
      await reader.initialize(storageFile: logFile);

      expect(reader.previousOperations, writer.operations);
      expect(reader.operations, isEmpty);
      expect(
        opsFile.existsSync(),
        isFalse,
        reason: 'initialize deletes the one-shot file it consumed',
      );
    });

    test('a second initialize sees no previous operations', () async {
      final ErrorLogCollector writer = newCollector();
      await writer.initialize(storageFile: logFile);
      writer.addOperation('op one');
      await writer.flushPersistence();

      final ErrorLogCollector reader = newCollector();
      await reader.initialize(storageFile: logFile);
      expect(reader.previousOperations, hasLength(1));

      await reader.initialize(storageFile: logFile);
      expect(reader.previousOperations, isEmpty);

      final ErrorLogCollector later = newCollector();
      await later.initialize(storageFile: logFile);
      expect(later.previousOperations, isEmpty);
    });

    test('persists only the bounded tail of a long ring', () async {
      final ErrorLogCollector collector = newCollector(maxOperations: 3);
      await collector.initialize(storageFile: logFile);
      for (int i = 1; i <= 5; i++) {
        collector.addOperation('op $i');
      }

      await collector.flushPersistence();

      final List<Object?> raw =
          jsonDecode(await opsFile.readAsString()) as List<Object?>;
      expect(raw, hasLength(3));
      expect(raw.first, endsWith('[OP] op 3'));
      expect(raw.last, endsWith('[OP] op 5'));
    });

    test(
      'operations captured before initialize persist once it resolves',
      () async {
        final ErrorLogCollector collector = newCollector();
        collector.addOperation('early op');

        await collector.initialize(storageFile: logFile);
        await collector.flushPersistence();

        expect(opsFile.existsSync(), isTrue);
        final List<Object?> raw =
            jsonDecode(await opsFile.readAsString()) as List<Object?>;
        expect(raw.single, endsWith('[OP] early op'));
      },
    );

    test(
      'tolerates a malformed previous-operations file and deletes it',
      () async {
        await opsFile.writeAsString('[ "op a", 7, null, "op b" ]');

        final ErrorLogCollector collector = newCollector();
        await collector.initialize(storageFile: logFile);

        expect(collector.previousOperations, <String>['op a', 'op b']);
        expect(opsFile.existsSync(), isFalse);

        await opsFile.writeAsString('not json at all');
        final ErrorLogCollector broken = newCollector();
        await broken.initialize(storageFile: logFile);
        expect(broken.previousOperations, isEmpty);
        expect(opsFile.existsSync(), isFalse);
      },
    );

    test('a disk failure never throws from addOperation', () async {
      final File blocker = File('${tempDir.path}/not_a_directory');
      await blocker.writeAsString('a file, not a directory');
      final File blockedLogs = File(
        '${blocker.path}/${ErrorLogCollector.errorLogsFileName}',
      );
      final ErrorLogCollector collector = newCollector();
      await collector.initialize(storageFile: blockedLogs);

      expect(() => collector.addOperation('disk full'), returnsNormally);
      await collector.flushPersistence();

      expect(collector.operations, hasLength(1));
      expect(
        File('${blocker.path}/${ErrorLogCollector.operationsFileName}')
            .existsSync(),
        isFalse,
      );
    });
  });

  group('clear', () {
    test('wipes the ring, the previous ring, and both files', () async {
      final ErrorLogCollector writer = newCollector();
      await writer.initialize(storageFile: logFile);
      writer.addOperation('op one');
      await writer.flushPersistence();

      final ErrorLogCollector collector = newCollector();
      await collector.initialize(storageFile: logFile);
      expect(collector.previousOperations, hasLength(1));
      collector
        ..addBreadcrumb('breadcrumb')
        ..addOperation('op two');
      await collector.flushPersistence();
      expect(logFile.existsSync(), isFalse, reason: 'no entry was captured');
      expect(opsFile.existsSync(), isTrue);

      collector.clear();

      expect(collector.entries, isEmpty);
      expect(collector.breadcrumbs, isEmpty);
      expect(collector.operations, isEmpty);
      expect(collector.previousOperations, isEmpty);
      expect(opsFile.existsSync(), isFalse);
    });

    test(
      'clear during a pending write leaves no file and no resurrection',
      () async {
        final ErrorLogCollector collector = newCollector();
        await collector.initialize(storageFile: logFile);

        collector.addOperation('will be cleared');
        // Let the write loop start and suspend on disk I/O, then clear.
        await null;
        collector.clear();
        expect(collector.operations, isEmpty);

        await collector.flushPersistence();
        expect(opsFile.existsSync(), isFalse);
        expect(File('${opsFile.path}.tmp').existsSync(), isFalse);

        // No later turn resurrects the file from the discarded snapshot.
        await Future<void>.delayed(Duration.zero);
        expect(opsFile.existsSync(), isFalse);
      },
    );
  });

  group('ErrorLogEntry.previousOperations', () {
    test('round-trips through JSON and renders a fenced block', () {
      final ErrorLogEntry entry = ErrorLogEntry(
        id: 'err_exit_ops',
        timestamp: DateTime.utc(2026, 11, 12, 9),
        level: ErrorLogLevel.fatal,
        type: '${kProcessExitTypePrefix}anr',
        message: 'Previous process exit: anr',
        previousOperations: const <String>[
          '09:00:01.000 [OP] network: GET /api/session/list',
          '09:00:02.000 [OP] adapter: decode session/list begin',
        ],
      );

      final Map<String, Object?> json = entry.toJson();
      expect(json['previousOperations'], isA<List<Object?>>());

      final ErrorLogEntry restored = ErrorLogEntry.fromJson(json);
      expect(restored.previousOperations, entry.previousOperations);

      final String markdown = restored.toMarkdown();
      expect(markdown, contains('- **Previous Run Operations**:'));
      expect(
        markdown,
        contains(
          '```\n'
          '09:00:01.000 [OP] network: GET /api/session/list\n'
          '09:00:02.000 [OP] adapter: decode session/list begin\n'
          '```',
        ),
      );
    });

    test('an entry without previous operations omits both key and section', () {
      final ErrorLogEntry entry = ErrorLogEntry(
        id: 'err_plain',
        timestamp: DateTime.utc(2026, 11, 12, 9),
        level: ErrorLogLevel.error,
        type: 'SocketException',
        message: 'connection refused',
      );

      expect(entry.previousOperations, isEmpty);
      expect(entry.toJson().containsKey('previousOperations'), isFalse);
      expect(entry.toMarkdown(), isNot(contains('- **Previous Run')));
    });

    test('fromJson tolerates non-list and non-string members', () {
      final ErrorLogEntry mixed = ErrorLogEntry.fromJson(<String, Object?>{
        'id': 'err_mixed',
        'previousOperations': <Object?>['op a', 42, null, 'op b'],
      });
      expect(mixed.previousOperations, <String>['op a', 'op b']);

      final ErrorLogEntry wrongType = ErrorLogEntry.fromJson(<String, Object?>{
        'id': 'err_wrong',
        'previousOperations': 'not a list',
      });
      expect(wrongType.previousOperations, isEmpty);
    });
  });

  group('recordProcessExitReasons previous operations', () {
    const MethodChannel channel = MethodChannel(kDiagnosticsChannel);
    final ErrorLogCollector singleton = ErrorLogCollector.instance;
    final DateTime exitAt = DateTime.utc(2026, 11, 12, 9);
    const String packageName = 'com.deepseek.harness.app';
    const int pid = 4242;

    void mockChannel() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
            if (call.method == 'lastExitReasons') {
              return <Object?>[
                <Object?, Object?>{
                  'timestamp': exitAt.millisecondsSinceEpoch,
                  'reason': 6,
                  'description': 'Input dispatching timed out',
                  'importance': 100,
                  'status': 0,
                  'processName': packageName,
                  'pid': pid,
                  'hasTrace': false,
                  'isOwnProcess': true,
                },
              ];
            }
            return null;
          });
    }

    Future<void> seedPreviousOperations(List<String> operations) async {
      final ErrorLogCollector writer = newCollector();
      await writer.initialize(storageFile: logFile);
      for (final String operation in operations) {
        writer.addOperation(operation);
      }
      await writer.flushPersistence();
      expect(opsFile.existsSync(), isTrue);

      await singleton.initialize(storageFile: logFile);
      expect(singleton.previousOperations, hasLength(operations.length));
      expect(opsFile.existsSync(), isFalse);
    }

    setUp(() {
      singleton.clear();
    });

    tearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      singleton.clear();
      await singleton.flushPersistence();
    });

    test(
      'the process-exit entry carries the previous run operations',
      () async {
        await seedPreviousOperations(const <String>[
          'network: GET /api/session/list',
          'adapter: decode session/list begin',
        ]);
        mockChannel();

        await recordProcessExitReasons();

        expect(singleton.entries, hasLength(1));
        final ErrorLogEntry entry = singleton.entries.single;
        expect(entry.type, '${kProcessExitTypePrefix}anr');
        expect(entry.previousOperations, hasLength(2));
        expect(
          entry.previousOperations.first,
          endsWith('[OP] network: GET /api/session/list'),
        );
        expect(entry.context?['previousOperationsCount'], 2);

        final String report = singleton.formatExportReport();
        expect(report, contains('- **Previous Run Operations**:'));
        expect(report, contains('adapter: decode session/list begin'));
      },
    );

    test('an exit with no previous operations keeps today output', () async {
      await singleton.initialize(storageFile: logFile);
      mockChannel();

      await recordProcessExitReasons();

      final ErrorLogEntry entry = singleton.entries.single;
      expect(entry.previousOperations, isEmpty);
      expect(entry.context?.containsKey('previousOperationsCount'), isFalse);
      expect(entry.toJson().containsKey('previousOperations'), isFalse);
      expect(
        singleton.formatExportReport(),
        isNot(contains('- **Previous Run Operations**')),
      );
    });
  });
}
