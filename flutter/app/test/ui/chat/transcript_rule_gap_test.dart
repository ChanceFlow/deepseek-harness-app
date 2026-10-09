/// The turn-process control's hairline keeps its clearance from the row under
/// it.
///
/// The reference lays a Turn's process control out as one flow item and the
/// rows it owns as the siblings after it, so the column's flow gap is what
/// stands between the control's rule and the first row: **16px** after a
/// `turn-process` item (`ChatView.module.css:93-94`) against the 6px default
/// and the 12px response gap. This port nests those rows inside the section to
/// keep one fold over them, so the section applies the transcript's own rule
/// ([chatFlowGapAfter]) between them. These tests hold that rule at the control
/// edge, where a bare padding left the reader's own bubble flush against the
/// rule.
library;

import 'package:app/ui/chat/chat_screen.dart' show chatFlowGapAfter;
import 'package:app/ui/chat/process_disclosure.dart';
import 'package:app/ui/chat/turn_process.dart';
import 'package:app/ui/theme/theme.dart';
import 'package:domain/model/chat_message.dart';
import 'package:domain/model/timeline_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../l10n_app.dart';

TimelineMessage _message(String id, {MessageRole role = MessageRole.user}) =>
    TimelineMessage(
      ChatMessage(id: id, sessionId: 's1', role: role, text: id, seq: 1),
    );

const TimelineToolCall _step = TimelineToolCall(
  id: 't1',
  name: 'read',
  arguments: '{"file_path":"AGENTS.md"}',
  status: ToolRunStatus.completed,
);

const TimelineToolCall _stepTwo = TimelineToolCall(
  id: 't2',
  name: 'read',
  arguments: '{"file_path":"docs/spec.md"}',
  status: ToolRunStatus.completed,
);

TurnProcessSection _section(List<TurnProcessMember> members) =>
    TurnProcessSection(
      facts: const TurnProcessFacts(
        turn: 1,
        closed: true,
        endReason: 'completed',
        startedAtEpochMs: 1000,
        endedAtEpochMs: 124000,
      ),
      members: members,
    );

/// The control's own box: the hairline rides its bottom edge
/// (`TurnProcessNodeView.module.css:13`).
Finder _rule() => find.byWidgetPredicate(
  (Widget widget) =>
      widget is Container &&
      widget.decoration is BoxDecoration &&
      (((widget.decoration! as BoxDecoration).border?.bottom.width) ?? 0) ==
          0.5,
);

void main() {
  test('the flow gap holds the turn-process clearance on both sides', () {
    final section = _section(const <TurnProcessMember>[]);
    final user = _message('u1');
    final answer = _message('a1', role: MessageRole.assistant);

    // `ChatView.module.css:91-94`: the item opens its block and the sibling
    // after it takes the same clearance — which is the row under its rule.
    expect(chatFlowGapAfter(user, section), kChatFlowGapAfterTurnHeader);
    expect(chatFlowGapAfter(section, user), kChatFlowGapAfterTurnHeader);
    // The rest of the column: steps 6px (`:70`), a message 12px (`:75-76`).
    expect(chatFlowGapAfter(_step, _stepTwo), kChatFlowGapStep);
    expect(chatFlowGapAfter(_step, answer), kChatFlowGap);
    expect(chatFlowGapAfter(answer, user), kChatFlowGap);
  });

  testWidgets('the control rule clears the bubble under it by the flow gap', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      l10nApp(
        home: Scaffold(
          body: TurnProcessRow(
            section: _section(<TurnProcessMember>[
              TurnProcessMember(_message('u1'), folds: false),
            ]),
            buildRow: (Object row) =>
                const SizedBox(height: 42, child: Text('bubble')),
            gapAfter: chatFlowGapAfter,
          ),
        ),
      ),
    );
    await tester.pump();

    // The rule is the control's bottom edge; the bubble's top is the first
    // member's top, so the difference is exactly the gap the section applies.
    final double ruleBottom = tester.getRect(_rule()).bottom;
    final double bubbleTop = tester.getRect(find.text('bubble')).top;
    expect(bubbleTop - ruleBottom, kChatFlowGapAfterTurnHeader);
  });
}
