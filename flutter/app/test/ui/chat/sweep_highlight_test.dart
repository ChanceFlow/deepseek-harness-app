/// The shared sweep primitive's contract: the reference's `steps(48, end)`
/// quantisation over a 1.5s cycle after a 0.3s delay, one announced and
/// selectable text node under the band, nesting that takes the enclosing row's
/// activity, and stillness under reduced motion.
library;

import 'package:app/ui/chat/sweep_highlight.dart';
import 'package:app/ui/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../l10n_app.dart';

/// One step of the reference's 48-step travel, in microseconds.
const int _stepUs = 1000000 ~/ 48;

/// [elapsed] measured on the row's clock, past the reference's start delay.
Duration _after(Duration elapsed) => kSweepDelay + elapsed;

/// A repeating clock of the period the app's call sites build today.
///
/// The test body must call [AnimationController.stop] before it ends: the
/// framework's ticker invariant runs ahead of `addTearDown`, so a live ticker
/// fails the test even though the teardown would dispose it.
AnimationController _clock(WidgetTester tester) {
  final controller = AnimationController(
    vsync: const TestVSync(),
    duration: const Duration(milliseconds: 2600),
  )..repeat();
  addTearDown(controller.dispose);
  return controller;
}

/// The caller's activity signal without a live ticker: the band is a structural
/// fact of the tree, so only the clock-wiring test needs the clock to run.
AnimationController _activeClock() {
  final controller = AnimationController(
    vsync: const TestVSync(),
    duration: const Duration(milliseconds: 2600),
  );
  addTearDown(controller.dispose);
  return controller;
}

