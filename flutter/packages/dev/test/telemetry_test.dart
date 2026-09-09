import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart'
    show Severity;
import 'package:dartastic_opentelemetry/testing.dart';
import 'package:dev/src/build_info.dart';
import 'package:dev/src/crash_record.dart';
import 'package:dev/src/telemetry.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TestHarness harness;
  late DebugTelemetry telemetry;

  setUpAll(() async {
    harness = await maybeInitializeOtelForTest();
    telemetry = DebugTelemetry.fromGlobal(
      const TelemetrySettings(
        endpoint: 'http://localhost:4318',
        serviceName: 'dsh-android',
        serviceVersion: '0.1.0-test',
      ),
    );
  });

  setUp(() => harness.clear());

  test('log records flow through the real SDK with the mapped severity', () {
    telemetry.log('warn message', level: 'warn', attributes: const {'k': 'v'});
    telemetry.log('error message', level: 'error');
    // SimpleLogRecordProcessor exports synchronously through the in-memory
    // exporter; no timer involved.
    expect(harness.logs.records, hasLength(2));
    expect(harness.logs.records[0].body, 'warn message');
    expect(harness.logs.records[0].severityNumber, Severity.WARN);
    expect(harness.logs.records[1].severityNumber, Severity.ERROR);
  });

  test('event records carry the event name', () {
    telemetry.event('app.start', attributes: const {'version': '0.1.0'});
    expect(harness.logs.records, hasLength(1));
    expect(harness.logs.records.single.eventName, 'app.start');
    expect(harness.logs.records.single.severityNumber, Severity.INFO);
  });

  test('counters and histograms export through the metric reader', () async {
    telemetry.count('app.op.count', 3);
    telemetry.record('app.op.dur_ms', 12.5);
    telemetry.record('app.op.dur_ms', 7.5);
    await harness.collectMetrics();
    expect(harness.metrics.findMetricByName('app.op.count'), isNotNull);
    expect(harness.metrics.findMetricByName('app.op.dur_ms'), isNotNull);
  });

  test('disable switch silences the facade', () {
    final off = DebugTelemetry.fromGlobal(
      const TelemetrySettings(
        endpoint: 'http://localhost:4318',
        enabled: false,
      ),
    );
    off.log('silenced');
    off.event('app.start');
    off.count('app.op.count', 1);
    expect(harness.logs.records, isEmpty);
  });

  test('debugPrint outputs log, event, and reportCrash in debug mode', () {
    final printed = <String>[];
    final originalDebugPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) printed.add(message);
    };
    try {
      telemetry.log(
        'hello from test',
        level: 'info',
        attributes: const {'env': 'test'},
      );
      expect(
        printed.any((l) => l.contains('[INFO] hello from test {env: test}')),
        isTrue,
      );

      telemetry.event('test.event', attributes: const {'foo': 'bar'});
      expect(
        printed.any((l) => l.contains('[EVENT] test.event {foo: bar}')),
        isTrue,
      );

      final record = CrashRecord(
        crash: CapturedCrash(
          kind: 'FlutterError',
          type: 'StateError',
          message: 'fatal crash',
          stackFrames: const ['#0 main', '#1 run'],
          occurredAt: DateTime.utc(2026, 8, 21),
        ),
        build: const DebugBuildInfo(),
        device: 'Pixel 9',
        dshBaseUrl: '',
        sessionId: '',
        logs: const ['log1'],
      );
      telemetry.reportCrash(record);
      expect(
        printed.any((l) => l.contains('*** CRASH REPORT [FlutterError] ***')),
        isTrue,
      );
      expect(printed.any((l) => l.contains('fatal crash')), isTrue);
      expect(printed.any((l) => l.contains('#0 main')), isTrue);
    } finally {
      debugPrint = originalDebugPrint;
    }
  });

  test('localFallback works standalone without remote OTel', () {
    final local = DebugTelemetry.localFallback(
      const TelemetrySettings(
        endpoint: 'http://invalid.host:9999',
        serviceName: 'dsh-android',
      ),
    );
    expect(local.isLocalFallback, isTrue);

    // Logs and events append to buffer
    local.log('local message', level: 'warn');
    local.event('local.event');
    expect(local.buffer.length, 2);
    expect(local.buffer.snapshot()[0], contains('WARN local message'));
    expect(local.buffer.snapshot()[1], contains('EVENT local.event'));

    // Metrics operations do not throw
    expect(() => local.count('local.count', 1), returnsNormally);
    expect(() => local.record('local.hist', 1.0), returnsNormally);
    expect(() => local.setGauge('local.gauge', 60.0), returnsNormally);

    // Crash reporting does not throw
    final record = CrashRecord(
      crash: CapturedCrash(
        kind: 'uncaught-async',
        type: 'StateError',
        message: 'local crash',
        occurredAt: DateTime.utc(2026, 8, 21),
      ),
      build: const DebugBuildInfo(),
      device: 'Pixel 9',
      dshBaseUrl: '',
      sessionId: '',
      logs: const [],
    );
    expect(() => local.reportCrash(record), returnsNormally);
  });
}
