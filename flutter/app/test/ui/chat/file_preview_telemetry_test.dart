/// File-preview telemetry test: a refused read reports its host code and path
/// through the real `DebugTelemetry` facade — the debug-build diagnostic seam
/// beside the error log. The assertion reads the OTel SDK's in-memory
/// exporter, not the facade's own ring buffer, so the facade's level mapping
/// is exercised end to end.
library;

import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart'
    show Severity;
import 'package:dartastic_opentelemetry/testing.dart';
import 'package:dev/dev.dart' show DebugTelemetry, TelemetrySettings;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/di/providers.dart' show DshBusinessException;
import 'package:app/ui/chat/file_preview_sheet.dart';

import '../../l10n_app.dart';

Future<void> _pumpRefused(
  WidgetTester tester,
  Object Function() failure,
) async {
  await tester.pumpWidget(
    l10nApp(
      home: Scaffold(
        body: FilePreviewSheet(
          sessionId: 's1',
          path: 'lib/main.dart',
          readFile: (String sessionId, String path) async => throw failure(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TestHarness harness;

  setUpAll(() async {
    harness = await maybeInitializeOtelForTest();
    DebugTelemetry.fromGlobal(
      const TelemetrySettings(
        endpoint: 'http://localhost:4318',
        serviceName: 'dsh-android',
        serviceVersion: '0.1.0-test',
      ),
    );
  });

  setUp(() => harness.clear());

  testWidgets('a refusal the app can explain reports at warn severity', (
    tester,
  ) async {
    await _pumpRefused(
      tester,
      () => DshBusinessException(
        code: 'workspace-file/not-text',
        message: '"lib/main.dart" contains NUL bytes',
      ),
    );

    final records = harness.logs.records;
    expect(records, hasLength(1));
    expect(
      records.single.body,
      'filePreview workspace-file/not-text: lib/main.dart',
    );
    expect(records.single.severityNumber, Severity.WARN);
  });

  testWidgets('an unexplained failure reports at error severity', (
    tester,
  ) async {
    await _pumpRefused(tester, () => Exception('workspaceFiles/read failed'));

    final records = harness.logs.records;
    expect(records, hasLength(1));
    expect(records.single.body, contains('lib/main.dart'));
    expect(records.single.severityNumber, Severity.ERROR);
  });
}
