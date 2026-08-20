/// SessionStatsFold tests — the host `sessionStats` projection semantics
/// (dsh-session-stats `projection.spec.ts`) folded from real wire
/// envelopes: `{type, seq, time, data}` with payload fields where the host
/// puts them.
library;

import 'package:harness_adapter/harness_adapter.dart';
import 'package:test/test.dart';

/// One session-log event envelope; `seq` mirrors `time` to keep both
/// unique and chronologically ordered per fixture.
JsonMap event(int time, String type, [JsonMap? data]) => <String, Object?>{
  'type': type,
  'seq': time,
  'time': time,
  'data': data ?? <String, Object?>{},
};

JsonMap textDelta(String text) => <String, Object?>{
  'type': 'text-delta',
  'index': 0,
  'text': text,
};

JsonMap assistantMessage() => <String, Object?>{
  'id': 'assistant-1',
  'role': 'assistant',
  'content': <Object?>[
    <String, Object?>{'type': 'text', 'text': 'answer'},
  ],
  'source': <String, Object?>{
    'kind': 'model',
    'provider': 'mock',
    'model': 'mock',
  },
};

/// A `tool/result` payload: the callId lives inside the result message's
/// source, not at the top level.
JsonMap toolResult(String callId) => <String, Object?>{
  'turn': 1,
  'step': 1,
  'message': <String, Object?>{
    'id': 'result-$callId',
    'role': 'user',
    'source': <String, Object?>{'kind': 'tool', 'callId': callId},
    'content': <Object?>[
      <String, Object?>{
        'type': 'tool-result',
        'toolCallId': callId,
        'content': <Object?>[
          <String, Object?>{'type': 'text', 'text': 'ok'},
        ],
        'isError': false,
      },
    ],
  },
};

