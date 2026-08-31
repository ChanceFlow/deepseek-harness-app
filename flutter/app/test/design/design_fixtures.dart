/// States the design shots render. A fixture is the screen's own
/// `ChatUiState`, so a shot exercises the real widgets against the real
/// vocabulary — the only thing faked is the transport.
///
/// Write a fixture the way a bad day looks: a running turn, a wrapped
/// path, prose that overflows the viewport. A screen only fails where it
/// is crowded.
library;

import 'package:domain/model/agent_preset.dart';
import 'package:domain/model/backend.dart';
import 'package:domain/model/chat_message.dart';
import 'package:domain/model/context_pressure.dart';
import 'package:domain/model/model_catalog.dart';
import 'package:domain/model/session.dart';
import 'package:domain/model/session_window_stats.dart';
import 'package:domain/model/settings.dart';
import 'package:domain/model/subagent.dart';
import 'package:domain/model/timeline_item.dart';
import 'package:domain/model/todo.dart';
import 'package:domain/model/workspace.dart';

import 'package:app/ui/chat/chat_ui_state.dart';
import 'package:app/ui/chat/session_panel.dart';
import 'package:app/ui/settings/settings_ui_state.dart';
import 'package:app/ui/subagents/subagent_ui_state.dart';

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
    pendingInteraction: SessionPendingInteraction.question,
    updatedAtEpochMs: kNow - 3600000,
    cwd: '/home/user/Projects/deepseek-harness-app',
  ),
  SessionSummary(
    id: 's3',
    title: 'telemetry sampling',
    blank: false,
    completed: true,
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
      text:
          'the dock eats half the screen on my phone — can you look at '
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
      reasoning:
          'The dock stacks four chrome strips above the composer. '
          'Measuring each one against the transcript budget.',
      text:
          'Three things stack above the composer:\n\n'
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
      text:
          'Done — `maxLines: 4`, and the field scrolls past that. The dock '
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
  // A crowded day the reader actually sees: one queued wait riding the
  // dock, one steering line pending at the conversation tail (host
  // claimed it mid-turn), and the turn-status line still on.
  TimelineQueue(
    items: [
      SessionQueueItem(
        itemId: 'dq1',
        placement: QueuePlacement.queued,
        text: 'Also re-measure the composer ceiling on a 3-line draft',
      ),
      SessionQueueItem(
        itemId: 'dq2',
        placement: QueuePlacement.steering,
        text: 'hold on - the plan strip is closed there, use the open one',
      ),
    ],
  ),
];

