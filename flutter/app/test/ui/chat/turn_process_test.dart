/// Turn-level process disclosure parity with the reference's `turn-process`
/// projection and control
/// (`reference/deepseek-harness/packages/client/ui-chat/src/client/
/// conversation-nodes/turn-process.ts` and `chat/TurnProcessNodeView.tsx`):
/// one control per Turn owns everything the agent did before its finalized
/// answer, and reports what the Turn is doing or how it ended.
library;

import 'package:app/l10n/app_localizations.dart';
import 'package:app/ui/chat/process_disclosure.dart';
import 'package:app/ui/chat/run_duration.dart';
import 'package:app/ui/chat/timeline_folding.dart';
import 'package:app/ui/chat/turn_process.dart';
import 'package:app/ui/theme/theme.dart';
import 'package:domain/model/chat_message.dart';
import 'package:domain/model/hook.dart';
import 'package:domain/model/timeline_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../l10n_app.dart';

final AppLocalizations _en = lookupAppLocalizations(const Locale('en'));

TimelineMessage _message({
  required String id,
  String text = '',
  MessageRole role = MessageRole.assistant,
  String? reasoning,
  int? seq,
}) => TimelineMessage(
  ChatMessage(
    id: id,
    sessionId: 's1',
    role: role,
    text: text,
    reasoning: reasoning,
    seq: seq,
  ),
);

TimelineToolCall _call({required String id, String name = 'read'}) =>
    TimelineToolCall(
      id: id,
      name: name,
      arguments: '{"file_path":"a.dart"}',
      status: ToolRunStatus.completed,
    );

TurnProcessFacts _facts({
  bool closed = true,
  String? endReason,
  int? startedAtEpochMs,
  int? endedAtEpochMs,
  int? answerSeq,
  bool hasInterleavedInput = false,
}) => TurnProcessFacts(
  turn: 1,
  closed: closed,
  endReason: endReason,
  startedAtEpochMs: startedAtEpochMs,
  endedAtEpochMs: endedAtEpochMs,
  answerSeq: answerSeq,
  hasInterleavedInput: hasInterleavedInput,
);

