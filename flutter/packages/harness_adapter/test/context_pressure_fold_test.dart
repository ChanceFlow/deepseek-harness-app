/// ContextPressureFold parity tests — the web contextPressure projection
/// semantics (last-wins pressure + capacity, chunk then final sample, and
/// the surface total carrying the sample forward as projectedTokens) over
/// the real wire envelope shape `{type, seq, time, data: {...}}`.
///
/// Reference: reference/deepseek-harness/packages/llm/token-meter/src/
/// usage-projection.ts (sample stamping + view rule) and
/// surface-projection.ts + estimate.ts (surface total), plus
/// reference/deepseek-harness/packages/compaction/compaction/src/types.ts
/// (compaction event wire shapes).
library;

import 'package:test/test.dart';
import 'package:harness_adapter/harness_adapter.dart';

JsonMap _event(String type, JsonMap data) => <String, Object?>{
  'type': type,
  'seq': 1,
  'time': 1,
  'data': data,
};

void main() {
  test('idle until any record exists', () {
    final fold = ContextPressureFold();
    fold.ingestEvent(_event('user/message', <String, Object?>{}));
    expect(fold.value, isNull);
  });

  test('usage chunk sets pressure; capacity rides request/context', () {
    final fold = ContextPressureFold();
    fold.ingestEvent(
      _event('assistant/chunk', <String, Object?>{
        'turn': 1,
        'step': 1,
        'chunk': {
          'type': 'usage',
          'usage': {
            'inputTokens': 1200,
            'outputTokens': 300,
            'cacheReadTokens': 200,
            'cacheWriteTokens': 100,
          },
        },
      }),
    );
    // input + cacheRead + cacheWrite; output excluded.
    expect(fold.value!.pressureTokens, 1500);
    expect(fold.value!.contextWindow, isNull);
    expect(fold.value!.occupancy, isNull);

    fold.ingestEvent(
      _event('request/context', <String, Object?>{
        'provider': 'deepseek',
        'model': 'glm-x',
        'contextWindow': 30000,
      }),
    );
    expect(fold.value!.contextWindow, 30000);
    expect(fold.value!.occupancy, closeTo(0.05, 0.0001));
  });

  test('finalized assistant message replaces the chunk sample', () {
    final fold = ContextPressureFold();
    fold.ingestEvent(
      _event('assistant/chunk', <String, Object?>{
        'turn': 1,
        'step': 1,
        'chunk': {
          'type': 'usage',
          'usage': {'inputTokens': 100},
        },
      }),
    );
    fold.ingestEvent(
      _event('assistant/message', <String, Object?>{
        'turn': 1,
        'step': 1,
        'message': <String, Object?>{'id': 'm1', 'content': <Object?>[]},
        'usage': {'inputTokens': 900, 'cacheWriteTokens': 100},
      }),
    );
    expect(fold.value!.pressureTokens, 1000);
  });

  test('reset replays a chronologically ordered log', () {
    final fold = ContextPressureFold();
    fold.reset([
      _event('request/context', <String, Object?>{'contextWindow': 60000}),
      _event('assistant/message', <String, Object?>{
        'turn': 1,
        'step': 1,
        'message': <String, Object?>{'id': 'm1', 'content': <Object?>[]},
        'usage': {'inputTokens': 24000},
      }),
      _event('assistant/message', <String, Object?>{
        'turn': 2,
        'step': 1,
        'message': <String, Object?>{'id': 'm2', 'content': <Object?>[]},
        'usage': {'inputTokens': 30000},
      }),
    ]);
    expect(fold.value!.pressureTokens, 30000); // last-wins
    expect(fold.value!.contextWindow, 60000);
    expect(fold.value!.occupancy, 0.5);
  });

  test('request/header prices system and tool schemas', () {
    final fold = ContextPressureFold();
    fold.ingestEvent(
      _event('request/header', <String, Object?>{
        'header': {
          'system': 'a'.padRight(40, 'a'), // 40 chars -> 10 tokens + 4 role
          'tools': [
            {'name': 'bash', 'schema': 'x'},
          ],
        },
        'reason': 'initial',
      }),
    );
    expect(fold.breakdown!.systemTokens, 14);
    expect(fold.breakdown!.toolsTokens, greaterThan(0));
    expect(fold.breakdown!.messageTokens, 0);
  });

  test('messages accumulate conversation tokens with block overheads', () {
    final fold = ContextPressureFold();
    fold.ingestEvent(
      _event('user/message', <String, Object?>{
        'id': 'u1',
        'content': [
          {'type': 'text', 'text': 'abcd'}, // 4 chars -> 1 token + 4 overhead
        ],
      }),
    );
    fold.ingestEvent(
      _event('assistant/message', <String, Object?>{
        'turn': 1,
        'step': 1,
        'message': <String, Object?>{
          'id': 'a1',
          'content': [
            {'type': 'text', 'text': 'abcdefgh'}, // 2 tokens + 4
          ],
        },
        'usage': {'inputTokens': 10},
      }),
    );
    // (1 + 4 + role 4) + (2 + 4 + role 4) = 19
    expect(fold.breakdown!.messageTokens, 19);
    expect(fold.value!.pressureTokens, 10); // usage still folds
  });

  test('non-positive capacities are ignored', () {
    final fold = ContextPressureFold();
    fold.ingestEvent(
      _event('request/context', <String, Object?>{'contextWindow': 0}),
    );
    expect(fold.value, isNull);
  });

  test('a usage chunk stamps the sample against the current surface', () {
    // Web usage-projection.ts: a usage sample sets pressureTokens AND
    // stamps sampledSurfaceTokens at the surface as of the request it
    // priced, so projectedTokens starts equal to the bare sample.
    final fold = ContextPressureFold();
    fold.ingestEvent(
      _event('user/message', <String, Object?>{
        'id': 'u1',
        'content': [
          {'type': 'text', 'text': 'q' * 16}, // 4 + 4 block + 4 role = 12
        ],
      }),
    );
    fold.ingestEvent(
      _event('assistant/chunk', <String, Object?>{
        'turn': 1,
        'step': 1,
        'chunk': {
          'type': 'usage',
          'usage': {'inputTokens': 900},
        },
      }),
    );
    expect(fold.value!.pressureTokens, 900);
    expect(fold.value!.projectedTokens, 900);
  });

  test('surface growth after the sample lifts projectedTokens beyond it', () {
    // Web usage-projection.ts: projectedTokens = max(0, pressureTokens +
    // surfaceTokens - sampledSurfaceTokens) — user, assistant, and
    // tool-result appends all join the surface (surface-projection.ts),
    // so the projection answers for the next request, not the last one.
    final fold = ContextPressureFold();
    fold.ingestEvent(
      _event('user/message', <String, Object?>{
        'id': 'u1',
        'content': [
          {'type': 'text', 'text': 'x' * 16}, // 12
        ],
      }),
    );
    fold.ingestEvent(
      _event('assistant/chunk', <String, Object?>{
        'turn': 1,
        'step': 1,
        'chunk': {
          'type': 'usage',
          'usage': {'inputTokens': 900},
        },
      }),
    );
    expect(fold.value!.projectedTokens, 900);

    // The finalized assistant message lands after the sample, so it
    // already shows (web surface.ts: an empty-content assistant message
    // prices at zero — this one carries text).
    fold.ingestEvent(
      _event('assistant/message', <String, Object?>{
        'turn': 1,
        'step': 1,
        'message': <String, Object?>{
          'id': 'a1',
          'content': [
            {'type': 'text', 'text': 'y' * 8}, // 2 + 4 + 4 = 10
          ],
        },
      }),
    );
    expect(fold.value!.projectedTokens, 910);

    // A follow-up user message grows the surface further.
    fold.ingestEvent(
      _event('user/message', <String, Object?>{
        'id': 'u2',
        'content': [
          {'type': 'text', 'text': 'w' * 20}, // 5 + 4 + 4 = 13
        ],
      }),
    );
    expect(fold.value!.projectedTokens, 923);

    // Tool results are model-visible surface (web surface.ts
    // deriveEventMessage) — the tool-result block's nested content prices
    // recursively (estimate.ts).
    fold.ingestEvent(
      _event('tool/result', <String, Object?>{
        'callId': 'c1',
        'message': <String, Object?>{
          'id': 't1',
          'content': [
            {
              'type': 'tool-result',
              'callId': 'c1',
              'content': [
                {'type': 'text', 'text': 'z' * 12}, // 3 + 4 nested block
              ],
            }, // + 4 block + 4 role = 15
          ],
        },
      }),
    );
    expect(fold.value!.pressureTokens, 900); // sample holds still
    expect(fold.value!.projectedTokens, 938);
  });

  test('projectedTokens stays absent until a usage sample exists', () {
    // Web usage-projection.ts view: projectedTokens is published only
    // while a sample exists; capacity or surface movement alone never
    // synthesizes one.
    final fold = ContextPressureFold();
    fold.ingestEvent(
      _event('request/context', <String, Object?>{'contextWindow': 30000}),
    );
    fold.ingestEvent(
      _event('user/message', <String, Object?>{
        'id': 'u1',
        'content': [
          {'type': 'text', 'text': 'x' * 16},
        ],
      }),
    );
    expect(fold.value, isNotNull);
    expect(fold.value!.contextWindow, 30000);
    expect(fold.value!.pressureTokens, isNull);
    expect(fold.value!.projectedTokens, isNull);

    fold.ingestEvent(
      _event('assistant/chunk', <String, Object?>{
        'turn': 1,
        'step': 1,
        'chunk': {
          'type': 'usage',
          'usage': {'inputTokens': 900},
        },
      }),
    );
    expect(fold.value!.projectedTokens, 900);
  });

  test('compaction/summary shrinks the surface by shadowedTokenCount and '
      'adds the summary estimate', () {
    // Web compaction pair (compaction/src/types.ts + surface-projection.ts):
    // the metering event states the replaced range's shadow price, and the
    // immediately following replacement user/message carries the summary
    // text. The fold subtracts shadowedTokenCount at the metering event
    // and prices the replacement as an ordinary append, so the compaction
    // nets to `surfaceTokens - shadowedTokenCount + estimate(summary)`.
    final fold = ContextPressureFold();
    fold.ingestEvent(
      _event('request/context', <String, Object?>{'contextWindow': 30000}),
    );
    fold.ingestEvent(
      _event('user/message', <String, Object?>{
        'id': 'u1',
        'content': [
          {'type': 'text', 'text': 'q' * 400}, // 100 + 4 + 4 = 108
        ],
      }),
    );
    fold.ingestEvent(
      _event('assistant/chunk', <String, Object?>{
        'turn': 1,
        'step': 1,
        'chunk': {
          'type': 'usage',
          'usage': {'inputTokens': 900},
        },
      }),
    );
    expect(fold.value!.projectedTokens, 900);

    fold.ingestEvent(
      _event('compaction/summary', <String, Object?>{
        'compactionId': 'cp-1',
        'summary': [
          {'type': 'text', 'text': 's' * 24},
        ],
        'shadowedRange': {'start': 2, 'end': 2},
        'shadowedSeqs': [2],
        'shadowedTokenCount': 96,
        'provider': 'deepseek',
        'model': 'glm-x',
      }),
    );
    // Compaction reports no usage, so pressureTokens cannot move; the
    // projection shrinks by the shadow price anyway.
    expect(fold.value!.pressureTokens, 900);
    expect(fold.value!.projectedTokens, 804); // 900 - 96

    // The adjacent replacement user/message (framed summary text, web
    // compaction checkpoint source) adds the summary estimate.
    fold.ingestEvent(
      _event('user/message', <String, Object?>{
        'id': 'u2',
        'content': [
          {'type': 'text', 'text': 's' * 24}, // 6 + 4 + 4 = 14
        ],
        'source': {
          'kind': 'plugin',
          'plugin': 'compact',
          'compactionId': 'cp-1',
        },
      }),
    );
    expect(fold.value!.projectedTokens, 818); // 900 - 96 + 14
  });

  test('compaction/prune subtracts only; the pruned result re-prices', () {
    // Web compaction/prune (compaction-tool-result-pruner): the shadow
    // price covers the whole shadowed tool result; the adjacent
    // replacement tool/result — the pruned remainder — joins the surface
    // through the ordinary append estimate.
    final fold = ContextPressureFold();
    fold.ingestEvent(
      _event('user/message', <String, Object?>{
        'id': 'u1',
        'content': [
          {'type': 'text', 'text': 'x' * 16}, // 12
        ],
      }),
    );
    fold.ingestEvent(
      _event('assistant/chunk', <String, Object?>{
        'turn': 1,
        'step': 1,
        'chunk': {
          'type': 'usage',
          'usage': {'inputTokens': 500},
        },
      }),
    );
    fold.ingestEvent(
      _event('tool/result', <String, Object?>{
        'callId': 'c1',
        'message': <String, Object?>{
          'id': 't1',
          'content': [
            {
              'type': 'tool-result',
              'callId': 'c1',
              'content': [
                {'type': 'text', 'text': 'r' * 40}, // 10 + 4
              ],
            }, // + 4 + 4 = 22
          ],
        },
      }),
    );
    expect(fold.value!.projectedTokens, 522); // 500 + 34 - 12

    fold.ingestEvent(
      _event('compaction/prune', <String, Object?>{
        'shadowedRange': {'start': 3, 'end': 3},
        'shadowedSeqs': [3],
        'shadowedTokenCount': 22,
      }),
    );
    expect(fold.value!.projectedTokens, 500); // 500 + 12 - 12

    fold.ingestEvent(
      _event('tool/result', <String, Object?>{
        'callId': 'c1',
        'message': <String, Object?>{
          'id': 't2',
          'content': [
            {
              'type': 'tool-result',
              'callId': 'c1',
              'content': [
                {'type': 'text', 'text': 'r' * 8}, // 2 + 4
              ],
            }, // + 4 + 4 = 14
          ],
        },
      }),
    );
    expect(fold.value!.projectedTokens, 514); // 522 - 22 + 14
  });
}
