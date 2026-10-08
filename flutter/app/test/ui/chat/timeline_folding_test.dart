import 'package:app/ui/chat/timeline_folding.dart';
import 'package:domain/model/chat_message.dart';
import 'package:domain/model/timeline_item.dart';
import 'package:flutter_test/flutter_test.dart';

TimelineMessage thoughtMessage({
  required String id,
  required String reasoning,
  Duration? duration,
  bool streaming = false,
  int createdAtEpochMs = 100,
  int? seq,
}) => TimelineMessage(
  ChatMessage(
    id: id,
    sessionId: 's1',
    role: MessageRole.assistant,
    text: '',
    reasoning: reasoning,
    reasoningDuration: duration,
    streaming: streaming,
    createdAtEpochMs: createdAtEpochMs,
    seq: seq,
  ),
);

TimelineMessage textMessage({
  required String id,
  required String text,
  MessageRole role = MessageRole.assistant,
}) => TimelineMessage(
  ChatMessage(id: id, sessionId: 's1', role: role, text: text),
);

TimelineToolCall toolCall({
  required String id,
  String name = 'bash',
  String? arguments,
  String? result,
  ToolRunStatus status = ToolRunStatus.completed,
}) => TimelineToolCall(
  id: id,
  name: name,
  arguments: arguments,
  result: result,
  status: status,
);