void main() {
  group('turnProcessLabel', () {
    // Fixture: TurnProcessNodeView returns null while the Turn's status is not
    // `closed` — the running row is the live status, so the control carries no
    // label of its own while the Turn runs.
    test('an open Turn renders no control label', () {
      expect(turnProcessLabel(_facts(closed: false), _en), isNull);
      expect(
        turnProcessLabel(
          _facts(closed: false, startedAtEpochMs: 1000, endedAtEpochMs: 9000),
          _en,
        ),
        isNull,
      );
    });

    // Fixture: `turnProcess.took` with the settled `formatRunDuration` parts —
    // whole numerals, never zero-padded.
    test('a finished Turn reads Completed in with unpadded parts', () {
      final label = turnProcessLabel(
        _facts(startedAtEpochMs: 1000, endedAtEpochMs: 124000),
        _en,
      )!;
      expect(label.prefix, _en.turnProcessTook);
      expect(label.duration.map((part) => part.text).join(), '2m 3s');
      expect(
        turnProcessLabel(
          _facts(startedAtEpochMs: 1000, endedAtEpochMs: 3904000),
          _en,
        )!.duration.map((part) => part.text).join(),
        '1h 5m 3s',
      );
    });

    // Fixture: the reference floors elapsed time at one second, so a Turn that
    // finished in milliseconds still reports a duration rather than 0s.
    test('a sub-second Turn floors to one second', () {
      final label = turnProcessLabel(
        _facts(startedAtEpochMs: 1000, endedAtEpochMs: 1200),
        _en,
      )!;
      expect(label.duration.map((part) => part.text).join(), '1s');
    });

    // Fixture: TurnProcessNodeView with no clock on either side — the settled
    // fallback is the reference's `turnProcess.worked`, with no duration.
    test('a finished Turn with no clock reads Completed', () {
      final label = turnProcessLabel(_facts(), _en)!;
      expect(label.prefix, _en.turnProcessWorked);
      expect(label.duration, isEmpty);
    });

    // Fixture: the reference maps the `turn/end` reason kinds onto
    // `turnProcess.stopped` and `turnProcess.failed`, each replacing the
    // duration rather than following it.
    test('a stopped Turn reads Stopped and a failed one Failed', () {
      final stopped = turnProcessLabel(
        _facts(
          endReason: 'aborted',
          startedAtEpochMs: 1000,
          endedAtEpochMs: 124000,
        ),
        _en,
      )!;
      expect(stopped.prefix, _en.turnProcessStopped);
      expect(stopped.duration, isEmpty);

      final failed = turnProcessLabel(
        _facts(
          endReason: 'error',
          startedAtEpochMs: 1000,
          endedAtEpochMs: 124000,
        ),
        _en,
      )!;
      expect(failed.prefix, _en.turnProcessFailed);
      expect(failed.duration, isEmpty);
    });
  });

  group('TurnProcessFacts.alwaysOpen', () {
    // Fixture: the reference's `turnProcessAlwaysOpen` plus its
    // `hasInterleavedInput` rule — a Turn that is still running, was stopped or
    // failed, or had a human speak inside it can never fold its process.
    test('a running, stopped, failed or interrupted Turn never folds', () {
      expect(_facts(closed: false).alwaysOpen, isTrue);
      expect(_facts(endReason: 'aborted').alwaysOpen, isTrue);
      expect(_facts(endReason: 'error').alwaysOpen, isTrue);
      expect(_facts(hasInterleavedInput: true).alwaysOpen, isTrue);
    });

    // Fixture: a cleanly finished Turn is the one case the reference folds.
    test('a cleanly finished Turn folds', () {
      expect(_facts().alwaysOpen, isFalse);
      expect(_facts(endReason: 'completed').alwaysOpen, isFalse);
    });
  });

  group('isFoldableProcessRow', () {
    // Fixture: the reference's `processMember` admits every visible node in the
    // Turn's range, the group seat (TimelineActivityGroup) included, so a
    // collapsed Turn hides the whole card rather than the card surviving its
    // owner's fold.
    test('process work is foldable', () {
      expect(
        isFoldableProcessRow(
          const TimelineActivityGroup(id: 'g1', entries: <TimelineItem>[]),
        ),
        isTrue,
      );
      expect(isFoldableProcessRow(_call(id: 't1')), isTrue);
      expect(
        isFoldableProcessRow(
          const TimelineContextInjection(id: 'ctx', text: 'context'),
        ),
        isTrue,
      );
      expect(
        isFoldableProcessRow(_message(id: 'm1', text: 'an answer')),
        isTrue,
      );
    });

    // Fixture: the reference's `INDEPENDENT` set keeps `user`, `steering`,
    // `turn-error`, and `turn-tail` out of the process range; this client also
    // keeps the interactive cards out, because hiding a blocking prompt behind
    // a disclosure loses the reader's only way to answer it.
    test('the reader-facing rows are never foldable', () {
      expect(
        isFoldableProcessRow(
          _message(id: 'u1', text: 'hello', role: MessageRole.user),
        ),
        isFalse,
      );
      expect(isFoldableProcessRow(const TimelineTurnBoundary(1)), isFalse);
      expect(
        isFoldableProcessRow(
          const TimelineCommand(commandId: 'c1', name: 'compact'),
        ),
        isFalse,
      );
      expect(
        isFoldableProcessRow(const TimelineCompaction(id: 'cp1')),
        isFalse,
      );
      expect(
        isFoldableProcessRow(const TimelineError(id: 'e1', message: 'boom')),
        isFalse,
      );
      expect(isFoldableProcessRow(const TimelineQueue()), isFalse);
      expect(isFoldableProcessRow(const TimelineJobs()), isFalse);
      expect(
        isFoldableProcessRow(
          const TimelineHookAudit(
            HookAudit(
              handlerId: 'h1',
              turn: 1,
              point: 'PreToolUse',
              dialect: HookDialect.claudeCode,
            ),
          ),
        ),
        isFalse,
      );
      expect(
        isFoldableProcessRow(
          const TimelineWorkflowRun(
            runId: 'w1',
            name: 'ship',
            status: WorkflowRunStatus.completed,
            phases: <WorkflowPhase>[],
          ),
        ),
        isFalse,
      );
      expect(
        isFoldableProcessRow(
          const TimelineApprovalRequest(
            requestId: 'rpc-1',
            sessionId: 's1',
            approvalId: 'a1',
            toolName: 'bash',
          ),
        ),
        isFalse,
      );
      expect(
        isFoldableProcessRow(
          const TimelineQuestionRequest(
            requestId: 'rpc-2',
            questions: <QuestionItem>[],
          ),
        ),
        isFalse,
      );
      // A row kind this fold does not know stays visible: a disclosure may hide
      // work it can name, never a fact it cannot.
      expect(isFoldableProcessRow(Object()), isFalse);
    });
  });

  group('turnProcessFacts', () {
    // Fixture: the reference's `latestAnswer` — the last reply-bearing
    // assistant step with no tool call after it.
    test('the answer is the last reply with no tool call after it', () {
      const boundary = TimelineTurnBoundary(1);
      final facts = turnProcessFacts(boundary, <TimelineItem>[
        boundary,
        _message(id: 'u1', text: 'do it', role: MessageRole.user),
        _call(id: 't1'),
        _message(id: 'a1', text: 'done', seq: 7),
      ]);
      expect(facts.answerSeq, 7);
      expect(facts.closed, isFalse);
    });

    // Fixture: the reference's `latestAnswer` reads the Turn's last
    // reply-bearing step — work logged before it is what the reply answers, so
    // it does not disqualify the reply.
    test('a reply after more work is still the answer', () {
      const boundary = TimelineTurnBoundary(1, endSeq: 9);
      final facts = turnProcessFacts(boundary, <TimelineItem>[
        boundary,
        _call(id: 't1'),
        _message(id: 'a1', text: 'the answer', seq: 7),
      ]);
      expect(facts.answerSeq, 7);
      expect(facts.closed, isTrue);
    });

    // Fixture: only the Turn's last reply is the finalized answer; an earlier
    // reply belongs to the process range the reference folds.
    test('an earlier reply is not the answer', () {
      const boundary = TimelineTurnBoundary(1, endSeq: 9);
      final facts = turnProcessFacts(boundary, <TimelineItem>[
        boundary,
        _message(id: 'a1', text: 'first attempt', seq: 7),
        _message(id: 'a2', text: 'the answer', seq: 8),
      ]);
      expect(facts.answerSeq, 8);
    });

    // Fixture: the reference's opening human message is not interleaved input;
    // anything the reader says after it is.
    test('only a human message after the opening one is interleaved', () {
      const boundary = TimelineTurnBoundary(1, endSeq: 9);
      expect(
        turnProcessFacts(boundary, <TimelineItem>[
          boundary,
          _message(id: 'u1', text: 'go', role: MessageRole.user),
          _call(id: 't1'),
        ]).hasInterleavedInput,
        isFalse,
      );
      expect(
        turnProcessFacts(boundary, <TimelineItem>[
          boundary,
          _message(id: 'u1', text: 'go', role: MessageRole.user),
          _call(id: 't1'),
          _message(id: 'u2', text: 'wait', role: MessageRole.user),
        ]).hasInterleavedInput,
        isTrue,
      );
    });

    // Fixture: the reference's `latestAnswer` requires the last step to carry
    // no tool call — work logged after the candidate reply is what the model
    // started on top of it, so the Turn has no answer to keep out of the fold.
    test('work after the candidate reply leaves the Turn with no answer', () {
      const boundary = TimelineTurnBoundary(1, endSeq: 9);
      final facts = turnProcessFacts(boundary, <TimelineItem>[
        boundary,
        _message(id: 'a1', text: 'the answer', seq: 7),
        _call(id: 't1'),
      ]);
      expect(facts.answerSeq, isNull);
    });
  });

  group('foldTurnProcesses', () {
    // Fixture: the reference's `processMember` requires
    // `anchorSeq < answerAnchorSeq` — the reply a Turn produced stays visible
    // while everything that led to it folds, and nothing after the answer may
    // be hidden either. The members keep transcript order: the control
    // replaces the boundary where it stood.
    test('the finalized answer stays visible while the work before it folds', () {
      const boundary = TimelineTurnBoundary(1, endSeq: 9);
      final rows = <Object>[
        boundary,
        _call(id: 't1'),
        _message(id: 'a1', text: 'done', seq: 7),
        _message(id: 'a2', text: 'more', seq: 8),
      ];

      final folded = foldTurnProcesses(rows);

      expect(folded, hasLength(1));
      final section = folded.single as TurnProcessSection;
      // The finalized answer is the Turn's last reply, so the earlier reply is
      // process work like the tool call before it.
      expect(section.facts.answerSeq, 8);
      expect(section.members.map((member) => member.row), <Object>[
        _call(id: 't1'),
        _message(id: 'a1', text: 'done', seq: 7),
        _message(id: 'a2', text: 'more', seq: 8),
      ]);
      expect(section.members.map((member) => member.folds), <bool>[
        true,
        true,
        false,
      ]);
      expect(section.hasContent, isTrue);
      expect(section.defaultOpen, isFalse);
    });

    // Fixture: `TurnProcessNodeView`'s `hasContent` — a Turn with nothing
    // behind the control stays open, because a chevron that reveals an empty
    // body is a lie.
    test('a Turn with no foldable row has no content to fold', () {
      const boundary = TimelineTurnBoundary(1, endSeq: 9);
      final folded = foldTurnProcesses(<Object>[
        boundary,
        _message(id: 'u1', text: 'go', role: MessageRole.user),
        const TimelineCompaction(id: 'cp1'),
      ]);

      final section = folded.single as TurnProcessSection;
      expect(section.members.map((member) => member.folds), <bool>[
        false,
        false,
      ]);
      expect(section.hasContent, isFalse);
    });

    // Fixture: a live Turn's control is open from the start, so its process
    // rows and its answer render together.
    test('an open Turn defaults to open', () {
      final folded = foldTurnProcesses(<Object>[
        const TimelineTurnBoundary(1),
        _call(id: 't1'),
      ]);

      final section = folded.single as TurnProcessSection;
      expect(section.defaultOpen, isTrue);
      expect(section.hasContent, isTrue);
    });

    // Fixture: a live Turn's rows the Turn owns include the phase card, so a
    // collapsed Turn hides the whole card rather than leaving its header
    // behind.
    test('a phase card is process work the Turn owns', () {
      final folded = foldTurnProcesses(<Object>[
        const TimelineTurnBoundary(1, endSeq: 9),
        const TimelineActivityGroup(
          id: 'g1',
          entries: <TimelineItem>[
            TimelineToolCall(id: 't1', name: 'read'),
            TimelineToolCall(id: 't2', name: 'grep'),
          ],
        ),
        _message(id: 'a1', text: 'done', seq: 7),
      ]);

      final section = folded.single as TurnProcessSection;
      expect(section.members, hasLength(2));
      expect(section.members.first.row, isA<TimelineActivityGroup>());
      expect(section.members.first.folds, isTrue);
      expect(
        section.members.last.row,
        _message(id: 'a1', text: 'done', seq: 7),
      );
      expect(section.members.last.folds, isFalse);
    });

    // Fixture: a phase card hides its members behind its own fold, but they are
    // still the Turn's log — the answer is decided over the expanded order, so
    // a call that ran inside a card still counts as work after the reply.
    test('a call inside a phase card still disqualifies an earlier reply', () {
      final folded = foldTurnProcesses(<Object>[
        const TimelineTurnBoundary(1, endSeq: 9),
        _message(id: 'a1', text: 'the answer', seq: 7),
        const TimelineActivityGroup(
          id: 'g1',
          entries: <TimelineItem>[
            TimelineToolCall(id: 't1', name: 'read'),
            TimelineToolCall(id: 't2', name: 'grep'),
          ],
        ),
      ]);

      final section = folded.single as TurnProcessSection;
      expect(section.facts.answerSeq, isNull);
      expect(section.members, hasLength(2));
      expect(section.members.map((member) => member.folds), <bool>[true, true]);
    });

    // Fixture: rows outside any Turn (the pre-turn prefix) pass through
    // untouched — the reference only folds a Turn's own range.
    test('rows before the first Turn boundary pass through', () {
      const boundary = TimelineTurnBoundary(1, endSeq: 9);
      final preTurn = _message(id: 'u0', text: 'hi', role: MessageRole.user);
      final folded = foldTurnProcesses(<Object>[
        preTurn,
        boundary,
        _call(id: 't1'),
      ]);

      expect(folded.first, preTurn);
      expect(folded.last, isA<TurnProcessSection>());
    });
  });

  group('TurnProcessRow', () {
    Future<void> pump(WidgetTester tester, TurnProcessFacts facts) async {
      await tester.pumpWidget(
        l10nApp(
          home: Scaffold(
            body: TurnProcessRow(
              section: TurnProcessSection(
                facts: facts,
                members: const <TurnProcessMember>[],
              ),
              buildRow: (row) => const SizedBox.shrink(),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('a settled control renders the unpadded duration in mono', (
      tester,
    ) async {
      await pump(
        tester,
        _facts(startedAtEpochMs: 1000, endedAtEpochMs: 124000),
      );

      // The reference's own prefix, then whole numerals: `2m 3s`, never
      // `2m 03s`.
      expect(find.text('Completed in 2m 3s'), findsOneWidget);
      final rich = tester.widget<Text>(find.text('Completed in 2m 3s'));
      final spans = (rich.textSpan! as TextSpan).children!.cast<TextSpan>();
      expect(spans.map((span) => span.text).join(), 'Completed in 2m 3s');
      // The prefix keeps the label's own type; every numeral wears the code
      // family with tabular figures, and every localized unit does not.
      expect(spans.first.style, isNull);
      var index = 1;
      for (final part in runDurationParts(123000, _en)) {
        expect(spans[index].text, part.text);
        expect(
          spans[index].style?.fontFamily,
          part.numeric ? kCodeFontFamily : null,
        );
        expect(
          spans[index].style?.fontFeatures,
          part.numeric
              ? const <FontFeature>[FontFeature.tabularFigures()]
              : null,
        );
        index += 1;
      }
      expect(index, spans.length);
    });

    testWidgets('an hours-long settled control stays unpadded', (tester) async {
      await pump(
        tester,
        _facts(startedAtEpochMs: 1000, endedAtEpochMs: 3904000),
      );
      expect(find.text('Completed in 1h 5m 3s'), findsOneWidget);
    });

    testWidgets('an open Turn renders the control with no label', (
      tester,
    ) async {
      await pump(
        tester,
        _facts(closed: false, startedAtEpochMs: 1000, endedAtEpochMs: 9000),
      );
      expect(find.byType(TurnProcessRow), findsOneWidget);
      expect(find.textContaining('Deep diving'), findsNothing);
      expect(find.textContaining('Completed'), findsNothing);
    });
  });
}
