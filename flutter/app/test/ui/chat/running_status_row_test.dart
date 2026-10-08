/// Running-status row tests: the tail, the app's own running label with its
/// separate clock, the reference's sweep timing, the single live-region
/// announcement, and the row's behaviour under reduced motion and large text
/// scales.
library;

import 'package:app/ui/chat/running_status_row.dart';
import 'package:app/ui/chat/running_whale_tail.dart';
import 'package:app/ui/chat/sweep_highlight.dart';
import 'package:app/ui/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../l10n_app.dart';

/// The app's own running label (`turnProcessDeepDiving`), never the reference's
/// `Deep diving for {duration} ···` sentence.
const String _label = 'Deep diving…';

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

/// One second of the row's clock: a real wall-clock advance (the clock reads
/// `DateTime.now`) plus the fake tick that republishes it (the 1 Hz timer).
Future<void> _tick(WidgetTester tester) async {
  await tester.runAsync(() async {
    await Future<void>.delayed(const Duration(milliseconds: 1200));
  });
  await tester.pump(const Duration(seconds: 1));
}

/// The clock node's text, or null when the row carries none.
String? _clockText(WidgetTester tester) {
  final label = find.text(_label);
  final texts = tester
      .widgetList<Text>(
        find.descendant(
          of: find.byType(RunningStatusRow),
          matching: find.byType(Text),
        ),
      )
      .toList();
  final clock = texts.where((text) => text.data != _label).toList();
  expect(label, findsOneWidget);
  expect(clock.length, lessThanOrEqualTo(1));
  return clock.isEmpty ? null : clock.single.data;
}

