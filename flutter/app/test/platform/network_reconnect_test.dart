/// Network-reconnect binder tests: one hint requests exactly one reconnect,
/// listening is idempotent, and a disposed binder stops listening (which is
/// also the path that unregisters the host's connectivity callback).
library;

import 'dart:async';

import 'package:app/platform/network_reconnect.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('start is idempotent and each hint requests one reconnect', () async {
    final StreamController<void> hints = StreamController<void>.broadcast();
    var reconnects = 0;
    final binder = NetworkReconnectBinder(
      available: hints.stream,
      reconnectAll: () => reconnects += 1,
    );

    binder.start();
    binder.start();
    expect(binder.isListening, isTrue);
    expect(reconnects, 0);

    hints.add(null);
    await pumpEventQueue();
    expect(reconnects, 1);

    hints.add(null);
    await pumpEventQueue();
    expect(reconnects, 2);

    binder.dispose();
    await pumpEventQueue();
    expect(binder.isListening, isFalse);

    hints.add(null);
    await pumpEventQueue();
    expect(reconnects, 2, reason: 'a disposed binder stops requesting');

    await hints.close();
  });

  test('dispose is safe to call twice', () async {
    final StreamController<void> hints = StreamController<void>.broadcast();
    final binder = NetworkReconnectBinder(
      available: hints.stream,
      reconnectAll: () {},
    );

    binder.start();
    binder.dispose();
    binder.dispose();

    expect(binder.isListening, isFalse);
    await hints.close();
  });
}
