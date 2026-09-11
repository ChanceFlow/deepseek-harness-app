import 'package:app/platform/network_status.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const EventChannel eventChannel = EventChannel(kNetworkStatusChannel);
  const MethodChannel controlChannel = MethodChannel(kNetworkStatusChannel);

  tearDown(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockStreamHandler(eventChannel, null);
    messenger.setMockMethodCallHandler(controlChannel, null);
    messenger.setMessageHandler(kNetworkStatusChannel, null);
  });

  test('delivers a default-network-available hint to listeners', () async {
    MockStreamHandlerEventSink? sink;
    var listens = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(
          eventChannel,
          MockStreamHandler.inline(
            onListen: (arguments, events) {
              listens += 1;
              sink = events;
            },
          ),
        );

    final status = NetworkStatus();
    final hints = <Object?>[];
    final subscription = status.available.listen(hints.add);
    await pumpEventQueue();
    expect(listens, 1);

    sink!.success(null);
    await pumpEventQueue();
    expect(hints, hasLength(1));

    await subscription.cancel();
    await status.dispose();
  });

  test('registers for the first listener and cancels for the last', () async {
    var listens = 0;
    var cancels = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(
          eventChannel,
          MockStreamHandler.inline(
            onListen: (arguments, events) => listens += 1,
            onCancel: (arguments) => cancels += 1,
          ),
        );

    final status = NetworkStatus();
    final first = status.available.listen((_) {});
    await pumpEventQueue();
    final second = status.available.listen((_) {});
    await pumpEventQueue();
    expect(listens, 1, reason: 'one host registration serves every listener');

    await first.cancel();
    await pumpEventQueue();
    expect(
      cancels,
      0,
      reason: 'the host callback stays registered while a listener remains',
    );

    await second.cancel();
    await pumpEventQueue();
    expect(cancels, 1);

    await status.dispose();
  });

  // The widget-test failure mode this seam has to survive: reading the host
  // channel with no platform implementation behind it. The framework answers
  // through FlutterError.reportError, so capturing that handler is the
  // assertion, not a re-encoding of the seam's own state.
  test('reports no error where no host implements the channel', () async {
    final reported = <FlutterErrorDetails>[];
    final previousHandler = FlutterError.onError;
    FlutterError.onError = reported.add;
    try {
      final status = NetworkStatus();
      final hints = <Object?>[];
      Object? error;
      final subscription = status.available.listen(
        hints.add,
        onError: (Object e) => error = e,
      );
      await pumpEventQueue();

      expect(hints, isEmpty);
      expect(error, isNull);
      expect(reported, isEmpty);

      await subscription.cancel();
      await status.dispose();
      await pumpEventQueue();
      expect(reported, isEmpty);
    } finally {
      FlutterError.onError = previousHandler;
    }
  });

  test('dispose unregisters the host callback', () async {
    var cancels = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(
          eventChannel,
          MockStreamHandler.inline(
            onListen: (arguments, events) {},
            onCancel: (arguments) => cancels += 1,
          ),
        );

    final status = NetworkStatus();
    final subscription = status.available.listen((_) {});
    await pumpEventQueue();

    await status.dispose();
    await pumpEventQueue();
    expect(cancels, 1);

    await subscription.cancel();
  });
}
