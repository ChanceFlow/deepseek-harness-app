import 'package:app/platform/disk_space.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const MethodChannel channel = MethodChannel(kDiskSpaceChannel);

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('returns the host-reported free bytes for the path', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
          expect(call.method, equals('availableBytes'));
          expect(
            (call.arguments as Map<Object?, Object?>)['path'],
            equals('/data'),
          );
          return 123456789;
        });

    expect(await freeDiskSpaceBytes('/data'), equals(123456789));
  });

  test('falls back when no host implements the channel', () async {
    expect(await freeDiskSpaceBytes('/data'), equals(kDiskSpaceFallbackBytes));
  });

  test('falls back on a host error', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
          throw PlatformException(code: 'stat_failed');
        });

    expect(await freeDiskSpaceBytes('/data'), equals(kDiskSpaceFallbackBytes));
  });

  test('falls back on a non-positive host result', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async => 0);

    expect(await freeDiskSpaceBytes('/data'), equals(kDiskSpaceFallbackBytes));
  });
}
