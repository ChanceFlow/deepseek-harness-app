/// The previous exit's bounded system trace: the `exitTrace` channel decode,
/// the capture path onto the recorded `process-exit:` entry, and its JSON and
/// Markdown round trip.
library;

import 'dart:async';

import 'package:app/logging/error_log_collector.dart';
import 'package:app/logging/error_log_entry.dart';
import 'package:app/logging/exit_reasons.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const MethodChannel channel = MethodChannel(kDiagnosticsChannel);
  final ErrorLogCollector collector = ErrorLogCollector.instance;
  const String packageName = 'com.deepseek.harness.app';
  const int pid = 4242;
  final DateTime exitAt = DateTime.utc(2026, 11, 12, 9);

  /// The ANR block the platform isolates for our process.
  const String ourBlock =
      '----- pid 4242 at 2026-11-12 09:00:00.000 -----\n'
      'Cmd line: com.deepseek.harness.app\n'
      '"main" prio=5 tid=1 Blocked\n'
      '  at com.deepseek.harness.app.MainActivity.onTouch(MainActivity.kt:42)\n'
      '----- end 4242 -----\n';

  late List<MethodCall> calls;

  ProcessExitReason exitRecord({bool hasTrace = true}) => ProcessExitReason(
    timestamp: exitAt,
    reason: 6,
    description: 'Input dispatching timed out',
    importance: 100,
    status: 0,
    processName: packageName,
    pid: pid,
    hasTrace: hasTrace,
  );

  Map<Object?, Object?> historyRecord({int reason = 6, bool hasTrace = true}) =>
      <Object?, Object?>{
        'timestamp': exitAt.millisecondsSinceEpoch,
        'reason': reason,
        'description': 'Input dispatching timed out',
        'importance': 100,
        'status': 0,
        'processName': packageName,
        'pid': pid,
        'hasTrace': hasTrace,
      };

  void mockChannel({
    required List<Object?> history,
    Future<Object?> Function(MethodCall call)? onExitTrace,
  }) {
    calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
          calls.add(call);
          if (call.method == 'lastExitReasons') return history;
          if (call.method == 'exitTrace') {
            return onExitTrace == null ? null : await onExitTrace(call);
          }
          return null;
        });
  }

  setUp(() {
    collector.clear();
    calls = <MethodCall>[];
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    collector.clear();
  });

  group('recordProcessExitReasons trace capture', () {
    test('records the selected exit with its bounded trace', () async {
      mockChannel(
        history: <Object?>[historyRecord()],
        onExitTrace: (MethodCall call) async => ourBlock,
      );

      await recordProcessExitReasons();

      final MethodCall traceCall = calls.firstWhere(
        (MethodCall call) => call.method == 'exitTrace',
      );
      expect(traceCall.arguments, <String, Object?>{
        'timestamp': exitAt.millisecondsSinceEpoch,
        'pid': pid,
      });

      expect(collector.entries, hasLength(1));
      final ErrorLogEntry entry = collector.entries.single;
      expect(entry.type, '${kProcessExitTypePrefix}anr');
      expect(entry.level, ErrorLogLevel.fatal);
      expect(entry.message, contains('Input dispatching timed out'));
      expect(entry.trace, ourBlock.trim());
      expect(entry.context?['traceChars'], ourBlock.trim().length);
      expect(entry.context?['traceTruncated'], isFalse);

      final String report = collector.formatExportReport();
      expect(report, contains('- **System Trace**:'));
      expect(report, contains('MainActivity.onTouch'));
      expect(report, contains('```'));
    });

    test('an exit without a readable trace records metadata only', () async {
      mockChannel(history: <Object?>[historyRecord(hasTrace: false)]);

      await recordProcessExitReasons();

      expect(
        calls.any((MethodCall call) => call.method == 'exitTrace'),
        isFalse,
      );
      final ErrorLogEntry entry = collector.entries.single;
      expect(entry.type, '${kProcessExitTypePrefix}anr');
      expect(entry.trace, isNull);
      expect(entry.context?.containsKey('traceChars'), isFalse);
      expect(entry.context?.containsKey('traceTruncated'), isFalse);
    });

    test('a deliberate exit records nothing and asks for no trace', () async {
      mockChannel(history: <Object?>[historyRecord(reason: 1)]);

      await recordProcessExitReasons();

      expect(collector.entries, isEmpty);
      expect(
        calls.any((MethodCall call) => call.method == 'exitTrace'),
        isFalse,
      );
    });

    test('a platform error on the trace read still records the exit', () async {
      mockChannel(
        history: <Object?>[historyRecord()],
        onExitTrace: (MethodCall call) async =>
            throw PlatformException(code: 'traceUnavailable'),
      );

      await expectLater(recordProcessExitReasons(), completes);

      final ErrorLogEntry entry = collector.entries.single;
      expect(entry.type, '${kProcessExitTypePrefix}anr');
      expect(entry.trace, isNull);
    });

    test('a null trace answer leaves the record as metadata only', () async {
      mockChannel(
        history: <Object?>[historyRecord()],
        onExitTrace: (MethodCall call) async => null,
      );

      await recordProcessExitReasons();

      final ErrorLogEntry entry = collector.entries.single;
      expect(entry.trace, isNull);
      expect(
        collector.formatExportReport(),
        isNot(contains('- **System Trace**:')),
      );
    });

    test('an over-cap trace is cut once and marked truncated', () async {
      final String huge = List<String>.filled(kMaxTraceChars + 500, 'x').join();
      mockChannel(
        history: <Object?>[historyRecord()],
        onExitTrace: (MethodCall call) async => huge,
      );

      await recordProcessExitReasons();

      final ErrorLogEntry entry = collector.entries.single;
      expect(entry.trace, isNotNull);
      expect(entry.trace, endsWith(kTraceTruncationMarker));
      expect(
        entry.trace!.length,
        lessThanOrEqualTo(kMaxTraceChars + kTraceTruncationMarker.length + 2),
      );
      expect(entry.context?['traceChars'], entry.trace!.length);
      expect(entry.context?['traceTruncated'], isTrue);
      final String report = collector.formatExportReport();
      expect(kTraceTruncationMarker.allMatches(report), hasLength(1));
    });

    test(
      'a platform-cut trace keeps its marker and reports truncation',
      () async {
        const String shortTrace =
            '----- pid 4242 at 2026-11-12 09:00:00.000 -----\n'
            'Cmd line: com.deepseek.harness.app\n'
            '$kTraceTruncationMarker';
        mockChannel(
          history: <Object?>[historyRecord()],
          onExitTrace: (MethodCall call) async => shortTrace,
        );

        await recordProcessExitReasons();

        final ErrorLogEntry entry = collector.entries.single;
        expect(entry.trace, contains(kTraceTruncationMarker));
        expect(entry.context?['traceTruncated'], isTrue);
      },
    );
  });

  group('readExitTrace', () {
    test('asks with the exit timestamp and pid', () async {
      mockChannel(
        history: <Object?>[],
        onExitTrace: (MethodCall call) async {
          expect(call.method, 'exitTrace');
          expect(call.arguments, <String, Object?>{
            'timestamp': exitAt.millisecondsSinceEpoch,
            'pid': pid,
          });
          return 'trace body';
        },
      );

      expect(await readExitTrace(exitRecord()), 'trace body');
    });

    test('answers null without a channel instead of throwing', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);

      expect(await readExitTrace(exitRecord()), isNull);
    });

    test('a blank platform answer is no trace', () async {
      mockChannel(
        history: <Object?>[],
        onExitTrace: (MethodCall call) async => '   \n',
      );

      expect(await readExitTrace(exitRecord()), isNull);
    });

    test('skips the channel when the record reports no trace', () async {
      mockChannel(history: <Object?>[]);

      expect(await readExitTrace(exitRecord(hasTrace: false)), isNull);
      expect(calls, isEmpty);
    });

    test('a stalled platform answer times out to null', () async {
      final Completer<Object?> never = Completer<Object?>();
      mockChannel(
        history: <Object?>[],
        onExitTrace: (MethodCall call) => never.future,
      );

      expect(
        await readExitTrace(
          exitRecord(),
          timeout: const Duration(milliseconds: 20),
        ),
        isNull,
      );
    });
  });

  group('ErrorLogEntry.trace', () {
    test('round-trips through JSON and renders a fenced block', () {
      final ErrorLogEntry entry = ErrorLogEntry(
        id: 'err_exit_trace',
        timestamp: exitAt,
        level: ErrorLogLevel.fatal,
        type: '${kProcessExitTypePrefix}anr',
        message: 'Previous process exit: anr',
        trace: ourBlock,
      );

      final Map<String, Object?> json = entry.toJson();
      expect(json['trace'], ourBlock);
      final ErrorLogEntry restored = ErrorLogEntry.fromJson(json);
      expect(restored.trace, ourBlock);

      final String markdown = restored.toMarkdown();
      expect(markdown, contains('- **System Trace**:'));
      expect(markdown, contains(ourBlock.trim()));
    });

    test('an entry without a trace omits the key and the block', () {
      final ErrorLogEntry entry = ErrorLogEntry(
        id: 'err_no_trace',
        timestamp: exitAt,
        level: ErrorLogLevel.error,
        type: '${kProcessExitTypePrefix}signaled',
        message: 'Previous process exit: signaled',
      );

      expect(entry.toJson().containsKey('trace'), isFalse);
      expect(entry.toMarkdown(), isNot(contains('- **System Trace**:')));
    });

    test('a huge trace is rendered cut once with the marker', () {
      final String huge = List<String>.filled(kMaxTraceChars + 10, 'y').join();
      final ErrorLogEntry entry = ErrorLogEntry(
        id: 'err_huge_trace',
        timestamp: exitAt,
        level: ErrorLogLevel.fatal,
        type: '${kProcessExitTypePrefix}crash-native',
        message: 'Previous process exit: crash-native',
        trace: huge,
      );

      final String markdown = entry.toMarkdown();
      expect(kTraceTruncationMarker.allMatches(markdown), hasLength(1));
      expect(markdown.length, lessThan(kMaxTraceChars + 1000));
    });

    test('a trace already stored at the cap does not double the marker', () {
      final String stored = renderableTrace(
        List<String>.filled(kMaxTraceChars + 10, 'z').join(),
      );
      final ErrorLogEntry entry = ErrorLogEntry(
        id: 'err_stored_trace',
        timestamp: exitAt,
        level: ErrorLogLevel.fatal,
        type: '${kProcessExitTypePrefix}crash',
        message: 'Previous process exit: crash',
        trace: stored,
      );

      final String markdown = entry.toMarkdown();
      expect(kTraceTruncationMarker.allMatches(markdown), hasLength(1));
      expect(isTraceTruncated(stored), isTrue);
    });
  });
}