void main() {
  group('sweepTravel', () {
    test('holds the band off the content through the 0.3s delay', () {
      expect(sweepTravel(Duration.zero), -1);
      expect(sweepTravel(const Duration(milliseconds: 150)), -1);
      expect(sweepTravel(kSweepDelay), -1);
    });

    test('quantises the travel instead of interpolating it', () {
      // The first step holds `-1` for 1/72 of the cycle (20.833ms); a smooth
      // lerp would already read -0.98 ten milliseconds in.
      expect(sweepTravel(_after(const Duration(milliseconds: 10))), -1);
      expect(sweepTravel(_after(const Duration(microseconds: _stepUs))), -1);
      expect(
        sweepTravel(_after(const Duration(microseconds: _stepUs + 1))),
        -1 + 2 / kSweepSteps,
      );
    });

    test('steps the whole travel in 48 equal positions', () {
      final positions = <double>[
        for (var step = 0; step < kSweepSteps; step++)
          // 10ms inside the step, which is shorter than its 20.833ms.
          sweepTravel(_after(Duration(microseconds: step * _stepUs + 10000))),
      ];
      expect(positions.toSet(), hasLength(kSweepSteps));
      expect(positions.first, -1);
      expect(
        positions.last,
        closeTo(-1 + 2 * (kSweepSteps - 1) / kSweepSteps, 1e-12),
      );
      for (var index = 1; index < positions.length; index++) {
        expect(
          positions[index] - positions[index - 1],
          closeTo(2 / kSweepSteps, 1e-12),
        );
      }
    });

    test('holds at the far edge for the last third of the cycle', () {
      expect(sweepTravel(_after(const Duration(milliseconds: 1000))), 1);
      expect(sweepTravel(_after(const Duration(milliseconds: 1200))), 1);
      expect(sweepTravel(_after(const Duration(milliseconds: 1499))), 1);
    });

    test('restarts every 1.5s', () {
      expect(sweepTravel(_after(kSweepCycle)), -1);
      expect(
        sweepTravel(_after(kSweepCycle + const Duration(milliseconds: 400))),
        sweepTravel(_after(const Duration(milliseconds: 400))),
      );
    });
  });

  group('sweepGlint', () {
    test('is the platform neutral wash on onSurface', () {
      final light = DshTheme.light().colorScheme;
      expect(sweepGlint(light), light.onSurface.withValues(alpha: 0.30));
      final dark = DshTheme.dark().colorScheme;
      expect(sweepGlint(dark), dark.onSurface.withValues(alpha: 0.45));
    });
  });

  group('sweepBand', () {
    test('is the reference trapezoid placed at the travel', () {
      final glint = DshTheme.light().colorScheme.onSurface.withValues(
        alpha: 0.30,
      );
      final band = sweepBand(0, glint);
      expect(band.colors, <Color>[
        glint.withValues(alpha: 0),
        glint,
        glint,
        glint.withValues(alpha: 0),
      ]);
      expect(band.stops, const <double>[0, 0.4, 0.6, 1]);
      expect(band.begin, const Alignment(-1, 0));
      expect(band.end, const Alignment(1, 0));
      expect(sweepBand(-1, glint).begin, const Alignment(-3, 0));
      expect(sweepBand(-1, glint).end, const Alignment(-1, 0));
      expect(sweepBand(1, glint).begin, const Alignment(1, 0));
      expect(sweepBand(1, glint).end, const Alignment(3, 0));
    });
  });

  testWidgets('paints the band over the one real text node', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      l10nApp(
        theme: DshTheme.light(),
        home: Center(
          child: SweepHighlight(
            controller: _activeClock(),
            child: const Text('deep diving'),
          ),
        ),
      ),
    );

    // One text node, announced once: the highlight adds no copy to the tree, so
    // the row cannot be read or selected twice.
    expect(find.text('deep diving'), findsOneWidget);
    expect(find.bySemanticsLabel('deep diving'), findsOneWidget);
    // The band tints that node: the mask wraps the row's own text.
    final mask = find.byType(ShaderMask);
    expect(mask, findsOneWidget);
    expect(
      find.descendant(of: mask, matching: find.text('deep diving')),
      findsOneWidget,
    );
    expect(tester.widget<ShaderMask>(mask).blendMode, BlendMode.srcATop);
    semantics.dispose();
  });

  testWidgets("a nested instance takes the enclosing row's activity", (
    tester,
  ) async {
    await tester.pumpWidget(
      l10nApp(
        theme: DshTheme.light(),
        home: SweepHighlight(
          controller: _activeClock(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Text('reading files'),
              SweepHighlight(
                controller: _activeClock(),
                child: const Text('and more'),
              ),
            ],
          ),
        ),
      ),
    );

    // One highlight for the row: the nested instance renders content only, and
    // the row's text stays single.
    expect(find.byType(ShaderMask), findsOneWidget);
    expect(find.text('reading files'), findsOneWidget);
    expect(find.text('and more'), findsOneWidget);
  });

  testWidgets("drives the band from the clock's elapsed time", (tester) async {
    final controller = _clock(tester);
    await tester.pumpWidget(
      l10nApp(
        theme: DshTheme.light(),
        home: Center(
          child: SweepHighlight(
            controller: controller,
            child: const Text('deep diving'),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));

    // The highlight layer reads the row's clock, not a period of its own: the
    // pinned 1.5s cycle comes off the controller's elapsed time, whatever period
    // the caller built the controller with.
    expect(
      tester
          .widget<AnimatedBuilder>(
            find
                .ancestor(
                  of: find.byType(ShaderMask),
                  matching: find.byType(AnimatedBuilder),
                )
                .first,
          )
          .animation,
      same(controller),
    );
    final elapsed = controller.lastElapsedDuration;
    expect(elapsed, isNotNull);
    expect(sweepTravel(elapsed!), greaterThan(-1));
    controller.stop();
  });

  testWidgets('reduced motion leaves the row still', (tester) async {
    final controller = _activeClock();
    await tester.pumpWidget(
      l10nApp(
        theme: DshTheme.light(),
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: SweepHighlight(
              controller: controller,
              child: const Text('deep diving'),
            ),
          ),
        ),
      ),
    );

    expect(find.byType(ShaderMask), findsNothing);
    expect(find.text('deep diving'), findsOneWidget);
  });

  testWidgets('a still row renders its child unchanged', (tester) async {
    await tester.pumpWidget(
      l10nApp(
        theme: DshTheme.light(),
        home: const SweepHighlight(controller: null, child: Text('settled')),
      ),
    );
    expect(find.byType(ShaderMask), findsNothing);
    expect(find.text('settled'), findsOneWidget);
  });
}
