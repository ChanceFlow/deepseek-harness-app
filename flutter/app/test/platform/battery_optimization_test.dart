/// Battery-optimization seam tests — the channel contract and its
/// non-throwing fallbacks.
library;

import 'package:app/platform/battery_optimization.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const MethodChannel channel = MethodChannel(kBatteryOptimizationChannel);

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('a true host answer reads as exempt', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
          expect(call.method, equals('isIgnoringBatteryOptimizations'));
          return true;
        });

    expect(
      await const BatteryOptimizationBridge().status(),
      BatteryOptimizationStatus.exempt,
    );
  });

  test('a false host answer reads as not exempt', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async => false);

    expect(
      await const BatteryOptimizationBridge().status(),
      BatteryOptimizationStatus.notExempt,
    );
  });

  test('a missing channel reads as unsupported', () async {
    expect(
      await const BatteryOptimizationBridge().status(),
      BatteryOptimizationStatus.unsupported,
    );
  });

  test('a host error reads as unsupported instead of throwing', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
          throw PlatformException(code: 'power_manager_failed');
        });

    expect(
      await const BatteryOptimizationBridge().status(),
      BatteryOptimizationStatus.unsupported,
    );
  });

  test('a resolved request reports that it opened', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
          expect(call.method, equals('requestIgnoreBatteryOptimizations'));
          return true;
        });

    expect(await const BatteryOptimizationBridge().requestExemption(), isTrue);
  });

  test('an unresolved request reports that nothing opened', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async => false);

    expect(await const BatteryOptimizationBridge().requestExemption(), isFalse);
  });

  test('a missing channel reports that nothing opened', () async {
    expect(await const BatteryOptimizationBridge().requestExemption(), isFalse);
  });

  test(
    'a host error reports that nothing opened instead of throwing',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
            throw PlatformException(code: 'no_activity');
          });

      expect(
        await const BatteryOptimizationBridge().requestExemption(),
        isFalse,
      );
    },
  );
}
