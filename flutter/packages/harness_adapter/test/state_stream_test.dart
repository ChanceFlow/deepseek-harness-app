/// StateStream value-semantics tests: the assignment gate keeps value-equal
/// writes silent while identity-different writes (fresh lists, fresh objects
/// for types without ==) publish normally. The coalescing tests pin the
/// latest-state shape the repository publishes under a burst.
library;

import 'dart:async';

import 'package:test/test.dart';

import 'package:harness_adapter/src/state_stream.dart';

void main() {
  test('a value-equal write publishes nothing', () async {
    final stream = StateStream<_Pair>(const _Pair(1, 2));
    final seen = <_Pair>[];
    final sub = stream.stream.listen(seen.add);
    addTearDown(sub.cancel);
    await pumpEventQueue();
    expect(seen, hasLength(1)); // the seed only

    stream.value = const _Pair(1, 2);
    await pumpEventQueue();
    expect(seen, hasLength(1));
  });

  test('an unequal write publishes and updates the held value', () async {
    final stream = StateStream<_Pair>(const _Pair(1, 2));
    final seen = <_Pair>[];
    final sub = stream.stream.listen(seen.add);
    addTearDown(sub.cancel);

    stream.value = const _Pair(1, 3);
    await pumpEventQueue();
    expect(seen, hasLength(2));
    expect(seen.last, const _Pair(1, 3));
    expect(stream.value, const _Pair(1, 3));
  });

  test(
    'lists publish on fresh instances and stay silent when identical',
    () async {
      final shared = <int>[1, 2];
      final stream = StateStream<List<int>>(shared);
      final seen = <List<int>>[];
      final sub = stream.stream.listen(seen.add);
      addTearDown(sub.cancel);
      await pumpEventQueue();
      expect(seen, hasLength(1));

      stream.value = shared; // same instance: identity-equal, suppressed.
      await pumpEventQueue();
      expect(seen, hasLength(1));

      stream.value = <int>[1, 2]; // equal contents, fresh instance: publishes.
      await pumpEventQueue();
      expect(seen, hasLength(2));
    },
  );

  test(
    'a late listener is seeded with the current value after suppression',
    () async {
      final stream = StateStream<_Pair>(const _Pair(1, 2));
      stream.value = const _Pair(1, 2); // suppressed write keeps the value.
      final seen = <_Pair>[];
      final sub = stream.stream.listen(seen.add);
      addTearDown(sub.cancel);
      await pumpEventQueue();
      expect(seen, <_Pair>[const _Pair(1, 2)]);
    },
  );
  test(
    'coalesceLatest collapses a synchronous burst to its newest value',
    () async {
      final source = StreamController<int>.broadcast();
      final seen = <int>[];
      final sub = coalesceLatest(source.stream).listen(seen.add);
      addTearDown(sub.cancel);
      addTearDown(source.close);
      await pumpEventQueue();

      for (var value = 0; value < 100; value++) {
        source.add(value);
      }
      await pumpEventQueue();

      expect(seen, <int>[99]);
    },
  );

  test('coalesceLatest delivers one value in each separate turn', () async {
    final source = StreamController<int>.broadcast();
    final seen = <int>[];
    final sub = coalesceLatest(source.stream).listen(seen.add);
    addTearDown(sub.cancel);
    addTearDown(source.close);
    await pumpEventQueue();

    source.add(1);
    await pumpEventQueue();
    source.add(2);
    await pumpEventQueue();

    expect(seen, <int>[1, 2]);
  });

  test('coalesceLatest follows its listeners to the source', () async {
    final source = StreamController<int>.broadcast();
    final sub = coalesceLatest(source.stream).listen((_) {});
    await pumpEventQueue();
    expect(source.hasListener, isTrue);

    await sub.cancel();
    expect(source.hasListener, isFalse);
  });

  test('coalesceLatest passes a source error through', () async {
    final source = StreamController<int>.broadcast();
    final errors = <Object>[];
    final sub = coalesceLatest(source.stream)
        .listen((_) {}, onError: errors.add);
    addTearDown(sub.cancel);
    addTearDown(source.close);
    await pumpEventQueue();

    source.addError(const FormatException('bad frame'));
    await pumpEventQueue();

    expect(errors, hasLength(1));
    expect(errors.single, isA<FormatException>());
  });

  test('coalesceLatest closes with its source', () async {
    final source = StreamController<int>.broadcast();
    final done = Completer<void>();
    final sub = coalesceLatest(source.stream)
        .listen((_) {}, onDone: done.complete);
    addTearDown(sub.cancel);
    await pumpEventQueue();

    source.add(1);
    await source.close();
    await done.future;

    expect(done.isCompleted, isTrue);
  });
}

class _Pair {
  const _Pair(this.a, this.b);

  final int a;
  final int b;

  @override
  bool operator ==(Object other) =>
      other is _Pair && other.a == a && other.b == b;

  @override
  int get hashCode => Object.hash(a, b);
}
