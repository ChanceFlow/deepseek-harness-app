/// ContextRing parity tests — the ring is a permanent composer seat (an
/// empty outline-variant track until a sample and a route capacity exist,
/// where the web meter removes itself: `ContextMeter.tsx` returns null),
/// and the tap-open composition panel is an anchored `MenuAnchor` popup,
/// the web popover's mobile equivalent.
library;

import 'package:domain/model/context_pressure.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/ui/chat/context_ring.dart';
import 'package:app/ui/theme/theme.dart';

import '../../l10n_app.dart';

const ContextPressure _half = ContextPressure(
  pressureTokens: 15000,
  contextWindow: 30000,
);

Widget _host(
  ContextPressure? pressure, {
  ContextBreakdown? breakdown,
  ThemeData? theme,
}) => l10nApp(
  theme: theme,
  home: Scaffold(
    body: Center(
      child: KeyedSubtree(
        key: const ValueKey('ring-scope'),
        child: ContextRing(pressure: pressure, breakdown: breakdown),
      ),
    ),
  ),
);

/// The occupancy seat is a native determinate progress indicator.
final Finder _ringPaint = find.descendant(
  of: find.byKey(const ValueKey('ring-scope')),
  matching: find.byType(CircularProgressIndicator),
);

/// The empty seat: the indicator's own track drawn as a static circle.
final Finder _ringTrack = find.descendant(
  of: find.byKey(const ValueKey('ring-scope')),
  matching: find.byKey(const ValueKey('context-ring-track')),
);

Finder get _panel => find.text('System prompt');