void main() {
  test('empty log yields zeroed stats', () {
    final fold = SessionStatsFold()..reset(const []);
    expect(fold.value.turns, 0);
    expect(fold.value.steps, 0);
    expect(fold.value.cacheHitPercent, isNull);
  });

  test('turns counts distinct turn values among closed steps', () {
    final fold = SessionStatsFold()
      ..reset([
        event(1, 'turn/start', {'turn': 1}),
        event(2, 'step/start', {'turn': 1, 'step': 1}),
        event(3, 'step/end', {'turn': 1, 'step': 1}),
        event(4, 'step/start', {'turn': 1, 'step': 2}),
        event(5, 'step/end', {'turn': 1, 'step': 2}),
        event(6, 'turn/end', {
          'turn': 1,
          'reason': {'kind': 'completed'},
        }),
        event(7, 'turn/start', {'turn': 2}),
        event(8, 'step/start', {'turn': 2, 'step': 1}),
        event(9, 'step/end', {'turn': 2, 'step': 1}),
        event(10, 'turn/end', {
          'turn': 2,
          'reason': {'kind': 'completed'},
        }),
      ]);
    expect(fold.value.turns, 2);
    expect(fold.value.steps, 3);
  });

  test('a turn that closes without entering a step counts nothing', () {
    final fold = SessionStatsFold()
      ..reset([
        event(1, 'turn/start', {'turn': 1}),
        event(2, 'turn/end', {
          'turn': 1,
          'reason': {'kind': 'blocked'},
        }),
      ]);
    expect(fold.value.turns, 0);
    expect(fold.value.steps, 0);
  });

  test('one fully recorded step accrues llm, ttft, and decode time', () {
    final fold = SessionStatsFold()
      ..reset([
        event(1, 'turn/start', {'turn': 1}),
        event(1000, 'step/start', {'turn': 1, 'step': 1}),
        event(1800, 'assistant/chunk', {
          'turn': 1,
          'step': 1,
          'chunk': textDelta('a'),
        }),
        event(4800, 'assistant/message', {
          'turn': 1,
          'step': 1,
          'message': assistantMessage(),
          'usage': {'inputTokens': 10, 'outputTokens': 60},
        }),
        event(4900, 'step/end', {'turn': 1, 'step': 1}),
      ]);
    final stats = fold.value;
    expect(stats.turns, 1);
    expect(stats.steps, 1);
    expect(stats.llmMs, 3800); // step/start 1000 -> message 4800
    expect(stats.ttftMs, 800); // step/start 1000 -> first delta 1800
    expect(stats.ttftSteps, 1);
    expect(stats.decodeMs, 3000); // first delta 1800 -> message 4800
    expect(stats.decodeTokens, 60);
    expect(stats.billedInputTokens, 10);
    expect(stats.outputTokens, 60);
  });

  test('a realistic turn: tool time, an unchunked step, and billing', () {
    final fold = SessionStatsFold()
      ..reset([
        event(1, 'turn/start', {'turn': 1}),
        event(1000, 'step/start', {'turn': 1, 'step': 1}),
        event(1100, 'user/message', {
          'message': {'role': 'user', 'content': <Object?>[]},
        }),
        event(1400, 'assistant/chunk', {
          'turn': 1,
          'step': 1,
          'chunk': textDelta('Hel'),
        }),
        event(1500, 'assistant/chunk', {
          'turn': 1,
          'step': 1,
          'chunk': textDelta('lo'),
        }),
        event(2000, 'assistant/message', {
          'turn': 1,
          'step': 1,
          'message': assistantMessage(),
          'usage': {
            'inputTokens': 800,
            'cacheReadTokens': 200,
            'cacheWriteTokens': 100,
            'outputTokens': 60,
          },
        }),
        event(2100, 'tool/call', {
          'turn': 1,
          'step': 1,
          'callId': 'c1',
          'name': 'bash',
          'arguments': '{}',
        }),
        event(3600, 'tool/result', toolResult('c1')),
        event(3700, 'step/end', {'turn': 1, 'step': 1}),
        event(3800, 'step/start', {'turn': 1, 'step': 2}),
        event(4200, 'assistant/message', {
          'turn': 1,
          'step': 2,
          'message': assistantMessage(),
          'usage': {'inputTokens': 900, 'outputTokens': 30},
        }),
        event(4300, 'step/end', {'turn': 1, 'step': 2}),
        event(4400, 'turn/end', {
          'turn': 1,
          'reason': {'kind': 'completed'},
        }),
      ]);
    final stats = fold.value;
    expect(stats.turns, 1);
    expect(stats.steps, 2);
    // Step 1 spans 1000 -> 2000; the unchunked step 2 spans 3800 -> 4200.
    expect(stats.llmMs, 1400);
    expect(stats.toolMs, 1500); // call 2100 -> result 3600
    expect(stats.ttftMs, 400); // first delta at 1400, not the second at 1500
    expect(stats.ttftSteps, 1);
    // Decode only prices the streamed step: 60 tokens over 1400 -> 2000.
    expect(stats.decodeMs, 600);
    expect(stats.decodeTokens, 60);
    // The "0 tok/s" regression: throughput numerator and denominator are
    // both non-zero.
    expect(stats.decodeTokens, greaterThan(0));
    expect(stats.decodeMs, greaterThan(0));
    expect(stats.billedInputTokens, 2000); // (800+200+100) + 900
    expect(stats.outputTokens, 90); // 60 + 30: billing counts both steps
    expect(stats.cacheHitPercent, 10); // 200 / 2000
  });

  test('a cancelled step counts as a step but accrues no time', () {
    final fold = SessionStatsFold()
      ..reset([
        event(1, 'turn/start', {'turn': 1}),
        event(1000, 'step/start', {'turn': 1, 'step': 1}),
        event(1500, 'assistant/chunk', {
          'turn': 1,
          'step': 1,
          'chunk': textDelta('partial'),
        }),
        event(2000, 'step/end', {'turn': 1, 'step': 1}),
        event(2100, 'turn/end', {
          'turn': 1,
          'reason': {
            'kind': 'aborted',
            'reason': {'kind': 'legacy'},
          },
        }),
      ]);
    final stats = fold.value;
    expect(stats.turns, 1);
    expect(stats.steps, 1); // counted from step/end, message or not
    expect(stats.llmMs, 0);
    expect(stats.ttftMs, 0);
    expect(stats.ttftSteps, 0);
    expect(stats.decodeMs, 0);
    expect(stats.decodeTokens, 0);
  });

  test('a max-tokens usage-host message adds no extra step', () {
    final fold = SessionStatsFold()
      ..reset([
        event(1, 'turn/start', {'turn': 1}),
        event(1000, 'step/start', {'turn': 1, 'step': 1}),
        event(1500, 'assistant/message', {
          'turn': 1,
          'step': 1,
          'message': {
            'id': 'assistant-1',
            'role': 'assistant',
            'content': <Object?>[],
            'source': <String, Object?>{
              'kind': 'model',
              'provider': 'mock',
              'model': 'mock',
            },
          },
          'usage': {'inputTokens': 5, 'outputTokens': 120},
        }),
        event(1600, 'step/end', {'turn': 1, 'step': 1}),
        event(1700, 'turn/end', {
          'turn': 1,
          'reason': {'kind': 'max-tokens'},
        }),
      ]);
    final stats = fold.value;
    expect(stats.turns, 1);
    expect(stats.steps, 1); // the empty message is not a second step
    expect(stats.llmMs, 500);
    expect(stats.ttftSteps, 0); // no chunks streamed
    expect(stats.decodeMs, 0);
    expect(stats.decodeTokens, 0); // decode needs a first token
    expect(stats.outputTokens, 120); // billing still prices the usage
    expect(stats.billedInputTokens, 5);
  });

  test('only the first token delta of the open step marks the first token', () {
    final fold = SessionStatsFold()
      ..reset([
        // Before any step/start: no open boundary.
        event(500, 'assistant/chunk', {
          'turn': 1,
          'step': 1,
          'chunk': textDelta('stray'),
        }),
        event(1000, 'step/start', {'turn': 1, 'step': 1}),
        event(1100, 'assistant/chunk', {
          'turn': 1,
          'step': 1,
          'chunk': {'type': 'block-start', 'index': 0, 'blockType': 'text'},
        }),
        event(1200, 'assistant/chunk', {
          'turn': 1,
          'step': 1,
          'chunk': textDelta(''),
        }),
        event(1300, 'assistant/chunk', {
          'turn': 2,
          'step': 9,
          'chunk': textDelta('other'),
        }),
        event(1400, 'assistant/chunk', {
          'turn': 1,
          'step': 1,
          'chunk': textDelta('first'),
        }),
        event(2000, 'assistant/message', {
          'turn': 1,
          'step': 1,
          'message': assistantMessage(),
        }),
        event(2100, 'step/end', {'turn': 1, 'step': 1}),
      ]);
    final stats = fold.value;
    expect(stats.llmMs, 1000);
    expect(stats.ttftMs, 400); // 1000 -> the 1400 delta
    expect(stats.ttftSteps, 1);
    expect(stats.decodeMs, 0); // the message reports no usage
    expect(stats.decodeTokens, 0);
  });

  test('a tool-call frame carrying a name marks the first token', () {
    final fold = SessionStatsFold()
      ..reset([
        event(1000, 'step/start', {'turn': 1, 'step': 1}),
        event(1200, 'assistant/chunk', {
          'turn': 1,
          'step': 1,
          'chunk': {
            'type': 'tool-call-delta',
            'index': 0,
            'id': 'call_1',
            'name': 'bash',
            'argumentsDelta': '',
          },
        }),
        event(1500, 'assistant/message', {
          'turn': 1,
          'step': 1,
          'message': assistantMessage(),
          'usage': {'inputTokens': 5, 'outputTokens': 5},
        }),
        event(1600, 'step/end', {'turn': 1, 'step': 1}),
      ]);
    final stats = fold.value;
    expect(stats.ttftMs, 200);
    expect(stats.ttftSteps, 1);
    expect(stats.decodeMs, 300);
    expect(stats.decodeTokens, 5);
  });

  test('the first-token boundary survives an in-step llm/retry', () {
    final fold = SessionStatsFold()
      ..reset([
        event(1000, 'step/start', {'turn': 1, 'step': 1}),
        event(1200, 'assistant/chunk', {
          'turn': 1,
          'step': 1,
          'chunk': {'type': 'reasoning-delta', 'index': 0, 'text': 'x'},
        }),
        event(2000, 'llm/retry', {'turn': 1, 'step': 1}),
        event(3000, 'assistant/chunk', {
          'turn': 1,
          'step': 1,
          'chunk': textDelta('y'),
        }),
        event(5000, 'assistant/message', {
          'turn': 1,
          'step': 1,
          'message': assistantMessage(),
        }),
        event(5100, 'step/end', {'turn': 1, 'step': 1}),
      ]);
    final stats = fold.value;
    expect(stats.llmMs, 4000); // the whole step, retry wait included
    expect(stats.ttftMs, 200); // kept from the first attempt
    expect(stats.ttftSteps, 1);
    expect(stats.decodeMs, 0);
  });

  test(
    'tool wall time pairs by callId, not adjacency, and ignores orphans',
    () {
      final fold = SessionStatsFold()
        ..reset([
          event(1000, 'step/start', {'turn': 1, 'step': 1}),
          event(1100, 'tool/call', {
            'turn': 1,
            'step': 1,
            'callId': 'a',
            'name': 'read',
            'arguments': '{}',
          }),
          event(1200, 'tool/call', {
            'turn': 1,
            'step': 1,
            'callId': 'b',
            'name': 'read',
            'arguments': '{}',
          }),
          // Out-of-order settlement pairs by id.
          event(4200, 'tool/result', toolResult('b')),
          event(1600, 'tool/result', toolResult('a')),
          // No recorded call: unmatched.
          event(5000, 'tool/result', toolResult('ghost')),
          event(5100, 'step/end', {'turn': 1, 'step': 1}),
        ]);
      expect(fold.value.toolMs, 3500); // (4200-1200) + (1600-1100)
      expect(fold.value.steps, 1);
    },
  );

  test('an unresolved call is pruned at turn/end and cannot pair later', () {
    final fold = SessionStatsFold()
      ..reset([
        event(1000, 'step/start', {'turn': 1, 'step': 1}),
        event(1100, 'tool/call', {
          'turn': 1,
          'step': 1,
          'callId': 'orphan',
          'name': 'read',
          'arguments': '{}',
        }),
        event(2000, 'step/end', {'turn': 1, 'step': 1}),
        event(2100, 'turn/end', {
          'turn': 1,
          'reason': {
            'kind': 'aborted',
            'reason': {'kind': 'legacy'},
          },
        }),
        event(9000, 'tool/result', toolResult('orphan')),
      ]);
    expect(fold.value.toolMs, 0);
    expect(fold.value.turns, 1);
  });

  test('an invalid usage report skips decode but keeps the first token', () {
    final fold = SessionStatsFold()
      ..reset([
        event(1000, 'step/start', {'turn': 1, 'step': 1}),
        event(1400, 'assistant/chunk', {
          'turn': 1,
          'step': 1,
          'chunk': textDelta('a'),
        }),
        event(2000, 'assistant/message', {
          'turn': 1,
          'step': 1,
          'message': assistantMessage(),
          'usage': {'inputTokens': 1, 'outputTokens': -5},
        }),
        event(2100, 'step/end', {'turn': 1, 'step': 1}),
      ]);
    final stats = fold.value;
    expect(stats.llmMs, 1000);
    expect(stats.ttftMs, 400);
    expect(stats.ttftSteps, 1);
    expect(stats.decodeMs, 0);
    expect(stats.decodeTokens, 0);
    expect(stats.billedInputTokens, 1);
    expect(stats.outputTokens, 0); // the negative report is rejected
  });

  test('a duplicate assembled message cannot accrue twice', () {
    final fold = SessionStatsFold()
      ..reset([
        event(1000, 'step/start', {'turn': 1, 'step': 1}),
        event(1400, 'assistant/chunk', {
          'turn': 1,
          'step': 1,
          'chunk': textDelta('a'),
        }),
        event(2000, 'assistant/message', {
          'turn': 1,
          'step': 1,
          'message': assistantMessage(),
        }),
        event(2100, 'step/end', {'turn': 1, 'step': 1}),
      ]);
    expect(fold.value.llmMs, 1000);
    // The first message closed the step boundary; a defensive duplicate
    // finds no open step.
    fold.ingestEvent(
      event(2050, 'assistant/message', {
        'turn': 1,
        'step': 1,
        'message': assistantMessage(),
      }),
    );
    expect(fold.value.llmMs, 1000);
    expect(fold.value.steps, 1);
  });
}
