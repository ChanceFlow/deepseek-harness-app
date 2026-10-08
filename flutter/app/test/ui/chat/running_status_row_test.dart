/// Running-status row tests: the tail, the deep-diving label with its clock,
/// the reference's sweep timing, the single live-region announcement, and the
/// row's behaviour under reduced motion and large text scales.
library;

import 'package:app/ui/chat/running_status_row.dart';
import 'package:app/ui/chat/running_whale_tail.dart';
import 'package:app/ui/chat/sweep_highlight.dart';
import 'package:app/ui/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../l10n_app.dart';

/// Pumps the row inside a bounded column, the way the transcript seats it.
///
/// The ambient [MediaQuery] is copied rather than replaced, so the surface
/// keeps its size while the accessibility facts change.
Future<void> _pump(
  WidgetTester tester, {
  int? startedAtEpochMs,
  bool showDivider = false,
  bool reducedMotion = false,
  double textScale = 1.0,
  double width = 320,
}) async {
  await tester.pumpWidget(
    l10nApp(
      theme: DshTheme.light(),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            child: Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  disableAnimations: reducedMotion,
                  textScaler: TextScaler.linear(textScale),
                ),
                child: RunningStatusRow(
                  startedAtEpochMs: startedAtEpochMs,
                  showDivider: showDivider,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

int _startedAgo(int ms) => DateTime.now().millisecondsSinceEpoch - ms;

/// One second of the row's clock: a real wall-clock advance (the label reads
/// `DateTime.now`) plus the fake tick that republishes it (the 1 Hz timer).
Future<void> _tick(WidgetTester tester) async {
  await tester.runAsync(() async {
    await Future<void>.delayed(const Duration(milliseconds: 1200));
  });
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  testWidgets('the clock reads unpadded minutes', (tester) async {
    await _pump(tester, startedAtEpochMs: _startedAgo(123000));
    // Not `2m 03s`: the reference pushes whole numerals, never zero-padded.
    expect(find.text('Deep diving for 2m 3s ···'), findsOneWidget);
  });

  testWidgets('the clock reads unpadded hours', (tester) async {
    await _pump(tester, startedAtEpochMs: _startedAgo(3903000));
    expect(find.text('Deep diving for 1h 5m 3s ···'), findsOneWidget);
  });

  testWidgets('a Turn whose start is unknown keeps the bare label', (
    tester,
  ) async {
    await _pump(tester);
    expect(find.text('Deep diving'), findsOneWidget);
    expect(find.textContaining('Deep diving for'), findsNothing);
  });

  testWidgets('a start arriving on a mounted row arms the clock', (
    tester,
  ) async {
    // Mounted with no start: the static state.
    await _pump(tester);
    expect(find.text('Deep diving'), findsOneWidget);

    // The same State now names a start, and the clock has to move with it.
    await _pump(tester, startedAtEpochMs: _startedAgo(5000));
    expect(find.text('Deep diving for 5s ···'), findsOneWidget);
    await _tick(tester);
    expect(find.text('Deep diving for 6s ···'), findsOneWidget);
    await _tick(tester);
    expect(find.text('Deep diving for 7s ···'), findsOneWidget);

    // The start leaves again: the static label, and the clock stops.
    await _pump(tester);
    expect(find.text('Deep diving'), findsOneWidget);
    final frozen = tester.widget<Text>(find.text('Deep diving'));
    await _tick(tester);
    expect(find.text('Deep diving'), findsOneWidget);
    expect(find.textContaining('Deep diving for'), findsNothing);
    // A live clock would have rebuilt the row against a label that cannot
    // change; a cancelled one leaves the same widget instance in place.
    expect(
      identical(tester.widget<Text>(find.text('Deep diving')), frozen),
      isTrue,
    );
  });

  testWidgets('a start leaving a mounted row disarms the clock', (
    tester,
  ) async {
    await _pump(tester, startedAtEpochMs: _startedAgo(5000));
    expect(find.text('Deep diving for 5s ···'), findsOneWidget);

    // The boundary leaves the window on the same State: static from here on.
    await _pump(tester);
    expect(find.text('Deep diving'), findsOneWidget);
    final frozen = tester.widget<Text>(find.text('Deep diving'));
    await _tick(tester);
    await _tick(tester);
    expect(find.text('Deep diving'), findsOneWidget);
    expect(
      identical(tester.widget<Text>(find.text('Deep diving')), frozen),
      isTrue,
    );

    // A start arriving again resumes the clock from its own baseline.
    await _pump(tester, startedAtEpochMs: _startedAgo(9000));
    expect(find.text('Deep diving for 9s ···'), findsOneWidget);
    await _tick(tester);
    expect(find.text('Deep diving for 10s ···'), findsOneWidget);
  });

  testWidgets('the tail leads the label in the row ink', (tester) async {
    await _pump(tester, startedAtEpochMs: _startedAgo(1000));

    final tail = tester.widget<RunningWhaleTail>(find.byType(RunningWhaleTail));
    expect(tail.size, 14);
    expect(tail.color, DshTheme.light().colorScheme.labelDeepDiving);

    // The label wears the same deep-diving role, not an accent one.
    final label = tester.widget<Text>(find.text('Deep diving for 1s ···'));
    expect(label.style?.color, DshTheme.light().colorScheme.labelDeepDiving);
    expect(label.style?.fontSize, 12);
    expect(label.style?.height, 22 / 12);
    expect(label.style?.fontFeatures, const <FontFeature>[
      FontFeature.tabularFigures(),
    ]);
  });

  testWidgets('the row sweeps through the shared primitive in its own tone', (
    tester,
  ) async {
    await _pump(tester, startedAtEpochMs: _startedAgo(1000));

    final sweep = tester.widget<SweepHighlight>(
      find.descendant(
        of: find.byType(RunningStatusRow),
        matching: find.byType(SweepHighlight),
      ),
    );
    // A running clock, painted in the deep-diving shimmer rather than the
    // primitive's neutral default.
    expect(sweep.controller, isNotNull);
    expect(sweep.color, DshTheme.light().colorScheme.labelDeepDivingShimmer);
    expect(find.byType(ShaderMask), findsOneWidget);
  });

  testWidgets('the ticking clock is announced once, never every second', (
    tester,
  ) async {
    await _pump(tester, startedAtEpochMs: _startedAgo(123000));
    await tester.pump(const Duration(milliseconds: 1100));

    // Exactly one running label is in the tree: the visible ticking text.
    expect(find.textContaining('Deep diving for 2m '), findsOneWidget);

    // One live region, carrying the static state rather than the clock.
    final live = tester
        .widgetList<Semantics>(find.byType(Semantics))
        .where((semantics) => semantics.properties.liveRegion == true)
        .toList();
    expect(live, hasLength(1));
    expect(live.single.properties.label, 'Deep diving');
    expect(find.bySemanticsLabel(RegExp('Deep diving for')), findsNothing);
  });

  testWidgets('reduced motion leaves the tail still and the sweep off', (
    tester,
  ) async {
    await _pump(
      tester,
      startedAtEpochMs: _startedAgo(1000),
      reducedMotion: true,
    );
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.byType(ShaderMask), findsNothing);
    expect(find.text('Deep diving for 1s ···'), findsOneWidget);
    // The tail is still there, drawn without its sway transform.
    expect(find.byType(RunningWhaleTail), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(RunningWhaleTail),
        matching: find.byType(Transform),
      ),
      findsNothing,
    );
  });

  testWidgets('the hairline is drawn only above output', (tester) async {
    await _pump(tester);
    expect(find.byType(Container), findsNothing);

    await _pump(tester, showDivider: true);
    final divider = tester.widget<Container>(find.byType(Container));
    expect(divider.color, DshTheme.light().colorScheme.runningDivider);
    expect(divider.margin, const EdgeInsets.only(top: 8, bottom: 10));
    expect(divider.constraints?.minHeight, 0.5);
    expect(divider.constraints?.maxHeight, 0.5);
  });

  for (final scale in <double>[1.5, 2.0]) {
    testWidgets('${scale}x text scale neither overflows nor clips the row', (
      tester,
    ) async {
      await _pump(
        tester,
        startedAtEpochMs: _startedAgo(3903000),
        textScale: scale,
        width: 240,
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(tester.takeException(), isNull);
      expect(find.byType(RunningWhaleTail), findsOneWidget);
      expect(find.textContaining('Deep diving for'), findsOneWidget);

      // The row grows with its line instead of cutting it: it is at least the
      // tail's own box, and stays inside the width it was given.
      final row = tester.getSize(find.byType(RunningStatusRow));
      final tail = tester.getSize(find.byType(RunningWhaleTail));
      expect(row.height, greaterThanOrEqualTo(tail.height));
      expect(row.width, lessThanOrEqualTo(240));
    });
  }
}
