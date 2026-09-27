/// Process-activity parity with the reference chat grouping's own module
/// (`reference/deepseek-harness/packages/client/ui-chat/src/client/
/// conversation-nodes/process-activity.ts` plus `chat/step-process.ts`): the
/// tool-name→category table, the count ranking with its first-appearance
/// tiebreak, the live one-liner and its 160-grapheme cap, and the settled
/// title.
library;

import 'dart:ui';

import 'package:app/l10n/app_localizations.dart';
import 'package:app/ui/chat/process_activity.dart';
import 'package:characters/characters.dart';
import 'package:domain/model/timeline_item.dart';
import 'package:flutter_test/flutter_test.dart';

final AppLocalizations _en = lookupAppLocalizations(const Locale('en'));

/// The reference's `continuation`: only the first character is lowered, so a
/// joined English title reads as one sentence.
String _continued(String label) =>
    label.isEmpty ? label : label[0].toLowerCase() + label.substring(1);

TimelineToolCall _call({
  required String id,
  required String name,
  ToolRunStatus status = ToolRunStatus.completed,
  String? arguments,
  int? startedAtEpochMs,
  List<TimelineToolCall> children = const <TimelineToolCall>[],
}) => TimelineToolCall(
  id: id,
  name: name,
  status: status,
  arguments: arguments,
  startedAtEpochMs: startedAtEpochMs,
  children: children,
);

ProcessActivitySummary _summary(List<ProcessActivityCount> counts) =>
    ProcessActivitySummary(
      counts: List<ProcessActivityCount>.unmodifiable(counts),
    );

