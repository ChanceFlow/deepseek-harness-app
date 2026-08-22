/// States the design shots render. A fixture is the screen's own
/// `ChatUiState`, so a shot exercises the real widgets against the real
/// vocabulary — the only thing faked is the transport.
///
/// Write a fixture the way a bad day looks: a running turn, a wrapped
/// path, prose that overflows the viewport. A screen only fails where it
/// is crowded.
library;

import 'package:domain/model/chat_message.dart';
import 'package:domain/model/context_pressure.dart';
import 'package:domain/model/model_catalog.dart';
import 'package:domain/model/session.dart';
import 'package:domain/model/session_window_stats.dart';
import 'package:domain/model/timeline_item.dart';
import 'package:domain/model/todo.dart';

import 'package:app/ui/chat/chat_ui_state.dart';

/// Fixed clock so a re-render diffs on the design, not on the hour.
const int kNow = 1755000000000;

/// The bubble `message-menu` holds; naming it keeps the shot and the
/// fixture from drifting apart.
const String kBubbleUnderTest = 'cap the composer at four lines then';

const List<SessionSummary> kSessions = <SessionSummary>[
  SessionSummary(
    id: 's1',
    title: 'dock vertical budget',
    running: true,
    blank: false,
    updatedAtEpochMs: kNow,
    cwd: '/home/user/Projects/deepseek-harness-app',
  ),
  SessionSummary(
    id: 's2',
    title: 'wire parity for session/fork',
    blank: false,
    updatedAtEpochMs: kNow - 3600000,
    cwd: '/home/user/Projects/deepseek-harness-app',
  ),
  SessionSummary(
    id: 's3',
    title: 'telemetry sampling',
    blank: false,
    updatedAtEpochMs: kNow - 86400000,
    cwd: '/home/user/Projects/signoz-stack',
  ),
];

const List<TimelineItem> _conversation = <TimelineItem>[
  TimelineMessage(
    ChatMessage(
      id: 'm1',
      sessionId: 's1',
      role: MessageRole.user,
      text: 'the dock eats half the screen on my phone — can you look at '
          'chat_screen.dart and tell me what is taking the space?',
      createdAtEpochMs: kNow,
      seq: 11,
    ),
  ),
  TimelineMessage(
    ChatMessage(
      id: 'm2',
      sessionId: 's1',
      role: MessageRole.assistant,
      reasoning: 'The dock stacks four chrome strips above the composer. '
          'Measuring each one against the transcript budget.',
      text: 'Three things stack above the composer:\n\n'
          '1. `TodoPanel` — 3 rows, always mounted\n'
          '2. `GoalBarStrip` — one line, only when a goal exists\n'
          '3. `StatsLine` — turns / steps / tokens\n\n'
          'The composer itself grows to eight lines before it scrolls, so a '
          'long draft pushes the transcript off screen entirely.',
      createdAtEpochMs: kNow + 1000,
      seq: 12,
    ),
  ),
  TimelineToolCall(
    id: 't1',
    name: 'read',
    arguments: '{"path":"flutter/app/lib/ui/chat/chat_screen.dart"}',
    result: '4794 lines',
    status: ToolRunStatus.completed,
  ),
  TimelineToolCall(
    id: 't2',
    name: 'grep',
    arguments: '{"pattern":"maxLines","glob":"**/chat_screen.dart"}',
    result: '3 matches',
    status: ToolRunStatus.completed,
  ),
  TimelineMessage(
    ChatMessage(
      id: 'm3',
      sessionId: 's1',
      role: MessageRole.user,
      text: kBubbleUnderTest,
      createdAtEpochMs: kNow + 2000,
      seq: 21,
    ),
  ),
  TimelineMessage(
    ChatMessage(
      id: 'm4',
      sessionId: 's1',
      role: MessageRole.assistant,
      text: 'Done — `maxLines: 4`, and the field scrolls past that. The dock '
          'now tops out at 168px with the plan strip open.',
      createdAtEpochMs: kNow + 3000,
      seq: 22,
    ),
  ),
  TimelineToolCall(
    id: 't3',
    name: 'edit',
    arguments: '{"path":"flutter/app/lib/ui/chat/chat_screen.dart"}',
    status: ToolRunStatus.running,
  ),
];

