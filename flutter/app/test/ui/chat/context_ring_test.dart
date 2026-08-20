/// ContextRing parity tests — hidden until pressure + capacity exist.
library;

import 'package:domain/model/context_pressure.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/ui/chat/context_ring.dart';

import '../../l10n_app.dart';

Widget _host(ContextPressure? pressure) => l10nApp(
  home: Scaffold(
    body: Center(
      child: KeyedSubtree(
        key: const ValueKey('ring-scope'),
        child: ContextRing(pressure: pressure),
      ),
    ),
  ),
);

final Finder _ringPaint = find.descendant(
  of: find.byKey(const ValueKey('ring-scope')),
  matching: find.byType(CustomPaint),
);

void main() {
  testWidgets('renders nothing without both records', (tester) async {
    await tester.pumpWidget(_host(null));
    expect(find.byType(ContextRing), findsOneWidget);
    expect(_ringPaint, findsNothing);

    await tester.pumpWidget(_host(const ContextPressure(pressureTokens: 100)));
    expect(_ringPaint, findsNothing);

    await tester.pumpWidget(_host(const ContextPressure(contextWindow: 100)));
    expect(_ringPaint, findsNothing);
  });

  testWidgets('ring appears with the occupancy semantics label', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(const ContextPressure(pressureTokens: 15000, contextWindow: 30000)),
    );
    expect(_ringPaint, findsOneWidget);
    expect(find.bySemanticsLabel('50% of context used'), findsOneWidget);
  });

  testWidgets('tap opens the composition panel', (tester) async {
    await tester.pumpWidget(
      _host(const ContextPressure(pressureTokens: 15000, contextWindow: 30000)),
    );
    await tester.tap(find.byType(ContextRing));
    await tester.pumpAndSettle();

    expect(find.text('50% of context used'), findsOneWidget);
    expect(find.text('System prompt'), findsOneWidget);
    expect(find.text('Tools'), findsOneWidget);
    expect(find.text('Messages'), findsOneWidget);
  });

  test('occupancy clamps above capacity', () {
    const pressure = ContextPressure(
      pressureTokens: 40000,
      contextWindow: 30000,
    );
    expect(pressure.occupancy, 1.0);
  });
}
