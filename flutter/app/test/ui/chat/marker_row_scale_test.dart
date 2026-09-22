/// The transcript's one-line marker rows read at one scale.
///
/// A context injection, a compaction marker and a slash-command row are
/// steps in the run like a tool call or a thought, so they carry the same
/// label role and — where they own a disclosure — the same row height. The
/// rule is asserted here because a size drift between them is invisible to
/// any single-row test.
library;

import 'package:app/ui/chat/chat_screen.dart';
import 'package:app/ui/chat/reasoning_row.dart';
import 'package:app/ui/theme/theme.dart';
import 'package:domain/model/chat_message.dart';
import 'package:domain/model/timeline_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../l10n_app.dart';

/// The label size a row paints, read off the [Text] the reader sees.
double? _labelSize(WidgetTester tester, String label) =>
    tester.widget<Text>(find.text(label)).style?.fontSize;

void main() {
  testWidgets('marker rows carry the step-row label size', (tester) async {
    final theme = DshTheme.light();
    await tester.pumpWidget(
      l10nApp(
        theme: theme,
        home: const Scaffold(
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ContextInjectionRow(
                injection: TimelineContextInjection(
                  id: 'ctx',
                  text: 'Earlier decision: the adapter owns every dsh type.',
                  producerLabel: 'AGENTS.md',
                  summary: 'workspace instructions',
                ),
              ),
              CompactionRow(
                compaction: TimelineCompaction(
                  id: 'cmp',
                  shadowedCount: 12,
                  shadowedTokens: 8400,
                ),
              ),
              CommandRow(
                command: TimelineCommand(
                  commandId: 'cmd',
                  name: 'compact',
                  status: CommandRunStatus.success,
                  text: 'Compacted 12 items',
                ),
              ),
              ToolCallRow(
                call: TimelineToolCall(
                  id: 't1',
                  name: 'read',
                  arguments: '{"file_path":"a.dart"}',
                  status: ToolRunStatus.completed,
                ),
              ),
              ReasoningRow(
                text: 'Weigh the note before touching the tree.',
                running: false,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final stepLabelSize = theme.textTheme.bodySmall!.fontSize;
    for (final label in <String>[
      'Context injection',
      'Context compacted',
      '/compact',
      'Read',
      'Think',
    ]) {
      expect(_labelSize(tester, label), stepLabelSize, reason: label);
    }
  });

  testWidgets('marker disclosures share one row height', (tester) async {
    await tester.pumpWidget(
      l10nApp(
        theme: DshTheme.light(),
        home: const Scaffold(
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ContextInjectionRow(
                injection: TimelineContextInjection(
                  id: 'ctx',
                  text: 'Earlier decision: the adapter owns every dsh type.',
                  producerLabel: 'AGENTS.md',
                ),
              ),
              CompactionRow(
                compaction: TimelineCompaction(
                  id: 'cmp',
                  shadowedCount: 12,
                  shadowedTokens: 8400,
                ),
              ),
              ToolCallRow(
                call: TimelineToolCall(
                  id: 't1',
                  name: 'read',
                  arguments: '{"file_path":"a.dart"}',
                  status: ToolRunStatus.completed,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final toolHeight = tester.getSize(find.byType(ToolCallRow)).height;
    expect(tester.getSize(find.byType(ContextInjectionRow)).height, toolHeight);
    expect(tester.getSize(find.byType(CompactionRow)).height, toolHeight);
  });

  testWidgets('the phase header draws no rule', (tester) async {
    const group = TimelineActivityGroup(
      id: 'th',
      entries: <TimelineItem>[
        TimelineMessage(
          ChatMessage(
            id: 'th',
            sessionId: 's1',
            role: MessageRole.assistant,
            text: '',
            reasoning: 'Weigh the note before touching the tree.',
            reasoningDuration: Duration(seconds: 4),
          ),
        ),
        TimelineToolCall(
          id: 't1',
          name: 'read',
          arguments: '{"file_path":"a.dart"}',
          status: ToolRunStatus.completed,
        ),
      ],
    );
    await tester.pumpWidget(
      l10nApp(
        theme: DshTheme.light(),
        home: Scaffold(
          body: ActivityGroupRow(
            group: group,
            onAction: (_) {},
            loadAttachment: (_, _) async => null,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The phase divides with space, not a rule: the header used to close
    // itself with a 0.5px full-width hairline.
    expect(
      find.descendant(
        of: find.byType(ActivityGroupRow),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Container &&
              widget.color != null &&
              widget.constraints?.maxHeight == 0.5,
        ),
      ),
      findsNothing,
    );
  });
}
