/// StateFlow-like helper for pure-Dart packages.
///
/// Keeps a current value and exposes independent broadcast streams that
/// seed new listeners with the current value before forwarding updates —
/// the same semantics Kotlin's `StateFlow.asStateFlow()` gives the legacy
/// adapter.
library;

import 'dart:async';

class StateStream<T> {
  StateStream(T initialValue)
    : _value = initialValue,
      _controller = StreamController<T>.broadcast();

  final StreamController<T> _controller;
  T _value;
  bool _closed = false;

  /// Current value; setting it publishes to every active listener.
  ///
  /// A write that is value-equal (`==`) to the current value publishes
  /// nothing: the stats/pressure folds mint a fresh equal instance on
  /// every folded event, and re-assigning unchanged facts downstream
  /// would rebuild the whole UI for no observable change. Lists and other
  /// identity-compared types pass the gate unless the same instance is
  /// re-assigned, so collection-backed state keeps publishing normally.
  T get value => _value;

  set value(T next) {
    if (_closed) return;
    if (_value == next) return;
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

  /// Closes the underlying controller. Late listeners still get seeded.
  Future<void> close() async {
    _closed = true;
    await _controller.close();
  }
}

/// Minimal async mutex: actions run in submission order, never interleaved
/// across await points. Mirrors `kotlinx.coroutines.sync.Mutex`.
class Mutex {
  Future<void> _tail = Future<void>.value();

  Future<T> synchronized<T>(Future<T> Function() action) {
    final run = _tail.then((_) => action());
    _tail = run.then((_) {}, onError: (_) {});
    return run;
  }
}

/// Combine-latest over two streams (both must have emitted at least once).
/// Used with [StateStream.stream]s which always seed immediately.
Stream<R> combineLatest2<A, B, R>(
  Stream<A> a,
  Stream<B> b,
  R Function(A, B) convert,
) {
  final outgoing = StreamController<R>.broadcast();
  var haveA = false;
  var haveB = false;
  var lastA = null as A?;
  var lastB = null as B?;
  late final StreamSubscription<A> subA;
  late final StreamSubscription<B> subB;
  void emit() {
    if (haveA && haveB) {
      outgoing.add(convert(lastA as A, lastB as B));
    }
  }

  outgoing.onListen = () {
    subA = a.listen((value) {
      lastA = value;
      haveA = true;
      emit();
    });
    subB = b.listen((value) {
      lastB = value;
      haveB = true;
      emit();
    });
  };
  outgoing.onCancel = () async {
    await subA.cancel();
    await subB.cancel();
  };
  return outgoing.stream;
}

/// Combine-latest over three streams (all must have emitted at least once).
/// Used with [StateStream.stream]s which always seed immediately.
Stream<R> combineLatest3<A, B, C, R>(
  Stream<A> a,
  Stream<B> b,
  Stream<C> c,
  R Function(A, B, C) convert,
) {
  final outgoing = StreamController<R>.broadcast();
  var haveA = false;
  var haveB = false;
  var haveC = false;
  var lastA = null as A?;
  var lastB = null as B?;
  var lastC = null as C?;
  late final StreamSubscription<A> subA;
  late final StreamSubscription<B> subB;
  late final StreamSubscription<C> subC;
  void emit() {
    if (haveA && haveB && haveC) {
      outgoing.add(convert(lastA as A, lastB as B, lastC as C));
    }
  }

  outgoing.onListen = () {
    subA = a.listen((value) {
      lastA = value;
      haveA = true;
      emit();
    });
    subB = b.listen((value) {
      lastB = value;
      haveB = true;
      emit();
    });
    subC = c.listen((value) {
      lastC = value;
      haveC = true;
      emit();
    });
  };
  outgoing.onCancel = () async {
    await subA.cancel();
    await subB.cancel();
    await subC.cancel();
  };
  return outgoing.stream;
}

/// Publish only the newest event of each event-loop turn.
///
/// A synchronous burst (or a backlog of already-queued events) reaches the
/// listener once, carrying the last value; an event that arrives after the
/// scheduled delivery starts a new turn. This is the stream form of a state
/// fact under load: a roster that changed five times before the microtask
/// queue drains is one roster, not five, so an O(roster) consumer cannot be
/// driven into an O(roster × burst) microtask chain that never yields to
/// input. The stream is broadcast and follows [combineLatest3]'s listener
/// lifecycle: the source is subscribed while someone listens, and the first
/// listener of a new cycle is seeded by the source.
Stream<T> coalesceLatest<T>(Stream<T> source) {
  final controller = StreamController<T>.broadcast();
  StreamSubscription<T>? subscription;
  T? latest;
  var hasLatest = false;
  var scheduled = false;

  void flush() {
    scheduled = false;
    if (!hasLatest || controller.isClosed || !controller.hasListener) {
      hasLatest = false;
      latest = null;
      return;
    }
    final T value = latest as T;
    hasLatest = false;
    latest = null;
    controller.add(value);
  }

  void onData(T value) {
    latest = value;
    hasLatest = true;
    if (scheduled) return;
    scheduled = true;
    // A timer, not a microtask: the source's own delivery is a chain of
    // microtasks, so a microtask flush would run between two source events
    // and coalesce nothing. A timer runs after that chain has drained, so a
    // burst becomes one delivery, and the event loop gets a turn to dispatch
    // input before the consumer's O(roster) work begins.
    Timer.run(flush);
  }

  controller.onListen = () {
    subscription = source.listen(
      onData,
      onError: controller.addError,
      onDone: controller.close,
    );
  };
  controller.onCancel = () async {
    hasLatest = false;
    latest = null;
    final StreamSubscription<T>? current = subscription;
    subscription = null;
    await current?.cancel();
  };
  return controller.stream;
}

/// Stable sort by [keyOf], mirroring Kotlin's `sortedBy` (List.sort in Dart
/// is not guaranteed stable).
List<T> stableSortedBy<T, K extends Comparable<K>>(
  List<T> input,
  K Function(T) keyOf,
) {
  final indexed = List<(int, T)>.generate(
    input.length,
    (i) => (i, input[i]),
    growable: false,
  );
  indexed.sort((a, b) {
    final byKey = keyOf(a.$2).compareTo(keyOf(b.$2));
    return byKey != 0 ? byKey : a.$1.compareTo(b.$1);
  });
  return indexed.map((pair) => pair.$2).toList();
}
