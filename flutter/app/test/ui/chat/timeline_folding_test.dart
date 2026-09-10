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

    expect(folded, hasLength(4));
    expect(folded[0], const TimelineTurnBoundary(1));

    expect(folded[1], isA<TimelineMessage>());
    final mergedThought = (folded[1] as TimelineMessage).value;
    expect(mergedThought.id, 'm2');
    expect(mergedThought.sessionId, 's1');
    expect(mergedThought.role, MessageRole.assistant);
    expect(mergedThought.text, '');
    expect(mergedThought.reasoning, 'think 1\n\nthink 2');
    expect(mergedThought.reasoningDuration, const Duration(seconds: 3));
    expect(mergedThought.seq, 42);

    expect(folded[2], TimelineToolGroup(id: 't1', calls: [t1, t2]));

    expect(folded[3], textMessage(id: 'm3', text: 'Done.'));
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

    expect(folded, [
      TimelineToolGroup(id: 't1', calls: [t1, t2]),
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

    expect(folded, [
      TimelineToolGroup(id: 't1a', calls: [tool1a, tool1b]),
      msg1,
      TimelineToolGroup(id: 't2a', calls: [tool2a, tool2b]),
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

  test('TimelineToolGroup value equality and hashCode', () {
    final t1 = toolCall(id: 't1');
    final t2 = toolCall(id: 't2');
    final group1 = TimelineToolGroup(id: 't1', calls: [t1, t2]);
    final group2 = TimelineToolGroup(id: 't1', calls: [t1, t2]);
    final groupDiffId = TimelineToolGroup(id: 'diff', calls: [t1, t2]);
    final groupDiffCalls = TimelineToolGroup(id: 't1', calls: [t1]);

    expect(group1, equals(group2));
    expect(group1.hashCode, equals(group2.hashCode));
    expect(group1, isNot(equals(groupDiffId)));
    expect(group1, isNot(equals(groupDiffCalls)));
  });

  test('empty list yields empty list', () {
    expect(foldTimelineActivities(<TimelineItem>[]), isEmpty);
  });
}
