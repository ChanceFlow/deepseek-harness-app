/// Battery-optimization settings tests — the UDF controller and the real
/// Settings surface with a fake platform bridge.
library;

import 'dart:async';
import 'dart:io';

import 'package:app/backends/backend_store.dart';
import 'package:app/config.dart';
import 'package:app/di/providers.dart';
import 'package:app/local_state/local_state_providers.dart';
import 'package:app/local_state/local_state_store.dart';
import 'package:app/ui/settings/battery_optimization_section.dart';
import 'package:app/ui/settings/settings_screen.dart';
import 'package:app/ui/settings/settings_ui_state.dart';
import 'package:app/ui/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../l10n_app.dart';

class _FakeBatteryBridge extends BatteryOptimizationBridge {
  _FakeBatteryBridge({
    this.statusValue = BatteryOptimizationStatus.notExempt,
    this.requestOpens = true,
  });

  BatteryOptimizationStatus statusValue;
  bool requestOpens;
  int statusReads = 0;
  int requestCount = 0;

  @override
  Future<BatteryOptimizationStatus> status() async {
    statusReads++;
    return statusValue;
  }

  @override
  Future<bool> requestExemption() async {
    requestCount++;
    if (requestOpens) statusValue = BatteryOptimizationStatus.exempt;
    return requestOpens;
  }
}

class _FakeRpc implements DshRpcClient {
  @override
  Future<RpcResult> call(
    String endpoint,
    String method,
    JsonMap payload, {
    Duration? timeout,
  }) async {
    return RpcResult(ok: true, value: <String, Object?>{});
  }

  @override
  Future<void> respond(String rpcId, RpcResult result) async {}
}

/// A socket that opens and stays silent: the connection never finishes its
/// handshake, so no reconnect loop churns under the widget test.
class _QuietSocket implements DshEventSocket {
  final StreamController<ServerRequest> _frames =
      StreamController<ServerRequest>.broadcast();

  @override
  Stream<ServerRequest> connect(String path, {void Function()? onOpen}) {
    onOpen?.call();
    return _frames.stream;
  }
}

File _storeFile() {
  final Directory directory = Directory.systemTemp.createTempSync(
    'battery_settings_test',
  );
  addTearDown(() => directory.deleteSync(recursive: true));
  return File('${directory.path}/local_state.json');
}

BackendStore _backendStore() {
  final Directory directory = Directory.systemTemp.createTempSync(
    'battery_backends_test',
  );
  addTearDown(() => directory.deleteSync(recursive: true));
  return BackendStore(
    File('${directory.path}/backends.json'),
    seedBaseUrl: kDshBaseUrl,
  );
}

