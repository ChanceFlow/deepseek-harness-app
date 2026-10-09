/// Tests for the `turnOutline` projection decode.
///
/// The wire view is the entry array itself
/// (`reference/deepseek-harness/packages/session/session-turn-outline/src/
/// projection.ts:132-137` `wire.view`), over `TurnOutlineEntry`
/// (`types.ts:15-24`), strictly increasing by turn — the host's own
/// `superRefine` invariant (`projection.ts:61-71`).
library;

import 'package:domain/model/turn_outline.dart';
import 'package:harness_adapter/src/dsh_wire_types.dart';
import 'package:network/rpc_envelope.dart';
import 'package:test/test.dart';

JsonMap _entry(
  int turn, {
  int seq = 1,
  String prompt = '',
  String response = '',
}) => <String, Object?>{
  'turn': turn,
  'seq': seq,
  'prompt': prompt,
  'response': response,
};

void main() {
  group('decodeTurnOutlineProjection', () {
    test('decodes the entry array with its previews', () {
      final outline = decodeTurnOutlineProjection(<Object?>[
        _entry(1, seq: 4, prompt: 'first ask', response: 'first answer'),
        _entry(2, seq: 9, prompt: 'second ask'),
      ]);

      expect(outline, hasLength(2));
      expect(
        outline[0],
        const TurnOutlineEntry(
          turn: 1,
          seq: 4,
          prompt: 'first ask',
          response: 'first answer',
        ),
      );
      expect(outline[1].turn, 2);
      expect(outline[1].seq, 9);
      expect(outline[1].prompt, 'second ask');
      expect(outline[1].response, '');
    });

    test('an empty outline is an empty array', () {
      expect(decodeTurnOutlineProjection(<Object?>[]), isEmpty);
    });

    test('a non-array value fails loud', () {
      for (final value in <Object?>[
        null,
        'nope',
        <String, Object?>{'turns': <Object?>[]},
      ]) {
        expect(
          () => decodeTurnOutlineProjection(value),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              contains('JSON array'),
            ),
          ),
          reason: '$value',
        );
      }
    });

    test('a non-object entry fails loud', () {
      expect(
        () => decodeTurnOutlineProjection(<Object?>[42]),
        throwsA(isA<FormatException>()),
      );
    });

    test('a missing required field fails loud naming it', () {
      expect(
        () => decodeTurnOutlineProjection(<Object?>[
          <String, Object?>{'turn': 1, 'seq': 2, 'response': ''},
        ]),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('prompt'),
          ),
        ),
      );
    });

    test('turns that do not strictly increase fail loud', () {
      // The host refuses to serve an unsorted outline; a violating value is
      // host breakage, not a list to sort client-side.
      for (final turns in <List<int>>[
        <int>[1, 1],
        <int>[2, 1],
      ]) {
        expect(
          () => decodeTurnOutlineProjection(
            turns.map((turn) => _entry(turn)).toList(),
          ),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              contains('strictly increasing'),
            ),
          ),
          reason: '$turns',
        );
      }
    });
  });
}
