/// Tests for the `subagentTiming` projection decode.
///
/// The wire view is `{settledMs, active?: {since, through},
/// lastTurnCompleted?}`
/// (`reference/deepseek-harness/packages/subagent/subagent/src/projection.ts:32-42`
/// `projectionSchema`, `:107-115` `wire.view`), read by the reference at
/// `client/ui-subagent/src/client/SubagentHeaderLineage.tsx:83-84,244`.
library;

import 'package:domain/model/subagent.dart';
import 'package:harness_adapter/src/dsh_wire_types.dart';
import 'package:test/test.dart';

void main() {
  group('decodeSubagentTimingProjection', () {
    test('decodes a settled child with an open turn', () {
      final timing = decodeSubagentTimingProjection(<String, Object?>{
        'settledMs': 1200,
        'active': <String, Object?>{'since': 5, 'through': 9},
        'lastTurnCompleted': true,
      });

      expect(timing, isNotNull);
      expect(timing!.settledMs, 1200);
      expect(timing.active, const SubagentActiveInterval(since: 5, through: 9));
      expect(timing.lastTurnCompleted, isTrue);
    });

    test('decodes a child whose descriptor has not landed yet', () {
      // `descriptorSeen: false` projects `{settledMs: 0}` alone.
      final timing = decodeSubagentTimingProjection(<String, Object?>{
        'settledMs': 0,
      });

      expect(timing!.settledMs, 0);
      expect(timing.active, isNull);
      expect(timing.lastTurnCompleted, isNull);
    });

    test('no published value is null, not an empty timing', () {
      expect(decodeSubagentTimingProjection(null), isNull);
      expect(decodeSubagentTimingProjection('null'), isNull);
    });

    test('a non-object value fails loud', () {
      expect(
        () => decodeSubagentTimingProjection(<Object?>[]),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('JSON object'),
          ),
        ),
      );
    });

    test('a missing settledMs fails loud naming it', () {
      expect(
        () => decodeSubagentTimingProjection(<String, Object?>{
          'lastTurnCompleted': true,
        }),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('settledMs'),
          ),
        ),
      );
    });

    test('an active interval without both ends fails loud', () {
      expect(
        () => decodeSubagentTimingProjection(<String, Object?>{
          'settledMs': 1,
          'active': <String, Object?>{'since': 5},
        }),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('through'),
          ),
        ),
      );
      expect(
        () => decodeSubagentTimingProjection(<String, Object?>{
          'settledMs': 1,
          'active': 'open',
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('a mistyped completion marker fails loud', () {
      expect(
        () => decodeSubagentTimingProjection(<String, Object?>{
          'settledMs': 1,
          'lastTurnCompleted': 'yes',
        }),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('lastTurnCompleted'),
          ),
        ),
      );
    });
  });
}