/// A turn in flight: steps, a plan, stats, and a reply long enough to push
/// the transcript past the viewport. [timeline] swaps the conversation for
/// a shot that needs a different fold (the outline's turn groups) while
/// keeping the session chrome identical.
ChatUiState busyState({List<TimelineItem>? timeline}) {
  return ChatUiState(
    sessions: kSessions,
    selectedSessionId: 's1',
    timeline: timeline ?? _conversation,
    todos: const <TodoItem>[
      TodoItem(content: 'measure the dock', status: TodoStatus.completed),
      TodoItem(content: 'cap the composer', status: TodoStatus.inProgress),
      TodoItem(content: 'land the gate', status: TodoStatus.pending),
    ],
    sessionStats: const SessionWindowStats(
      turns: 12,
      steps: 47,
      llmMs: 84000,
      toolMs: 12000,
      billedInputTokens: 128400,
      outputTokens: 9100,
      cacheReadTokens: 96000,
    ),
    contextPressure: const ContextPressure(
      pressureTokens: 128400,
      contextWindow: 200000,
    ),
    models: const SessionModels(
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

/// The outline's own fold: one settled turn carrying a failed tool (the
/// ledger header wears the error dot and an error-ink failure count) and
/// one still-running turn (the ongoing dot; singular counts too). The
/// session chrome rides [busyState] unchanged so the shot diffs on the
/// turn-group header alone.
ChatUiState outlineState() {
  return busyState(
    timeline: const <TimelineItem>[
      TimelineTurnBoundary(1),
      TimelineMessage(
        ChatMessage(
          id: 'o1',
          sessionId: 's1',
          role: MessageRole.user,
          text: 'why does the dock eat half the screen? measure it',
          createdAtEpochMs: kNow,
          seq: 11,
        ),
      ),
      TimelineMessage(
        ChatMessage(
          id: 'o2',
          sessionId: 's1',
          role: MessageRole.assistant,
          text:
              'Four strips stack above the composer: the todo panel, the '
              'goal line, the stats line, and the eight-line composer.',
          createdAtEpochMs: kNow + 1000,
          seq: 12,
        ),
      ),
      TimelineToolCall(
        id: 'ot1',
        name: 'read',
        status: ToolRunStatus.completed,
      ),
      TimelineToolCall(
        id: 'ot2',
        name: 'bash',
        status: ToolRunStatus.completed,
      ),
      TimelineToolCall(id: 'ot3', name: 'bash', status: ToolRunStatus.failed),
      TimelineToolCall(
        id: 'ot4',
        name: 'edit',
        status: ToolRunStatus.completed,
      ),
      TimelineTurnBoundary(2),
      TimelineMessage(
        ChatMessage(
          id: 'o3',
          sessionId: 's1',
          role: MessageRole.user,
          text: 'cap it, then land the gate',
          createdAtEpochMs: kNow + 2000,
          seq: 21,
        ),
      ),
      TimelineToolCall(id: 'ot5', name: 'grep', status: ToolRunStatus.running),
    ],
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

ChatUiState emptyStateWithWorkspaces() {
  return const ChatUiState(
    sessions: <SessionSummary>[
      SessionSummary(id: 's9', title: '', blank: true),
    ],
    selectedSessionId: 's9',
    workspaces: <WorkspaceSummary>[
      WorkspaceSummary(
        workspaceId: 'w1',
        title: 'deepseek-harness-app',
        path: '/home/user/Projects/deepseek-harness-app',
        sessionIds: <String>['s1', 's2'],
      ),
      WorkspaceSummary(
        workspaceId: 'w2',
        title: 'signoz-stack',
        path: '/home/user/Projects/signoz-stack',
        sessionIds: <String>['s3'],
      ),
    ],
  );
}

/// The ask_user_question control, fed with REAL recorded data: the
/// `ask_user_question` tool payload from dsh session
/// `--home-chance-Projects-deepseek-harness-android--/session-50a3fe03-…`
/// (step 33, call `call_hx2whh2dpi2uvay7gn6vgb82`). The question, header,
/// option labels and descriptions below are that session's verbatim wire
/// arguments — not fabricated. Option one carries the model's conventional
/// `(Recommended)` suffix; the UI must strip it into the localized badge
/// ("Recommended" / "推荐").
const List<TimelineItem> _questionTimeline = <TimelineItem>[
  TimelineMessage(
    ChatMessage(
      id: 'u1',
      sessionId: 's1',
      role: MessageRole.user,
      text: '侧边栏的归档动作按参考实现来,还是按产品扩展做?',
      createdAtEpochMs: kNow,
      seq: 51,
    ),
  ),
  TimelineMessage(
    ChatMessage(
      id: 'a1',
      sessionId: 's1',
      role: MessageRole.assistant,
      text: '参考 web 确认了一下归档语义,回来问你两件事。',
      createdAtEpochMs: kNow + 1000,
      seq: 52,
    ),
  ),
  TimelineQuestionRequest(
    requestId: 'rpc-real-q1',
    questions: [
      QuestionItem(
        id: 'archive_scope',
        question:
            '在 web 参考实现里，没有“归档工作区”这个字段/动作——归档是按会话的'
            '（字段是 archivedSessionIds，会话行菜单里有“归档会话”，归档后该会话'
            '在所有分组界面消失，但工作区组头仍显示）。侧边栏要哪种归档？',
        header: '归档范围',
        options: ['会话行归档（web 平价）(Recommended)', '工作区组头“归档此工作区”', '两者都要'],
        optionDescriptions: {
          '会话行归档（web 平价）(Recommended)':
              '每个侧边栏会话行加“⋮ 菜单 → 归档会话”，归档后该行消失，'
              '与 web 完全一致；工作区组头仍保留。',
          '工作区组头“归档此工作区”':
              '在工作区组头加“归档此工作区”，一键归档该组所有会话，'
              '整组随后消失（web 无此动作，属产品扩展）。',
          '两者都要': '会话行归档（web 平价）+ 组头“归档此工作区”批量归档该组全部会话。',
        },
      ),
    ],
  ),
];

ChatUiState questionState() {
  return const ChatUiState(
    sessions: kSessions,
    selectedSessionId: 's1',
    timeline: _questionTimeline,
  );
}

/// ── Settings shots ────────────────────────────────────────────────────────
/// The Settings tab's two-category surface (App / Host) on a two-host
/// registry: the shots exercise the real screen against the real
/// registry chain, the only fakes being the transport seams.

/// Two-host registry document: the scope bar and the Hosts page render
/// their multi-host chrome.
const String kSettingsRegistryDoc =
    '{"backends": ['
    '{"id": "default", "label": "Laptop", "baseUrl": "http://10.0.2.2:3080"},'
    '{"id": "b1", "label": "Build box", "baseUrl": "http://10.0.2.2:3081"}'
    '], "activeId": "default"}';

/// The described host snapshot for the General page's fact rows.
const SettingsSnapshot kSettingsSnapshot = SettingsSnapshot(
  writable: true,
  hasDocument: true,
  namespaces: [
    SettingsNamespace(
      ns: 'llm-deepseek',
      applies: SettingsApplies.live,
      revision: 3,
      hasUserLayer: true,
      secretCount: 1,
    ),
    SettingsNamespace(
      ns: 'shell',
      applies: SettingsApplies.restart,
      revision: 0,
      hasUserLayer: false,
      secretCount: 0,
    ),
  ],
  credentialRefs: ['DEEPSEEK_API_KEY'],
);

const List<CredentialStatus> kSettingsCredentials = <CredentialStatus>[
  CredentialStatus(
    ref: 'DEEPSEEK_API_KEY',
    configured: true,
    source: 'file',
    writable: true,
  ),
];

const AgentPresetRoster kSettingsRoster = AgentPresetRoster(
  entries: [
    AgentPresetEntry(
      id: 'standard',
      trust: AgentPresetTrust.system,
      isDefault: true,
      description: 'Full coding agent with file editing, shell, and search.',
    ),
    AgentPresetEntry(id: 'code', trust: AgentPresetTrust.system),
    AgentPresetEntry(id: 'minimal', trust: AgentPresetTrust.system),
    AgentPresetEntry(
      id: 'my-agent',
      trust: AgentPresetTrust.user,
      name: 'My Agent',
      broken: 'agent.cordis.yml not found',
    ),
  ],
);

SettingsUiState settingsUiState() => const SettingsUiState(
  snapshot: kSettingsSnapshot,
  credentials: kSettingsCredentials,
  roster: kSettingsRoster,
);

/// The Subagents screen's catalog fixture: the same family the widget
/// test tree renders — a running continuable child with an expandable
/// branch, a settled one-shot child, and a corrupt diagnostic row.
const String kSubagentWorkerId = 'child-12345678abcd';

const SubagentCatalog kSubagentCatalog = SubagentCatalog(
  parentSessionId: 'p1',
  parentAvailable: true,
  entries: [
    SubagentEntry(
      id: kSubagentWorkerId,
      kind: 'child',
      mode: SubagentMode.continuable,
      activity: 'running',
      hasChildren: true,
      label: 'Worker',
    ),
    SubagentEntry(
      id: 'one-shot-1',
      kind: 'child',
      mode: SubagentMode.oneShot,
      activity: 'inactive',
    ),
    SubagentEntry(id: 'broken-1', kind: 'diagnostic', reason: 'corrupt'),
  ],
);

const List<SessionSummary> kSubagentSessions = <SessionSummary>[
  SessionSummary(
    id: 'p1',
    title: 'Porting the catalog surface',
    running: true,
    blank: false,
    updatedAtEpochMs: kNow,
  ),
  SessionSummary(
    id: 'p2',
    title: 'Reviewing the wire contract',
    blank: false,
    updatedAtEpochMs: kNow - 3600000,
  ),
  SessionSummary(
    id: kSubagentWorkerId,
    title: 'Porting tests',
    blank: false,
    updatedAtEpochMs: kNow - 60000,
  ),
];

SubagentUiState subagentsState() => const SubagentUiState(
  sessions: kSubagentSessions,
  selectedParentId: 'p1',
  catalog: kSubagentCatalog,
);

/// The catalog with a host failure on top: the banner is the surface
/// under review, so the error rides the same crowded tree.
SubagentUiState subagentsErrorState() => const SubagentUiState(
  sessions: kSubagentSessions,
  selectedParentId: 'p1',
  catalog: kSubagentCatalog,
  errorMessage: 'subagent.interrupt: child-12345678abcd not found on host',
);

/// The one-shot child's read-only record: a real transcript row, a
/// queued message riding the read-only dock, and the notice replacing
/// the message field.
SubagentUiState subagentsChildState() => const SubagentUiState(
  sessions: kSubagentSessions,
  selectedParentId: 'p1',
  catalog: kSubagentCatalog,
  selectedChildId: 'one-shot-1',
  childTimeline: [
    TimelineMessage(
      ChatMessage(
        id: 'm1',
        sessionId: 'one-shot-1',
        role: MessageRole.user,
        text: 'Audit the import boundary and report violations.',
        createdAtEpochMs: kNow - 120000,
        seq: 1,
      ),
    ),
    TimelineMessage(
      ChatMessage(
        id: 'm2',
        sessionId: 'one-shot-1',
        role: MessageRole.assistant,
        text:
            'Boundary holds: no app import crosses into the adapter '
            'outside lib/di/. Two dev-package leaves verified.',
        createdAtEpochMs: kNow - 60000,
        seq: 2,
      ),
    ),
    TimelineQueue(
      items: [
        SessionQueueItem(
          itemId: 'q1',
          placement: QueuePlacement.queued,
          text: 'Also check the asr package leaf',
        ),
      ],
    ),
  ],
);

/// ── Multi-backend sidebar scroll fixture ──────────────────────────────────
/// Crowded multi-backend session tree where the active backend's blue header
/// sits at the top of the scrolling list.

final BackendConfig kBackendLaptop = BackendConfig(
  id: 'default',
  label: 'Laptop',
  baseUri: Uri.parse('http://10.0.2.2:3080'),
);

final BackendConfig kBackendBuildBox = BackendConfig(
  id: 'b1',
  label: 'Build box',
  baseUri: Uri.parse('http://10.0.2.2:3081'),
);

final BackendConfig kBackendGpuServer = BackendConfig(
  id: 'b2',
  label: 'GPU Cluster',
  baseUri: Uri.parse('http://10.0.2.2:3082'),
);

final List<BackendSessionSlice> kCrowdedBackendSlices = <BackendSessionSlice>[
  BackendSessionSlice(
    backend: kBackendLaptop,
    active: true,
    sessions: const <SessionSummary>[
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
        pendingInteraction: SessionPendingInteraction.question,
        updatedAtEpochMs: kNow - 3600000,
        cwd: '/home/user/Projects/deepseek-harness-app',
      ),
      SessionSummary(
        id: 's3',
        title: 'telemetry sampling',
        blank: false,
        completed: true,
        updatedAtEpochMs: kNow - 86400000,
        cwd: '/home/user/Projects/signoz-stack',
      ),
    ],
    workspaces: const <WorkspaceSummary>[
      WorkspaceSummary(
        workspaceId: 'w1',
        title: 'deepseek-harness-app',
        path: '/home/user/Projects/deepseek-harness-app',
        sessionIds: <String>['s1', 's2'],
      ),
      WorkspaceSummary(
        workspaceId: 'w2',
        title: 'signoz-stack',
        path: '/home/user/Projects/signoz-stack',
        sessionIds: <String>['s3'],
      ),
    ],
  ),
  BackendSessionSlice(
    backend: kBackendBuildBox,
    active: false,
    sessions: const <SessionSummary>[
      SessionSummary(
        id: 'sb1',
        title: 'nightly release verification',
        blank: false,
        updatedAtEpochMs: kNow - 7200000,
        cwd: '/opt/builds/release',
      ),
    ],
    workspaces: const <WorkspaceSummary>[
      WorkspaceSummary(
        workspaceId: 'wb1',
        title: 'builds',
        path: '/opt/builds',
        sessionIds: <String>['sb1'],
      ),
    ],
  ),
  BackendSessionSlice(
    backend: kBackendGpuServer,
    active: false,
    sessions: const <SessionSummary>[
      SessionSummary(
        id: 'sg1',
        title: 'eval benchmark run 42',
        running: true,
        blank: false,
        updatedAtEpochMs: kNow - 1800000,
        cwd: '/srv/models/eval',
      ),
    ],
    workspaces: const <WorkspaceSummary>[
      WorkspaceSummary(
        workspaceId: 'wg1',
        title: 'eval',
        path: '/srv/models/eval',
        sessionIds: <String>['sg1'],
      ),
    ],
  ),
  BackendSessionSlice(
    backend: BackendConfig(
      id: 'b3',
      label: 'Staging Host',
      baseUri: Uri.parse('http://10.0.2.2:3083'),
    ),
    active: false,
    sessions: const <SessionSummary>[
      SessionSummary(id: 'st1', title: 'integration tests', blank: false),
    ],
    workspaces: const <WorkspaceSummary>[
      WorkspaceSummary(
        workspaceId: 'wst1',
        title: 'staging',
        path: '/opt/stage',
        sessionIds: ['st1'],
      ),
    ],
  ),
  BackendSessionSlice(
    backend: BackendConfig(
      id: 'b4',
      label: 'QA Matrix Box',
      baseUri: Uri.parse('http://10.0.2.2:3084'),
    ),
    active: false,
    sessions: const <SessionSummary>[
      SessionSummary(id: 'qa1', title: 'regression run', blank: false),
    ],
    workspaces: const <WorkspaceSummary>[
      WorkspaceSummary(
        workspaceId: 'wqa1',
        title: 'qa',
        path: '/opt/qa',
        sessionIds: ['qa1'],
      ),
    ],
  ),
  BackendSessionSlice(
    backend: BackendConfig(
      id: 'b5',
      label: 'US East Cluster',
      baseUri: Uri.parse('http://10.0.2.2:3085'),
    ),
    active: false,
    sessions: const <SessionSummary>[
      SessionSummary(id: 'us1', title: 'cluster telemetry sync', blank: false),
    ],
    workspaces: const <WorkspaceSummary>[
      WorkspaceSummary(
        workspaceId: 'wus1',
        title: 'useast',
        path: '/srv/us',
        sessionIds: ['us1'],
      ),
    ],
  ),
  BackendSessionSlice(
    backend: BackendConfig(
      id: 'b6',
      label: 'EU Central Node',
      baseUri: Uri.parse('http://10.0.2.2:3086'),
    ),
    active: false,
    sessions: const <SessionSummary>[
      SessionSummary(id: 'eu1', title: 'replica replication', blank: false),
    ],
    workspaces: const <WorkspaceSummary>[
      WorkspaceSummary(
        workspaceId: 'weu1',
        title: 'eucentral',
        path: '/srv/eu',
        sessionIds: ['eu1'],
      ),
    ],
  ),
  BackendSessionSlice(
    backend: BackendConfig(
      id: 'b7',
      label: 'APAC Edge Gateway',
      baseUri: Uri.parse('http://10.0.2.2:3087'),
    ),
    active: false,
    sessions: const <SessionSummary>[
      SessionSummary(id: 'ap1', title: 'edge gateway health', blank: false),
    ],
    workspaces: const <WorkspaceSummary>[
      WorkspaceSummary(
        workspaceId: 'wap1',
        title: 'apac',
        path: '/srv/apac',
        sessionIds: ['ap1'],
      ),
    ],
  ),
];

ChatUiState multiBackendDrawerState() => const ChatUiState(
  sessions: kSessions,
  selectedSessionId: 's1',
  timeline: _conversation,
);
