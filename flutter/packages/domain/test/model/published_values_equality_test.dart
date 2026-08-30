/// Value equality of the per-event republished projection values.
///
/// The adapter's folds re-mint these types on every session event; the
/// StateStream assignment gate suppresses a republish only when the fresh
/// value equals the current one, so this equality is the load-bearing
/// contract for "no change, no publish".
library;

import 'package:test/test.dart';

import 'package:domain/model/context_pressure.dart';
import 'package:domain/model/session_window_stats.dart';

void main() {
  group('ContextPressure', () {
    test('equal when all three records match', () {
      const a = ContextPressure(
        pressureTokens: 100,
        projectedTokens: 120,
        contextWindow: 1000,
      );
      const b = ContextPressure(
        pressureTokens: 100,
        projectedTokens: 120,
        contextWindow: 1000,
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('unequal when any record moves', () {
      const base = ContextPressure(
        pressureTokens: 100,
        projectedTokens: 120,
        contextWindow: 1000,
      );
      expect(
        base,
        isNot(
          const ContextPressure(
            pressureTokens: 101,
            projectedTokens: 120,
            contextWindow: 1000,
          ),
        ),
      );
      expect(
        base,
        isNot(
          const ContextPressure(
            pressureTokens: 100,
            projectedTokens: 121,
            contextWindow: 1000,
          ),
        ),
      );
      expect(
        base,
        isNot(
          const ContextPressure(
            pressureTokens: 100,
            projectedTokens: 120,
            contextWindow: 1001,
          ),
        ),
      );
    });

    test('nulls compare by field', () {
      expect(const ContextPressure(), const ContextPressure());
      expect(
        const ContextPressure(),
        isNot(const ContextPressure(pressureTokens: 0)),
      );
    });
  });

  group('ContextBreakdown', () {
    test('equal when all three token totals match', () {
      const a = ContextBreakdown(
        systemTokens: 10,
        toolsTokens: 20,
        messageTokens: 30,
      );
      const b = ContextBreakdown(
        systemTokens: 10,
        toolsTokens: 20,
        messageTokens: 30,
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a.total, 60);
    });

    test('unequal when any bucket moves', () {
      const base = ContextBreakdown(
        systemTokens: 10,
        toolsTokens: 20,
        messageTokens: 30,
      );
      expect(
        base,
        isNot(
          const ContextBreakdown(
            systemTokens: 11,
            toolsTokens: 20,
            messageTokens: 30,
          ),
        ),
      );
    });
  });

  group('SessionWindowStats', () {
    test('defaults are equal', () {
      expect(const SessionWindowStats(), const SessionWindowStats());
      expect(
        const SessionWindowStats().hashCode,
        const SessionWindowStats().hashCode,
      );
    });

    test('every folded field participates in equality', () {
      const base = SessionWindowStats(
        turns: 1,
        steps: 2,
        llmMs: 3,
        toolMs: 4,
        ttftMs: 5,
        ttftSteps: 6,
        decodeMs: 7,
        decodeTokens: 8,
        billedInputTokens: 9,
        outputTokens: 10,
        cacheReadTokens: 11,
      );
      expect(base, isNot(const SessionWindowStats(turns: 2)));
      expect(
        base,
        isNot(
          const SessionWindowStats(
            turns: 1,
            steps: 2,
            llmMs: 3,
            toolMs: 4,
            ttftMs: 5,
            ttftSteps: 6,
            decodeMs: 7,
            decodeTokens: 8,
            billedInputTokens: 9,
            outputTokens: 10,
            cacheReadTokens: 12,
          ),
        ),
      );
    });

    test('equal stats carry equal cache-hit share', () {
      const a = SessionWindowStats(billedInputTokens: 100, cacheReadTokens: 50);
      const b = SessionWindowStats(billedInputTokens: 100, cacheReadTokens: 50);
      expect(a, b);
      expect(a.cacheHitPercent, b.cacheHitPercent);
    });
  });
}