void main() {
  testWidgets('the label is the app wording and the clock stands beside it', (
    tester,
  ) async {
    await _pump(tester, startedAtEpochMs: _startedAgo(5000));

    // Two nodes, not one sentence.
    expect(find.text(_label), findsOneWidget);
    expect(find.text('5s'), findsOneWidget);
    expect(find.textContaining('Deep diving for'), findsNothing);
  });

  testWidgets('the clock reads unpadded minutes', (tester) async {
    await _pump(tester, startedAtEpochMs: _startedAgo(123000));
    // Not `2m 03s`: the reference pushes whole numerals, never zero-padded.
    expect(_clockText(tester), '2m 3s');
    expect(find.text(_label), findsOneWidget);
  });

  testWidgets('the clock reads unpadded hours', (tester) async {
    await _pump(tester, startedAtEpochMs: _startedAgo(3903000));
    expect(_clockText(tester), '1h 5m 3s');
  });

  testWidgets('a Turn whose start is unknown keeps the label alone', (
    tester,
  ) async {
    await _pump(tester);
    expect(find.text(_label), findsOneWidget);
    expect(_clockText(tester), isNull);
  });

  testWidgets('the clock is its own dimmer node on the label line', (
    tester,
  ) async {
    await _pump(tester, startedAtEpochMs: _startedAgo(5000));
    final scheme = DshTheme.light().colorScheme;

    final label = tester.widget<Text>(find.text(_label));
    expect(label.style?.color, scheme.labelDeepDiving);
    expect(label.style?.fontSize, 12);
    expect(label.style?.height, 22 / 12);
    expect(label.style?.fontFeatures, const <FontFeature>[
      FontFeature.tabularFigures(),
    ]);

    final clock = tester.widget<Text>(find.text('5s'));
    expect(clock.style?.color, scheme.onSurfaceVariant);
    expect(clock.style?.fontSize, 12);
    expect(clock.style?.height, 22 / 12);
    expect(clock.style?.fontFeatures, const <FontFeature>[
      FontFeature.tabularFigures(),
    ]);
  });

  testWidgets('the tail leads the label with the reference gaps', (
    tester,
  ) async {
    await _pump(tester, startedAtEpochMs: _startedAgo(1000));

    final tail = tester.widget<RunningWhaleTail>(find.byType(RunningWhaleTail));
    expect(tail.size, 14);
    expect(tail.color, DshTheme.light().colorScheme.labelDeepDiving);

    // The tail-to-label gap is 6; the label-to-clock gap is 8.
    final gaps = tester
        .widgetList<SizedBox>(
          find.descendant(
            of: find.byType(RunningStatusRow),
            matching: find.byType(SizedBox),
          ),
        )
        .map((box) => box.width)
        .toList();
    expect(gaps, contains(6.0));
    expect(gaps, contains(8.0));
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
    // Only the label rides the sweep; the clock is its own node outside it.
    expect(
      find.descendant(
        of: find.byType(SweepHighlight),
        matching: find.text(_label),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(SweepHighlight),
        matching: find.text('1s'),
      ),
      findsNothing,
    );
  });

  testWidgets('the ticking clock is announced once, never every second', (
    tester,
  ) async {
    await _pump(tester, startedAtEpochMs: _startedAgo(123000));
    await _tick(tester);
    expect(_clockText(tester), '2m 4s');

    // One live region, carrying the static label rather than the clock.
    final live = tester
        .widgetList<Semantics>(find.byType(Semantics))
        .where((semantics) => semantics.properties.liveRegion == true)
        .toList();
    expect(live, hasLength(1));
    expect(live.single.properties.label, _label);
    expect(find.bySemanticsLabel(RegExp(r'\d+m')), findsNothing);
  });

  testWidgets('a start arriving on a mounted row arms the clock', (
    tester,
  ) async {
    // Mounted with no start: the label alone.
    await _pump(tester);
    expect(find.text(_label), findsOneWidget);
    expect(_clockText(tester), isNull);

    // The same State now names a start, and the clock has to move with it.
    await _pump(tester, startedAtEpochMs: _startedAgo(5000));
    expect(_clockText(tester), '5s');
    await _tick(tester);
    expect(_clockText(tester), '6s');
    await _tick(tester);
    expect(_clockText(tester), '7s');

    // The start leaves again: no clock, and the row stops rebuilding.
    await _pump(tester);
    expect(_clockText(tester), isNull);
    final frozen = tester.widget<Text>(find.text(_label));
    await _tick(tester);
    expect(_clockText(tester), isNull);
    // A live clock would have rebuilt the row against a label that cannot
    // change; a cancelled one leaves the same widget instance in place.
    expect(identical(tester.widget<Text>(find.text(_label)), frozen), isTrue);
  });

  testWidgets('a start leaving a mounted row disarms the clock', (
    tester,
  ) async {
    await _pump(tester, startedAtEpochMs: _startedAgo(5000));
    expect(_clockText(tester), '5s');

    // The boundary leaves the window on the same State: no clock from here on.
    await _pump(tester);
    expect(_clockText(tester), isNull);
    final frozen = tester.widget<Text>(find.text(_label));
    await _tick(tester);
    await _tick(tester);
    expect(_clockText(tester), isNull);
    expect(identical(tester.widget<Text>(find.text(_label)), frozen), isTrue);

    // A start arriving again resumes the clock from its own baseline.
    await _pump(tester, startedAtEpochMs: _startedAgo(9000));
    expect(_clockText(tester), '9s');
    await _tick(tester);
    expect(_clockText(tester), '10s');
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
    expect(find.text(_label), findsOneWidget);
    expect(_clockText(tester), '1s');
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

  testWidgets('the zh label and clock use our own wording', (tester) async {
    await tester.pumpWidget(
      l10nApp(
        theme: DshTheme.light(),
        locale: const Locale('zh'),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              child: RunningStatusRow(startedAtEpochMs: _startedAgo(123000)),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('正在深入研究…'), findsOneWidget);
    expect(find.text('2分3秒'), findsOneWidget);
    expect(find.textContaining('深度求索中'), findsNothing);
  });

  testWidgets('the hairline is drawn only above output', (tester) async {
    await _pump(tester);
    expect(find.byType(Container), findsNothing);

    await _pump(tester, showDivider: true);
    final divider = tester.widget<Container>(find.byType(Container));
    expect(divider.color, DshTheme.light().colorScheme.outlineVariant);
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
      expect(find.text(_label), findsOneWidget);
      expect(_clockText(tester), '1h 5m 3s');

      // The row grows with its line instead of cutting it: it is at least the
      // tail's own box, and stays inside the width it was given.
      final row = tester.getSize(find.byType(RunningStatusRow));
      final tail = tester.getSize(find.byType(RunningWhaleTail));
      expect(row.height, greaterThanOrEqualTo(tail.height));
      expect(row.width, lessThanOrEqualTo(240));
    });
  }
}
