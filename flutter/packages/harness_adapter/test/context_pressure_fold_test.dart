/// ContextPressureFold parity tests — the web contextPressure projection
/// semantics (last-wins pressure + capacity, chunk then final sample) over
/// the real wire envelope shape `{type, seq, time, data: {...}}`.
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
}
