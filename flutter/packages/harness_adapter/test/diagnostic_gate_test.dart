/// Unit tests for [DiagnosticGate]: the throttle behind the adapter's
/// repeated-decode diagnostics. The clock is injected so a window is crossed
/// without a real wait.
library;

import 'package:harness_adapter/src/diagnostic_gate.dart';
import 'package:test/test.dart';

void main() {
  group('DiagnosticGate', () {
    late DateTime now;
    late DiagnosticGate gate;

    setUp(() {
      now = DateTime.utc(2026, 1, 1, 12);
      gate = DiagnosticGate(now: () => now);
    });

    test(
      'admits the first occurrence and suppresses repeats in the window',
      () {
        expect(gate.admit('agentTeam|FormatException|missing tasks'), 0);
        expect(gate.admit('agentTeam|FormatException|missing tasks'), isNull);
        now = now.add(const Duration(seconds: 59));
        expect(gate.admit('agentTeam|FormatException|missing tasks'), isNull);
      },
    );

    test('the first admit after the window reports and resets the count', () {
      expect(gate.admit('key'), 0);
      expect(gate.admit('key'), isNull);
      expect(gate.admit('key'), isNull);
      now = now.add(const Duration(seconds: 60));
      expect(gate.admit('key'), 2);
      expect(gate.admit('key'), isNull);
      now = now.add(const Duration(seconds: 60));
      expect(gate.admit('key'), 1);
    });

    test('distinct keys do not interfere', () {
      expect(gate.admit('a'), 0);
      expect(gate.admit('b'), 0);
      expect(gate.admit('a'), isNull);
      expect(gate.admit('b'), isNull);
      now = now.add(const Duration(seconds: 60));
      expect(gate.admit('a'), 1);
      expect(gate.admit('b'), 1);
    });

    test('honours an injected window shorter than the default', () {
      final fast = DiagnosticGate(
        now: () => now,
        window: const Duration(seconds: 5),
      );
      expect(fast.admit('key'), 0);
      now = now.add(const Duration(seconds: 4));
      expect(fast.admit('key'), isNull);
      now = now.add(const Duration(seconds: 1));
      expect(fast.admit('key'), 1);
    });
  });
}
