import 'package:app/platform/device_abi.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const MethodChannel channel = MethodChannel(kDeviceChannel);

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('returns the host-reported ABI list in priority order', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
          expect(call.method, equals('abis'));
          return <String>['arm64-v8a', 'armeabi-v7a', 'armeabi'];
        });

    expect(await deviceAbis(), <String>['arm64-v8a', 'armeabi-v7a', 'armeabi']);
  });

  test('an absent platform side yields no ABI rather than a guess', () async {
    expect(await deviceAbis(), isEmpty);
  });

  test('a host error yields no ABI', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
          throw PlatformException(code: 'unsupported');
        });

    expect(await deviceAbis(), isEmpty);
  });

  test('drops non-string entries from a malformed answer', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
          return <Object?>['arm64-v8a', 7, ''];
        });

    expect(await deviceAbis(), <String>['arm64-v8a']);
  });
}
