/// Per-message run metrics tests — the real figures a finalized assistant
/// action row carries, and the ones it refuses to invent.
library;

import 'package:app/l10n/app_localizations.dart';
import 'package:app/ui/chat/chat_screen.dart';
import 'package:app/ui/chat/chat_ui_state.dart';
import 'package:app/ui/chat/message_run_metrics.dart';
import 'package:domain/model/chat_message.dart';
import 'package:domain/model/session.dart';
import 'package:domain/model/timeline_item.dart';
import 'package:domain/model/token_usage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../l10n_app.dart';

// 2024-08-18T16:00:00Z; the decode window is measured from here.
const int _completedAt = 1723996800000;
const int _firstTokenAt = _completedAt - 2000;

const TokenUsage _usage = TokenUsage(
  inputTokens: 10,
  outputTokens: 100,
  totalTokens: 110,
);

TimelineMessage _assistant({
  TokenUsage? usage,
  int? firstTokenAtEpochMs,
  bool streaming = false,
}) => TimelineMessage(
  ChatMessage(
    id: 'm1',
    sessionId: 's1',
    role: MessageRole.assistant,
    text: 'done',
    streaming: streaming,
    createdAtEpochMs: _completedAt,
  ),
  usage: usage,
  firstTokenAtEpochMs: firstTokenAtEpochMs,
);

void main() {
  late AppLocalizations en;

  setUp(() async {
    en = await AppLocalizations.delegate.load(const Locale('en'));
  });

  group('messageRunMetricsText', () {
    test('measures throughput over the first-token..message window', () {
      expect(
        messageRunMetricsText(
          usage: _usage,
          firstTokenAtEpochMs: _firstTokenAt,
          messageAtEpochMs: _completedAt,
          l10n: en,
        ),
        '50 tok/s · 110 tok',
      );
    });

    test('states the token total without a throughput when unrecorded', () {
      expect(
        messageRunMetricsText(
          usage: _usage,
          firstTokenAtEpochMs: null,
          messageAtEpochMs: _completedAt,
          l10n: en,
        ),
        '110 tok',
      );
    });

    test('a zero or inverted window prints no throughput', () {
      expect(
        messageRunMetricsText(
          usage: _usage,
          firstTokenAtEpochMs: _completedAt,
          messageAtEpochMs: _completedAt,
          l10n: en,
        ),
        '110 tok',
      );
      expect(
        messageRunMetricsText(
          usage: _usage,
          firstTokenAtEpochMs: _completedAt + 500,
          messageAtEpochMs: _completedAt,
          l10n: en,
        ),
        '110 tok',
      );
    });

    test('no reported usage prints nothing at all', () {
      expect(
        messageRunMetricsText(
          usage: null,
          firstTokenAtEpochMs: _firstTokenAt,
          messageAtEpochMs: _completedAt,
          l10n: en,
        ),
        isNull,
      );
    });

    test('a missing provider total sums only the reported buckets', () {
      expect(
        messageRunMetricsText(
          usage: const TokenUsage(
            inputTokens: 10,
            outputTokens: 100,
            cacheReadTokens: 5,
          ),
          firstTokenAtEpochMs: null,
          messageAtEpochMs: _completedAt,
          l10n: en,
        ),
        '115 tok',
      );
    });
  });

  group('the finalized assistant action row', () {
    Future<void> pump(WidgetTester tester, TimelineItem item) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          child: l10nApp(
            home: ChatScreen(
              uiState: ChatUiState(
                sessions: const <SessionSummary>[
                  SessionSummary(id: 's1', title: 'Alpha', blank: false),
                ],
                selectedSessionId: 's1',
                timeline: <TimelineItem>[item],
              ),
              onAction: (_) {},
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('renders the reported figures', (tester) async {
      await pump(
        tester,
        _assistant(usage: _usage, firstTokenAtEpochMs: _firstTokenAt),
      );

      expect(find.text('50 tok/s · 110 tok'), findsOneWidget);
    });

    testWidgets('omits the row when the host reported no figures', (
      tester,
    ) async {
      await pump(tester, _assistant());

      expect(find.textContaining('tok/s'), findsNothing);
      expect(find.textContaining(' tok'), findsNothing);
      // The clock still dates the message.
      expect(find.textContaining(RegExp(r'^\d{2}:\d{2}$')), findsOneWidget);
    });

    testWidgets('a streaming reply carries no metrics row', (tester) async {
      await pump(
        tester,
        _assistant(
          usage: _usage,
          firstTokenAtEpochMs: _firstTokenAt,
          streaming: true,
        ),
      );

      expect(find.textContaining('tok/s'), findsNothing);
    });
  });
}
