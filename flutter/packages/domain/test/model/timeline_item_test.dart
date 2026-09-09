import 'package:test/test.dart';

import 'package:domain/model/chat_message.dart';
import 'package:domain/model/jobs.dart';
import 'package:domain/model/session.dart';
import 'package:domain/model/timeline_item.dart';

void main() {
  group('TimelineItem subclasses equality and hashCode', () {
    const msg = ChatMessage(
      id: 'm1',
      sessionId: 's1',
      role: MessageRole.user,
      text: 'hi',
    );

    test('TimelineMessage', () {
      const a = TimelineMessage(msg);
      const b = TimelineMessage(msg);
      const c = TimelineMessage(
        ChatMessage(
          id: 'm2',
          sessionId: 's1',
          role: MessageRole.user,
          text: 'hi',
        ),
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, equals(a));
      expect(a, isNot(equals(c)));
    });

    test('TimelineTurnBoundary', () {
      const a = TimelineTurnBoundary(1);
      const b = TimelineTurnBoundary(1);
      const c = TimelineTurnBoundary(2);

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });

    test('TimelineCommand', () {
      const a = TimelineCommand(
        commandId: 'c1',
        name: 'grep',
        args: 'foo',
        status: CommandRunStatus.success,
        text: 'matched',
      );
      const b = TimelineCommand(
        commandId: 'c1',
        name: 'grep',
        args: 'foo',
        status: CommandRunStatus.success,
        text: 'matched',
      );
      const diff = TimelineCommand(
        commandId: 'c1',
        name: 'grep',
        args: 'foo',
        status: CommandRunStatus.failed,
        text: 'matched',
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(diff)));
    });

    test('TimelineContextInjection', () {
      const a = TimelineContextInjection(
        id: 'ctx-1',
        text: 'injected instructions',
        producerLabel: 'agent-rule',
        isRecall: false,
        summary: 'rule loaded',
      );
      const b = TimelineContextInjection(
        id: 'ctx-1',
        text: 'injected instructions',
        producerLabel: 'agent-rule',
        isRecall: false,
        summary: 'rule loaded',
      );
      const diff = TimelineContextInjection(
        id: 'ctx-1',
        text: 'injected instructions',
        producerLabel: 'agent-rule',
        isRecall: true,
        summary: 'rule loaded',
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(diff)));
    });

    test('TimelineToolCall', () {
      const a = TimelineToolCall(
        id: 'tc-1',
        name: 'bash',
        arguments: '{"cmd":"ls"}',
        result: 'file.txt',
        isError: false,
        status: ToolRunStatus.completed,
      );
      const b = TimelineToolCall(
        id: 'tc-1',
        name: 'bash',
        arguments: '{"cmd":"ls"}',
        result: 'file.txt',
        isError: false,
        status: ToolRunStatus.completed,
      );
      const diff = TimelineToolCall(
        id: 'tc-1',
        name: 'bash',
        arguments: '{"cmd":"ls"}',
        result: 'file.txt',
        isError: true,
        status: ToolRunStatus.failed,
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(diff)));
    });

    test('TimelineApprovalRequest', () {
      const a = TimelineApprovalRequest(
        requestId: 'req-1',
        sessionId: 'sess-1',
        approvalId: 'app-1',
        toolName: 'bash',
        callId: 'call-1',
        reason: 'danger',
      );
      const b = TimelineApprovalRequest(
        requestId: 'req-1',
        sessionId: 'sess-1',
        approvalId: 'app-1',
        toolName: 'bash',
        callId: 'call-1',
        reason: 'danger',
      );
      const diff = TimelineApprovalRequest(
        requestId: 'req-1',
        sessionId: 'sess-1',
        approvalId: 'app-2',
        toolName: 'bash',
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(diff)));
    });

    test('TimelineQuestionRequest with question collection', () {
      const q1 = QuestionItem(id: 'q1', question: 'Allow?');
      const a = TimelineQuestionRequest(requestId: 'req-1', questions: [q1]);
      const b = TimelineQuestionRequest(
        requestId: 'req-1',
        questions: [QuestionItem(id: 'q1', question: 'Allow?')],
      );
      const diff = TimelineQuestionRequest(requestId: 'req-1', questions: []);

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(diff)));
    });

    test('TimelineQueue with item collection', () {
      const item1 = SessionQueueItem(
        itemId: 'qi-1',
        placement: QueuePlacement.queued,
        text: 'run task',
      );
      const a = TimelineQueue(items: [item1]);
      const b = TimelineQueue(
        items: [
          SessionQueueItem(
            itemId: 'qi-1',
            placement: QueuePlacement.queued,
            text: 'run task',
          ),
        ],
      );
      const diff = TimelineQueue(items: []);

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(diff)));
    });

    test('TimelineJobs with jobs collection', () {
      const job1 = JobView(
        id: 'j1',
        kind: 'bash',
        label: 'compile',
        status: JobStatus.running,
      );
      const a = TimelineJobs(jobs: [job1]);
      const b = TimelineJobs(
        jobs: [
          JobView(
            id: 'j1',
            kind: 'bash',
            label: 'compile',
            status: JobStatus.running,
          ),
        ],
      );
      const diff = TimelineJobs(jobs: []);

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(diff)));
    });

    test('TimelineError', () {
      const a = TimelineError(id: 'err-1', message: 'Fail', code: 'E100');
      const b = TimelineError(id: 'err-1', message: 'Fail', code: 'E100');
      const diff = TimelineError(id: 'err-1', message: 'Fail', code: 'E101');

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(diff)));
    });
  });

  group('Question and interaction models', () {
    test('QuestionItem collection and map equality', () {
      const a = QuestionItem(
        id: 'q1',
        question: 'Choose mode',
        options: ['opt1', 'opt2'],
        multiSelect: true,
        detail: 'detail text',
        header: 'Mode',
        optionDescriptions: {'opt1': 'First', 'opt2': 'Second'},
        intent: QuestionIntent(kind: 'plan-review', approve: 'approve'),
      );
      const b = QuestionItem(
        id: 'q1',
        question: 'Choose mode',
        options: ['opt1', 'opt2'],
        multiSelect: true,
        detail: 'detail text',
        header: 'Mode',
        optionDescriptions: {'opt1': 'First', 'opt2': 'Second'},
        intent: QuestionIntent(kind: 'plan-review', approve: 'approve'),
      );
      const diffOptions = QuestionItem(
        id: 'q1',
        question: 'Choose mode',
        options: ['opt1'],
      );
      const diffDescriptions = QuestionItem(
        id: 'q1',
        question: 'Choose mode',
        options: ['opt1', 'opt2'],
        multiSelect: true,
        detail: 'detail text',
        header: 'Mode',
        optionDescriptions: {'opt1': 'First', 'opt2': 'Different'},
        intent: QuestionIntent(kind: 'plan-review', approve: 'approve'),
      );
      const missingKeyDescriptions = QuestionItem(
        id: 'q1',
        question: 'Choose mode',
        options: ['opt1', 'opt2'],
        multiSelect: true,
        detail: 'detail text',
        header: 'Mode',
        optionDescriptions: {'opt1': 'First', 'opt3': 'Second'},
        intent: QuestionIntent(kind: 'plan-review', approve: 'approve'),
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, equals(a));
      expect(a, isNot(equals(diffOptions)));
      expect(a, isNot(equals(diffDescriptions)));
      expect(a, isNot(equals(missingKeyDescriptions)));
    });

    test('QuestionIntent equality', () {
      const a = QuestionIntent(kind: 'confirm', approve: 'yes');
      const b = QuestionIntent(kind: 'confirm', approve: 'yes');
      const diff = QuestionIntent(kind: 'confirm', approve: 'no');

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(diff)));
    });

    test('ApprovalAnswer equality', () {
      const a = ApprovalAnswer(
        requestId: 'r1',
        sessionId: 's1',
        approvalId: 'a1',
        allowed: true,
      );
      const b = ApprovalAnswer(
        requestId: 'r1',
        sessionId: 's1',
        approvalId: 'a1',
        allowed: true,
      );
      const diff = ApprovalAnswer(
        requestId: 'r1',
        sessionId: 's1',
        approvalId: 'a1',
        allowed: false,
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(diff)));
    });

    test('QuestionAnswer equality with options list', () {
      const a = QuestionAnswer(
        questionId: 'q1',
        selectedOptions: ['opt1', 'opt2'],
        customText: 'note',
      );
      const b = QuestionAnswer(
        questionId: 'q1',
        selectedOptions: ['opt1', 'opt2'],
        customText: 'note',
      );
      const diff = QuestionAnswer(questionId: 'q1', selectedOptions: ['opt1']);

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(diff)));
    });

    test('SessionQueueItem equality', () {
      const a = SessionQueueItem(
        itemId: 'qi-1',
        placement: QueuePlacement.steering,
        text: 'steer next',
      );
      const b = SessionQueueItem(
        itemId: 'qi-1',
        placement: QueuePlacement.steering,
        text: 'steer next',
      );
      const diff = SessionQueueItem(
        itemId: 'qi-1',
        placement: QueuePlacement.context,
        text: 'steer next',
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(diff)));
    });
  });
}
