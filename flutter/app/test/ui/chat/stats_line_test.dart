/// StatsLine parity tests — web format functions and group composition.
library;

import 'package:domain/model/session_window_stats.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/ui/chat/stats_line.dart';

import '../../l10n_app.dart';

void main() {
  test('formatTokens matches the web compact scale', () {
    expect(formatTokens(517), '517');
    expect(formatTokens(12200), '12.2K');
    expect(formatTokens(517000), '517K');
    expect(formatTokens(1200000), '1.2M');
  });

  test('formatDuration switches at one minute', () {
    expect(formatDuration(45200), '45.2s');
    expect(formatDuration(162000), '2m42s');
  });

  test('formatTokensPerSecond keeps one decimal under ten', () {
    expect(formatTokensPerSecond(9.96), '10');
    expect(formatTokensPerSecond(4.34), '4.3');
  });

  const stats = SessionWindowStats(
    turns: 3,
    steps: 5,
    llmMs: 42000,
    toolMs: 8000,
    ttftMs: 3000,
    ttftSteps: 3,
    decodeMs: 60000,
    decodeTokens: 900,
    billedInputTokens: 12200,
    outputTokens: 900,
    cacheReadTokens: 6100,
  );

  Future<void> pumpAt(WidgetTester tester, double width) async {
    tester.view.physicalSize = Size(width, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      l10nApp(
        home: const Scaffold(
          body: Center(child: StatsLine(stats: stats)),
        ),
      ),
    );
  }

  testWidgets('a wide strip carries every group', (tester) async {
    await pumpAt(tester, 4000);
    expect(find.textContaining('3 turns · 5 steps'), findsOneWidget);
    expect(find.textContaining('LLM 42s'), findsOneWidget);
    expect(find.textContaining('TTFT avg 1s'), findsOneWidget);
    expect(find.textContaining('15 tok/s'), findsOneWidget);
    expect(find.textContaining('Cache hit 50%'), findsOneWidget);
    expect(find.textContaining('Input 12.2K tok'), findsOneWidget);
  });

  testWidgets('a phone strip drops whole facts, keeping the leading one', (
    tester,
  ) async {
    await pumpAt(tester, 400);
    // Priority order survives width: how far the session ran stays, the
    // timings a phone reader rarely acts on are the first to go.
    expect(find.textContaining('3 turns · 5 steps'), findsOneWidget);
    expect(find.textContaining('TTFT avg 1s'), findsNothing);
    expect(find.textContaining('15 tok/s'), findsNothing);
  });

  test('fitStatsGroups adds groups only while they fit', () {
    const style = TextStyle(fontSize: 10);
    // The test font paints one em per glyph: 'aaaa' is 40 logical pixels
    // wide, and each ' · ' join adds three more.
    const groups = <String>['aaaa', 'bbbb', 'cccc'];
    expect(
      fitStatsGroups(groups, style, 1000, TextScaler.noScaling),
      'aaaa · bbbb · cccc',
    );
    expect(
      fitStatsGroups(groups, style, 120, TextScaler.noScaling),
      'aaaa · bbbb',
    );
    // Below the first group's own width the strip still names one fact and
    // leaves the clipping to the Text's ellipsis.
    expect(fitStatsGroups(groups, style, 10, TextScaler.noScaling), 'aaaa');
  });

  testWidgets('empty stats render nothing', (tester) async {
    await tester.pumpWidget(
      l10nApp(
        home: const Scaffold(
          body: Center(child: StatsLine(stats: SessionWindowStats())),
        ),
      ),
    );
    expect(find.byType(Text), findsNothing);
  });

  testWidgets(
    'tapping stats line opens detailed stats sheet with all metrics',
    (tester) async {
      await pumpAt(tester, 400);

      // On 400dp width, TTFT and tokens/s were dropped from the single line.
      expect(find.textContaining('TTFT avg 1s'), findsNothing);

      // Tap the stats line to open the full breakdown sheet.
      await tester.tap(find.byType(StatsLine));
      await tester.pumpAndSettle();

      // The modal sheet now reveals all metrics.
      expect(find.textContaining('3 turns · 5 steps'), findsWidgets);
      expect(find.textContaining('Input 12.2K tok'), findsOneWidget);
      expect(find.textContaining('Output 900 tok'), findsOneWidget);
      expect(find.textContaining('Cache hit 50%'), findsOneWidget);
      expect(find.textContaining('LLM 42s'), findsOneWidget);
      expect(find.textContaining('Tool call 8s'), findsOneWidget);
      expect(find.textContaining('TTFT avg 1s'), findsOneWidget);
      expect(find.textContaining('15 tok/s'), findsOneWidget);
    },
  );
}
