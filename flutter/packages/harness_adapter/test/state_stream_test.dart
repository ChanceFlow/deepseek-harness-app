/// StateStream value-semantics tests: the assignment gate keeps value-equal
/// writes silent while identity-different writes (fresh lists, fresh objects
/// for types without ==) publish normally.
library;

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
