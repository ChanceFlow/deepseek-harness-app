import 'package:app/ui/chat/activity_dot.dart';
import 'package:app/ui/chat/chat_screen.dart';
import 'package:app/ui/chat/markdown/markdown_text.dart';
import 'package:app/ui/theme/theme.dart';
import 'package:domain/model/timeline_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../l10n_app.dart';

void main() {
  group('CompactionRow reference parity', () {
    testWidgets('renders items and tokens count caption in en and zh', (
      tester,
    ) async {
      const compaction = TimelineCompaction(
        id: 'c-1',
        shadowedCount: 42,
        shadowedTokens: 1500,
      );

      // EN
      await tester.pumpWidget(
        l10nApp(
          theme: DshTheme.light(),
          locale: const Locale('en'),
          home: const Scaffold(body: CompactionRow(compaction: compaction)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Context compacted'), findsOneWidget);
      expect(
        find.text('Compacted 42 history items (~1500 tokens)'),
        findsOneWidget,
      );

      // ZH
      await tester.pumpWidget(
        l10nApp(
          theme: DshTheme.light(),
          locale: const Locale('zh'),
          home: const Scaffold(body: CompactionRow(compaction: compaction)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('上下文已压缩'), findsOneWidget);
      expect(find.text('已压缩 42 条历史记录（约 1500 tokens）'), findsOneWidget);
    });

    testWidgets(
      'fallback to view summary when counts null, expandable on tap',
      (tester) async {
        const compaction = TimelineCompaction(
          id: 'c-2',
          summary:
              '## Summary of compacted turns\n- Tool executed\n- File edited',
        );

        // EN
        await tester.pumpWidget(
          l10nApp(
            theme: DshTheme.light(),
            locale: const Locale('en'),
            home: const Scaffold(body: CompactionRow(compaction: compaction)),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Context compacted'), findsOneWidget);
        expect(find.text('View compaction summary'), findsOneWidget);
        expect(find.byType(MarkdownText), findsNothing);

        // Tap to expand
        await tester.tap(find.text('Context compacted'));
        await tester.pumpAndSettle();

        expect(find.byType(MarkdownText), findsOneWidget);
        expect(find.text('Summary of compacted turns'), findsOneWidget);

        // ZH
        await tester.pumpWidget(
          l10nApp(
            theme: DshTheme.light(),
            locale: const Locale('zh'),
            home: const Scaffold(body: CompactionRow(compaction: compaction)),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('上下文已压缩'), findsOneWidget);
        expect(find.text('点击查看压缩摘要'), findsOneWidget);
      },
    );

    testWidgets(
      'fallback to summary unavailable when counts and summary are null (non-expandable)',
      (tester) async {
        const compaction = TimelineCompaction(id: 'c-3');

        // EN
        await tester.pumpWidget(
          l10nApp(
            theme: DshTheme.light(),
            locale: const Locale('en'),
            home: const Scaffold(body: CompactionRow(compaction: compaction)),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Context compacted'), findsOneWidget);
        expect(find.text('Compaction summary unavailable'), findsOneWidget);

        final tile = tester.widget<ExpansionTile>(find.byType(ExpansionTile));
        expect(tile.enabled, isFalse);

        // ZH
        await tester.pumpWidget(
          l10nApp(
            theme: DshTheme.light(),
            locale: const Locale('zh'),
            home: const Scaffold(body: CompactionRow(compaction: compaction)),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('上下文已压缩'), findsOneWidget);
        expect(find.text('压缩摘要不可用'), findsOneWidget);
      },
    );
  });

  group('CommandRow /compact running and outcome parity', () {
    testWidgets('shows running summary for running /compact in en and zh', (
      tester,
    ) async {
      const command = TimelineCommand(
        commandId: 'cmd-1',
        name: 'compact',
        status: CommandRunStatus.running,
      );

      // EN
      await tester.pumpWidget(
        l10nApp(
          theme: DshTheme.light(),
          locale: const Locale('en'),
          home: const Scaffold(body: CommandRow(command: command)),
        ),
      );
      await tester.pump();

      expect(find.text('/compact'), findsOneWidget);
      expect(find.text('Compacting context…'), findsOneWidget);
      expect(find.byType(ActivityDot), findsOneWidget);

      // ZH
      await tester.pumpWidget(
        l10nApp(
          theme: DshTheme.light(),
          locale: const Locale('zh'),
          home: const Scaffold(body: CommandRow(command: command)),
        ),
      );
      await tester.pump();

      expect(find.text('/compact'), findsOneWidget);
      expect(find.text('正在压缩…'), findsOneWidget);
    });

    testWidgets('shows handler outcome text when settled without checkpoint', (
      tester,
    ) async {
      const failedCommand = TimelineCommand(
        commandId: 'cmd-2',
        name: 'compact',
        status: CommandRunStatus.failed,
        text: 'This operation was aborted',
      );

      await tester.pumpWidget(
        l10nApp(
          theme: DshTheme.light(),
          locale: const Locale('en'),
          home: const Scaffold(body: CommandRow(command: failedCommand)),
        ),
      );
      await tester.pump();

      expect(find.text('/compact'), findsOneWidget);
      expect(find.text('This operation was aborted'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);

      const noHistoryCommand = TimelineCommand(
        commandId: 'cmd-3',
        name: 'compact',
        status: CommandRunStatus.success,
        text: 'No history to compact',
      );

      await tester.pumpWidget(
        l10nApp(
          theme: DshTheme.light(),
          locale: const Locale('en'),
          home: const Scaffold(body: CommandRow(command: noHistoryCommand)),
        ),
      );
      await tester.pump();

      expect(find.text('/compact'), findsOneWidget);
      expect(find.text('No history to compact'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
    });
  });
}
