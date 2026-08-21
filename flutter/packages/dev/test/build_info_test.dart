import 'package:dev/src/build_info.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('kDebugTelemetryEnabled (compile-time telemetry switch)', () {
    test('defaults to true so a build that forgets the define reports', () {
      // Test runs without DSH_TELEMETRY_ENABLED; the default must favour
      // reporting (the pre-release contract prefers observability over
      // silence). The release pipeline overrides it explicitly per channel.
      expect(kDebugTelemetryEnabled, isTrue);
    });

    test('DebugBuildInfo keeps the version provenance fields', () {
      const info = DebugBuildInfo(version: '0.1.0-alpha.1', sourceCommit: 'abc');
      expect(info.version, '0.1.0-alpha.1');
      expect(info.toResourceAttributes()['service.version'], '0.1.0-alpha.1');
      expect(info.toResourceAttributes()['deployment.environment'], 'dev');
    });
  });
}
