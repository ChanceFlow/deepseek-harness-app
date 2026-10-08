/// RunningWhaleTail tests — the running Turn's brand mark fills the reference
/// 14px icon seat with the reference `REST_PATH` geometry, takes its ink from
/// the caller or the ambient text colour, sways only where the host allows
/// motion, and disposes its controller on unmount.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/ui/chat/fish_logo.dart' show parseSvgPath;
import 'package:app/ui/chat/running_whale_tail.dart';
import 'package:app/ui/theme/theme.dart';

import '../../l10n_app.dart';

/// The sway amplitude the widget carries, in radians: the reference APNG's
/// measured ink-centroid excursion (0.86px in its 28px frame) expressed at the
/// 14px seat.
const double _amplitude = 0.05;

/// The mark in the app's localization shell, with the ambient text style and
/// accessibility settings a case needs.
Widget _host(
  Widget child, {
  MediaQueryData? media,
  TextStyle? ambient,
  ThemeData? theme,
}) => l10nApp(
  theme: theme,
  home: MediaQuery(
    data: media ?? const MediaQueryData(size: Size(400, 800)),
    child: Scaffold(
      body: Center(
        child: DefaultTextStyle(
          style: ambient ?? const TextStyle(fontSize: 14),
          child: child,
        ),
      ),
    ),
  ),
);

final Finder _paintFinder = find.descendant(
  of: find.byType(RunningWhaleTail),
  matching: find.byType(CustomPaint),
);

final Finder _swayFinder = find.descendant(
  of: find.byType(RunningWhaleTail),
  matching: find.byType(Transform),
);

/// The painter the mark mounted, read back from the render tree.
RunningWhaleTailPainter _ink(WidgetTester tester) =>
    tester.widget<CustomPaint>(_paintFinder).painter!
        as RunningWhaleTailPainter;

/// The mounted sway's sine term: zero at the beat's start, ± [_amplitude] at
/// its quarter points.
double _sway(WidgetTester tester) =>
    tester.widget<Transform>(_swayFinder).transform.entry(0, 1);

