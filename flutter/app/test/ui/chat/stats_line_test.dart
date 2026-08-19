/// StatsLine parity tests — web format functions and group composition.
library;

import 'package:domain/model/session_window_stats.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/ui/chat/stats_line.dart';

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

  testWidgets('renders pipe-separated groups', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: StatsLine(
              stats: SessionWindowStats(
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
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.textContaining('3 turns · 5 steps'), findsOneWidget);
    expect(find.textContaining('LLM 42s'), findsOneWidget);
    expect(find.textContaining('TTFT avg 1s'), findsOneWidget);
    expect(find.textContaining('15 tok/s'), findsOneWidget);
    expect(find.textContaining('Cache hit 50%'), findsOneWidget);
    expect(find.textContaining('Input 12.2K tok'), findsOneWidget);
  });

  testWidgets('empty stats render nothing', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(child: StatsLine(stats: SessionWindowStats())),
        ),
      ),
    );
    expect(find.byType(Text), findsNothing);
  });
}
