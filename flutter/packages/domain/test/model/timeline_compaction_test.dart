import 'package:test/test.dart';

import 'package:domain/model/timeline_item.dart';

void main() {
  group('TimelineCompaction', () {
    test('isExpandable is derived from summary != null', () {
      const withSummary = TimelineCompaction(
        id: 'c1',
        shadowedCount: 10,
        shadowedTokens: 500,
        summary: 'Compacted 10 items into summary',
      );
      expect(withSummary.isExpandable, isTrue);

      const withoutSummary = TimelineCompaction(
        id: 'c2',
        shadowedCount: 10,
        shadowedTokens: 500,
      );
      expect(withoutSummary.isExpandable, isFalse);
    });

    test('value equality and hashCode include all fields', () {
      const a = TimelineCompaction(
        id: 'c1',
        shadowedCount: 5,
        shadowedTokens: 200,
        summary: 'summary text',
      );
      const b = TimelineCompaction(
        id: 'c1',
        shadowedCount: 5,
        shadowedTokens: 200,
        summary: 'summary text',
      );
      const diffTokens = TimelineCompaction(
        id: 'c1',
        shadowedCount: 5,
        shadowedTokens: 250,
        summary: 'summary text',
      );
      const diffSummary = TimelineCompaction(
        id: 'c1',
        shadowedCount: 5,
        shadowedTokens: 200,
        summary: 'different',
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(diffTokens)));
      expect(a, isNot(equals(diffSummary)));
    });

    test('nullable count and token fields default to null', () {
      const minimal = TimelineCompaction(id: 'c-min');
      expect(minimal.id, 'c-min');
      expect(minimal.shadowedCount, isNull);
      expect(minimal.shadowedTokens, isNull);
      expect(minimal.summary, isNull);
      expect(minimal.isExpandable, isFalse);
    });
  });
}