Future<void> _pumpSettings(
  WidgetTester tester,
  BatteryOptimizationBridge bridge, {
  ThemeData? theme,
}) async {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        batteryOptimizationBridgeProvider.overrideWithValue(bridge),
        localStateStoreProvider.overrideWith(
          (Ref ref) async => LocalStateStore(_storeFile()),
        ),
        backendStoreProvider.overrideWith((Ref ref) async => _backendStore()),
        dshRpcClientProvider(Uri.parse(kDshBaseUrl))
            .overrideWithValue(_FakeRpc()),
        dshEventSocketProvider(Uri.parse(kDshBaseUrl))
            .overrideWithValue(_QuietSocket()),
      ],
      child: l10nApp(
        theme: theme,
        home: SettingsScreen(
          uiState: const SettingsUiState(),
          onAction: (SettingsAction _) {},
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  // Past MaterialApp's theme lerp, so a second pump with the other
  // brightness reads the resolved scheme rather than the blend.
  await tester.pump(DshMotion.durationMedium);
}

final Finder _rowFinder = find.byType(SettingsBatteryOptimizationRow);

void main() {
  test('refresh publishes the bridge standing', () async {
    final bridge = _FakeBatteryBridge();
    final controller = BatteryOptimizationController(bridge: bridge);
    addTearDown(controller.dispose);

    await pumpEventQueue();

    expect(controller.state.status, BatteryOptimizationStatus.notExempt);
    expect(controller.state.requestFailed, isFalse);
  });

  test('an app lifecycle change re-reads the standing', () async {
    final bridge = _FakeBatteryBridge();
    final lifecycle = StreamController<void>.broadcast();
    addTearDown(lifecycle.close);
    final controller = BatteryOptimizationController(
      bridge: bridge,
      lifecycleChanges: lifecycle.stream,
    );
    addTearDown(controller.dispose);
    await pumpEventQueue();
    expect(controller.state.status, BatteryOptimizationStatus.notExempt);

    bridge.statusValue = BatteryOptimizationStatus.exempt;
    lifecycle.add(null);
    await pumpEventQueue();

    expect(controller.state.status, BatteryOptimizationStatus.exempt);
    expect(bridge.statusReads, greaterThanOrEqualTo(2));
  });

  test('a resolved request re-reads and settles exempt', () async {
    final bridge = _FakeBatteryBridge();
    final controller = BatteryOptimizationController(bridge: bridge);
    addTearDown(controller.dispose);
    await pumpEventQueue();

    expect(await controller.requestExemption(), isTrue);

    expect(bridge.requestCount, 1);
    expect(controller.state.status, BatteryOptimizationStatus.exempt);
    expect(controller.state.requestFailed, isFalse);
  });

  test(
    'an unresolved request states the failure and keeps the state',
    () async {
      final bridge = _FakeBatteryBridge(requestOpens: false);
      final controller = BatteryOptimizationController(bridge: bridge);
      addTearDown(controller.dispose);
      await pumpEventQueue();

      expect(await controller.requestExemption(), isFalse);

      expect(controller.state.status, BatteryOptimizationStatus.notExempt);
      expect(controller.state.requestFailed, isTrue);
    },
  );

  testWidgets('the not-exempted row states it and requests the exemption', (
    WidgetTester tester,
  ) async {
    final bridge = _FakeBatteryBridge();
    await _pumpSettings(tester, bridge);

    expect(find.text('Background connection'), findsOneWidget);
    expect(find.textContaining('Android can suspend'), findsOneWidget);
    final Finder button = find.descendant(
      of: _rowFinder,
      matching: find.widgetWithText(OutlinedButton, 'Allow'),
    );
    expect(button, findsOneWidget);

    await tester.tap(button);
    await tester.pump();
    await tester.pump();

    expect(bridge.requestCount, 1);
    expect(
      find.textContaining('Background running is allowed'),
      findsOneWidget,
    );
    expect(
      find.descendant(of: _rowFinder, matching: find.byType(OutlinedButton)),
      findsNothing,
    );
  });

  testWidgets('the exempted row is settled copy with no control', (
    WidgetTester tester,
  ) async {
    final bridge = _FakeBatteryBridge(
      statusValue: BatteryOptimizationStatus.exempt,
    );
    await _pumpSettings(tester, bridge);

    expect(find.text('Background connection'), findsOneWidget);
    expect(
      find.textContaining('Background running is allowed'),
      findsOneWidget,
    );
    expect(find.textContaining('Android can suspend'), findsNothing);
    expect(
      find.descendant(of: _rowFinder, matching: find.byType(OutlinedButton)),
      findsNothing,
    );
  });

  testWidgets('a host without the bridge renders no row', (
    WidgetTester tester,
  ) async {
    final bridge = _FakeBatteryBridge(
      statusValue: BatteryOptimizationStatus.unsupported,
    );
    await _pumpSettings(tester, bridge);

    expect(find.text('Background connection'), findsNothing);
    expect(
      find.descendant(of: _rowFinder, matching: find.byType(OutlinedButton)),
      findsNothing,
    );
  });

  testWidgets('the standing glyphs take the warning and success roles', (
    WidgetTester tester,
  ) async {
    for (final ThemeData theme in <ThemeData>[
      DshTheme.light(),
      DshTheme.dark(),
    ]) {
      await _pumpSettings(tester, _FakeBatteryBridge(), theme: theme);
      final Icon warning = tester.widget<Icon>(
        find.descendant(
          of: _rowFinder,
          matching: find.byIcon(Icons.warning_amber_rounded),
        ),
      );
      expect(warning.color, theme.colorScheme.warning);

      await _pumpSettings(
        tester,
        _FakeBatteryBridge(statusValue: BatteryOptimizationStatus.exempt),
        theme: theme,
      );
      final Icon allowed = tester.widget<Icon>(
        find.descendant(
          of: _rowFinder,
          matching: find.byIcon(Icons.check_circle_outline),
        ),
      );
      expect(allowed.color, theme.colorScheme.success);
    }
  });
}
