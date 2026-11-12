/// Process-exit attribution: the reason vocabulary, the abnormal-exit filter,
/// the newest-unreported selection, and the platform-channel decode.
library;

import 'package:app/logging/error_log_entry.dart';
import 'package:app/logging/exit_reasons.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const MethodChannel channel = MethodChannel(kDiagnosticsChannel);

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  ProcessExitReason exit(int reason, {DateTime? at}) => ProcessExitReason(
    timestamp: at ?? DateTime.utc(2026, 11, 12, 9),
    reason: reason,
    description: null,
    importance: 400,
    status: 0,
    processName: 'com.deepseek.harness.app',
  );

  ErrorLogEntry recordedExit(String name, DateTime at) => ErrorLogEntry(
    id: 'err_$name',
    timestamp: at,
    level: ErrorLogLevel.error,
    type: '$kProcessExitTypePrefix$name',
    message: '',
  );

  group('processExitReasonName', () {
    test('names every ApplicationExitInfo constant', () {
      const Map<int, String> names = <int, String>{
        0: 'unknown',
        1: 'exit-self',
        2: 'signaled',
        3: 'low-memory',
        4: 'crash',
        5: 'crash-native',
        6: 'anr',
        7: 'initialization-failure',
        8: 'permission-change',
        9: 'excessive-resource-usage',
        10: 'user-requested',
        11: 'user-stopped',
        12: 'dependency-died',
        13: 'other',
        14: 'freezer',
        15: 'package-state-change',
        16: 'package-updated',
      };
      for (final MapEntry<int, String> entry in names.entries) {
        expect(processExitReasonName(entry.key), entry.value);
      }
    });

    test('keeps an unknown constant numeric instead of guessing', () {
      expect(processExitReasonName(99), 'reason-99');
      expect(processExitReasonName(-1), 'reason--1');
    });
  });

  group('isAbnormalExit', () {
    test('treats deliberate exits as normal', () {
      for (final int reason in <int>[1, 10, 11, 15, 16]) {
        expect(isAbnormalExit(exit(reason)), isFalse, reason: '$reason');
      }
    });

    test('treats every other reported exit as abnormal', () {
      for (final int reason in <int>[0, 2, 3, 4, 5, 6, 7, 8, 9, 12, 13, 14]) {
        expect(isAbnormalExit(exit(reason)), isTrue, reason: '$reason');
      }
    });
  });

  group('exitReasonLevel', () {
    test('low-memory, signaled and other are warnings', () {
      for (final int reason in <int>[2, 3, 13]) {
        expect(
          exitReasonLevel(reason),
          ErrorLogLevel.warning,
          reason: '$reason',
        );
      }
    });

    test('native crash, ANR and initialization failure are fatal', () {
      for (final int reason in <int>[5, 6, 7]) {
        expect(exitReasonLevel(reason), ErrorLogLevel.fatal, reason: '$reason');
      }
    });

    test('the remaining reasons are errors', () {
      for (final int reason in <int>[0, 4, 8, 9, 12, 14]) {
        expect(exitReasonLevel(reason), ErrorLogLevel.error, reason: '$reason');
      }
    });
  });

  group('ProcessExitReason.fromMap', () {
    test('decodes a complete platform map', () {
      final ProcessExitReason decoded = ProcessExitReason.fromMap(
        <Object?, Object?>{
          'timestamp': 1762920000000,
          'reason': 5,
          'description': 'native crash in RenderThread',
          'importance': 400,
          'status': 11,
          'processName': 'com.deepseek.harness.app',
        },
      );

      expect(
        decoded.timestamp,
        DateTime.fromMillisecondsSinceEpoch(1762920000000, isUtc: true),
      );
      expect(decoded.reason, 5);
      expect(decoded.description, 'native crash in RenderThread');
      expect(decoded.importance, 400);
      expect(decoded.status, 11);
      expect(decoded.processName, 'com.deepseek.harness.app');
    });

    test('tolerates missing and mistyped fields', () {
      final ProcessExitReason decoded = ProcessExitReason.fromMap(
        <Object?, Object?>{
          'timestamp': 'yesterday',
          'reason': 'crash',
          'description': 7,
          'importance': 'high',
          'status': null,
          'processName': false,
        },
      );

      expect(
        decoded.timestamp,
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      );
      expect(decoded.reason, 0);
      expect(decoded.description, isNull);
      expect(decoded.importance, 0);
      expect(decoded.status, 0);
      expect(decoded.processName, isNull);
    });
  });

  group('newestUnreportedExit', () {
    test('answers null without reasons', () {
      expect(
        newestUnreportedExit(const <ProcessExitReason>[], const []),
        isNull,
      );
    });

    test('answers null when every exit was deliberate', () {
      final List<ProcessExitReason> reasons = <ProcessExitReason>[
        for (final int reason in <int>[1, 10, 11, 15, 16]) exit(reason),
      ];
      expect(newestUnreportedExit(reasons, const []), isNull);
    });

    test('picks the newest abnormal exit regardless of list order', () {
      final DateTime early = DateTime.utc(2026, 11, 12, 8);
      final DateTime middle = DateTime.utc(2026, 11, 12, 9);
      final DateTime late = DateTime.utc(2026, 11, 12, 10);
      final List<ProcessExitReason> reasons = <ProcessExitReason>[
        exit(4, at: middle),
        exit(3, at: late),
        exit(6, at: early),
      ];

      expect(newestUnreportedExit(reasons, const [])?.timestamp, late);
    });

    test('skips an exit at or before the newest recorded one', () {
      final DateTime recorded = DateTime.utc(2026, 11, 12, 9);
      final List<ProcessExitReason> reasons = <ProcessExitReason>[
        exit(4, at: DateTime.utc(2026, 11, 12, 8)),
        exit(4, at: recorded),
      ];

      expect(
        newestUnreportedExit(reasons, <ErrorLogEntry>[
          recordedExit('crash', recorded),
        ]),
        isNull,
      );
    });

    test('records an exit strictly newer than the newest record', () {
      final DateTime recorded = DateTime.utc(2026, 11, 12, 9);
      final DateTime newer = DateTime.utc(2026, 11, 12, 10);
      final ProcessExitReason unreported = exit(3, at: newer);

      expect(
        newestUnreportedExit(
          <ProcessExitReason>[exit(4, at: recorded), unreported],
          <ErrorLogEntry>[recordedExit('crash', recorded)],
        ),
        same(unreported),
      );
    });

    test('takes the cutoff from the newest process-exit record only', () {
      final DateTime recordEarly = DateTime.utc(2026, 11, 12, 7);
      final DateTime recordLate = DateTime.utc(2026, 11, 12, 9);
      final DateTime exitTime = DateTime.utc(2026, 11, 12, 8);
      final ErrorLogEntry unrelated = ErrorLogEntry(
        id: 'err_socket',
        timestamp: DateTime.utc(2026, 11, 12, 12),
        level: ErrorLogLevel.error,
        type: 'SocketException',
        message: '',
      );

      expect(
        newestUnreportedExit(
          <ProcessExitReason>[exit(4, at: exitTime)],
          <ErrorLogEntry>[
            recordedExit('anr', recordEarly),
            unrelated,
            recordedExit('crash', recordLate),
          ],
        ),
        isNull,
      );
    });
  });

  group('readProcessExitReasons', () {
    test('decodes the native lastExitReasons list', () async {
      const List<Object?> payload = <Object?>[
        <Object?, Object?>{
          'timestamp': 1762920000000,
          'reason': 5,
          'description': 'native crash in RenderThread',
          'importance': 400,
          'status': 11,
          'processName': 'com.deepseek.harness.app',
        },
        <Object?, Object?>{'reason': 3},
      ];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
            expect(call.method, 'lastExitReasons');
            expect(call.arguments, isNull);
            return payload;
          });

      final List<ProcessExitReason> reasons = await readProcessExitReasons();

      expect(reasons, hasLength(2));
      expect(reasons.first.timestamp.millisecondsSinceEpoch, 1762920000000);
      expect(reasons.first.reason, 5);
      expect(reasons.first.description, 'native crash in RenderThread');
      expect(reasons.first.importance, 400);
      expect(reasons.first.status, 11);
      expect(reasons.first.processName, 'com.deepseek.harness.app');
      expect(reasons.last.reason, 3);
      expect(reasons.last.description, isNull);
    });

    test('an absent channel yields no reasons instead of throwing', () async {
      expect(await readProcessExitReasons(), isEmpty);
    });
  });
}