void main() {
  group('phase identity', () {
    final anchor = textMessage(id: 'u1', text: 'go');
    final t1 = toolCall(id: 't1', name: 'bash');
    final t2 = toolCall(id: 't2', name: 'read');
    final t3 = toolCall(id: 't3', name: 'edit');

    String idOf(List<TimelineItem> items) {
      final folded = foldTimelineActivities(items);
      return folded.whereType<TimelineActivityGroup>().last.id;
    }

    test('survives every move of its own rows, and a message above', () {
      final String base = idOf(<TimelineItem>[anchor, t1, t2]);
      expect(base, 'window:phase:0');
      // An older history page's tail folds into the phase's head.
      expect(idOf(<TimelineItem>[anchor, t3, t1, t2]), base);
      // A live step appends into the phase.
      expect(idOf(<TimelineItem>[anchor, t1, t2, t3]), base);
      // The same members, reordered.
      expect(idOf(<TimelineItem>[anchor, t2, t1]), base);
      // A prepend that lands a *message* directly above the phase — the window
      // cut mid-phase case: the older page's tail becomes the new anchor, and
      // the phase still keeps its identity.
      expect(
        idOf(<TimelineItem>[
          textMessage(id: 'u0', text: 'older'),
          anchor,
          t1,
          t2,
        ]),
        base,
      );
      // The same move inside a Turn, with the boundary loaded.
      // The same move inside a Turn, with the boundary loaded.
      final String turnBase = idOf(<TimelineItem>[
        const TimelineTurnBoundary(1),
        anchor,
        t1,
        t2,
      ]);
      expect(turnBase, 'window:phase:0');
      expect(
        idOf(<TimelineItem>[
          const TimelineTurnBoundary(1),
          textMessage(id: 'u0', text: 'older'),
          anchor,
          t1,
          t2,
        ]),
        turnBase,
      );
      // The Turn boundary *arriving*: the page that reaches it brings no new
      // phase and no new member, so the phase keeps its identity.
      expect(
        idOf(<TimelineItem>[
          const TimelineTurnBoundary(1, endSeq: 9),
          anchor,
          t1,
          t2,
        ]),
        base,
      );
    });

    test('pins the accepted limit: any prepend that adds a phase above', () {
      // The identity counts phases from the top of the loaded window, so any
      // prepend that moves this phase's ordinal — an earlier phase of the same
      // Turn, a phase of an older Turn, a page that reaches the Turn boundary
      // *and* adds a phase above this one — re-keys it. Pinned here rather than
      // left as prose: the card remounts (and a reader's open fold collapses),
      // which is the price of naming a phase by its own window position instead
      // of by the row above it.
      final String base = idOf(<TimelineItem>[
        const TimelineTurnBoundary(1),
        anchor,
        t1,
        t2,
      ]);
      expect(base, 'window:phase:0');
      expect(
        idOf(<TimelineItem>[
          const TimelineTurnBoundary(1),
          t3,
          textMessage(id: 'u2', text: 'mid'),
          anchor,
          t1,
          t2,
        ]),
        'window:phase:1',
      );
    });
  });

  test('interleaved thought + tool + thought + tool + text merges thoughts and groups tools', () {
    final t1 = toolCall(id: 't1', name: 'read');
    final t2 = toolCall(id: 't2', name: 'edit');
    final items = <TimelineItem>[
      const TimelineTurnBoundary(1),
      thoughtMessage(
        id: 'm1',
        reasoning: 'think 1',
        duration: const Duration(seconds: 1),
      ),
      t1,
      thoughtMessage(
        id: 'm2',
        reasoning: 'think 2',
        duration: const Duration(seconds: 2),
        seq: 42,
      ),
      t2,
      textMessage(id: 'm3', text: 'Done.'),
    ];

    final folded = foldTimelineActivities(items);

    // One phase, one card: the phase's thoughts merge into a single block at
    // the position of the first one, and the tool calls keep their order.
    expect(folded, hasLength(3));
    expect(folded[0], const TimelineTurnBoundary(1));

    expect(folded[1], isA<TimelineActivityGroup>());
    final group = folded[1] as TimelineActivityGroup;
    // The phase is named by its ordinal in the loaded window, not by any of
    // its rows: members change, the count of phases above it does not.
    expect(group.id, 'window:phase:0');
    expect(group.calls, <TimelineToolCall>[t1, t2]);

    final mergedThought = group.thought!.value;
    expect(mergedThought.id, 'm2');
    expect(mergedThought.sessionId, 's1');
    expect(mergedThought.role, MessageRole.assistant);
    expect(mergedThought.text, '');
    expect(mergedThought.reasoning, 'think 1\n\nthink 2');
    expect(mergedThought.reasoningDuration, const Duration(seconds: 3));
    expect(mergedThought.seq, 42);
    expect(
      group.entries.map(
        (entry) => entry is TimelineMessage ? 'thought' : 'tool',
      ),
      <String>['thought', 'tool', 'tool'],
    );

    expect(folded[2], textMessage(id: 'm3', text: 'Done.'));
  });

  test(
    'a phase folds its thoughts, injected context and tool calls into one card',
    () {
      final thought = thoughtMessage(id: 'th1', reasoning: 'consider the wire');
      const injection = TimelineContextInjection(
        id: 'ctx-1',
        text: 'recalled material',
        producerLabel: 'yesterday',
        isRecall: true,
      );
      final t1 = toolCall(id: 't1', name: 'read');
      final t2 = toolCall(id: 't2', name: 'edit');

      final folded = foldTimelineActivities(<TimelineItem>[
        thought,
        injection,
        t1,
        t2,
      ]);

      expect(folded, hasLength(1));
      final group = folded.single as TimelineActivityGroup;
      // The window's first phase.
      expect(group.id, 'window:phase:0');
      // The injection is a step in the run, not a phase boundary: it rides the
      // card with the thought and the calls.
      expect(group.entries, <TimelineItem>[thought, injection, t1, t2]);
      expect(group.calls, <TimelineToolCall>[t1, t2]);
      expect(group.thought!.value.reasoning, 'consider the wire');
    },
  );

  test('a lone injected context keeps its own row', () {
    const injection = TimelineContextInjection(
      id: 'ctx-1',
      text: 'goal objective: ship it',
      producerLabel: 'goal',
    );

    expect(foldTimelineActivities(<TimelineItem>[injection]), <TimelineItem>[
      injection,
    ]);
  });

  test(
    'single tool call is emitted directly without unnecessary group wrapper',
    () {
      final t1 = toolCall(id: 't1', name: 'bash');
      final folded = foldTimelineActivities(<TimelineItem>[t1]);

      expect(folded, [t1]);
    },
  );

  test('empty message artifact without text or reasoning is dropped', () {
    final t1 = toolCall(id: 't1', name: 'read');
    final t2 = toolCall(id: 't2', name: 'edit');
    const emptyMsg = TimelineMessage(
      ChatMessage(
        id: 'empty',
        sessionId: 's1',
        role: MessageRole.assistant,
        text: '',
        reasoning: null,
      ),
    );
    const emptyWhitespaceMsg = TimelineMessage(
      ChatMessage(
        id: 'empty_ws',
        sessionId: 's1',
        role: MessageRole.assistant,
        text: '   ',
        reasoning: '   ',
      ),
    );

    final folded = foldTimelineActivities(<TimelineItem>[
      t1,
      emptyMsg,
      emptyWhitespaceMsg,
      t2,
    ]);

    expect(folded, <Object>[
      isA<TimelineActivityGroup>().having(
        (g) => g.calls,
        'calls',
        <TimelineToolCall>[t1, t2],
      ),
    ]);
  });

  test('multi-phase transcript with intermediate statements emits separate tool groups', () {
    final tool1a = toolCall(id: 't1a', name: 'read');
    final tool1b = toolCall(id: 't1b', name: 'glob');
    final tool2a = toolCall(id: 't2a', name: 'edit');
    final tool2b = toolCall(id: 't2b', name: 'write');
    final msg1 = textMessage(id: 'm1', text: 'Phase 1 done');
    final msg2 = textMessage(id: 'm2', text: 'Phase 2 done');

    final folded = foldTimelineActivities(<TimelineItem>[
      tool1a,
      tool1b,
      msg1,
      tool2a,
      tool2b,
      msg2,
    ]);

    expect(folded, <Object>[
      isA<TimelineActivityGroup>().having(
        (g) => g.calls,
        'calls',
        <TimelineToolCall>[tool1a, tool1b],
      ),
      msg1,
      isA<TimelineActivityGroup>().having(
        (g) => g.calls,
        'calls',
        <TimelineToolCall>[tool2a, tool2b],
      ),
      msg2,
    ]);
  });

  test('single thought message is emitted directly without merging', () {
    final thought = thoughtMessage(id: 'th1', reasoning: 'single thought');
    final folded = foldTimelineActivities(<TimelineItem>[thought]);

    expect(folded, hasLength(1));
    expect(identical(folded.first, thought), isTrue);
  });

  test('merged thought sets streaming to true if any constituent thought was streaming', () {
    final th1 = thoughtMessage(id: 'th1', reasoning: 'first', streaming: false);
    final th2 = thoughtMessage(id: 'th2', reasoning: 'second', streaming: true);
    final folded = foldTimelineActivities(<TimelineItem>[th1, th2]);

    expect(folded, hasLength(1));
    final msg = (folded.first as TimelineMessage).value;
    expect(msg.streaming, isTrue);
  });

  test('merged thought has null reasoningDuration when constituent thoughts have no duration', () {
    final th1 = thoughtMessage(id: 'th1', reasoning: 'first');
    final th2 = thoughtMessage(id: 'th2', reasoning: 'second');
    final folded = foldTimelineActivities(<TimelineItem>[th1, th2]);

    expect(folded, hasLength(1));
    final msg = (folded.first as TimelineMessage).value;
    expect(msg.reasoningDuration, isNull);
  });

  test('user message, turn boundary, and interactive items delimit execution phases', () {
    final t1 = toolCall(id: 't1');
    final userMsg = textMessage(
      id: 'u1',
      text: 'hello',
      role: MessageRole.user,
    );
    final t2 = toolCall(id: 't2');
    const question = TimelineQuestionRequest(
      requestId: 'q1',
      questions: [QuestionItem(id: 'q_id', question: 'Proceed?')],
    );
    final t3 = toolCall(id: 't3');

    final folded = foldTimelineActivities(<TimelineItem>[
      t1,
      userMsg,
      t2,
      question,
      t3,
    ]);

    expect(folded, [t1, userMsg, t2, question, t3]);
  });

  test('TimelineActivityGroup value equality and hashCode', () {
    final t1 = toolCall(id: 't1');
    final t2 = toolCall(id: 't2');
    final group1 = TimelineActivityGroup(id: 't1', entries: [t1, t2]);
    final group2 = TimelineActivityGroup(id: 't1', entries: [t1, t2]);
    final groupDiffId = TimelineActivityGroup(id: 'diff', entries: [t1, t2]);
    final groupDiffCalls = TimelineActivityGroup(id: 't1', entries: [t1]);

    expect(group1, equals(group2));
    expect(group1.hashCode, equals(group2.hashCode));
    expect(group1, isNot(equals(groupDiffId)));
    expect(group1, isNot(equals(groupDiffCalls)));
  });

  test('empty list yields empty list', () {
    expect(foldTimelineActivities(<TimelineItem>[]), isEmpty);
  });
}
