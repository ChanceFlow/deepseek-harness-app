/// Wire-coverage fixtures for the session-event folds added on the
/// `dsh-v0.1.5-rc.2` pin: `tool/result.meta` presentation, the log-only
/// `hook/*` audit pair, the log-only `sandbox/mode` fact, the durable
/// `schedule/change` stream, and the `tool-workflow/*` durable run family.
///
/// Wire truth read from the reference submodule at `dsh-v0.1.5-rc.2`
/// (`fb2c4b9e698e30edb738bca4cf0618587db7d203`):
/// - `packages/core/tools/src/presentation.ts` (`ToolResultView` arms) and
///   each tool's `output.presentationMeta` projection:
///   `packages/fs/tool-fs/src/diff.ts` `FsDiffMeta`,
///   `packages/fs/tool-fs/src/read.ts` read meta,
///   `packages/fs/tool-fs-search/src/presentation.ts` `SearchMeta`,
///   `packages/web/tool-web/src/{search,fetch}.ts` meta,
///   `packages/terminal/tool-terminal/src/index.ts` terminal meta;
/// - `packages/hooks/hook-protocol/src/events.ts` `hook/invoked` +
///   `hook/result`;
/// - `packages/sandbox/sandbox-policy/src/session-mode.ts` `sandbox/mode`;
/// - `packages/schedule/schedule/src/types.ts` `schedule/change`;
/// - `packages/workflow/tool-workflow/src/types.ts` `tool-workflow/*`.
library;

import 'dart:convert';

import 'package:domain/model/hook.dart';
import 'package:domain/model/sandbox.dart';
import 'package:domain/model/schedule.dart';
import 'package:domain/model/timeline_item.dart';
import 'package:domain/model/tool_presentation.dart';
import 'package:network/rpc_envelope.dart';
import 'package:test/test.dart';

import 'package:harness_adapter/src/timeline_reducer.dart';

JsonMap event(int seq, String type, JsonMap data) => <String, Object?>{
  'type': type,
  'seq': seq,
  'time': seq,
  'data': data,
};

JsonMap toolCall(int seq, String callId, String name, JsonMap args) =>
    event(seq, 'tool/call', <String, Object?>{
      'turn': 1,
      'step': 1,
      'callId': callId,
      'name': name,
      'arguments': jsonEncode(args),
    });

JsonMap toolResult(int seq, String callId, JsonMap meta) =>
    event(seq, 'tool/result', <String, Object?>{
      'turn': 1,
      'step': 1,
      'message': <String, Object?>{
        'id': 'tool-msg-$callId',
        'role': 'user',
        'source': <String, Object?>{'kind': 'tool', 'callId': callId},
        'content': <Object?>[
          <String, Object?>{
            'type': 'tool-result',
            'toolCallId': callId,
            'content': <Object?>[
              <String, Object?>{'type': 'text', 'text': 'ok'},
            ],
            'isError': false,
          },
        ],
      },
      'meta': meta,
    });

TimelineToolCall onlyTool(TimelineReducer reducer) =>
    reducer.snapshot().whereType<TimelineToolCall>().single;