void main() {
  testWidgets('the ring stays present as an empty track without data', (
    tester,
  ) async {
    // Null pressure, a bare sample without capacity, and a capacity
    // without a sample all keep the ring mounted — no layout reflow
    // beside the send control. The placeholder is the static track
    // circle, never a progress indicator (activity spinners elsewhere
    // are asserted absent through that same type finder).
    for (final pressure in <ContextPressure?>[
      null,
      const ContextPressure(pressureTokens: 100),
      const ContextPressure(contextWindow: 100),
    ]) {
      await tester.pumpWidget(_host(pressure));
      expect(find.byType(ContextRing), findsOneWidget);
      expect(_ringTrack, findsOneWidget);
      expect(_ringPaint, findsNothing);
    }
  });

  testWidgets('an empty ring carries the plain context label and is inert', (
    tester,
  ) async {
    await tester.pumpWidget(_host(const ContextPressure(pressureTokens: 100)));
    expect(find.bySemanticsLabel('Context'), findsOneWidget);

    await tester.tap(find.byType(ContextRing));
    await tester.pumpAndSettle();
    expect(_panel, findsNothing);
  });

  testWidgets('ring appears with the occupancy semantics label', (
    tester,
  ) async {
    await tester.pumpWidget(_host(_half));
    expect(_ringPaint, findsOneWidget);
    // The native ring is determinate at the occupancy fraction.
    final ring = tester.widget<CircularProgressIndicator>(_ringPaint);
    expect(ring.value, 0.5);
    expect(ring.strokeWidth, 2);
    expect(find.bySemanticsLabel('50% of context used'), findsOneWidget);
  });

  testWidgets('occupancy rides the projection, not the bare sample', (
    tester,
  ) async {
    // Web contextOccupancy (StatsLine.tsx): projectedTokens ?? pressureTokens.
    await tester.pumpWidget(
      _host(
        const ContextPressure(
          pressureTokens: 15000,
          projectedTokens: 7500,
          contextWindow: 30000,
        ),
      ),
    );
    final ring = tester.widget<CircularProgressIndicator>(_ringPaint);
    expect(ring.value, 0.25);
  });

  testWidgets('the ring reads its colors from scheme roles', (tester) async {
    for (final theme in [DshTheme.light(), DshTheme.dark()]) {
      await tester.pumpWidget(_host(_half, theme: theme));
      // MaterialApp lerps between themes; land on the new one.
      await tester.pump(const Duration(milliseconds: 400));
      final ring = tester.widget<CircularProgressIndicator>(_ringPaint);
      expect(ring.color, theme.colorScheme.secondary);
      expect(ring.backgroundColor, theme.colorScheme.outlineVariant);

      // The empty seat's placeholder circle carries the same track role.
      await tester.pumpWidget(_host(null, theme: theme));
      await tester.pump(const Duration(milliseconds: 400));
      final track = tester.widget<DecoratedBox>(_ringTrack);
      final border = (track.decoration as BoxDecoration).border as Border;
      expect(border.top.color, theme.colorScheme.outlineVariant);
      expect(border.top.width, 2);
    }
  });

  testWidgets('tap opens the anchored composition popup', (tester) async {
    final theme = DshTheme.light();
    await tester.pumpWidget(
      _host(
        _half,
        breakdown: const ContextBreakdown(
          systemTokens: 4000,
          toolsTokens: 1000,
          messageTokens: 10000,
        ),
        theme: theme,
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byType(ContextRing));
    await tester.pumpAndSettle();

    // The popup is the web panel's content: header, figures, legend.
    expect(find.text('50% of context used'), findsOneWidget);
    expect(find.text('~15K / 30K'), findsOneWidget);
    expect(_panel, findsOneWidget);
    expect(find.text('Tools'), findsOneWidget);
    expect(find.text('Messages'), findsOneWidget);

    // True figures render in the legend rows rather than constant 0s.
    expect(find.text('4000'), findsOneWidget);
    expect(find.text('1000'), findsOneWidget);
    expect(find.text('10000'), findsOneWidget);

    // The segmented breakdown bar exists with proportional segment flexes.
    final barFinder = find.byKey(const ValueKey('context-breakdown-bar'));
    expect(barFinder, findsOneWidget);
    final segments = tester
        .widgetList<Expanded>(
          find.descendant(of: barFinder, matching: find.byType(Expanded)),
        )
        .toList();
    expect(segments, hasLength(4));
    expect(segments[0].flex, 4000); // System prompt
    expect(segments[1].flex, 1000); // Tools
    expect(segments[2].flex, 10000); // Messages / conversation
    expect(segments[3].flex, 15000); // Remaining window track

    // Segment colors map to stock M3 scheme roles.
    final systemBox = tester.widget<ColoredBox>(
      find.descendant(
        of: find.byWidget(segments[0]),
        matching: find.byType(ColoredBox),
      ),
    );
    expect(systemBox.color, theme.colorScheme.outline);
    final toolsBox = tester.widget<ColoredBox>(
      find.descendant(
        of: find.byWidget(segments[1]),
        matching: find.byType(ColoredBox),
      ),
    );
    expect(toolsBox.color, theme.colorScheme.tertiary);
    final messagesBox = tester.widget<ColoredBox>(
      find.descendant(
        of: find.byWidget(segments[2]),
        matching: find.byType(ColoredBox),
      ),
    );
    expect(messagesBox.color, theme.colorScheme.primary);
    final trackBox = tester.widget<ColoredBox>(
      find.descendant(
        of: find.byWidget(segments[3]),
        matching: find.byType(ColoredBox),
      ),
    );
    expect(trackBox.color, theme.colorScheme.outlineVariant);
  });

  testWidgets('missing breakdown omits the bar and shows 0 counts', (
    tester,
  ) async {
    await tester.pumpWidget(_host(_half, breakdown: null));
    await tester.tap(find.byType(ContextRing));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('context-breakdown-bar')), findsNothing);
    expect(find.text('0'), findsNWidgets(3));
  });

  testWidgets('0-token breakdown parts are omitted from the segmented bar', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const ContextPressure(pressureTokens: 10000, contextWindow: 40000),
        breakdown: const ContextBreakdown(
          systemTokens: 0,
          toolsTokens: 2000,
          messageTokens: 8000,
        ),
      ),
    );
    await tester.tap(find.byType(ContextRing));
    await tester.pumpAndSettle();

    final barFinder = find.byKey(const ValueKey('context-breakdown-bar'));
    expect(barFinder, findsOneWidget);
    final segments = tester
        .widgetList<Expanded>(
          find.descendant(of: barFinder, matching: find.byType(Expanded)),
        )
        .toList();
    // System part with 0 tokens is dropped; tools, messages, remaining remain.
    expect(segments, hasLength(3));
    expect(segments[0].flex, 2000); // Tools
    expect(segments[1].flex, 8000); // Messages
    expect(segments[2].flex, 30000); // Remaining window track (40000 - 10000)
  });

  testWidgets('the popup floats on the house menu-surface card', (
    tester,
  ) async {
    final theme = DshTheme.light();
    await tester.pumpWidget(_host(_half, theme: theme));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byType(ContextRing));
    await tester.pumpAndSettle();

    // The panel rides a Material whose values match the kShapeMenuSheet
    // family: surfaceContainer, elevation 3, r12, outline-variant hairline.
    final menuMaterial = tester.widget<Material>(
      find.ancestor(of: _panel, matching: find.byType(Material)).first,
    );
    expect(menuMaterial.color, theme.colorScheme.surfaceContainer);
    expect(menuMaterial.elevation, 3);
    final shape = menuMaterial.shape as RoundedRectangleBorder;
    expect(shape.borderRadius, BorderRadius.circular(kShapeMenuSheet));
    expect(shape.side.color, theme.colorScheme.outlineVariant);
    expect(shape.side.width, 1);
    // A popup, not a modal dialog.
    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets('a second tap on the ring closes the popup', (tester) async {
    await tester.pumpWidget(_host(_half));
    await tester.tap(find.byType(ContextRing));
    await tester.pumpAndSettle();
    expect(_panel, findsOneWidget);

    // The popup owns the screen while open; the dismiss tap is consumed
    // at the ring's spot, leaving the popup closed.
    await tester.tap(find.byType(ContextRing));
    await tester.pumpAndSettle();
    expect(_panel, findsNothing);
  });

  testWidgets('tapping outside closes the popup', (tester) async {
    await tester.pumpWidget(_host(_half));
    await tester.tap(find.byType(ContextRing));
    await tester.pumpAndSettle();
    expect(_panel, findsOneWidget);

    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(_panel, findsNothing);

    // And the ring reopens it.
    await tester.tap(find.byType(ContextRing));
    await tester.pumpAndSettle();
    expect(_panel, findsOneWidget);
  });

  testWidgets('losing the sample while open closes the stale panel', (
    tester,
  ) async {
    await tester.pumpWidget(_host(_half));
    await tester.tap(find.byType(ContextRing));
    await tester.pumpAndSettle();
    expect(_panel, findsOneWidget);

    // A model switch can drop capacity while the popup is mounted
    // (the web meter's availability effect closes the panel).
    await tester.pumpWidget(_host(const ContextPressure(pressureTokens: 100)));
    await tester.pumpAndSettle();
    expect(_panel, findsNothing);
  });

  test('occupancy clamps above capacity', () {
    const pressure = ContextPressure(
      pressureTokens: 40000,
      contextWindow: 30000,
    );
    expect(pressure.occupancy, 1.0);
  });
}
