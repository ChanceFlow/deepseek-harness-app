import 'package:dev/src/build_info.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('kDebugTelemetryEnabled (compile-time telemetry switch)', () {
    test('defaults to false — telemetry is opt-in', () {
      // Test runs without DSH_TELEMETRY_ENABLED; the default must keep a
      // build silent, so only an explicit
      // `--dart-define=DSH_TELEMETRY_ENABLED=true` turns reporting on.
      expect(kDebugTelemetryEnabled, isFalse);
    });

    test('an omitted define never reports implicitly', () {
      // Pins the stdlib semantics the switch relies on: reading the key
      // with no define yields the opt-out default, never a silent `true`.
      expect(const bool.fromEnvironment('DSH_TELEMETRY_ENABLED'), isFalse);
    });

    test('DebugBuildInfo keeps the version provenance fields', () {
      const info = DebugBuildInfo(
        version: '0.1.0-alpha.1',
        sourceCommit: 'abc',
      );
      expect(info.version, '0.1.0-alpha.1');
      expect(info.toResourceAttributes()['service.version'], '0.1.0-alpha.1');
      expect(info.toResourceAttributes()['deployment.environment'], 'dev');
    });
  });
}