void main() {
  group('processActivityOf', () {
    // Fixture: process-activity.ts `activity()` — the table's probe order and
    // membership, `_inspect`/`terminal_`/`subagent_` prefixes included.
    test('maps every tool name family onto its category', () {
      expect(processActivityOf('read'), ProcessActivity.read);
      expect(processActivityOf('read_image'), ProcessActivity.readImage);
      for (final name in <String>[
        'grep',
        'glob',
        'file_inspect',
        'lsp_inspect',
      ]) {
        expect(processActivityOf(name), ProcessActivity.search, reason: name);
      }
      expect(processActivityOf('write'), ProcessActivity.write);
      for (final name in <String>['edit', 'apply_patch']) {
        expect(processActivityOf(name), ProcessActivity.edit, reason: name);
      }
      for (final name in <String>[
        'bash',
        'pwsh',
        'exec_command',
        'write_stdin',
        'terminal_run',
      ]) {
        expect(processActivityOf(name), ProcessActivity.commands, reason: name);
      }
      expect(processActivityOf('run_code'), ProcessActivity.code);
      expect(processActivityOf('web_search'), ProcessActivity.webSearch);
      expect(processActivityOf('web_fetch'), ProcessActivity.webFetch);
      for (final name in <String>['subagent', 'subagent_explore']) {
        expect(
          processActivityOf(name),
          ProcessActivity.subagents,
          reason: name,
        );
      }
      for (final name in <String>[
        'todo_write',
        'create_goal',
        'update_goal',
        'get_goal',
      ]) {
        expect(processActivityOf(name), ProcessActivity.plan, reason: name);
      }
      for (final name in <String>['ask_user_question', 'request_user_input']) {
        expect(
          processActivityOf(name),
          ProcessActivity.questions,
          reason: name,
        );
      }
      // The control tools are ordinary work, not delegations.
      expect(processActivityOf('send_message'), ProcessActivity.tools);
      expect(processActivityOf('anything_else'), ProcessActivity.tools);
    });
  });

  group('deriveProcessActivity', () {
    // Fixture: process-activity.ts `processActivity()` — counts descend, and
    // the reference's stable sort leaves equal counts in first-appearance
    // order.
    test('ranks by count and breaks ties by first appearance', () {
      final summary = deriveProcessActivity(<TimelineToolCall>[
        _call(id: 'a', name: 'read'),
        _call(id: 'b', name: 'grep'),
        _call(id: 'c', name: 'edit'),
        _call(id: 'd', name: 'read'),
      ]);

      expect(
        summary.counts.map((count) => (count.kind, count.count)).toList(),
        <(ProcessActivity, int)>[
          (ProcessActivity.read, 2),
          (ProcessActivity.search, 1),
          (ProcessActivity.edit, 1),
        ],
      );
    });

    // Fixture: the reference counts every call in the tree once, deduped by
    // call id, so a nested dispatch is neither lost nor double-counted.
    test('counts nested calls once and dedupes by call id', () {
      final nested = _call(id: 'c', name: 'grep');
      final summary = deriveProcessActivity(<TimelineToolCall>[
        _call(id: 'r', name: 'read', children: <TimelineToolCall>[nested]),
        nested,
      ]);

      expect(
        summary.counts.map((count) => (count.kind, count.count)).toList(),
        <(ProcessActivity, int)>[
          (ProcessActivity.read, 1),
          (ProcessActivity.search, 1),
        ],
      );
    });

    // Fixture: the reference picks the running tool with the greatest `time`
    // and reads its one-line detail from its arguments.
    test('names the latest running call and its live detail', () {
      final summary = deriveProcessActivity(<TimelineToolCall>[
        _call(
          id: 'r',
          name: 'read',
          arguments: '{"file_path":"pubspec.yaml"}',
          status: ToolRunStatus.running,
          startedAtEpochMs: 100,
        ),
        _call(
          id: 'b',
          name: 'bash',
          arguments: '{"command":"flutter test"}',
          status: ToolRunStatus.running,
          startedAtEpochMs: 200,
        ),
      ]);

      expect(summary.running, ProcessActivity.commands);
      expect(summary.runningDetail, 'flutter test');
      expect(summary.preparing, isFalse);
    });

    // Fixture: the reference's `phase: 'preparing'` — arguments that are not
    // usable yet name the tool instead of a task detail, and a known category
    // has no detail to show.
    test('reports a call whose arguments are not usable as preparing', () {
      final unnamed = deriveProcessActivity(<TimelineToolCall>[
        _call(id: 'x', name: 'mystery_tool', status: ToolRunStatus.running),
      ]);
      expect(unnamed.running, ProcessActivity.tools);
      expect(unnamed.runningDetail, 'mystery_tool');
      expect(unnamed.preparing, isTrue);

      final known = deriveProcessActivity(<TimelineToolCall>[
        _call(
          id: 'r',
          name: 'read',
          arguments: '{"file_path":',
          status: ToolRunStatus.running,
        ),
      ]);
      expect(known.running, ProcessActivity.read);
      expect(known.runningDetail, isEmpty);
      expect(known.preparing, isTrue);
    });

    // Fixture: `runningDetail` falls back to the newest reasoning paragraph
    // when no tool call is in flight.
    test('falls back to the reasoning detail when nothing runs', () {
      final summary = deriveProcessActivity(<TimelineToolCall>[
        _call(id: 'r', name: 'read'),
      ], reasoningDetail: () => 'latest thought');

      expect(summary.running, isNull);
      expect(summary.runningDetail, 'latest thought');
    });
  });

  group('liveToolDetail', () {
    // Fixture: process-activity.ts `LIVE_TOOL_DETAIL_KEYS` — the first key in
    // priority order that carries a readable value wins.
    test('reads the first readable argument in priority order', () {
      expect(
        liveToolDetail('read', '{"file_path":"src/main.dart"}'),
        'src/main.dart',
      );
      expect(
        liveToolDetail('bash', '{"command":"ls","title":"List files"}'),
        'List files',
      );
      expect(liveToolDetail('web_search', '{"queries":["a","b"]}'), 'a, b');
      expect(
        liveToolDetail(
          'ask_user_question',
          '{"questions":[{"question":"Which one?"},{"question":"And?"}]}',
        ),
        'Which one?',
      );
    });

    // Fixture: `normalizeLiveToolDetail` — whitespace collapses to single
    // spaces and the value is trimmed.
    test('collapses whitespace to one bounded line', () {
      expect(
        liveToolDetail('bash', '{"command":"  cargo   check \\n --all "}'),
        'cargo check --all',
      );
    });

    // Fixture: the reference falls back to the call's own name when the
    // arguments are absent, unparseable, or carry no readable key.
    test('falls back to the call name', () {
      expect(liveToolDetail('bash', ''), 'bash');
      expect(liveToolDetail('bash', '{"command":'), 'bash');
      expect(liveToolDetail('bash', '{"other":1}'), 'bash');
      expect(liveToolDetail('bash', '{"command":42}'), 'bash');
    });

    // Fixture: `LIVE_TOOL_DETAIL_MAX_CHARS` counts grapheme clusters, so a
    // truncated line never splits an emoji and never exceeds the cap.
    test('caps a detail line at 160 graphemes', () {
      final short = 'a' * 160;
      expect(normalizeLiveToolDetail(short), short);

      final over = 'a' * 161;
      final capped = normalizeLiveToolDetail(over);
      expect(capped.characters.length, liveToolDetailMaxChars);
      expect(capped, '${'a' * 159}…');

      final emoji = List<String>.filled(161, '👍').join();
      final cappedEmoji = normalizeLiveToolDetail(emoji);
      expect(cappedEmoji.characters.length, liveToolDetailMaxChars);
      expect(cappedEmoji, '${List<String>.filled(159, '👍').join()}…');
    });
  });

  group('latestReasoningDetail', () {
    // Fixture: process-activity.ts `liveReasoningDetail` — the newest
    // non-empty paragraph, with emphasis markers stripped.
    test('reads the newest non-empty paragraph without emphasis markers', () {
      expect(
        latestReasoningDetail('first\n\n**second** thought'),
        'second thought',
      );
      expect(latestReasoningDetail('only'), 'only');
      expect(latestReasoningDetail('first\n\n   \n\n'), 'first');
      expect(latestReasoningDetail(null), isEmpty);
      expect(latestReasoningDetail('  '), isEmpty);
    });
  });

  group('processTitle', () {
    // Fixture: chat/step-process.ts `processTitle` — a closed group's top
    // three categories without counts.
    test('one category reads its own settled label', () {
      expect(
        processTitle(
          _summary(<ProcessActivityCount>[
            const ProcessActivityCount(ProcessActivity.read, 3),
          ]),
          _en,
        ),
        _en.stepProcessDoneRead,
      );
    });

    test('two categories join through stepProcessJoinTwo', () {
      expect(
        processTitle(
          _summary(<ProcessActivityCount>[
            const ProcessActivityCount(ProcessActivity.read, 3),
            const ProcessActivityCount(ProcessActivity.search, 2),
          ]),
          _en,
        ),
        _en.stepProcessJoinTwo(
          _en.stepProcessDoneRead,
          _continued(_en.stepProcessDoneSearch),
        ),
      );
    });

    test('three categories join through stepProcessComma', () {
      expect(
        processTitle(
          _summary(<ProcessActivityCount>[
            const ProcessActivityCount(ProcessActivity.commands, 3),
            const ProcessActivityCount(ProcessActivity.read, 1),
            const ProcessActivityCount(ProcessActivity.edit, 1),
          ]),
          _en,
        ),
        <String>[
          _en.stepProcessDoneCommands,
          _continued(_en.stepProcessDoneRead),
          _continued(_en.stepProcessDoneEdit),
        ].join(_en.stepProcessComma),
      );
    });

    // Fixture: a fourth category is dropped from the title and marked with
    // `message.stepProcess.more`.
    test('a fourth category appends stepProcessMore', () {
      expect(
        processTitle(
          _summary(<ProcessActivityCount>[
            const ProcessActivityCount(ProcessActivity.commands, 4),
            const ProcessActivityCount(ProcessActivity.read, 3),
            const ProcessActivityCount(ProcessActivity.edit, 2),
            const ProcessActivityCount(ProcessActivity.search, 1),
          ]),
          _en,
        ),
        _en.stepProcessMore(
          <String>[
            _en.stepProcessDoneCommands,
            _continued(_en.stepProcessDoneRead),
            _continued(_en.stepProcessDoneEdit),
          ].join(_en.stepProcessComma),
        ),
      );
    });

    // Fixture: the reference returns `stepProcess.done.thinking` for a group
    // that ranked no category at all.
    test('no category reads the thinking label', () {
      expect(
        processTitle(_summary(<ProcessActivityCount>[]), _en),
        _en.stepProcessDoneThinking,
      );
    });
  });

  group('activity labels', () {
    // Fixture: ChatGroupSeat's live title — `message.stepProcess.<activity>`
    // while running, `message.stepProcess.prepare.<activity>` while preparing,
    // and `message.stepProcess.done.<activity>` once settled. A group that has
    // not named a tool yet prepares to call one, so `thinking` prepares as
    // `tools`.
    test('every activity reads its live, preparing and done label', () {
      final live = <ProcessActivity, String Function(AppLocalizations)>{
        ProcessActivity.thinking: (l10n) => l10n.stepProcessThinking,
        ProcessActivity.read: (l10n) => l10n.stepProcessRead,
        ProcessActivity.readImage: (l10n) => l10n.stepProcessReadImage,
        ProcessActivity.search: (l10n) => l10n.stepProcessSearch,
        ProcessActivity.write: (l10n) => l10n.stepProcessWrite,
        ProcessActivity.edit: (l10n) => l10n.stepProcessEdit,
        ProcessActivity.commands: (l10n) => l10n.stepProcessCommands,
        ProcessActivity.code: (l10n) => l10n.stepProcessCode,
        ProcessActivity.webSearch: (l10n) => l10n.stepProcessWebSearch,
        ProcessActivity.webFetch: (l10n) => l10n.stepProcessWebFetch,
        ProcessActivity.subagents: (l10n) => l10n.stepProcessSubagents,
        ProcessActivity.plan: (l10n) => l10n.stepProcessPlan,
        ProcessActivity.questions: (l10n) => l10n.stepProcessQuestions,
        ProcessActivity.tools: (l10n) => l10n.stepProcessTools,
      };
      final preparing = <ProcessActivity, String Function(AppLocalizations)>{
        ProcessActivity.thinking: (l10n) => l10n.stepProcessPrepareTools,
        ProcessActivity.read: (l10n) => l10n.stepProcessPrepareRead,
        ProcessActivity.readImage: (l10n) => l10n.stepProcessPrepareReadImage,
        ProcessActivity.search: (l10n) => l10n.stepProcessPrepareSearch,
        ProcessActivity.write: (l10n) => l10n.stepProcessPrepareWrite,
        ProcessActivity.edit: (l10n) => l10n.stepProcessPrepareEdit,
        ProcessActivity.commands: (l10n) => l10n.stepProcessPrepareCommands,
        ProcessActivity.code: (l10n) => l10n.stepProcessPrepareCode,
        ProcessActivity.webSearch: (l10n) => l10n.stepProcessPrepareWebSearch,
        ProcessActivity.webFetch: (l10n) => l10n.stepProcessPrepareWebFetch,
        ProcessActivity.subagents: (l10n) => l10n.stepProcessPrepareSubagents,
        ProcessActivity.plan: (l10n) => l10n.stepProcessPreparePlan,
        ProcessActivity.questions: (l10n) => l10n.stepProcessPrepareQuestions,
        ProcessActivity.tools: (l10n) => l10n.stepProcessPrepareTools,
      };
      final done = <ProcessActivity, String Function(AppLocalizations)>{
        ProcessActivity.thinking: (l10n) => l10n.stepProcessDoneThinking,
        ProcessActivity.read: (l10n) => l10n.stepProcessDoneRead,
        ProcessActivity.readImage: (l10n) => l10n.stepProcessDoneReadImage,
        ProcessActivity.search: (l10n) => l10n.stepProcessDoneSearch,
        ProcessActivity.write: (l10n) => l10n.stepProcessDoneWrite,
        ProcessActivity.edit: (l10n) => l10n.stepProcessDoneEdit,
        ProcessActivity.commands: (l10n) => l10n.stepProcessDoneCommands,
        ProcessActivity.code: (l10n) => l10n.stepProcessDoneCode,
        ProcessActivity.webSearch: (l10n) => l10n.stepProcessDoneWebSearch,
        ProcessActivity.webFetch: (l10n) => l10n.stepProcessDoneWebFetch,
        ProcessActivity.subagents: (l10n) => l10n.stepProcessDoneSubagents,
        ProcessActivity.plan: (l10n) => l10n.stepProcessDonePlan,
        ProcessActivity.questions: (l10n) => l10n.stepProcessDoneQuestions,
        ProcessActivity.tools: (l10n) => l10n.stepProcessDoneTools,
      };
      for (final activity in ProcessActivity.values) {
        expect(
          liveActivityLabel(activity, _en),
          live[activity]!(_en),
          reason: '$activity live',
        );
        expect(
          liveActivityLabel(activity, _en, preparing: true),
          preparing[activity]!(_en),
          reason: '$activity preparing',
        );
        expect(
          doneActivityLabel(activity, _en),
          done[activity]!(_en),
          reason: '$activity done',
        );
      }
    });
  });
}
