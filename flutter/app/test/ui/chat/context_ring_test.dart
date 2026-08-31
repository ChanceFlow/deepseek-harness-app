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
  Locale? locale,
}) => l10nApp(
  locale: locale,
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

Finder get _panel => find.byKey(const ValueKey('context-breakdown-bar'));

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

    // True figures render in the legend rows with compact token formatting.
    expect(find.text('~4K'), findsOneWidget);
    expect(find.text('~1K'), findsOneWidget);
    expect(find.text('~10K'), findsOneWidget);

    // The segmented breakdown bar exists with web's px geometry:
    // region = 240 × percent%, parts by share with a 2px min-width and
    // 1px gaps.
    final barFinder = find.byKey(const ValueKey('context-breakdown-bar'));
    expect(barFinder, findsOneWidget);
    final segmentBoxes = find.descendant(
      of: barFinder,
      matching: find.byType(ColoredBox),
    );
    final segments = tester
        .widgetList<ColoredBox>(segmentBoxes)
        .toList(growable: false);
    expect(segments, hasLength(3)); // remaining window is the track itself
    // used=15000 of 30000 → percent 50 → region 120px; shares
    // 4000/15000, 1000/15000, 10000/15000 → 32 + 8 + 80 (+2px of gaps).
    expect(tester.getSize(segmentBoxes.at(0)).width, closeTo(32, 0.5));
    expect(tester.getSize(segmentBoxes.at(1)).width, closeTo(8, 0.5));
    expect(tester.getSize(segmentBoxes.at(2)).width, closeTo(80, 0.5));

    // Segment colors map to stock M3 scheme roles.
    expect(segments[0].color, theme.colorScheme.outline); // System prompt
    expect(segments[1].color, theme.colorScheme.tertiary); // Tools
    expect(segments[2].color, theme.colorScheme.primary); // Messages
    // The bar's own background is the remaining-window track.
    final barBox = tester.widget<DecoratedBox>(
      find.descendant(of: barFinder, matching: find.byType(DecoratedBox)),
    );
    final track = (barBox.decoration as BoxDecoration).color;
    expect(track, theme.colorScheme.outlineVariant);
  });

  testWidgets(
    'missing breakdown renders the fallback bar and omits legend rows',
    (tester) async {
      final theme = DshTheme.light();
      await tester.pumpWidget(_host(_half, breakdown: null, theme: theme));
      await tester.tap(find.byType(ContextRing));
      await tester.pumpAndSettle();

      // The bar always renders with the single fallback segment (used
      // fraction): 50% of 240 = 120px of outline tint.
      final barFinder = find.byKey(const ValueKey('context-breakdown-bar'));
      expect(barFinder, findsOneWidget);
      final segmentBoxes = find.descendant(
        of: barFinder,
        matching: find.byType(ColoredBox),
      );
      expect(segmentBoxes, findsOneWidget);
      expect(tester.getSize(segmentBoxes).width, closeTo(120, 0.5));
      expect(
        tester.widget<ColoredBox>(segmentBoxes).color,
        theme.colorScheme.outline,
      );

      // Legend rows are gated on breakdown presence and omitted when null.
      expect(find.text('System prompt'), findsNothing);
      expect(find.text('Tools'), findsNothing);
      expect(find.text('Messages'), findsNothing);
    },
  );

  testWidgets(
    'all-zero breakdown parts render fallback single segment with legend rows',
    (tester) async {
      final theme = DshTheme.light();
      await tester.pumpWidget(
        _host(
          _half,
          breakdown: const ContextBreakdown(
            systemTokens: 0,
            toolsTokens: 0,
            messageTokens: 0,
          ),
          theme: theme,
        ),
      );
      await tester.tap(find.byType(ContextRing));
      await tester.pumpAndSettle();

      // Breakdown total is 0, so the bar falls back to the single used
      // segment: 120px of outline tint, and no colored Expanded.
      final barFinder = find.byKey(const ValueKey('context-breakdown-bar'));
      expect(barFinder, findsOneWidget);
      final segmentBoxes = find.descendant(
        of: barFinder,
        matching: find.byType(ColoredBox),
      );
      expect(segmentBoxes, findsOneWidget);
      expect(tester.getSize(segmentBoxes).width, closeTo(120, 0.5));

      // Legend rows render because breakdown is non-null.
      expect(find.text('System prompt'), findsOneWidget);
      expect(find.text('Tools'), findsOneWidget);
      expect(find.text('Messages'), findsOneWidget);
      expect(find.text('~0'), findsNWidgets(3));
    },
  );

  testWidgets('bilingual composition panel rendering (en and zh)', (
    tester,
  ) async {
    for (final (locale, usedText, tokensText, sysLabel) in [
      (
        const Locale('en'),
        '50% of context used',
        '~15K / 30K',
        'System prompt',
      ),
      (const Locale('zh'), '上下文已用 50%', '约 15K / 30K', '系统提示词'),
    ]) {
      await tester.pumpWidget(
        _host(
          _half,
          breakdown: const ContextBreakdown(
            systemTokens: 4000,
            toolsTokens: 1000,
            messageTokens: 10000,
          ),
          locale: locale,
        ),
      );
      await tester.tap(find.byType(ContextRing));
      await tester.pumpAndSettle();

      expect(find.text(usedText), findsOneWidget);
      expect(find.text(tokensText), findsOneWidget);
      expect(find.text(sysLabel), findsOneWidget);
      expect(
        find.byKey(const ValueKey('context-breakdown-bar')),
        findsOneWidget,
      );

      // Close for next iteration
      await tester.tap(find.byType(ContextRing));
      await tester.pumpAndSettle();
    }
  });

  testWidgets('a low-occupancy 1M-window session still shows hairline color '
      '(the web min-width rule)', (tester) async {
    // Real post-compaction figures from the live host: ~13K tokens in a
    // 1048576 window → 1% occupancy. The old integer-flex port rounded
    // every part to zero width and rendered a colorless bar.
    final theme = DshTheme.light();
    await tester.pumpWidget(
      _host(
        const ContextPressure(pressureTokens: 13409, contextWindow: 1048576),
        breakdown: const ContextBreakdown(
          systemTokens: 1600,
          toolsTokens: 6500,
          messageTokens: 5309,
        ),
        theme: theme,
      ),
    );
    await tester.tap(find.byType(ContextRing));
    await tester.pumpAndSettle();

    final segmentBoxes = find.descendant(
      of: find.byKey(const ValueKey('context-breakdown-bar')),
      matching: find.byType(ColoredBox),
    );
    // Region = 240 × 1% = 2.4px; shares would put system at 0.29px and
    // tools at 1.2px — the web `.segment` min-width 2px keeps each a
    // visible hairline instead of dropping it.
    expect(segmentBoxes, findsNWidgets(3));
    for (final width in [
      tester.getSize(segmentBoxes.at(0)).width,
      tester.getSize(segmentBoxes.at(1)).width,
      tester.getSize(segmentBoxes.at(2)).width,
    ]) {
      expect(width, greaterThanOrEqualTo(2.0));
    }
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
    final segmentBoxes = find.descendant(
      of: barFinder,
      matching: find.byType(ColoredBox),
    );
    final colors = tester
        .widgetList<ColoredBox>(segmentBoxes)
        .map((box) => box.color)
        .toList(growable: false);
    // The 0-token system part is dropped; tools and messages remain,
    // sized by their share of the 25% used region (60px).
    expect(colors, hasLength(2));
    expect(tester.getSize(segmentBoxes.at(0)).width, closeTo(12, 0.5));
    expect(tester.getSize(segmentBoxes.at(1)).width, closeTo(48, 0.5));

    // Legend rows display formatted token numbers with ~ prefix.
    expect(find.text('~0'), findsOneWidget);
    expect(find.text('~2K'), findsOneWidget);
    expect(find.text('~8K'), findsOneWidget);
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
