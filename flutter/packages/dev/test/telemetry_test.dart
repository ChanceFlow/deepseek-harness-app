import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart'
    show Severity;
import 'package:dartastic_opentelemetry/testing.dart';
import 'package:dev/src/telemetry.dart';
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
}