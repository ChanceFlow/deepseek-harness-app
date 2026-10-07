/// Fixture tests for the trajectory decoders: provider token accounting
/// (`TokenUsage`) and the recorded assistant stream's first-token
/// timestamp.
///
/// Payload shapes are transcribed from the pinned submodule:
/// `packages/llm/llm/src/types.ts` (`TokenUsage`, disjoint cache buckets) and
/// `packages/llm/llm/src/assistant-stream.ts` (`AssistantStreamRecord`'s
/// packed `text-chunks` runs, raw `chunk` records, and the
/// `assistantStreamFirstTokenTime` walk order), plus the background-job
/// vocabulary of `packages/api/job-controller/src/types.ts`
/// (`JobFollowFrame`) and `packages/jobs/jobs/src/view.ts` (`JobView`,
/// `JobChunk`).
library;

import 'package:domain/model/agent_team.dart';
import 'package:domain/model/jobs.dart';
import 'package:domain/model/plugin_management.dart';
import 'package:domain/model/schedule.dart';
import 'package:domain/model/terminal.dart';
import 'package:domain/model/token_usage.dart';
import 'package:test/test.dart';

import 'package:harness_adapter/src/dsh_wire_types.dart';

void main() {
  group('decodeTokenUsage', () {
    test('decodes a provider usage object with disjoint cache buckets', () {
      // reference `assistant/message.data.usage` (TokenUsage): the required
      // prompt/completion counts plus the optional cache and reasoning split.
      final usage = decodeTokenUsage(<String, Object?>{
        'inputTokens': 1200,
        'outputTokens': 340,
        'totalTokens': 1710,
        'cacheReadTokens': 150,
        'cacheWriteTokens': 20,
        'reasoningTokens': 90,
      });

      expect(usage, isNotNull);
      expect(usage!.inputTokens, 1200);
      expect(usage.outputTokens, 340);
      expect(usage.totalTokens, 1710);
      expect(usage.cacheReadTokens, 150);
      expect(usage.cacheWriteTokens, 20);
      expect(usage.reasoningTokens, 90);
      // Billed input is the disjoint sum, never a cached-inclusive total.
      expect(usage.billedInputTokens, 1370);
    });

    test('keeps an unreported optional bucket null instead of zero', () {
      final usage = decodeTokenUsage(<String, Object?>{
        'inputTokens': 10,
        'outputTokens': 2,
      });

      expect(usage!.cacheReadTokens, isNull);
      expect(usage.cacheWriteTokens, isNull);
      expect(usage.reasoningTokens, isNull);
      expect(usage.totalTokens, isNull);
      expect(usage.billedInputTokens, 10);
    });

    test('an absent usage member is null, a malformed one fails loud', () {
      // `usage` is optional on the event: absent means the adapter reported
      // no accounting, which the ledger renders as unavailable.
      expect(decodeTokenUsage(null), isNull);
      expect(
        () => decodeTokenUsage('nope'),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('usage'),
          ),
        ),
      );
      // `inputTokens`/`outputTokens` are required on the reference record.
      expect(
        () => decodeTokenUsage(<String, Object?>{'outputTokens': 3}),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('inputTokens'),
          ),
        ),
      );
    });
  });

  group('assistantStreamFirstTokenTime', () {
    test('reconstructs the first member time of a packed run across gaps', () {
      // Records exactly as `AssistantStreamAccumulator.snapshot` emits them:
      // the run starts at time0 and each member sits one `dt` later.
      final time = assistantStreamFirstTokenTime(<Object?>[
        <String, Object?>{
          'type': 'text-chunks',
          'time0': 1000,
          'index': 0,
          'dt': <Object?>[30, 45],
          'texts': <Object?>['first', ' second', ' third'],
        },
      ]);

      // The first non-empty member is at time0; a later member would add dt.
      expect(time, 1000);
    });

    test('skips empty fragments and accumulates their gaps', () {
      final time = assistantStreamFirstTokenTime(<Object?>[
        <String, Object?>{
          'type': 'reasoning-chunks',
          'time0': 5000,
          'index': 0,
          'dt': <Object?>[12, 8, 4],
          'texts': <Object?>['', '', 'token'],
        },
      ]);

      // '' at 5000, '' at 5012, 'token' at 5020.
      expect(time, 5020);
    });

    test('a name-bearing tool-call run starts at its first member', () {
      final time = assistantStreamFirstTokenTime(<Object?>[
        <String, Object?>{
          'type': 'tool-call-chunks',
          'time0': 700,
          'index': 0,
          'dt': <Object?>[],
          'id': 'call-1',
          'name': 'bash',
          'args': <Object?>[''],
        },
      ]);

      expect(time, 700);
    });

    test(
      'raw records keep their own timestamp and take precedence in order',
      () {
        final time = assistantStreamFirstTokenTime(<Object?>[
          <String, Object?>{
            'type': 'chunk',
            'time': 100,
            'chunk': <String, Object?>{
              'type': 'block-start',
              'blockType': 'text',
            },
          },
          <String, Object?>{
            'type': 'chunk',
            'time': 250,
            'chunk': <String, Object?>{'type': 'text-delta', 'text': 'hi'},
          },
        ]);

        expect(time, 250);
      },
    );

    test('a stream with no token delta reports no first token', () {
      expect(
        assistantStreamFirstTokenTime(<Object?>[
          <String, Object?>{
            'type': 'chunk',
            'time': 10,
            'chunk': <String, Object?>{'type': 'finish', 'reason': 'stop'},
          },
        ]),
        isNull,
      );
      expect(assistantStreamFirstTokenTime(null), isNull);
      expect(assistantStreamFirstTokenTime(const <Object?>[]), isNull);
    });

    test('a malformed run is skipped rather than failing session replay', () {
      // A run whose gaps cannot reconstruct the member time carries no
      // usable boundary; the walk continues to the next record.
      final time = assistantStreamFirstTokenTime(<Object?>[
        <String, Object?>{
          'type': 'text-chunks',
          'time0': 1,
          'index': 0,
          'dt': <Object?>['not-a-number'],
          'texts': <Object?>['a', 'b'],
        },
        <String, Object?>{
          'type': 'chunk',
          'time': 42,
          'chunk': <String, Object?>{'type': 'text-delta', 'text': 'z'},
        },
      ]);

      expect(time, 42);
    });
  });

  group('TokenUsage', () {
    test('equality covers every optional bucket', () {
      const base = TokenUsage(inputTokens: 1, outputTokens: 2);
      expect(base, const TokenUsage(inputTokens: 1, outputTokens: 2));
      expect(
        base,
        isNot(
          const TokenUsage(inputTokens: 1, outputTokens: 2, cacheReadTokens: 3),
        ),
      );
    });
  });

  group('terminal decoders', () {
    // Payload shapes transcribed from
    // `packages/api/terminal-controller/src/types.ts`.
    Map<String, Object?> info({String state = 'running', int? exitCode}) =>
        <String, Object?>{
          'id': 'term-1',
          'title': 'bash',
          'shell': <String, Object?>{
            'path': '/bin/bash',
            'name': 'bash',
            'args': <Object?>['-i'],
          },
          'cwd': '/home/tester/project',
          'cols': 80,
          'rows': 24,
          'state': state,
          'exitCode': exitCode,
        };

    test('a running terminal keeps its absent exit code null', () {
      final decoded = decodeTerminalInfo(info());

      expect(decoded.state, TerminalState.running);
      expect(decoded.isRunning, isTrue);
      // Null is "still running", which is not exit code zero.
      expect(decoded.exitCode, isNull);
      expect(decoded.shell.args, <String>['-i']);
      expect(decoded.controllerId, isNull);
    });

    test('an exited terminal carries its code and no controller', () {
      final decoded = decodeTerminalInfo(info(state: 'exited', exitCode: 0));

      expect(decoded.state, TerminalState.exited);
      expect(decoded.isRunning, isFalse);
      expect(decoded.exitCode, 0);
    });

    test('an unknown process state throws naming it', () {
      expect(
        () => decodeTerminalInfo(info(state: 'restarting')),
        throwsA(
          isA<FormatException>().having(
            (FormatException error) => error.message,
            'message',
            contains('restarting'),
          ),
        ),
      );
    });

    test('a snapshot anchors the generation and carries the screen', () {
      final frame = decodeTerminalFrame(<String, Object?>{
        'type': 'snapshot',
        'sequence': 42,
        'screen': 'ready\r\n\$ ',
        'info': info(),
      }) as TerminalSnapshot;

      expect(frame.sequence, 42);
      expect(frame.screen, contains('ready'));
      expect(frame.info.id, 'term-1');
    });

    test('output and state frames decode without a screen', () {
      final output = decodeTerminalFrame(<String, Object?>{
        'type': 'output',
        'sequence': 43,
        'data': 'ls\r\n',
      }) as TerminalOutput;
      expect(output.sequence, 43);
      expect(output.data, 'ls\r\n');

      final state = decodeTerminalFrame(<String, Object?>{
        'type': 'state',
        'info': info(state: 'failed'),
      }) as TerminalStateChange;
      expect(state.info.state, TerminalState.failed);
    });

    test('an unknown frame type throws naming it', () {
      expect(
        () => decodeTerminalFrame(<String, Object?>{'type': 'resize'}),
        throwsA(
          isA<FormatException>().having(
            (FormatException error) => error.message,
            'message',
            contains('resize'),
          ),
        ),
      );
    });

    test('an environment names its working directory and every limit', () {
      final environment = decodeTerminalEnvironment(<String, Object?>{
        'cwd': '/home/tester/project',
        'maxInputBytes': 65536,
        'maxCols': 500,
        'maxRows': 200,
        'scrollback': 1000,
      });

      expect(environment.cwd, '/home/tester/project');
      expect(environment.maxInputBytes, 65536);
      expect(environment.scrollback, 1000);
    });

    test('a shell without its name fails loud', () {
      expect(
        () => decodeTerminalShell(<String, Object?>{'path': '/bin/bash'}),
        throwsA(
          isA<FormatException>().having(
            (FormatException error) => error.message,
            'message',
            contains('name'),
          ),
        ),
      );
    });
  });

  group('schedule decoders', () {
    // Payload shapes transcribed from
    // `packages/schedule/schedule/src/types.ts`.
    test('each rule kind carries exactly its own required fields', () {
      final after = decodeScheduleRecordWire(<String, Object?>{
        'id': 'schedule-1',
        'kind': 'after',
        'title': 'Later',
        'prompt': 'remind me',
        'scheduledAt': '2026-09-30T09:00:00.000Z',
        'afterSeconds': 600,
      });
      expect(after.kind, ScheduleKind.after);
      expect(after.afterSeconds, 600);
      expect(after.isRecurring, isFalse);
      expect(after.timeZone, isNull);

      final daily = decodeScheduleRecordWire(<String, Object?>{
        'id': 'schedule-2',
        'kind': 'daily',
        'title': 'Daily',
        'prompt': 'stand up',
        'scheduledAt': '2026-09-30T01:00:00.000Z',
        'time': '09:00:00.000',
        'timeZone': 'Asia/Shanghai',
      });
      expect(daily.kind, ScheduleKind.daily);
      expect(daily.time, '09:00:00.000');
      expect(daily.isRecurring, isTrue);

      final weekly = decodeScheduleRecordWire(<String, Object?>{
        'id': 'schedule-3',
        'kind': 'weekly',
        'title': 'Weekly',
        'prompt': 'review',
        'scheduledAt': '2026-09-30T01:00:00.000Z',
        'time': '09:00:00.000',
        'timeZone': 'UTC',
        'weekdays': <Object?>[1, 5],
      });
      expect(weekly.weekdays, <int>[1, 5]);

      final cron = decodeScheduleRecordWire(<String, Object?>{
        'id': 'schedule-4',
        'kind': 'cron',
        'title': 'Nightly',
        'prompt': 'smoke',
        'scheduledAt': '2026-09-30T18:00:00.000Z',
        'expression': '0 2 * * *',
        'timeZone': 'UTC',
      });
      expect(cron.expression, '0 2 * * *');
    });

    test('a weekly record without its weekdays fails loud', () {
      expect(
        () => decodeScheduleRecordWire(<String, Object?>{
          'id': 'schedule-3',
          'kind': 'weekly',
          'title': 'Weekly',
          'prompt': 'review',
          'scheduledAt': '2026-09-30T01:00:00.000Z',
          'time': '09:00:00.000',
          'timeZone': 'UTC',
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('an unknown rule kind throws naming the value', () {
      expect(
        () => decodeScheduleRecordWire(<String, Object?>{
          'id': 'schedule-9',
          'kind': 'hourly',
          'title': 'x',
          'prompt': 'y',
          'scheduledAt': '2026-09-30T01:00:00.000Z',
        }),
        throwsA(
          isA<FormatException>().having(
            (FormatException error) => error.message,
            'message',
            contains('hourly'),
          ),
        ),
      );
    });

    test('the update snapshot drops the catalog binding', () {
      const record = ScheduleRecord(
        id: 'schedule-1',
        kind: ScheduleKind.every,
        title: 'Poll',
        prompt: 'check',
        scheduledAt: '2026-09-30T09:00:00.000Z',
        everySeconds: 900,
      );

      final snapshot = encodeScheduleRecordSnapshot(record);
      expect(snapshot['kind'], 'every');
      expect(snapshot['everySeconds'], 900);
      expect(snapshot.containsKey('sessionId'), isFalse);
      expect(snapshot.containsKey('status'), isFalse);
      expect(snapshot.containsKey('lastDelivery'), isFalse);
    });

    test('a timing change encodes its snake_case input record', () {
      expect(
        encodeScheduleTimingChange(
          const ScheduleCronChange(expression: '*/5 * * * *', timeZone: 'UTC'),
        ),
        <String, Object?>{
          'kind': 'cron',
          'cron': <String, Object?>{
            'expression': '*/5 * * * *',
            'time_zone': 'UTC',
          },
        },
      );
      expect(
        encodeScheduleTimingChange(
          const ScheduleAtChange(at: '2030-01-01T00:00:00Z'),
        ),
        <String, Object?>{'kind': 'at', 'at': '2030-01-01T00:00:00Z'},
      );
    });
  });

  group('plugin management decoders', () {
    // Payload shapes transcribed from
    // `packages/boot/plugin-manager/src/types.ts`.
    test('a ChangeResult folds refusals into the value', () {
      final result = decodePluginChangeResult(<String, Object?>{
        'changed': false,
        'application': 'failed',
        'stage': 'install',
        'target': '@deepseek-ai/dsh-schedule@1.0.0',
        'error': <String, Object?>{
          'code': 'incompatible-version',
          'diagnostic': 'the running harness rejects this peer range',
          'incompatible': <Object?>[
            <String, Object?>{
              'name': '@deepseek-ai/dsh-schedule',
              'version': '1.0.0',
              'runtimeVersion': '0.1.7-rc.2',
              'peers': <String, Object?>{'@deepseek-ai/dsh-core': '^2.0.0'},
            },
          ],
        },
        'packageResult': <String, Object?>{
          'exitCode': 1,
          'output': 'ERR_PNPM_NO_MATCHING_VERSION',
          'truncated': false,
          'logPath': '/tmp/pnpm.log',
          'kind': 'no-matching-version',
          'timedOut': false,
        },
        'pendingBuilds': <Object?>['esbuild'],
        'failedAt': 'spec-host',
      });

      expect(result.changed, isFalse);
      expect(result.application, PluginChangeApplication.failed);
      expect(result.stage, PluginChangeStage.install);
      expect(result.error?.code, PluginManagementErrorCode.incompatibleVersion);
      final incompatible = result.error!.incompatible.single;
      expect(incompatible.name, '@deepseek-ai/dsh-schedule');
      expect(incompatible.peers['@deepseek-ai/dsh-core'], '^2.0.0');
      expect(
        result.packageResult?.kind,
        PluginInstallFailureKind.noMatchingVersion,
      );
      expect(result.packageResult?.exitCode, 1);
      expect(result.pendingBuilds, <String>['esbuild']);
      expect(result.failedAt, 'spec-host');
      expect(result.needsRestart, isFalse);
    });

    test('an inspection refusal carries its problem and registries', () {
      final refused = decodePluginSpecInspection(<String, Object?>{
        'status': 'refused',
        'problem': 'already-installed',
        'reason': 'this package is already in the profile',
      }) as PluginSpecRefused;

      expect(refused.problem, PluginInspectProblem.alreadyInstalled);
      expect(refused.registries, isEmpty);
    });

    test('an accepted inspection keeps an unknown bundle-ness null', () {
      final accepted = decodePluginSpecInspection(<String, Object?>{
        'status': 'accepted',
        'kind': 'git',
        'bundle': null,
        'registry': null,
        'host': 'github.com',
      }) as PluginSpecAccepted;

      expect(accepted.kind, PluginSpecKind.git);
      // Null is "not yet knowable", which is not the same as false.
      expect(accepted.bundle, isNull);
      expect(accepted.registry, isNull);
      expect(accepted.host, 'github.com');
    });

    test('a bundle roster row decodes its localized meta and rows', () {
      final bundle = decodePluginBundle(<String, Object?>{
        'name': 'dsh-schedule',
        'enabled': true,
        'installed': true,
        'optional': false,
        'removable': true,
        'meta': <String, Object?>{
          'title': <String, Object?>{'zh': '定时任务'},
          'description': 'Reminders',
        },
        'rows': <Object?>[
          <String, Object?>{'rowId': 'core', 'moduleName': 'core'},
        ],
      });

      // A host that ships only a non-English title still renders.
      expect(bundle.title?.resolve('zh'), '定时任务');
      expect(bundle.title?.resolve('en'), '定时任务');
      expect(bundle.metaDescription?.resolve('en'), 'Reminders');
      expect(bundle.rows.single.rowId, 'core');
      expect(bundle.rows.single.entryId, isNull);
    });

    test('a bundle row without its required shape fails loud', () {
      expect(
        () => decodePluginBundle(<String, Object?>{
          'name': 'dsh-schedule',
          'enabled': true,
        }),
        throwsA(
          isA<FormatException>().having(
            (FormatException error) => error.message,
            'message',
            contains('installed'),
          ),
        ),
      );
    });

    test('install progress decodes its attempt position', () {
      final progress = decodePluginInstallProgress(<String, Object?>{
        'requestId': 'req-1',
        'phase': 'installing',
        'attempt': <String, Object?>{
          'registry': 'https://registry.npmjs.org/',
          'index': 2,
          'total': 3,
        },
      });

      expect(progress.phase, PluginInstallPhase.installing);
      expect(progress.registry, 'https://registry.npmjs.org/');
      expect(progress.attemptIndex, 2);
      expect(progress.attemptTotal, 3);
    });

    test('an unknown install phase throws naming the value', () {
      expect(
        () => decodePluginInstallProgress(<String, Object?>{
          'requestId': 'req-1',
          'phase': 'downloading',
        }),
        throwsA(
          isA<FormatException>().having(
            (FormatException error) => error.message,
            'message',
            contains('downloading'),
          ),
        ),
      );
    });

    test('an install log chunk separates stderr from stdout', () {
      final chunk = decodePluginInstallLogChunk(<String, Object?>{
        'jobId': 'bash-1',
        'argv': <Object?>['pnpm', 'add', 'x'],
        'cwd': '/tmp',
        'stream': 'stderr',
        'text': 'ERR!',
        'exitCode': 1,
      });

      expect(chunk.isStderr, isTrue);
      expect(chunk.exitCode, 1);
      expect(chunk.requestId, isNull);
    });
  });

  group('decodeAgentTeamProjection', () {
    // Payload shapes transcribed from
    // `packages/experimental/agent-team/src/types.ts` (`TeamProjection`,
    // `TeamMemberProjection`, `TeamTaskView`).
    test('decodes the synthesized Lead row, teammates, and the board', () {
      final team = decodeAgentTeamProjection(<String, Object?>{
        'members': <Object?>[
          <String, Object?>{
            'id': 'lead-session',
            'name': 'lead',
            'role': 'lead',
            'phase': 'active',
          },
          <String, Object?>{
            'id': 'child-1',
            'name': 'reviewer',
            'role': 'teammate',
            'phase': 'failed',
            'error': 'spawn exited',
          },
        ],
        'tasks': <Object?>[
          <String, Object?>{
            'id': 'task-1',
            'revision': 3,
            'subject': 'Audit the diff',
            'description': 'Read every hunk',
            'status': 'in_progress',
            'blockedBy': <Object?>['task-0'],
            'writeScopes': <Object?>['flutter/app'],
            'ownerName': 'reviewer',
            'ready': false,
            'writeScopeWarnings': <Object?>['write scopes overlap with task-2'],
          },
        ],
      });

      expect(team.members, hasLength(2));
      expect(team.members.first.isLead, isTrue);
      expect(team.members.first.phase, TeamMemberPhase.active);
      expect(team.members.last.name, 'reviewer');
      expect(team.members.last.error, 'spawn exited');
      expect(
        team.members.last.activity(running: true),
        TeamMemberActivity.failed,
        reason: 'a failed member keeps its durable phase over live running',
      );
      final task = team.tasks.single;
      expect(task.revision, 3);
      expect(task.status, TeamTaskStatus.inProgress);
      expect(task.blockedBy, <String>['task-0']);
      expect(task.writeScopes, <String>['flutter/app']);
      expect(task.ownerName, 'reviewer');
      expect(task.writeScopeWarnings, <String>[
        'write scopes overlap with task-2',
      ]);
      expect(team.failure, isNull);
    });

    test('an active member reads its activity from the live running bit', () {
      final team = decodeAgentTeamProjection(<String, Object?>{
        'members': <Object?>[
          <String, Object?>{
            'id': 'child-1',
            'name': 'reviewer',
            'role': 'teammate',
            'phase': 'active',
          },
        ],
        'tasks': <Object?>[],
      });

      final member = team.members.single;
      expect(member.activity(running: true), TeamMemberActivity.running);
      expect(member.activity(running: false), TeamMemberActivity.inactive);
      // A Session the roster does not know reads inactive, never running.
      expect(member.activity(running: null), TeamMemberActivity.inactive);
    });

    test('a ready pending task is the only one labelled ready', () {
      final team = decodeAgentTeamProjection(<String, Object?>{
        'members': <Object?>[],
        'tasks': <Object?>[
          <String, Object?>{
            'id': 'task-1',
            'revision': 1,
            'subject': 'Ready',
            'description': '',
            'status': 'pending',
            'ready': true,
          },
          <String, Object?>{
            'id': 'task-2',
            'revision': 1,
            'subject': 'Blocked',
            'description': '',
            'status': 'pending',
            'ready': false,
          },
          <String, Object?>{
            'id': 'task-3',
            'revision': 1,
            'subject': 'Done',
            'description': '',
            'status': 'completed',
            'ready': true,
          },
        ],
        'failure': 'invalid persisted team record',
      });

      expect(team.tasks[0].isReady, isTrue);
      expect(team.tasks[1].isReady, isFalse);
      expect(
        team.tasks[2].isReady,
        isFalse,
        reason: 'readiness is a pending-only label',
      );
      expect(team.failure, 'invalid persisted team record');
    });

    test('a member with an unknown phase fails loud naming the value', () {
      expect(
        () => decodeAgentTeamProjection(<String, Object?>{
          'members': <Object?>[
            <String, Object?>{
              'id': 'child-1',
              'name': 'reviewer',
              'role': 'teammate',
              'phase': 'sleeping',
            },
          ],
          'tasks': <Object?>[],
        }),
        throwsA(
          isA<FormatException>().having(
            (FormatException error) => error.message,
            'message',
            contains('sleeping'),
          ),
        ),
      );
    });

    test('a projection without members fails loud naming the field', () {
      expect(
        () =>
            decodeAgentTeamProjection(<String, Object?>{'tasks': <Object?>[]}),
        throwsA(
          isA<FormatException>().having(
            (FormatException error) => error.message,
            'message',
            contains('members'),
          ),
        ),
      );
    });
  });

  group('decodeJobFollowFrame', () {
    // Payload shapes transcribed from
    // `packages/api/job-controller/src/types.ts` (`JobFollowFrame`) and
    // `packages/jobs/jobs/src/view.ts` (`JobView`, `JobChunk`).
    Map<String, Object?> jobRow({
      String status = 'running',
      int total = 12,
      int earliest = 0,
      String? detail,
    }) => <String, Object?>{
      'id': 'bash-1',
      'kind': 'bash',
      'label': 'pnpm test',
      'owner': 'session-j',
      'progress': '3/10',
      'status': status,
      'startedAt': 5,
      if (detail != null) 'detail': detail,
      'output': <String, Object?>{
        'total': total,
        'earliest': earliest,
        'spillPaths': <Object?>['/tmp/spill.log'],
      },
    };

    test('decodes the opened anchor and its job row', () {
      final frame = decodeJobFollowFrame(<String, Object?>{
        'type': 'opened',
        'from': 4,
        'job': jobRow(earliest: 4),
      });

      final opened = frame as JobOutputOpened;
      expect(opened.from, 4);
      expect(opened.job.owner, 'session-j');
      expect(opened.job.progress, '3/10');
      expect(opened.job.output?.total, 12);
      expect(opened.job.output?.earliest, 4);
      expect(opened.job.output?.spillPaths, <String>['/tmp/spill.log']);
    });

    test('decodes an output frame with channels, gap flag, and next', () {
      final frame = decodeJobFollowFrame(<String, Object?>{
        'type': 'output',
        'next': 22,
        'lossy': true,
        'chunks': <Object?>[
          <String, Object?>{'at': 0, 'text': 'building\n', 'channel': 'stdout'},
          <String, Object?>{
            'at': 9,
            'text': 'oops\n',
            'channel': 'stderr',
            'gapBefore': true,
          },
          <String, Object?>{'at': 14, 'text': 'plain\n'},
        ],
      });

      final chunks = frame as JobOutputChunks;
      expect(chunks.lossy, isTrue);
      expect(chunks.next, 22);
      expect(chunks.chunks, hasLength(3));
      expect(chunks.chunks.first.channel, JobChannel.stdout);
      expect(chunks.chunks[1].channel, JobChannel.stderr);
      expect(chunks.chunks[1].gapBefore, isTrue);
      // A producer that supplies no channel leaves it absent.
      expect(chunks.chunks.last.channel, isNull);
      expect(chunks.chunks.last.gapBefore, isFalse);
    });

    test('decodes the terminal status frame', () {
      final frame = decodeJobFollowFrame(<String, Object?>{
        'type': 'status',
        'job': jobRow(status: 'killed', detail: 'cancelled by the user'),
      });

      final status = frame as JobOutputStatus;
      expect(status.job.status, JobStatus.killed);
      expect(status.job.detail, 'cancelled by the user');
    });

    test('an unknown frame type throws naming the value', () {
      expect(
        () => decodeJobFollowFrame(<String, Object?>{'type': 'chunk'}),
        throwsA(
          isA<FormatException>().having(
            (FormatException error) => error.message,
            'message',
            contains('chunk'),
          ),
        ),
      );
    });

    test('an output frame without next fails loud naming the field', () {
      expect(
        () => decodeJobFollowFrame(<String, Object?>{
          'type': 'output',
          'chunks': <Object?>[
            <String, Object?>{'at': 0, 'text': 'x'},
          ],
        }),
        throwsA(
          isA<FormatException>().having(
            (FormatException error) => error.message,
            'message',
            contains('next'),
          ),
        ),
      );
    });

    test('a job row without a required field fails loud naming it', () {
      expect(
        () => decodeJobFollowFrame(<String, Object?>{
          'type': 'status',
          'job': <String, Object?>{'id': 'bash-1', 'kind': 'bash'},
        }),
        throwsA(
          isA<FormatException>().having(
            (FormatException error) => error.message,
            'message',
            contains('label'),
          ),
        ),
      );
    });
  });
}
