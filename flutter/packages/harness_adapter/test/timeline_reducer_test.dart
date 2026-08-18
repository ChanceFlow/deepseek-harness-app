import 'package:domain/model/jobs.dart';
import 'package:domain/model/timeline_item.dart';
import 'package:domain/model/chat_message.dart';
import 'package:network/rpc_envelope.dart';
import 'package:test/test.dart';

import 'package:harness_adapter/src/rpc_map.dart';
import 'package:harness_adapter/src/timeline_reducer.dart';

JsonMap event(int seq, String type, JsonMap data) => <String, Object?>{
      'type': type,
      'seq': seq,
      'time': 1,
      'data': data,
    };

JsonMap textBlock(String text) => <String, Object?>{
      'type': 'text',
      'text': text,
    };

void main() {
  test('history finalizes live assistant text from chunks', () {
    final history = <JsonMap>[
      event(
        1,
        'assistant/chunk',
        <String, Object?>{
          'turn': 1,
          'step': 1,
          'chunk': <String, Object?>{
            'type': 'text-delta',
            'index': 0,
            'text': 'hello',
          },
        },
      ),
      event(
        2,
        'assistant/message',
        <String, Object?>{
          'turn': 1,
          'step': 1,
          'message': <String, Object?>{
            'id': 'assistant-1',
            'role': 'assistant',
            'content': <Object?>[textBlock('hello')],
          },
        },
      ),
    ];

    final reducer = TimelineReducer('s1');
    reducer.reset(history);

    final snapshot = reducer.snapshot();
    expect(snapshot, hasLength(1));
    final message = snapshot.single as TimelineMessage;
    expect(message.value.id, 'assistant-1');
    expect(message.value.role, MessageRole.assistant);
    expect(message.value.text, 'hello');
    expect(message.value.streaming, false);
  });

  test('tool call pairs with result', () {
    final history = <JsonMap>[
      event(
        1,
        'tool/call',
        <String, Object?>{
          'turn': 1,
          'step': 1,
          'callId': 'call-1',
          'name': 'bash',
          'arguments': '{}',
        },
      ),
      event(
        2,
        'tool/result',
        <String, Object?>{
          'turn': 1,
          'step': 1,
          'message': <String, Object?>{
            'content': <Object?>[
              <String, Object?>{
                'type': 'tool-result',
                'toolCallId': 'call-1',
                'content': <Object?>[textBlock('ok')],
              },
            ],
          },
        },
      ),
    ];

    final reducer = TimelineReducer('s1');
    reducer.reset(history);

    final tool = reducer.snapshot().single as TimelineToolCall;
    expect(tool.id, 'call-1');
    expect(tool.name, 'bash');
    expect(tool.status, ToolRunStatus.completed);
    expect(tool.result, 'ok');
  });

  test('tool result block isError marks the paired call failed', () {
    final history = <JsonMap>[
      event(
        1,
        'tool/call',
        <String, Object?>{
          'turn': 1,
          'step': 1,
          'callId': 'call-failed',
          'name': 'bash',
          'arguments': '{}',
        },
      ),
      event(
        2,
        'tool/result',
        <String, Object?>{
          'turn': 1,
          'step': 1,
          'message': <String, Object?>{
            'content': <Object?>[
              <String, Object?>{
                'type': 'tool-result',
                'toolCallId': 'call-failed',
                'content': <Object?>[textBlock('boom')],
                'isError': true,
              },
            ],
          },
        },
      ),
    ];

    final reducer = TimelineReducer('s1');
    reducer.reset(history);

    final tool = reducer.snapshot().single as TimelineToolCall;
    expect(tool.status, ToolRunStatus.failed);
    expect(tool.isError, true);
    expect(tool.result, 'boom');
  });

  test('approval frame becomes answerable card and resolved removes it', () {
    final reducer = TimelineReducer('s1');
    final requested = ServerRequest(
      rpcId: 'rpc-1',
      method: 'approval/requested',
      payload: <String, Object?>{
        'type': 'approval/requested',
        'sessionId': 's1',
        'approvalId': 'approval-1',
        'toolName': 'bash',
        'reason': 'run command',
      },
    );
    final resolved = ServerRequest(
      rpcId: 'rpc-2',
      method: 'approval/resolved',
      payload: <String, Object?>{
        'type': 'approval/resolved',
        'sessionId': 's1',
        'approvalId': 'approval-1',
        'outcome': 'allowed-once',
      },
    );

    reducer.ingestFrame(requested);
    final approval = reducer.snapshot().single as TimelineApprovalRequest;
    expect(approval.requestId, 'rpc-1');
    expect(approval.toolName, 'bash');

    reducer.ingestFrame(resolved);
    expect(reducer.snapshot(), isEmpty);
  });

  test('question intent parses for plan review presentation', () {
    final reducer = TimelineReducer('s1');
    reducer.ingestFrame(
      ServerRequest(
        rpcId: 'rpc-plan',
        method: 'question/requested',
        payload: <String, Object?>{
          'type': 'question/requested',
          'sessionId': 's1',
          'questions': <Object?>[
            <String, Object?>{
              'id': 'plan-review',
              'header': 'Plan review',
              'question': 'Approve this plan and leave plan mode?',
              'detail': '# The plan',
              'options': <Object?>[
                <String, Object?>{'label': 'Approve plan'},
                <String, Object?>{'label': 'Keep planning'},
              ],
              'intent': <String, Object?>{
                'kind': 'plan-review',
                'approve': 'Approve plan',
              },
            },
          ],
        },
      ),
    );

    final question =
        (reducer.snapshot().single as TimelineQuestionRequest).questions.single;
    expect(question.intent,
        const QuestionIntent(kind: 'plan-review', approve: 'Approve plan'));
    expect(question.detail, '# The plan');
  });

  test('question frame keeps header and option descriptions and resolution removes it', () {
    final reducer = TimelineReducer('s1');
    final requested = ServerRequest(
      rpcId: 'rpc-question',
      method: 'question/requested',
      payload: <String, Object?>{
        'type': 'question/requested',
        'sessionId': 's1',
        'questions': <Object?>[
          <String, Object?>{
            'id': 'q1',
            'header': 'Before continuing',
            'question': 'Proceed?',
            'detail': 'This command writes files',
            'multiSelect': true,
            'options': <Object?>[
              <String, Object?>{
                'label': 'yes',
                'description': 'Continue now',
              },
              <String, Object?>{'label': 'no'},
            ],
          },
        ],
      },
    );

    reducer.ingestFrame(requested);

    final question = reducer.snapshot().single as TimelineQuestionRequest;
    final item = question.questions.single;
    expect(item.id, 'q1');
    expect(item.header, 'Before continuing');
    expect(item.multiSelect, isTrue);
    expect(item.optionDescriptions['yes'], 'Continue now');
    expect(item.options, <String>['yes', 'no']);

    reducer.ingestFrame(
      ServerRequest(
        rpcId: 'rpc-resolved',
        method: 'question/resolved',
        payload: <String, Object?>{
          'type': 'question/resolved',
          'sessionId': 's1',
          'questionRpcId': 'rpc-question',
          'outcome': 'answered',
        },
      ),
    );
    expect(reducer.snapshot(), isEmpty);
  });

  test('session jobs frame becomes job snapshot', () {
    final reducer = TimelineReducer('s1');
    final frame = ServerRequest(
      rpcId: 'rpc-jobs',
      method: 'session/jobs',
      payload: <String, Object?>{
        'type': 'session/jobs',
        'sessionId': 's1',
        'jobs': <Object?>[
          <String, Object?>{
            'id': 'bash-1',
            'kind': 'bash',
            'label': 'sleep 10',
            'status': 'running',
            'startedAt': 10,
          },
        ],
      },
    );

    reducer.ingestFrame(frame);

    final jobs = reducer.snapshot().single as TimelineJobs;
    expect(jobs.jobs, hasLength(1));
    expect(jobs.jobs.single.id, 'bash-1');
    expect(jobs.jobs.single.status, JobStatus.running);
  });

  test('user message image blocks fold into attachment refs', () {
    final history = <JsonMap>[
      event(
        1,
        'user/message',
        <String, Object?>{
          'id': 'user-1',
          'content': <Object?>[
            textBlock('look at this'),
            <String, Object?>{
              'type': 'image',
              'attachment': <String, Object?>{
                'attachmentId': 'sha256:abc',
                'mediaType': 'image/png',
                'bytes': 2048,
                'width': 640,
                'height': 480,
                'name': 'shot.png',
              },
            },
          ],
        },
      ),
    ];

    final reducer = TimelineReducer('s1');
    reducer.reset(history);

    final message = (reducer.snapshot().single as TimelineMessage).value;
    expect(message.text, 'look at this');
    final image = message.images.single;
    expect(image.attachmentId, 'sha256:abc');
    expect(image.mediaType, 'image/png');
    expect(image.bytes, 2048);
    expect(image.width, 640);
    expect(image.height, 480);
    expect(image.name, 'shot.png');
  });

  test('turn start events become boundaries and dedupe per turn', () {
    final history = <JsonMap>[
      event(1, 'turn/start', <String, Object?>{'turn': 1}),
      event(
        2,
        'user/message',
        <String, Object?>{
          'id': 'user-1',
          'content': <Object?>[textBlock('hi')],
        },
      ),
      event(3, 'turn/start', <String, Object?>{'turn': 1}),
      event(4, 'turn/start', <String, Object?>{'turn': 2}),
      event(
        5,
        'user/message',
        <String, Object?>{
          'id': 'user-2',
          'content': <Object?>[textBlock('again')],
        },
      ),
    ];

    final reducer = TimelineReducer('s1');
    reducer.reset(history);

    final snapshot = reducer.snapshot();
    final turns =
        snapshot.whereType<TimelineTurnBoundary>().toList();
    expect(turns.map((turn) => turn.turn), <int>[1, 2]);
    expect(
      snapshot.indexWhere((item) =>
          item is TimelineTurnBoundary && item.turn == 1),
      0,
    );
    expect(
      snapshot.indexWhere((item) =>
          item is TimelineTurnBoundary && item.turn == 2),
      2,
    );
  });

  test('compaction summary folds into a shadowed-count marker', () {
    final history = <JsonMap>[
      event(
        1,
        'compaction/summary',
        <String, Object?>{
          'compactionId': 'c-1',
          'shadowedSeqs': <Object?>[1, 2, 3, 4],
        },
      ),
    ];

    final reducer = TimelineReducer('s1');
    reducer.reset(history);

    final marker = reducer.snapshot().single as TimelineCompaction;
    expect(marker.shadowedCount, 4);
  });
}
