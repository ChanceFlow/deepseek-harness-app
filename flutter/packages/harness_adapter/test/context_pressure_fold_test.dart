/// ContextPressureFold parity tests — the web contextPressure projection
/// semantics (last-wins pressure + capacity, chunk then final sample).
library;

import 'package:test/test.dart';
import 'package:harness_adapter/harness_adapter.dart';

void main() {
  test('idle until any record exists', () {
    final fold = ContextPressureFold();
    fold.ingestEvent(<String, Object?>{'type': 'user/message'});
    expect(fold.value, isNull);
  });

  test('usage chunk sets pressure; capacity rides request/context', () {
    final fold = ContextPressureFold();
    fold.ingestEvent(<String, Object?>{
      'type': 'assistant/chunk',
      'chunk': {
        'type': 'usage',
        'usage': {
          'inputTokens': 1200,
          'outputTokens': 300,
          'cacheReadTokens': 200,
          'cacheWriteTokens': 100,
        },
      },
    });
    // input + cacheRead + cacheWrite; output excluded.
    expect(fold.value!.pressureTokens, 1500);
    expect(fold.value!.contextWindow, isNull);
    expect(fold.value!.occupancy, isNull);

    fold.ingestEvent(<String, Object?>{
      'type': 'request/context',
      'contextWindow': 30000,
    });
    expect(fold.value!.contextWindow, 30000);
    expect(fold.value!.occupancy, closeTo(0.05, 0.0001));
  });

  test('finalized assistant message replaces the chunk sample', () {
    final fold = ContextPressureFold();
    fold.ingestEvent(<String, Object?>{
      'type': 'assistant/chunk',
      'chunk': {
        'type': 'usage',
        'usage': {'inputTokens': 100},
      },
    });
    fold.ingestEvent(<String, Object?>{
      'type': 'assistant/message',
      'usage': {'inputTokens': 900, 'cacheWriteTokens': 100},
    });
    expect(fold.value!.pressureTokens, 1000);
  });

  test('reset replays a chronologically ordered log', () {
    final fold = ContextPressureFold();
    fold.reset([
      <String, Object?>{'type': 'request/context', 'contextWindow': 60000},
      <String, Object?>{
        'type': 'assistant/message',
        'usage': {'inputTokens': 24000},
      },
      <String, Object?>{
        'type': 'assistant/message',
        'usage': {'inputTokens': 30000},
      },
    ]);
    expect(fold.value!.pressureTokens, 30000); // last-wins
    expect(fold.value!.contextWindow, 60000);
    expect(fold.value!.occupancy, 0.5);
  });

  test('request/header prices system and tool schemas', () {
    final fold = ContextPressureFold();
    fold.ingestEvent(<String, Object?>{
      'type': 'request/header',
      'header': {
        'system': 'a'.padRight(40, 'a'), // 40 chars -> 10 tokens + 4 role
        'tools': [
          {'name': 'bash', 'schema': 'x'},
        ],
      },
    });
    expect(fold.breakdown!.systemTokens, 14);
    expect(fold.breakdown!.toolsTokens, greaterThan(0));
    expect(fold.breakdown!.messageTokens, 0);
  });

  test('messages accumulate conversation tokens with block overheads', () {
    final fold = ContextPressureFold();
    fold.ingestEvent(<String, Object?>{
      'type': 'user/message',
      'content': [
        {'type': 'text', 'text': 'abcd'}, // 4 chars -> 1 token + 4 overhead
      ],
    });
    fold.ingestEvent(<String, Object?>{
      'type': 'assistant/message',
      'usage': {'inputTokens': 10},
      'content': [
        {'type': 'text', 'text': 'abcdefgh'}, // 2 tokens + 4
      ],
    });
    // (1 + 4 + role 4) + (2 + 4 + role 4) = 19
    expect(fold.breakdown!.messageTokens, 19);
    expect(fold.value!.pressureTokens, 10); // usage still folds
  });

  test('non-positive capacities are ignored', () {
    final fold = ContextPressureFold();
    fold.ingestEvent(<String, Object?>{
      'type': 'request/context',
      'contextWindow': 0,
    });
    expect(fold.value, isNull);
  });
}
