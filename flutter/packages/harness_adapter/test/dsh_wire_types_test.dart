/// Fixture tests for the trajectory decoders: provider token accounting
/// (`TokenUsage`) and the recorded assistant stream's first-token
/// timestamp.
///
/// Payload shapes are transcribed from the pinned submodule:
/// `packages/llm/llm/src/types.ts` (`TokenUsage`, disjoint cache buckets) and
/// `packages/llm/llm/src/assistant-stream.ts` (`AssistantStreamRecord`'s
/// packed `text-chunks` runs, raw `chunk` records, and the
/// `assistantStreamFirstTokenTime` walk order).
library;

import 'package:domain/model/token_usage.dart';
import 'package:test/test.dart';

import 'package:harness_adapter/src/dsh_wire_types.dart';

void main() {
  group('decodeTokenUsage', () {
    test('decodes a provider usage object with disjoint cache buckets', () {
      // reference `assistant/message.data.usage` (TokenUsage): the required
      // prompt/completion counts plus the optional cache and reasoning split.
      final usage = decodeTokenUsage(<String, Object?>{
        'inputTokens': 1200,
        'outputTokens': 340,
        'totalTokens': 1710,
        'cacheReadTokens': 150,
        'cacheWriteTokens': 20,
        'reasoningTokens': 90,
      });

      expect(usage, isNotNull);
      expect(usage!.inputTokens, 1200);
      expect(usage.outputTokens, 340);
      expect(usage.totalTokens, 1710);
      expect(usage.cacheReadTokens, 150);
      expect(usage.cacheWriteTokens, 20);
      expect(usage.reasoningTokens, 90);
      // Billed input is the disjoint sum, never a cached-inclusive total.
      expect(usage.billedInputTokens, 1370);
    });

    test('keeps an unreported optional bucket null instead of zero', () {
      final usage = decodeTokenUsage(<String, Object?>{
        'inputTokens': 10,
        'outputTokens': 2,
      });

      expect(usage!.cacheReadTokens, isNull);
      expect(usage.cacheWriteTokens, isNull);
      expect(usage.reasoningTokens, isNull);
      expect(usage.totalTokens, isNull);
      expect(usage.billedInputTokens, 10);
    });

    test('an absent usage member is null, a malformed one fails loud', () {
      // `usage` is optional on the event: absent means the adapter reported
      // no accounting, which the ledger renders as unavailable.
      expect(decodeTokenUsage(null), isNull);
      expect(
        () => decodeTokenUsage('nope'),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('usage'),
          ),
        ),
      );
      // `inputTokens`/`outputTokens` are required on the reference record.
      expect(
        () => decodeTokenUsage(<String, Object?>{'outputTokens': 3}),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('inputTokens'),
          ),
        ),
      );
    });
  });

  group('assistantStreamFirstTokenTime', () {
    test('reconstructs the first member time of a packed run across gaps', () {
      // Records exactly as `AssistantStreamAccumulator.snapshot` emits them:
      // the run starts at time0 and each member sits one `dt` later.
      final time = assistantStreamFirstTokenTime(<Object?>[
        <String, Object?>{
          'type': 'text-chunks',
          'time0': 1000,
          'index': 0,
          'dt': <Object?>[30, 45],
          'texts': <Object?>['first', ' second', ' third'],
        },
      ]);

      // The first non-empty member is at time0; a later member would add dt.
      expect(time, 1000);
    });

    test('skips empty fragments and accumulates their gaps', () {
      final time = assistantStreamFirstTokenTime(<Object?>[
        <String, Object?>{
          'type': 'reasoning-chunks',
          'time0': 5000,
          'index': 0,
          'dt': <Object?>[12, 8, 4],
          'texts': <Object?>['', '', 'token'],
        },
      ]);

      // '' at 5000, '' at 5012, 'token' at 5020.
      expect(time, 5020);
    });

    test('a name-bearing tool-call run starts at its first member', () {
      final time = assistantStreamFirstTokenTime(<Object?>[
        <String, Object?>{
          'type': 'tool-call-chunks',
          'time0': 700,
          'index': 0,
          'dt': <Object?>[],
          'id': 'call-1',
          'name': 'bash',
          'args': <Object?>[''],
        },
      ]);

      expect(time, 700);
    });

    test(
      'raw records keep their own timestamp and take precedence in order',
      () {
        final time = assistantStreamFirstTokenTime(<Object?>[
          <String, Object?>{
            'type': 'chunk',
            'time': 100,
            'chunk': <String, Object?>{
              'type': 'block-start',
              'blockType': 'text',
            },
          },
          <String, Object?>{
            'type': 'chunk',
            'time': 250,
            'chunk': <String, Object?>{'type': 'text-delta', 'text': 'hi'},
          },
        ]);

        expect(time, 250);
      },
    );

    test('a stream with no token delta reports no first token', () {
      expect(
        assistantStreamFirstTokenTime(<Object?>[
          <String, Object?>{
            'type': 'chunk',
            'time': 10,
            'chunk': <String, Object?>{'type': 'finish', 'reason': 'stop'},
          },
        ]),
        isNull,
      );
      expect(assistantStreamFirstTokenTime(null), isNull);
      expect(assistantStreamFirstTokenTime(const <Object?>[]), isNull);
    });

    test('a malformed run is skipped rather than failing session replay', () {
      // A run whose gaps cannot reconstruct the member time carries no
      // usable boundary; the walk continues to the next record.
      final time = assistantStreamFirstTokenTime(<Object?>[
        <String, Object?>{
          'type': 'text-chunks',
          'time0': 1,
          'index': 0,
          'dt': <Object?>['not-a-number'],
          'texts': <Object?>['a', 'b'],
        },
        <String, Object?>{
          'type': 'chunk',
          'time': 42,
          'chunk': <String, Object?>{'type': 'text-delta', 'text': 'z'},
        },
      ]);

      expect(time, 42);
    });
  });

  group('TokenUsage', () {
    test('equality covers every optional bucket', () {
      const base = TokenUsage(inputTokens: 1, outputTokens: 2);
      expect(base, const TokenUsage(inputTokens: 1, outputTokens: 2));
      expect(
        base,
        isNot(
          const TokenUsage(inputTokens: 1, outputTokens: 2, cacheReadTokens: 3),
        ),
      );
    });
  });
}