void main() {
  group('tool/result presentation (persisted output.presentationMeta)', () {
    test('a read window narrows into a line-numbered read card', () {
      final reducer = TimelineReducer('s1')
        ..reset(<JsonMap>[
          toolCall(1, 'c1', 'read', <String, Object?>{'file_path': 'a.dart'}),
          toolResult(2, 'c1', <String, Object?>{
            'path': 'a.dart',
            'offset': 62,
            'lines': <Object?>[
              <String, Object?>{'number': 62, 'text': 'final x = 1;'},
            ],
            'totalLines': 204,
            'lang': 'dart',
          }),
        ]);
      final presentation = onlyTool(reducer).presentation;
      expect(presentation, isA<ReadToolPresentation>());
      final read = presentation as ReadToolPresentation;
      expect(read.path, 'a.dart');
      expect(read.offset, 62);
      expect(read.totalLines, 204);
      expect(read.lang, 'dart');
      expect(
        read.lines.single,
        const ReadFileLine(number: 62, text: 'final x = 1;'),
      );
    });

    test('an applied write narrows into a read-only diff card', () {
      final reducer = TimelineReducer('s1')
        ..reset(<JsonMap>[
          toolCall(1, 'c1', 'write', <String, Object?>{'file_path': 'a.txt'}),
          toolResult(2, 'c1', <String, Object?>{
            'diffs': <Object?>[
              <String, Object?>{
                'path': 'a.txt',
                'oldText': null,
                'newText': 'hello\n',
              },
            ],
          }),
        ]);
      final presentation = onlyTool(reducer).presentation;
      expect(presentation, isA<DiffToolPresentation>());
      final diffs = (presentation as DiffToolPresentation).diffs;
      expect(diffs, hasLength(1));
      expect(diffs.single.path, 'a.txt');
      expect(diffs.single.oldText, isNull);
      expect(diffs.single.newText, 'hello\n');
      // The reference diff card is read-only: the domain type carries no
      // accept/reject member at all.
    });

    test('an empty diff list keeps the generic row', () {
      final reducer = TimelineReducer('s1')
        ..reset(<JsonMap>[
          toolCall(1, 'c1', 'write', <String, Object?>{'file_path': 'a.txt'}),
          toolResult(2, 'c1', <String, Object?>{'diffs': <Object?>[]}),
        ]);
      expect(onlyTool(reducer).presentation, isNull);
    });

    test('grep matches and glob paths narrow into search cards', () {
      final matchesReducer = TimelineReducer('s1')
        ..reset(<JsonMap>[
          toolCall(1, 'c1', 'grep', <String, Object?>{'pattern': 'x'}),
          toolResult(2, 'c1', <String, Object?>{
            'shape': 'matches',
            'files': <Object?>[
              <String, Object?>{
                'path': 'lib/a.dart',
                'matches': <Object?>[
                  <String, Object?>{'lineNumber': 4, 'line': 'x = 1'},
                ],
              },
            ],
            'truncated': false,
            'total': 1,
          }),
        ]);
      final matches =
          onlyTool(matchesReducer).presentation! as SearchToolPresentation;
      expect(matches.shape, SearchPresentationShape.matches);
      expect(matches.files.single.path, 'lib/a.dart');
      expect(matches.files.single.matches.single.lineNumber, 4);

      final pathsReducer = TimelineReducer('s1')
        ..reset(<JsonMap>[
          toolCall(1, 'c1', 'glob', <String, Object?>{'pattern': '**/*.ts'}),
          toolResult(2, 'c1', <String, Object?>{
            'shape': 'paths',
            'paths': <Object?>['a.ts', 'b.ts'],
            'truncated': true,
            'total': 9,
          }),
        ]);
      final paths =
          onlyTool(pathsReducer).presentation! as SearchToolPresentation;
      expect(paths.shape, SearchPresentationShape.paths);
      expect(paths.paths, <String>['a.ts', 'b.ts']);
      expect(paths.truncated, isTrue);
      expect(paths.total, 9);
    });

    test('web search sources and a fetch summary narrow into web cards', () {
      final searchReducer = TimelineReducer('s1')
        ..reset(<JsonMap>[
          toolCall(1, 'c1', 'web_search', <String, Object?>{'query': 'x'}),
          toolResult(2, 'c1', <String, Object?>{
            'sources': <Object?>[
              <String, Object?>{
                'url': 'https://example.test/a',
                'title': 'A',
                'snippet': 'snip',
                'publishedAt': '2026-01-01T00:00:00.000Z',
              },
            ],
            'truncated': false,
            'answer': 'yes',
          }),
        ]);
      final search =
          onlyTool(searchReducer).presentation! as WebToolPresentation;
      expect(search.kind, WebPresentationKind.search);
      expect(search.sources.single.url, 'https://example.test/a');
      expect(search.answer, 'yes');

      final fetchReducer = TimelineReducer('s1')
        ..reset(<JsonMap>[
          toolCall(1, 'c1', 'web_fetch', <String, Object?>{'url': 'u'}),
          toolResult(2, 'c1', <String, Object?>{
            'url': 'https://example.test/final',
            'statusCode': 200,
            'truncated': false,
          }),
        ]);
      final fetch = onlyTool(fetchReducer).presentation! as WebToolPresentation;
      expect(fetch.kind, WebPresentationKind.fetch);
      expect(fetch.url, 'https://example.test/final');
      expect(fetch.statusCode, 200);
    });

    test('a terminal viewport payload narrows into a terminal card', () {
      final reducer = TimelineReducer('s1')
        ..reset(<JsonMap>[
          toolCall(1, 'c1', 'terminal_send', <String, Object?>{
            'sessionId': 't1',
            'text': 'ls',
          }),
          toolResult(2, 'c1', <String, Object?>{
            'viewport': 'a.txt\n',
            'waitReason': 'timeout',
            'sessionStatus': <String, Object?>{'state': 'running'},
            'truncated': false,
          }),
        ]);
      final terminal =
          onlyTool(reducer).presentation! as TerminalToolPresentation;
      expect(terminal.viewport, 'a.txt\n');
      expect(terminal.waitReason, TerminalWaitReason.timeout);
      expect(terminal.sessionStatus, <String, Object?>{'state': 'running'});
    });

    test('a recognized diff card with a missing member throws', () {
      final reducer = TimelineReducer('s1');
      expect(
        () => reducer.reset(<JsonMap>[
          toolCall(1, 'c1', 'write', <String, Object?>{'file_path': 'a.txt'}),
          toolResult(2, 'c1', <String, Object?>{
            'diffs': <Object?>[
              <String, Object?>{'path': 'a.txt'},
            ],
          }),
        ]),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('newText'),
          ),
        ),
      );
    });

    test('an unrecognized meta payload keeps the generic row', () {
      final reducer = TimelineReducer('s1')
        ..reset(<JsonMap>[
          toolCall(1, 'c1', 'image_read', <String, Object?>{'path': 'a.png'}),
          toolResult(2, 'c1', <String, Object?>{'labelPath': '/tmp/a.png'}),
        ]);
      expect(onlyTool(reducer).presentation, isNull);
    });
  });

  group('hook/* audit pair (log-only)', () {
    test('invoked + result fold into one settled audit row', () {
      final reducer = TimelineReducer('s1')
        ..reset(<JsonMap>[
          event(1, 'hook/invoked', <String, Object?>{
            'turn': 1,
            'point': 'PreToolUse',
            'dialect': 'claude-code',
            'handlerId': 'h1',
            'matcher': 'Bash',
          }),
          event(2, 'hook/result', <String, Object?>{
            'turn': 1,
            'point': 'PreToolUse',
            'handlerId': 'h1',
            'decision': 'deny',
            'exitCode': 2,
            'stderrSummary': 'blocked by policy',
            'durationMs': 12,
          }),
        ]);
      final audit = reducer
          .snapshot()
          .whereType<TimelineHookAudit>()
          .single
          .audit;
      expect(audit.dialect, HookDialect.claudeCode);
      expect(audit.point, 'PreToolUse');
      expect(audit.matcher, 'Bash');
      expect(audit.decision, 'deny');
      expect(audit.exitCode, 2);
      expect(audit.stderrSummary, 'blocked by policy');
      expect(audit.durationMs, 12);
      expect(audit.settled, isTrue);
    });

    test('an invoked without a result keeps the audit pending', () {
      final reducer = TimelineReducer('s1')
        ..reset(<JsonMap>[
          event(1, 'hook/invoked', <String, Object?>{
            'turn': 1,
            'point': 'Stop',
            'dialect': 'codex',
            'handlerId': 'h2',
          }),
        ]);
      final audit = reducer
          .snapshot()
          .whereType<TimelineHookAudit>()
          .single
          .audit;
      expect(audit.settled, isFalse);
      expect(audit.decision, isNull);
      expect(audit.matcher, isNull);
    });

    test('hook/invoked without handlerId throws naming the field', () {
      final reducer = TimelineReducer('s1');
      expect(
        () => reducer.reset(<JsonMap>[
          event(1, 'hook/invoked', <String, Object?>{
            'turn': 1,
            'point': 'PreToolUse',
            'dialect': 'claude-code',
          }),
        ]),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('handlerId'),
          ),
        ),
      );
    });
  });

  group('sandbox/mode fact', () {
    test('the last switch is the session override', () {
      final reducer = TimelineReducer('s1')
        ..reset(<JsonMap>[
          event(1, 'sandbox/mode', <String, Object?>{'mode': 'read-only'}),
          event(2, 'sandbox/mode', <String, Object?>{
            'mode': 'workspace-write',
            'source': 'delegation',
          }),
        ]);
      expect(
        reducer.sandboxMode,
        const SandboxModeFact(
          mode: SandboxMode.workspaceWrite,
          seededByDelegation: true,
        ),
      );
      expect(reducer.factsRevision, greaterThan(0));
    });

    test('an unknown mode throws naming the field value', () {
      final reducer = TimelineReducer('s1');
      expect(
        () => reducer.reset(<JsonMap>[
          event(1, 'sandbox/mode', <String, Object?>{'mode': 'unbounded'}),
        ]),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('unbounded'),
          ),
        ),
      );
    });
  });

  group('schedule/change fact', () {
    test('create, one-shot dispatch and delete fold the active set', () {
      final reducer = TimelineReducer('s1')
        ..reset(<JsonMap>[
          event(1, 'schedule/change', <String, Object?>{
            'version': 1,
            'operation': 'create',
            'schedule': <String, Object?>{
              'id': 'r1',
              'kind': 'after',
              'prompt': 'check the build',
              'afterSeconds': 300,
              'scheduledAt': '2026-01-01T00:05:00.000Z',
            },
          }),
          event(2, 'schedule/change', <String, Object?>{
            'version': 1,
            'operation': 'create',
            'schedule': <String, Object?>{
              'id': 'r2',
              'kind': 'every',
              'prompt': 'hourly sweep',
              'everySeconds': 3600,
              'scheduledAt': '2026-01-01T00:00:00.000Z',
            },
          }),
        ]);
      expect(reducer.schedules, hasLength(2));
      expect(reducer.schedules.first.kind, ScheduleReminderKind.after);
      expect(reducer.schedules.first.afterSeconds, 300);

      reducer.ingestFrame(
        _frame(
          event(3, 'schedule/change', <String, Object?>{
            'version': 1,
            'operation': 'dispatch',
            'id': 'r1',
          }),
        ),
      );
      expect(reducer.schedules.map((item) => item.id), <String>['r2']);

      reducer.ingestFrame(
        _frame(
          event(4, 'schedule/change', <String, Object?>{
            'version': 1,
            'operation': 'delete',
            'id': 'r2',
          }),
        ),
      );
      expect(reducer.schedules, isEmpty);
    });

    test('a fixed-rate dispatch advances to the next aligned target', () {
      final reducer = TimelineReducer('s1')
        ..reset(<JsonMap>[
          event(1, 'schedule/change', <String, Object?>{
            'version': 1,
            'operation': 'create',
            'schedule': <String, Object?>{
              'id': 'r1',
              'kind': 'every',
              'prompt': 'hourly sweep',
              'everySeconds': 3600,
              'scheduledAt': '2026-01-01T00:00:00.000Z',
            },
          }),
          event(2, 'schedule/change', <String, Object?>{
            'version': 1,
            'operation': 'dispatch',
            'id': 'r1',
            'acceptedAt': '2026-01-01T02:30:00.000Z',
          }),
        ]);
      expect(reducer.schedules.single.scheduledAt, '2026-01-01T03:00:00.000Z');
    });

    test('a fixed-rate dispatch without acceptedAt fails loud', () {
      final reducer = TimelineReducer('s1');
      final create = event(1, 'schedule/change', <String, Object?>{
        'version': 1,
        'operation': 'create',
        'schedule': <String, Object?>{
          'id': 'r1',
          'kind': 'every',
          'prompt': 'sweep',
          'everySeconds': 3600,
          'scheduledAt': '2026-01-01T00:00:00.000Z',
        },
      });
      expect(
        () => reducer.reset(<JsonMap>[
          create,
          event(2, 'schedule/change', <String, Object?>{
            'version': 1,
            'operation': 'dispatch',
            'id': 'r1',
          }),
        ]),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('acceptedAt'),
          ),
        ),
      );
    });

    test('a one-shot dispatch carrying acceptedAt fails loud', () {
      final reducer = TimelineReducer('s1');
      expect(
        () => reducer.reset(<JsonMap>[
          event(1, 'schedule/change', <String, Object?>{
            'version': 1,
            'operation': 'create',
            'schedule': <String, Object?>{
              'id': 'r1',
              'kind': 'at',
              'prompt': 'once',
              'scheduledAt': '2026-01-01T00:00:00.000Z',
            },
          }),
          event(2, 'schedule/change', <String, Object?>{
            'version': 1,
            'operation': 'dispatch',
            'id': 'r1',
            'acceptedAt': '2026-01-01T00:00:00.000Z',
          }),
        ]),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('acceptedAt'),
          ),
        ),
      );
    });

    test('a change whose record predates the folded window is tolerated', () {
      // The reducer replays a history page, not the complete log: a dispatch
      // or delete for an id created before the page must neither throw nor
      // invent a reminder.
      final reducer = TimelineReducer('s1')
        ..reset(<JsonMap>[
          event(1, 'schedule/change', <String, Object?>{
            'version': 1,
            'operation': 'dispatch',
            'id': 'r-old',
          }),
          event(2, 'schedule/change', <String, Object?>{
            'version': 1,
            'operation': 'delete',
            'id': 'r-old',
          }),
        ]);
      expect(reducer.schedules, isEmpty);
    });

    test('a schedule/change with an unknown version throws', () {
      final reducer = TimelineReducer('s1');
      expect(
        () => reducer.reset(<JsonMap>[
          event(1, 'schedule/change', <String, Object?>{
            'version': 2,
            'operation': 'delete',
            'id': 'r1',
          }),
        ]),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('version'),
          ),
        ),
      );
    });
  });

  group('tool-workflow/* durable runs', () {
    test('the four events fold into one completed run with phases', () {
      final reducer = TimelineReducer('s1')
        ..reset(<JsonMap>[
          event(1, 'tool-workflow/run-start', <String, Object?>{
            'runId': 'run-1',
            'name': 'audit',
          }),
          event(2, 'tool-workflow/agent-start', <String, Object?>{
            'runId': 'run-1',
            'seq': 1,
            'label': 'scan a',
            'phase': 'scan',
            'childId': 's-a',
          }),
          event(3, 'tool-workflow/agent-start', <String, Object?>{
            'runId': 'run-1',
            'seq': 2,
            'label': 'scan b',
            'phase': 'scan',
            'childId': 's-b',
          }),
          event(4, 'tool-workflow/agent-start', <String, Object?>{
            'runId': 'run-1',
            'seq': 3,
            'label': 'verify',
            'childId': 's-c',
          }),
          event(5, 'tool-workflow/agent-end', <String, Object?>{
            'runId': 'run-1',
            'seq': 1,
            'outcome': 'completed',
          }),
          event(6, 'tool-workflow/run-end', <String, Object?>{
            'runId': 'run-1',
            'stopReason': 'completed',
          }),
        ]);
      final run = reducer.snapshot().whereType<TimelineWorkflowRun>().single;
      expect(run.runId, 'run-1');
      expect(run.name, 'audit');
      expect(run.status, WorkflowRunStatus.completed);
      expect(run.stopReason, 'completed');
      expect(run.phases, hasLength(2));
      expect(run.phases.first.phase, 'scan');
      expect(run.phases.first.members, hasLength(2));
      expect(
        run.phases.first.members.first.status,
        WorkflowRunStatus.completed,
      );
      expect(run.phases.first.members.last.status, WorkflowRunStatus.running);
      // The absent phase is a distinct identity from an empty string.
      expect(run.phases.last.key, 'missing');
      expect(run.phases.last.phase, isNull);
    });

    test('a history tail of updates stays pending until the start arrives', () {
      final reducer = TimelineReducer('s1')
        ..reset(<JsonMap>[
          event(1, 'tool-workflow/agent-start', <String, Object?>{
            'runId': 'run-2',
            'seq': 1,
            'label': 'late member',
            'childId': 's-a',
          }),
          event(2, 'tool-workflow/agent-end', <String, Object?>{
            'runId': 'run-2',
            'seq': 1,
            'outcome': 'failed',
          }),
          event(3, 'tool-workflow/run-end', <String, Object?>{
            'runId': 'run-2',
            'stopReason': 'error',
          }),
          event(4, 'tool-workflow/run-start', <String, Object?>{
            'runId': 'run-2',
            'name': 'recovered',
          }),
        ]);
      final run = reducer.snapshot().whereType<TimelineWorkflowRun>().single;
      expect(run.name, 'recovered');
      expect(run.status, WorkflowRunStatus.failed);
      expect(run.phases.single.members.single.status, WorkflowRunStatus.failed);
    });

    test('updates never seen a start publish no item', () {
      final reducer = TimelineReducer('s1')
        ..reset(<JsonMap>[
          event(1, 'tool-workflow/agent-start', <String, Object?>{
            'runId': 'run-3',
            'seq': 1,
            'label': 'orphan',
            'childId': 's-a',
          }),
        ]);
      expect(reducer.snapshot().whereType<TimelineWorkflowRun>(), isEmpty);
    });

    test('a closed turn with no terminal event interrupts the run', () {
      final reducer = TimelineReducer('s1')
        ..reset(<JsonMap>[
          event(1, 'turn/start', <String, Object?>{'turn': 1}),
          event(2, 'tool-workflow/run-start', <String, Object?>{
            'runId': 'run-4',
            'name': 'stalled',
          }),
          event(3, 'tool-workflow/agent-start', <String, Object?>{
            'runId': 'run-4',
            'seq': 1,
            'label': 'member',
            'childId': 's-a',
          }),
          toolCall(4, 'c1', 'workflow', <String, Object?>{'script': 'x'}),
          toolResult(5, 'c1', <String, Object?>{}),
          event(6, 'turn/end', <String, Object?>{
            'turn': 1,
            'reason': <String, Object?>{'kind': 'completed'},
          }),
        ]);
      final run = reducer.snapshot().whereType<TimelineWorkflowRun>().single;
      expect(run.status, WorkflowRunStatus.interrupted);
      expect(
        run.phases.single.members.single.status,
        WorkflowRunStatus.interrupted,
      );
      // The workflow tool's own result row is untouched by the projection.
      final tool = reducer.snapshot().whereType<TimelineToolCall>().single;
      expect(tool.status, ToolRunStatus.completed);
      expect(tool.isError, isFalse);
    });

    test('a run-end without stopReason throws naming the field', () {
      final reducer = TimelineReducer('s1');
      expect(
        () => reducer.reset(<JsonMap>[
          event(1, 'tool-workflow/run-start', <String, Object?>{
            'runId': 'run-5',
            'name': 'broken',
          }),
          event(2, 'tool-workflow/run-end', <String, Object?>{
            'runId': 'run-5',
          }),
        ]),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('stopReason'),
          ),
        ),
      );
    });
  });

  group('latency boundaries (never fabricated)', () {
    test('an assistant row carries its step start and first-token time', () {
      final reducer = TimelineReducer('s1')
        ..reset(<JsonMap>[
          event(1, 'step/start', <String, Object?>{'turn': 1, 'step': 1}),
          event(2, 'assistant/chunk', <String, Object?>{
            'turn': 1,
            'step': 1,
            'chunk': <String, Object?>{
              'type': 'text-delta',
              'index': 0,
              'text': 'hi',
            },
          }),
          event(3, 'assistant/message', <String, Object?>{
            'turn': 1,
            'step': 1,
            'message': <String, Object?>{
              'id': 'assistant-1',
              'role': 'assistant',
              'content': <Object?>[
                <String, Object?>{'type': 'text', 'text': 'hi'},
              ],
            },
          }),
        ]);
      final message = reducer.snapshot().whereType<TimelineMessage>().single;
      // `event()` stamps time = seq: step/start at 1, the first delta at 2.
      expect(message.stepStartedAtEpochMs, 1);
      expect(message.firstTokenAtEpochMs, 2);
      // The reference's TTFT reading (turn-metrics.ts `assistantStepReading`).
      expect(message.firstTokenAtEpochMs! - message.stepStartedAtEpochMs!, 1);
    });

    test('a step start outside the folded window leaves the figure null', () {
      final reducer = TimelineReducer('s1')
        ..reset(<JsonMap>[
          event(9, 'assistant/message', <String, Object?>{
            'turn': 1,
            'step': 1,
            'message': <String, Object?>{
              'id': 'assistant-1',
              'role': 'assistant',
              'content': <Object?>[
                <String, Object?>{'type': 'text', 'text': 'hi'},
              ],
            },
          }),
        ]);
      final message = reducer.snapshot().whereType<TimelineMessage>().single;
      expect(message.stepStartedAtEpochMs, isNull);
      expect(message.firstTokenAtEpochMs, isNull);
    });

    test('a turn boundary carries its start and end times', () {
      final reducer = TimelineReducer('s1')
        ..reset(<JsonMap>[
          event(10, 'turn/start', <String, Object?>{'turn': 1}),
          event(20, 'turn/end', <String, Object?>{
            'turn': 1,
            'reason': <String, Object?>{'kind': 'completed'},
          }),
        ]);
      final boundary = reducer
          .snapshot()
          .whereType<TimelineTurnBoundary>()
          .single;
      expect(boundary.startedAtEpochMs, 10);
      expect(boundary.endedAtEpochMs, 20);
      expect(boundary.usage, isNull);
    });

    test('an open turn keeps its end time null', () {
      final reducer = TimelineReducer('s1')
        ..reset(<JsonMap>[
          event(10, 'turn/start', <String, Object?>{'turn': 1}),
        ]);
      final boundary = reducer
          .snapshot()
          .whereType<TimelineTurnBoundary>()
          .single;
      expect(boundary.startedAtEpochMs, 10);
      expect(boundary.endedAtEpochMs, isNull);
    });
  });
}

ServerRequest _frame(JsonMap event) => ServerRequest(
  rpcId: 'rpc-${event['seq']}',
  method: 'session/event',
  payload: <String, Object?>{'type': 'session/event', 'event': event},
);
