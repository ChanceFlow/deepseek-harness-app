/// App-local StateFlow-like state holder.
///
/// Deliberately independent from the adapter's StateStream so `app` never
/// imports a wire-layer package outside `lib/di/` (import gate).
library;

import 'dart:async';

class AppStateStream<T> {
  AppStateStream(T initialValue)
    : _value = initialValue,
      _controller = StreamController<T>.broadcast();

  final StreamController<T> _controller;
  T _value;
  bool _closed = false;

  T get value => _value;

  set value(T next) {
    if (_closed) return;
    _value = next;
    _controller.add(next);
  }

  /// A fresh broadcast stream seeded with the current value.
  Stream<T> get stream {
    final outgoing = StreamController<T>.broadcast();
    StreamSubscription<T>? inner;
    outgoing.onListen = () {
      outgoing.add(_value);
      inner = _controller.stream.listen(outgoing.add);
    };
    outgoing.onCancel = () async {
      await inner?.cancel();
    };
    return outgoing.stream;
  }

  Future<void> close() async {
    _closed = true;
    await _controller.close();
  }
}