/// A turn in flight: steps, a plan, stats, and a reply long enough to push
/// the transcript past the viewport.
ChatUiState busyState() {
  return const ChatUiState(
    sessions: kSessions,
    selectedSessionId: 's1',
    timeline: _conversation,
    todos: <TodoItem>[
      TodoItem(content: 'measure the dock', status: TodoStatus.completed),
      TodoItem(content: 'cap the composer', status: TodoStatus.inProgress),
      TodoItem(content: 'land the gate', status: TodoStatus.pending),
    ],
    sessionStats: SessionWindowStats(
      turns: 12,
      steps: 47,
      llmMs: 84000,
      toolMs: 12000,
      billedInputTokens: 128400,
      outputTokens: 9100,
      cacheReadTokens: 96000,
    ),
    contextPressure: ContextPressure(
      pressureTokens: 128400,
      contextWindow: 200000,
    ),
    models: SessionModels(
      current: ModelSelection(
        provider: 'deepseek',
        model: 'glm-x',
        reasoningEffort: 'high',
      ),
      routable: true,
      groups: <ModelProviderGroup>[
        ModelProviderGroup(
          id: 'deepseek',
          name: 'DeepSeek',
          models: <ModelCatalogModel>[
            ModelCatalogModel(id: 'glm-x', name: 'GLM X'),
          ],
        ),
      ],
    ),
  );
}

/// Every markdown block in one reply, wrapped near 80 columns the way an
/// agent writes it, with a CJK paragraph that must fold without a space.
const String _proseReply = '''
## What is taking the space

The dock stacks four strips above the composer. Measured on a 360dp
viewport, at rest, with one goal set:

1. `TodoPanel` — 3 rows, always mounted
2. `GoalBarStrip` — one line, only when a goal exists
3. `StatsLine` — turns / steps / tokens

Two of them are optional, so the honest number is a range. The composer
itself grows to eight lines before it scrolls, which is where the rest
of the transcript goes.

| Strip | Height | Optional |
|---|---|---|
| Plan | 48 | yes |
| Goal | 28 | yes |
| Stats | 22 | no |

### The fix

Cap the field and let the dock own one surface:

```dart
TextField(
  maxLines: 4,
  minLines: 1,
  decoration: const InputDecoration(border: InputBorder.none),
)
```

> A dock that grows without a ceiling is a scroll view wearing a
> composer's clothes.

See `flutter/app/lib/ui/chat/chat_screen.dart` and the note at
[docs/design-standard.md](https://example.com/design), which sets the
rule this follows.

**下一步**:先把输入区封顶,再看待办条能不能折起来 —— 两处都在
`_InputDock` 里,改完一起量。
''';

ChatUiState proseState() {
  return const ChatUiState(
    sessions: kSessions,
    selectedSessionId: 's1',
    timeline: <TimelineItem>[
      TimelineMessage(
        ChatMessage(
          id: 'p1',
          sessionId: 's1',
          role: MessageRole.user,
          text: 'the dock eats half the screen — what is taking the space?',
          createdAtEpochMs: kNow,
          seq: 31,
        ),
      ),
      TimelineMessage(
        ChatMessage(
          id: 'p2',
          sessionId: 's1',
          role: MessageRole.assistant,
          text: _proseReply,
          createdAtEpochMs: kNow + 1000,
          seq: 32,
        ),
      ),
    ],
  );
}

/// The head of a reply: heading, both list kinds, and a source-wrapped
/// item that has to hang under its own text.
const String _proseLists = '''
## What is taking the space

The dock stacks four strips above the composer. Measured on a 360dp
viewport, at rest, with one goal set:

1. `TodoPanel` — three rows, always mounted, even when the plan is empty
2. `GoalBarStrip` — one line, only when a goal exists
3. `StatsLine` — turns / steps / tokens

- the composer grows to eight lines before it scrolls
- a long draft pushes the transcript off screen entirely
  and the reader loses the answer they asked for

Two of them are optional, so the honest number is a range.
''';

ChatUiState proseListsState() {
  return const ChatUiState(
    sessions: kSessions,
    selectedSessionId: 's1',
    timeline: <TimelineItem>[
      TimelineMessage(
        ChatMessage(
          id: 'l1',
          sessionId: 's1',
          role: MessageRole.assistant,
          text: _proseLists,
          createdAtEpochMs: kNow,
          seq: 41,
        ),
      ),
    ],
  );
}

/// A session with nothing in it yet — the first screen a reader meets.
ChatUiState emptyState() {
  return const ChatUiState(
    sessions: <SessionSummary>[
      SessionSummary(
        id: 's9',
        title: '',
        blank: true,
        cwd: '/home/user/Projects/deepseek-harness-app',
      ),
    ],
    selectedSessionId: 's9',
  );
}
