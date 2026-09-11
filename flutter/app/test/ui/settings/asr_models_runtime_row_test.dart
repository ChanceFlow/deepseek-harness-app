/// The ASR settings screen's on-device runtime row: install, delete, and the
/// unavailable state.
///
/// The row is the only place a reader can install the engine the offline
/// voice dock needs (the APK no longer carries it), so its copy and its
/// button states are the feature's discoverability.
library;

import 'package:app/ui/settings/asr/asr_models_controller.dart';
import 'package:app/ui/settings/asr/asr_models_screen.dart';
import 'package:asr/asr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../l10n_app.dart';

const AsrRuntimeState _missing = AsrRuntimeState(
  status: AsrRuntimeStatus.missing,
  totalBytes: 26211864,
);

const AsrRuntimeState _ready = AsrRuntimeState(
  status: AsrRuntimeStatus.ready,
  downloadedBytes: 26211864,
  totalBytes: 26211864,
);

Future<void> _pump(
  WidgetTester tester,
  AsrModelsUiState uiState,
  List<AsrModelsAction> actions,
) async {
  tester.view.physicalSize = const Size(900, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    l10nApp(
      home: AsrModelsScreen(uiState: uiState, onAction: actions.add),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a missing runtime offers the install and names its cost', (
    WidgetTester tester,
  ) async {
    final actions = <AsrModelsAction>[];
    await _pump(tester, const AsrModelsUiState(runtime: _missing), actions);

    expect(find.text('On-device engine'), findsOneWidget);
    expect(
      find.textContaining('sherpa-onnx $kSherpaOnnxVersion'),
      findsOneWidget,
    );
    expect(find.text('Install engine'), findsOneWidget);
    expect(find.text('Delete engine'), findsNothing);

    await tester.tap(find.text('Install engine'));
    expect(actions.single, isA<InstallAsrRuntimeAction>());
  });

  testWidgets('an installed runtime offers the delete instead', (
    WidgetTester tester,
  ) async {
    final actions = <AsrModelsAction>[];
    await _pump(tester, const AsrModelsUiState(runtime: _ready), actions);

    expect(find.text('Installed'), findsOneWidget);
    expect(find.text('Delete engine'), findsOneWidget);
    expect(find.text('Install engine'), findsNothing);

    await tester.tap(find.text('Delete engine'));
    expect(actions.single, isA<UninstallAsrRuntimeAction>());
  });

  testWidgets('an ABI with no published runtime cannot install', (
    WidgetTester tester,
  ) async {
    final actions = <AsrModelsAction>[];
    await _pump(
      tester,
      const AsrModelsUiState(runtime: _missing, runtimeAvailable: false),
      actions,
    );

    expect(find.text('Not available for this device'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('Install engine'),
        matching: find.byType(FilledButton),
      ),
    );
    expect(button.onPressed, isNull);
    expect(actions, isEmpty);
  });

  testWidgets('a runtime-less surface shows no row at all', (
    WidgetTester tester,
  ) async {
    await _pump(tester, const AsrModelsUiState(), <AsrModelsAction>[]);
    expect(find.text('On-device engine'), findsNothing);
  });
}
