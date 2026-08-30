/// Context projection DTO tests — verifies decoding of `contextPressure` and
/// `contextBreakdown` projections against the reference shapes
/// (reference/deepseek-harness/packages/llm/token-meter/src/usage-projection.ts,
/// reference/deepseek-harness/packages/llm/token-meter/src/breakdown-projection.ts,
/// reference/deepseek-harness/packages/host/apiproxy/src/api/sessions.schema.ts,
/// reference/deepseek-harness/packages/host/apiproxy/src/api/events.schema.ts).
library;

import 'package:harness_adapter/harness_adapter.dart';
import 'package:test/test.dart';

void main() {
  group('decodeContextPressureProjection', () {
    test('decodes full live host payload', () {
      // Live host payload shape captured from dsh 127.0.0.1:3080
      final json = <String, Object?>{
        'pressureTokens': 390103,
        'projectedTokens': 390450,
        'contextWindow': 1000000,
      };

      final decoded = decodeContextPressureProjection(json);

      expect(decoded.pressureTokens, 390103);
      expect(decoded.projectedTokens, 390450);
      expect(decoded.contextWindow, 1000000);
      expect(decoded.occupancy, closeTo(0.390103, 1e-6));
    });

    test('tolerates missing optional fields without guessing', () {
      final json = <String, Object?>{
        'pressureTokens': 15000,
        'contextWindow': 30000,
      };

      final decoded = decodeContextPressureProjection(json);

      expect(decoded.pressureTokens, 15000);
      expect(decoded.projectedTokens, isNull);
      expect(decoded.contextWindow, 30000);
      expect(decoded.occupancy, 0.5);
    });

    test('decodes empty object to all nulls', () {
      final decoded = decodeContextPressureProjection(<String, Object?>{});

      expect(decoded.pressureTokens, isNull);
      expect(decoded.projectedTokens, isNull);
      expect(decoded.contextWindow, isNull);
      expect(decoded.occupancy, isNull);
    });

    test('coerces string numbers and floats defensively', () {
      final json = <String, Object?>{
        'pressureTokens': '20000',
        'projectedTokens': 25000.0,
        'contextWindow': '100000',
      };

      final decoded = decodeContextPressureProjection(json);

      expect(decoded.pressureTokens, 20000);
      expect(decoded.projectedTokens, 25000);
      expect(decoded.contextWindow, 100000);
    });

    test('throws FormatException on non-object values (fail loud)', () {
      expect(
        () => decodeContextPressureProjection(null),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => decodeContextPressureProjection('malformed'),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => decodeContextPressureProjection(12345),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => decodeContextPressureProjection(<Object?>[1, 2, 3]),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('decodeContextBreakdownProjection', () {
    test('decodes full live host payload', () {
      // Live host payload shape captured from dsh 127.0.0.1:3080
      final json = <String, Object?>{
        'systemTokens': 1582,
        'toolsTokens': 6475,
        'messageTokens': 269949,
      };

      final decoded = decodeContextBreakdownProjection(json);

      expect(decoded.systemTokens, 1582);
      expect(decoded.toolsTokens, 6475);
      expect(decoded.messageTokens, 269949);
      expect(decoded.total, 1582 + 6475 + 269949);
    });

    test('defaults omitted fields to 0', () {
      final json = <String, Object?>{'messageTokens': 500};

      final decoded = decodeContextBreakdownProjection(json);

      expect(decoded.systemTokens, 0);
      expect(decoded.toolsTokens, 0);
      expect(decoded.messageTokens, 500);
      expect(decoded.total, 500);
    });

    test('decodes empty object to all zeroes', () {
      final decoded = decodeContextBreakdownProjection(<String, Object?>{});

      expect(decoded.systemTokens, 0);
      expect(decoded.toolsTokens, 0);
      expect(decoded.messageTokens, 0);
      expect(decoded.total, 0);
    });

    test('coerces string numbers defensively', () {
      final json = <String, Object?>{
        'systemTokens': '100',
        'toolsTokens': '200',
        'messageTokens': '300',
      };

      final decoded = decodeContextBreakdownProjection(json);

      expect(decoded.systemTokens, 100);
      expect(decoded.toolsTokens, 200);
      expect(decoded.messageTokens, 300);
    });

    test('throws FormatException on non-object values (fail loud)', () {
      expect(
        () => decodeContextBreakdownProjection(null),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => decodeContextBreakdownProjection('malformed'),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => decodeContextBreakdownProjection(42),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('SessionHistoryValueWire projections parsing', () {
    test('parses asOfSeq and projection values from history tail page', () {
      final historyJson = <String, Object?>{
        'events': <Object?>[],
        'hasMore': false,
        'projections': <String, Object?>{
          'asOfSeq': 90132,
          'values': <String, Object?>{
            'contextPressure': <String, Object?>{
              'pressureTokens': 390103,
              'projectedTokens': 390450,
              'contextWindow': 1000000,
            },
            'contextBreakdown': <String, Object?>{
              'systemTokens': 1582,
              'toolsTokens': 6475,
              'messageTokens': 269949,
            },
          },
        },
      };

      final wire = SessionHistoryValueWire.fromJson(historyJson);

      expect(wire.hasMore, isFalse);
      expect(wire.asOfSeq, 90132);
      expect(wire.projectionValues, isNotNull);
      expect(wire.projectionValues!['contextPressure'], isNotNull);
      expect(wire.projectionValues!['contextBreakdown'], isNotNull);

      final pressure = decodeContextPressureProjection(
        wire.projectionValues!['contextPressure'],
      );
      expect(pressure.pressureTokens, 390103);
      expect(pressure.contextWindow, 1000000);

      final breakdown = decodeContextBreakdownProjection(
        wire.projectionValues!['contextBreakdown'],
      );
      expect(breakdown.systemTokens, 1582);
      expect(breakdown.toolsTokens, 6475);
      expect(breakdown.messageTokens, 269949);
    });

    test('handles absent projections block on non-tail pages', () {
      final historyJson = <String, Object?>{
        'events': <Object?>[],
        'hasMore': true,
      };

      final wire = SessionHistoryValueWire.fromJson(historyJson);

      expect(wire.hasMore, isTrue);
      expect(wire.projections, isNull);
      expect(wire.asOfSeq, -1);
      expect(wire.projectionValues, isNull);
    });
  });
}