void main() {
  testWidgets('the mark fills the reference 14px seat and honours size', (
    tester,
  ) async {
    await tester.pumpWidget(_host(const RunningWhaleTail()));
    expect(tester.getSize(find.byType(RunningWhaleTail)), const Size(14, 14));
    expect(tester.getSize(_paintFinder), const Size(14, 14));
    // The reference's `overflow: hidden`: the fixed footprint contains the
    // sway at every size.
    expect(
      find.descendant(
        of: find.byType(RunningWhaleTail),
        matching: find.byType(ClipRect),
      ),
      findsOneWidget,
    );

    await tester.pumpWidget(_host(const RunningWhaleTail(size: 28)));
    expect(tester.getSize(find.byType(RunningWhaleTail)), const Size(28, 28));
    expect(tester.getSize(_paintFinder), const Size(28, 28));
  });

  testWidgets('the ink follows the ambient text colour', (tester) async {
    final theme = DshTheme.light();
    await tester.pumpWidget(
      _host(
        const RunningWhaleTail(),
        theme: theme,
        ambient: TextStyle(color: theme.colorScheme.error),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));

    expect(_ink(tester).color, theme.colorScheme.error);
  });

  testWidgets('an explicit colour overrides the ambient one', (tester) async {
    final theme = DshTheme.light();
    await tester.pumpWidget(
      _host(
        RunningWhaleTail(color: theme.colorScheme.primary),
        theme: theme,
        ambient: TextStyle(color: theme.colorScheme.error),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));

    expect(_ink(tester).color, theme.colorScheme.primary);
  });

  testWidgets('without an ambient text colour the ink is the scheme role', (
    tester,
  ) async {
    for (final theme in [DshTheme.light(), DshTheme.dark()]) {
      await tester.pumpWidget(_host(const RunningWhaleTail(), theme: theme));
      await tester.pump(const Duration(milliseconds: 400));

      expect(_ink(tester).color, theme.colorScheme.onSurface);
    }
  });

  testWidgets('the tail sways one beat while motion is allowed', (
    tester,
  ) async {
    await tester.pumpWidget(_host(const RunningWhaleTail()));
    // The ticker's first tick seeds its start time; the beat runs from there.
    await tester.pump();

    expect(_swayFinder, findsOneWidget);
    expect(tester.binding.transientCallbackCount, greaterThan(0));
    expect(_sway(tester), 0.0);

    await tester.pump(const Duration(milliseconds: 250));
    // The fake clock's frame granularity leaves the quarter point approximate,
    // so the amplitude is pinned within 4% of the value the widget declares.
    final quarter = _sway(tester);
    expect(quarter.abs(), closeTo(_amplitude, 0.002));

    // Half a beat later the sway has reversed.
    await tester.pump(const Duration(milliseconds: 500));
    final threeQuarter = _sway(tester);
    expect(threeQuarter * quarter, lessThan(0));
    expect(threeQuarter.abs(), closeTo(quarter.abs(), 0.002));
  });

  testWidgets('reduced motion draws the still path with no ticker', (
    tester,
  ) async {
    final theme = DshTheme.light();
    await tester.pumpWidget(
      _host(
        const RunningWhaleTail(),
        theme: theme,
        ambient: TextStyle(color: theme.colorScheme.error),
        media: const MediaQueryData(
          size: Size(400, 800),
          disableAnimations: true,
        ),
      ),
    );
    await tester.pump();

    expect(_swayFinder, findsNothing);
    expect(tester.binding.transientCallbackCount, 0);
    // The still path is drawn, in the resolved ink.
    expect(_ink(tester).color, theme.colorScheme.error);

    // Two beats later the frame is unchanged: no controller, no ticker.
    await tester.pump(const Duration(seconds: 2));
    expect(_swayFinder, findsNothing);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('turning animations off stops the sway and on resumes it', (
    tester,
  ) async {
    await tester.pumpWidget(_host(const RunningWhaleTail()));
    await tester.pump();
    expect(_swayFinder, findsOneWidget);
    expect(tester.binding.transientCallbackCount, greaterThan(0));

    await tester.pumpWidget(
      _host(
        const RunningWhaleTail(),
        media: const MediaQueryData(
          size: Size(400, 800),
          disableAnimations: true,
        ),
      ),
    );
    await tester.pump();
    expect(_swayFinder, findsNothing);
    expect(tester.binding.transientCallbackCount, 0);

    await tester.pumpWidget(_host(const RunningWhaleTail()));
    await tester.pump();
    expect(_swayFinder, findsOneWidget);
    expect(tester.binding.transientCallbackCount, greaterThan(0));
  });

  testWidgets('unmounting disposes the sway controller', (tester) async {
    await tester.pumpWidget(_host(const RunningWhaleTail()));
    await tester.pump();
    expect(tester.binding.transientCallbackCount, greaterThan(0));

    await tester.pumpWidget(_host(const SizedBox.shrink()));
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);

    // A reduced-motion mount (controller created, never started) disposes just
    // as cleanly.
    await tester.pumpWidget(
      _host(
        const RunningWhaleTail(),
        media: const MediaQueryData(
          size: Size(400, 800),
          disableAnimations: true,
        ),
      ),
    );
    await tester.pumpWidget(_host(const SizedBox.shrink()));
    expect(tester.takeException(), isNull);
  });

  test('the still path is the reference REST_PATH, verbatim', () {
    // 547 characters: one absolute M and fifteen absolute C segments. A
    // relative or unsupported command would not survive parseSvgPath.
    expect(runningWhaleRestPath.length, 547);
    expect(runningWhaleRestPath.startsWith('M8.844 13.742'), isTrue);
    expect(runningWhaleRestPath.endsWith('4.926 13.742'), isTrue);
    expect(RegExp('[a-z]').hasMatch(runningWhaleRestPath), isFalse);
    expect('M'.allMatches(runningWhaleRestPath).length, 1);
    expect('C'.allMatches(runningWhaleRestPath).length, 15);

    final bounds = parseSvgPath(runningWhaleRestPath).getBounds();
    expect(bounds.isEmpty, isFalse);
    expect(bounds.left, greaterThanOrEqualTo(0.0));
    expect(bounds.top, greaterThanOrEqualTo(0.0));
    expect(bounds.right, lessThanOrEqualTo(runningWhaleViewBox));
    expect(bounds.bottom, lessThanOrEqualTo(runningWhaleViewBox));
  });

  test('the stroke scales with the box like the reference viewBox', () {
    // The SVG strokes a 16-unit viewBox at width 1, so the 14px seat renders
    // the reference's own 0.875px weight.
    expect(RunningWhaleTailPainter.strokeWidthFor(14), closeTo(0.875, 1e-9));
    expect(RunningWhaleTailPainter.strokeWidthFor(28), closeTo(1.75, 1e-9));
  });
}
