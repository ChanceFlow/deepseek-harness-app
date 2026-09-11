/// Keep-alive platform seam tests: the channel method names, the copy the
/// host receives, and the two failure shapes the coordinator distinguishes
/// (a refused start versus a host with no channel at all).
library;

import 'package:app/platform/keep_alive_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const MethodChannel channel = MethodChannel(kKeepAliveChannel);
  const KeepAliveNotificationCopy copy = KeepAliveNotificationCopy(
    title: 'Title',
    text: 'Body',
    channelName: 'Channel',
    channelDescription: 'Description',
  );

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('start forwards the resolved copy to the host', () async {
    MethodCall? seen;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
          seen = call;
          return null;
        });

    await const KeepAliveService().start(copy);

    expect(seen?.method, equals('start'));
    expect(seen?.arguments, equals(copy.toMap()));
  });

  test('stop asks the host to tear the service down', () async {
    final List<String> methods = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
          methods.add(call.method);
          return null;
        });

    await const KeepAliveService().stop();

    expect(methods, equals(<String>['stop']));
  });

  test('a refused start surfaces as a PlatformException', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
          throw PlatformException(code: 'start_refused', message: 'denied');
        });

    await expectLater(
      const KeepAliveService().start(copy),
      throwsA(isA<PlatformException>()),
    );
  });

  test('a host without the channel surfaces as MissingPluginException', () {
    expect(
      const KeepAliveService().start(copy),
      throwsA(isA<MissingPluginException>()),
    );
  });
}
