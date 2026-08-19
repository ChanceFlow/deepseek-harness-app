/// SessionStatsFold parity tests — the web deriveStats fallback semantics.
library;

import 'package:harness_adapter/harness_adapter.dart';
import 'package:test/test.dart';

void main() {
  test('empty log yields zeroed stats', () {
    final fold = SessionStatsFold()..reset(const []);
    expect(fold.value.turns, 0);
    expect(fold.value.steps, 0);
    expect(fold.value.cacheHitPercent, isNull);
  });

  test('one full turn: counts, llm, ttft, decode, usage', () {
    final fold = SessionStatsFold()
      ..reset([
        <String, Object?>{'type': 'turn/start', 'turn': 1, 'time': 1000},
        <String, Object?>{'type': 'user/message', 'time': 1100},
        <String, Object?>{
          'type': 'assistant/chunk',
          'time': 2200,
          'chunk': {'type': 'text-delta', 'text': 'a'},
        },
        <String, Object?>{
          'type': 'assistant/message',
          'time': 5200,
          'usage': {
            'inputTokens': 800,
            'cacheReadTokens': 200,
            'cacheWriteTokens': 100,
            'outputTokens': 60,
          },
        },
      ]);
    final stats = fold.value;
    expect(stats.turns, 1);
    expect(stats.steps, 1);
    expect(stats.llmMs, 4100); // step start (user msg 1100) -> 5200
    expect(stats.ttftMs, 1100); // 1100 -> first chunk 2200
    expect(stats.ttftSteps, 1);
    expect(stats.decodeMs, 3000); // first chunk 2200 -> 5200
    expect(stats.decodeTokens, 60);
    expect(stats.billedInputTokens, 1100); // 800+200+100
    expect(stats.outputTokens, 60);
    expect(stats.cacheHitPercent, 18); // 200/1100
  });

  test('tool call pairs accumulate tool wall time', () {
    final fold = SessionStatsFold()
      ..reset([
        <String, Object?>{'type': 'turn/start', 'turn': 1, 'time': 1000},
        <String, Object?>{'type': 'tool/call', 'id': 'c1', 'time': 2000},
        <String, Object?>{'type': 'tool/result', 'callId': 'c1', 'time': 4500},
      ]);
    expect(fold.value.toolMs, 2500);
    expect(fold.value.turns, 1);
  });

  test('step anchor advances after tool results', () {
    final fold = SessionStatsFold()
      ..reset([
        <String, Object?>{'type': 'turn/start', 'turn': 1, 'time': 1000},
        <String, Object?>{'type': 'tool/call', 'id': 'c1', 'time': 1100},
        <String, Object?>{'type': 'tool/result', 'callId': 'c1', 'time': 2100},
        <String, Object?>{
          'type': 'assistant/message',
          'time': 3100,
          'usage': {'inputTokens': 10, 'outputTokens': 5},
        },
      ]);
    // llm measured from the tool result (2100), not the turn start.
    expect(fold.value.llmMs, 1000);
  });
}
