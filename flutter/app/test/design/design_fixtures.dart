/// States the design shots render. A fixture is the screen's own
/// `ChatUiState`, so a shot exercises the real widgets against the real
/// vocabulary — the only thing faked is the transport.
///
/// Write a fixture the way a bad day looks: a running turn, a wrapped
/// path, prose that overflows the viewport. A screen only fails where it
/// is crowded.
library;

import 'package:domain/model/agent_preset.dart';
import 'package:domain/model/attachment.dart';
import 'package:domain/model/backend.dart';
import 'package:domain/model/chat_message.dart';
import 'package:domain/model/context_pressure.dart';
import 'package:domain/model/model_catalog.dart';
import 'package:domain/model/permission_select.dart';
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
/// keeping the session chrome identical. [permissions] mounts the dock's
/// access chip, which a live host always publishes.
/// A running turn the reader steered mid-step, then an answer that closed its
/// step: the two wire facts nothing rendered yet — the spliced row's
/// `steering` badge and the step's own `step/end − step/start` range.
ChatUiState steeringAndStepState() => busyState(
  timeline: const <TimelineItem>[
    TimelineTurnBoundary(1, startedAtEpochMs: 1700000000000),
    TimelineMessage(
      ChatMessage(
        id: 'ss-u1',
        sessionId: 's1',
        role: MessageRole.user,
        text: 'Take the parser first.',
        createdAtEpochMs: 1700000000000,
        seq: 1,
      ),
    ),
    TimelineMessage(
      ChatMessage(
        id: 'ss-u2',
        sessionId: 's1',
        role: MessageRole.user,
        text: 'Stop; use the other branch.',
        createdAtEpochMs: 1700000002000,
        seq: 3,
      ),
      steering: true,
    ),
    TimelineMessage(
      ChatMessage(
        id: 'ss-a1',
        sessionId: 's1',
        role: MessageRole.assistant,
        text: 'Switched to the other branch and re-ran the parser.',
        createdAtEpochMs: 1700000009000,
        seq: 5,
      ),
      stepStartedAtEpochMs: 1700000003000,
      stepEndedAtEpochMs: 1700000008000,
    ),
  ],
);

ChatUiState busyState({
  List<TimelineItem>? timeline,
  PermissionSelect? permissions,
}) {
  return ChatUiState(
    permissions: permissions,
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

/// The dock with every seat a host can mount — the access chip included —
/// plus a draft waiting to be queued while the turn runs. The draft band is
/// only crowded here: every other fixture mounts no access chip, so their
/// action rows happen to fit a 360dp phone.
ChatUiState composerCrowdedState() => busyState(permissions: kDockAccess);

/// The browsing sidebar with a pin block: 's3' pinned last, so it leads,
/// 's2' after it — the Host's own "most recently pinned first" order.
ChatUiState pinnedSidebarState() {
  final base = busyState();
  return ChatUiState(
    sessions: base.sessions,
    workspaces: base.workspaces,
    selectedSessionId: base.selectedSessionId,
    timeline: base.timeline,
    pinnedSessionIds: const <String>['s3', 's2'],
  );
}

/// The preset table a live host publishes: three switchable presets.
const PermissionSelect kDockAccess = PermissionSelect(
  currentValue: 'workspace-write',
  options: <PermissionPresetOption>[
    PermissionPresetOption(
      value: 'read-only',
      name: 'read-only',
      description: 'Reads files without changing anything',
    ),
    PermissionPresetOption(
      value: 'workspace-write',
      name: 'workspace-write',
      description: 'Writes inside the workspace directory',
    ),
    PermissionPresetOption(
      value: 'danger-full-access',
      name: 'danger-full-access',
      description: 'Runs every action without asking',
    ),
  ],
);

/// The `permissions` Session projection as the Host publishes it:
/// `currentValue` and nothing else (`interaction/permission-presets/src/index.ts:243`).
/// The selectable presets come from the process catalog, never from here, so a
/// seat that lists them from this value has nothing to render.
const PermissionSelect kProjectionOnlyAccess = PermissionSelect(
  currentValue: 'workspace-write',
  options: <PermissionPresetOption>[],
);

/// The process catalog those presets come from
/// (`permissionPresets/catalog`).
const PermissionPresetCatalog kPermissionCatalog = PermissionPresetCatalog(
  options: <PermissionPresetOption>[
    PermissionPresetOption(
      value: 'read-only',
      name: 'read-only',
      description: 'Reads files without changing anything',
    ),
    PermissionPresetOption(
      value: 'workspace-write',
      name: 'workspace-write',
      description: 'Writes inside the workspace directory',
    ),
    PermissionPresetOption(
      value: 'danger-full-access',
      name: 'danger-full-access',
      description: 'Runs every action without asking',
    ),
  ],
  defaultOptions: <PermissionPresetOption>[
    PermissionPresetOption(
      value: 'workspace-write',
      name: 'workspace-write',
      description: 'Writes inside the workspace directory',
    ),
  ],
  defaultPreset: 'workspace-write',
);

/// A settled turn that both wrote and delivered files: the produced-files
/// chips row (本轮文件改动) and the delivered-files cards (交付文件) close the
/// reply, and the `present` call itself is an ordinary transcript row above
/// them. Five declarations so the collapse toggle is exercised the way a
/// crowded turn looks.
///
/// The session is idle on purpose: the turn-tail rows wait for `turn/end`
/// ([turnFilesByClosingMessage]), so a state with `running: true` would hide
/// exactly what this shot exists to show.
ChatUiState presentedFilesState() {
  return const ChatUiState(
    sessions: <SessionSummary>[
      SessionSummary(
        id: 's1',
        title: 'hero render handoff',
        blank: false,
        updatedAtEpochMs: kNow,
        cwd: '/home/user/Projects/art-pipeline',
      ),
    ],
    selectedSessionId: 's1',
    timeline: <TimelineItem>[
      TimelineTurnBoundary(1),
      TimelineMessage(
        ChatMessage(
          id: 'pf-u1',
          sessionId: 's1',
          role: MessageRole.user,
          text: 'render the hero and hand me the assets',
          createdAtEpochMs: kNow,
          seq: 11,
        ),
      ),
      TimelineToolCall(
        id: 'pf-t1',
        name: 'write',
        arguments: '{"file_path":"out/hero.png","content":"<binary>"}',
        status: ToolRunStatus.completed,
      ),
      TimelineToolCall(
        id: 'pf-t2',
        name: 'write',
        arguments: '{"file_path":"out/hero@2x.png","content":"<binary>"}',
        status: ToolRunStatus.completed,
      ),
      TimelineToolCall(
        id: 'pf-t3',
        name: 'present',
        arguments:
            '{"files":[{"path":"out/hero.png","description":"1x hero"},'
            '{"path":"out/hero@2x.png"},{"path":"out/report.pdf"},'
            '{"path":"out/LICENSE"},{"path":"out/atlas.png"}]}',
        status: ToolRunStatus.completed,
        presentedFiles: <PresentedFile>[
          PresentedFile(path: 'out/hero.png', description: '1x hero'),
          PresentedFile(path: 'out/hero@2x.png'),
          PresentedFile(path: 'out/report.pdf', description: 'Render report'),
          PresentedFile(path: 'out/LICENSE'),
          PresentedFile(path: 'out/atlas.png'),
        ],
      ),
      TimelineMessage(
        ChatMessage(
          id: 'pf-a1',
          sessionId: 's1',
          role: MessageRole.assistant,
          text:
              'Rendered both densities and attached the report. The license '
              'copy rides along for the store listing.',
          createdAtEpochMs: kNow + 1000,
          seq: 12,
        ),
      ),
    ],
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

/// Inline code in both scripts and across a wrap: the chip the user's
/// screenshot asked for, with Latin context, Han context, and a long line that
/// carries a chip onto the next line.
const String _proseCodeReply = '''
The fix lives in `markdown_text.dart`, where the inline run is built.

中文说明：路径 `root:root` 和它旁边的中文要在同一个段落里读起来是一行，
所以代码片段后面的汉字必须落在同一个行高上，不能被 chip 顶开。

A long line that has to wrap with a chip in it: the dock keeps one surface, the
field caps at four lines, and `_InputDock.withChrome(...)` still owns the
`root:root` path when the reader's viewport is narrow.
''';

ChatUiState proseCodeState() {
  return const ChatUiState(
    sessions: kSessions,
    selectedSessionId: 's1',
    timeline: <TimelineItem>[
      TimelineMessage(
        ChatMessage(
          id: 'pc1',
          sessionId: 's1',
          role: MessageRole.user,
          text: 'inline code, both scripts, and a wrapped line please',
          createdAtEpochMs: kNow,
          seq: 41,
        ),
      ),
      TimelineMessage(
        ChatMessage(
          id: 'pc2',
          sessionId: 's1',
          role: MessageRole.assistant,
          text: _proseCodeReply,
          createdAtEpochMs: kNow + 1000,
          seq: 42,
        ),
      ),
    ],
  );
}

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

/// A plan-review decision card: the warn strip, the plan as markdown, and the
/// discuss/decline/approve row. The plan is long on purpose — it is the card
/// whose fold control this change adds.
ChatUiState planReviewState() {
  return const ChatUiState(
    sessions: kSessions,
    selectedSessionId: 's1',
    timeline: <TimelineItem>[
      TimelineMessage(
        ChatMessage(
          id: 'pr-u1',
          sessionId: 's1',
          role: MessageRole.user,
          text: '先给我计划，确认之后再动手。',
          createdAtEpochMs: kNow,
          seq: 61,
        ),
      ),
      TimelineMessage(
        ChatMessage(
          id: 'pr-a1',
          sessionId: 's1',
          role: MessageRole.assistant,
          text: '计划如下，确认后我就开工。',
          createdAtEpochMs: kNow + 1000,
          seq: 62,
        ),
      ),
      TimelineQuestionRequest(
        requestId: 'rpc-plan-shot',
        questions: <QuestionItem>[
          QuestionItem(
            id: 'plan-shot',
            question: '执行这份计划吗？',
            detail:
                '## 交付文件行\n\n'
                '1. `deliverables/presented` 折到 `present` 调用自己的行上；\n'
                '2. 回合收尾处新增「交付文件」卡片行，超过 4 个折叠；\n'
                '3. `present` 工具行改用「交付文件」标题与 `files[].path` 摘要；\n'
                '4. 补单测与 before/after 设计图。\n\n'
                '风险：主桌面打开动作不做，只走应用内预览。',
            options: <String>['确认执行', '继续规划'],
            intent: QuestionIntent(kind: 'plan-review', approve: '确认执行'),
          ),
        ],
      ),
    ],
  );
}

/// An approval request: the wait as the dock's one line, with the paired
/// command and both answers one surface deeper.
ChatUiState approvalState() {
  return const ChatUiState(
    sessions: kSessions,
    selectedSessionId: 's1',
    timeline: <TimelineItem>[
      TimelineMessage(
        ChatMessage(
          id: 'ap-u1',
          sessionId: 's1',
          role: MessageRole.user,
          text: '先把本地构建产物清掉，再从干净状态打一次包。',
          createdAtEpochMs: kNow,
          seq: 71,
        ),
      ),
      TimelineToolCall(
        id: 'call-approval-shot',
        name: 'bash',
        arguments:
            '{"command":"rm -rf build && flutter build apk --debug",'
            '"description":"Clean and rebuild the debug APK"}',
        status: ToolRunStatus.running,
      ),
      TimelineApprovalRequest(
        requestId: 'rpc-approval-shot',
        sessionId: 's1',
        approvalId: 'ap-shot',
        toolName: 'bash',
        callId: 'call-approval-shot',
        reason: '删除 build/ 目录后重新打包，这会移除本地未提交的构建产物。',
      ),
    ],
  );
}

/// ── Settings shots ────────────────────────────────────────────────────────
/// The Settings index and the pages and sheets its rows open, on a two-host
/// registry: the shots exercise the real screen against the real registry
/// chain, the only fakes being the transport seams.
///
/// Two-host registry document: the host sheet lists both hosts and the
/// root's host tile names the scoped one.
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
      schema: SettingsSchema.empty,
    ),
    SettingsNamespace(
      ns: 'shell',
      applies: SettingsApplies.restart,
      revision: 0,
      hasUserLayer: false,
      secretCount: 0,
      schema: SettingsSchema.empty,
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
      isDefault: true,
      description: 'Full coding agent with file editing, shell, and search.',
    ),
    AgentPresetEntry(id: 'code'),
    AgentPresetEntry(id: 'minimal'),
    AgentPresetEntry(
      id: 'my-agent',
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
/// branch and a settled one-shot child.
const String kSubagentWorkerId = 'child-12345678abcd';

const SubagentCatalog kSubagentCatalog = SubagentCatalog(
  parentSessionId: 'p1',
  entries: [
    SubagentEntry(
      id: kSubagentWorkerId,
      mode: SubagentMode.continuable,
      activity: 'running',
      hasChildren: true,
      label: 'Worker',
    ),
    SubagentEntry(
      id: 'one-shot-1',
      mode: SubagentMode.oneShot,
      activity: 'inactive',
    ),
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

ChatUiState timelineFoldingStateZh() {
  final items = <TimelineItem>[
    const TimelineMessage(
      ChatMessage(
        id: 'u1',
        sessionId: 's1',
        role: MessageRole.user,
        text: '看看这个项目',
        createdAtEpochMs: kNow,
        seq: 1,
      ),
    ),
    const TimelineMessage(
      ChatMessage(
        id: 'a1',
        sessionId: 's1',
        role: MessageRole.assistant,
        reasoning: '先分析仓库结构和核心架构设计文档，梳理客户端与服务端之间的通讯契约和主要模块划分。',
        reasoningDuration: Duration(seconds: 10),
        text: '先从仓库结构和核心文档入手，摸清这个项目是做什么的、模块怎么拆。',
        createdAtEpochMs: kNow + 1000,
        seq: 2,
      ),
    ),
    const TimelineToolCall(
      id: 'tf1_1',
      name: 'read',
      arguments: '{"file_path":"AGENTS.md"}',
      status: ToolRunStatus.completed,
    ),
    const TimelineToolCall(
      id: 'tf1_2',
      name: 'read',
      arguments: '{"file_path":"README.md"}',
      status: ToolRunStatus.completed,
    ),
    const TimelineToolCall(
      id: 'tf1_3',
      name: 'read',
      arguments: '{"file_path":"pubspec.yaml"}',
      status: ToolRunStatus.completed,
    ),
    const TimelineToolCall(
      id: 'tf1_4',
      name: 'grep',
      arguments: '{"pattern":"TimelineItem"}',
      status: ToolRunStatus.completed,
    ),
    const TimelineToolCall(
      id: 'tf1_5',
      name: 'glob',
      arguments: '{"pattern":"lib/**/*.dart"}',
      status: ToolRunStatus.completed,
    ),
    const TimelineMessage(
      ChatMessage(
        id: 'a2',
        sessionId: 's1',
        role: MessageRole.assistant,
        text: '正在读各模块入口文档和目录，把产品、客户端、生成链路和基础设施串起来。',
        createdAtEpochMs: kNow + 2000,
        seq: 3,
      ),
    ),
    for (var i = 1; i <= 6; i++)
      TimelineToolCall(
        id: 'tf2_$i',
        name: 'read',
        arguments: '{"file_path":"module_$i.dart"}',
        status: ToolRunStatus.completed,
      ),
    const TimelineToolCall(
      id: 'tf2_search',
      name: 'grep',
      arguments: '{"pattern":"pipeline"}',
      status: ToolRunStatus.completed,
    ),
    const TimelineMessage(
      ChatMessage(
        id: 'a3',
        sessionId: 's1',
        role: MessageRole.assistant,
        text: '继续补齐生成链路、后端和客户端的关键细节，再给你一份整体图。',
        createdAtEpochMs: kNow + 3000,
        seq: 4,
      ),
    ),
    for (var i = 1; i <= 17; i++)
      TimelineToolCall(
        id: 'tf3_$i',
        name: 'read',
        arguments: '{"file_path":"src/layer_$i.dart"}',
        status: ToolRunStatus.completed,
      ),
    for (var i = 1; i <= 3; i++)
      TimelineToolCall(
        id: 'tf3_search_$i',
        name: 'grep',
        arguments: '{"pattern":"query_$i"}',
        status: ToolRunStatus.completed,
      ),
    // The phase that reasons, is handed recalled context and then runs
    // tools: one activity card with every member behind its own fold. It
    // rides the tail so the shot renders it without chasing the scroll.
    const TimelineMessage(
      ChatMessage(
        id: 'th4',
        sessionId: 's1',
        role: MessageRole.assistant,
        reasoning:
            'Weigh the recalled decision about the wire seam before touching '
            'the tree: the adapter owns every dsh type, and the app never sees '
            'one.',
        reasoningDuration: Duration(seconds: 7),
        text: '',
        createdAtEpochMs: kNow + 4000,
        seq: 5,
      ),
    ),
    const TimelineContextInjection(
      id: 'ctx4',
      text:
          'Earlier decision: the adapter owns every dsh type; app and domain '
          'never see one.',
      producerLabel: 'recall · wire seam',
      isRecall: true,
      summary: 'recalled 1 decision',
    ),
    for (var i = 1; i <= 4; i++)
      TimelineToolCall(
        id: 'tf4_$i',
        name: 'read',
        arguments: '{"file_path":"adapter_$i.dart"}',
        status: ToolRunStatus.completed,
      ),
  ];

  return ChatUiState(
    sessions: kSessions,
    selectedSessionId: 's1',
    timeline: items,
  );
}

/// A 16x10 PNG (a stand-in screenshot) so the image card renders real
/// pixels instead of its placeholder glyph.
const String kDesignImagePngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAABAAAAAKCAIAAAAy3EnLAAAAFElEQVR4nGOIqnhGEmIY1TA0NQAA6MQTEJdTNawAAAAASUVORK5CYII=';

ChatUiState timelineFoldingStateEn() {
  final items = <TimelineItem>[
    const TimelineMessage(
      ChatMessage(
        id: 'u1',
        sessionId: 's1',
        role: MessageRole.user,
        text: 'Analyze this project structure',
        createdAtEpochMs: kNow,
        seq: 1,
      ),
    ),
    const TimelineMessage(
      ChatMessage(
        id: 'a1',
        sessionId: 's1',
        role: MessageRole.assistant,
        reasoning: 'Inspect repository layout and core architectural documentation to understand module boundaries.',
        reasoningDuration: Duration(seconds: 10),
        text: 'Starting with the repository structure and core documentation to map out modules and boundaries.',
        createdAtEpochMs: kNow + 1000,
        seq: 2,
      ),
    ),
    const TimelineToolCall(
      id: 'tf1_1',
      name: 'read',
      arguments: '{"file_path":"AGENTS.md"}',
      status: ToolRunStatus.completed,
    ),
    const TimelineToolCall(
      id: 'tf1_2',
      name: 'read',
      arguments: '{"file_path":"README.md"}',
      status: ToolRunStatus.completed,
    ),
    const TimelineToolCall(
      id: 'tf1_3',
      name: 'read',
      arguments: '{"file_path":"pubspec.yaml"}',
      status: ToolRunStatus.completed,
    ),
    const TimelineToolCall(
      id: 'tf1_4',
      name: 'grep',
      arguments: '{"pattern":"TimelineItem"}',
      status: ToolRunStatus.completed,
    ),
    const TimelineToolCall(
      id: 'tf1_5',
      name: 'glob',
      arguments: '{"pattern":"lib/**/*.dart"}',
      status: ToolRunStatus.completed,
    ),
    const TimelineMessage(
      ChatMessage(
        id: 'a2',
        sessionId: 's1',
        role: MessageRole.assistant,
        text: 'Reading entry docs and directories to connect product features, client runtime, and wire protocol.',
        createdAtEpochMs: kNow + 2000,
        seq: 3,
      ),
    ),
    for (var i = 1; i <= 6; i++)
      TimelineToolCall(
        id: 'tf2_$i',
        name: 'read',
        arguments: '{"file_path":"module_$i.dart"}',
        status: ToolRunStatus.completed,
      ),
    const TimelineToolCall(
      id: 'tf2_search',
      name: 'grep',
      arguments: '{"pattern":"pipeline"}',
      status: ToolRunStatus.completed,
    ),
    const TimelineMessage(
      ChatMessage(
        id: 'a3',
        sessionId: 's1',
        role: MessageRole.assistant,
        text: 'Fleshing out generation pipeline and backend details to synthesize an end-to-end architecture overview.',
        createdAtEpochMs: kNow + 3000,
        seq: 4,
      ),
    ),
    for (var i = 1; i <= 17; i++)
      TimelineToolCall(
        id: 'tf3_$i',
        name: 'read',
        arguments: '{"file_path":"src/layer_$i.dart"}',
        status: ToolRunStatus.completed,
      ),
    for (var i = 1; i <= 3; i++)
      TimelineToolCall(
        id: 'tf3_search_$i',
        name: 'grep',
        arguments: '{"pattern":"query_$i"}',
        status: ToolRunStatus.completed,
      ),
  ];

  return ChatUiState(
    sessions: kSessions,
    selectedSessionId: 's1',
    timeline: items,
  );
}

ChatUiState timelineFoldingState() => timelineFoldingStateEn();

/// [kSessions] with the selected session settled. A shot about a finished Turn
/// must not mount the running chrome: the live status line would sit under a
/// control that already reports the Turn's total time.
final List<SessionSummary> kSettledSessions = <SessionSummary>[
  const SessionSummary(
    id: 's1',
    title: 'dock vertical budget',
    blank: false,
    updatedAtEpochMs: kNow,
    cwd: '/home/user/Projects/deepseek-harness-app',
  ),
  ...kSessions.skip(1),
];

/// Two settled Turns with their work behind the Turn control. The Turn control
/// and the phase card are the transcript's two disclosures and they only meet
/// here — the control owns the card — so this is the fixture where "the reply
/// survives the fold" and "the collapsed Turn is one line plus its answer" are
/// visible. Short enough that a whole Turn fits above the fold: the expanded
/// shot must show its body, not the scroll position.
ChatUiState turnProcessFoldedState({bool zh = false}) {
  final String ask = zh ? '把生成链路的关键细节补齐' : 'Fill in the pipeline details';
  final String opened = zh
      ? '先看仓库结构和核心文档，确认客户端与服务端之间的通讯契约。'
      : 'Start from the repository layout and the core docs to pin down the '
            'client/server wire contract.';
  final String closing = zh
      ? '适配层独占所有 dsh 类型，结论可以写得短一些。'
      : 'The adapter owns every dsh type, so the answer can stay short.';
  final String firstAnswer = zh
      ? '仓库分三层：提示词模板、步骤编排和产物落盘。'
      : 'The repository splits into prompt templates, step orchestration and '
            'artifact landing.';
  final String answer = zh
      ? '生成链路的细节在 docs/spec.md 里：一次 run 从模板渲染开始，'
            '按步骤编排调用工具，最后把产物写回工作区。适配层独占所有 dsh 类型，'
            'app 和 domain 都看不到一个。'
      : 'The pipeline details live in docs/spec.md: a run renders its template, '
            'walks the steps through their tool calls, then lands the artifacts '
            'back in the workspace. The adapter owns every dsh type, so neither '
            'app nor domain ever sees one.';
  return ChatUiState(
    sessions: kSettledSessions,
    selectedSessionId: 's1',
    timeline: <TimelineItem>[
      // A settled Turn above, so the reader sees the fold repeat rather than
      // one control floating alone.
      const TimelineTurnBoundary(
        1,
        startedAtEpochMs: kNow - 300000,
        endedAtEpochMs: kNow - 240000,
        endSeq: 3,
        endReason: 'completed',
      ),
      TimelineMessage(
        ChatMessage(
          id: 'tp0-u1',
          sessionId: 's1',
          role: MessageRole.user,
          text: zh ? '这个项目是做什么的' : 'What is this project',
          createdAtEpochMs: kNow - 300000,
          seq: 1,
        ),
      ),
      TimelineMessage(
        ChatMessage(
          id: 'tp0-a1',
          sessionId: 's1',
          role: MessageRole.assistant,
          text: firstAnswer,
          createdAtEpochMs: kNow - 240000,
          seq: 3,
        ),
      ),
      // The Turn the two shots act on: reads and a search, then an answer that
      // carries reasoning of its own — the reference keeps that reasoning with
      // the work and renders the reply as its own row.
      const TimelineTurnBoundary(
        2,
        startedAtEpochMs: kNow - 123000,
        endedAtEpochMs: kNow,
        endSeq: 12,
        endReason: 'completed',
      ),
      TimelineMessage(
        ChatMessage(
          id: 'tp1-u1',
          sessionId: 's1',
          role: MessageRole.user,
          text: ask,
          createdAtEpochMs: kNow - 123000,
          seq: 4,
        ),
      ),
      TimelineMessage(
        ChatMessage(
          id: 'tp1-th1',
          sessionId: 's1',
          role: MessageRole.assistant,
          reasoning: opened,
          reasoningDuration: const Duration(seconds: 6),
          text: '',
          createdAtEpochMs: kNow - 120000,
          seq: 5,
        ),
      ),
      const TimelineToolCall(
        id: 'tp1-t1',
        name: 'read',
        arguments: '{"file_path":"AGENTS.md"}',
        status: ToolRunStatus.completed,
      ),
      const TimelineToolCall(
        id: 'tp1-t2',
        name: 'read',
        arguments: '{"file_path":"docs/spec.md"}',
        status: ToolRunStatus.completed,
      ),
      const TimelineToolCall(
        id: 'tp1-t3',
        name: 'grep',
        arguments: '{"pattern":"pipeline"}',
        status: ToolRunStatus.completed,
      ),
      TimelineMessage(
        ChatMessage(
          id: 'tp1-a1',
          sessionId: 's1',
          role: MessageRole.assistant,
          reasoning: closing,
          reasoningDuration: const Duration(seconds: 4),
          text: answer,
          createdAtEpochMs: kNow,
          seq: 12,
        ),
      ),
    ],
  );
}

/// A Turn in flight with a tool call still running: the control counts the
/// elapsed seconds and never folds, and the phase card names what is happening
/// right now — its live label plus the first readable argument of the running
/// call, which is the one line the reference adds over a bare tool name.
ChatUiState turnProcessLiveState() {
  // A live Turn's label counts real elapsed time, so its clock is the host's:
  // the fixtures' fixed [kNow] would render the run as years long.
  final int now = DateTime.now().millisecondsSinceEpoch;
  return ChatUiState(
    sessions: kSessions,
    selectedSessionId: 's1',
    timeline: <TimelineItem>[
      TimelineTurnBoundary(1, startedAtEpochMs: now - 8000),
      TimelineMessage(
        ChatMessage(
          id: 'tl-u1',
          sessionId: 's1',
          role: MessageRole.user,
          text: 'Run the chat tests',
          createdAtEpochMs: now - 8000,
          seq: 1,
        ),
      ),
      TimelineToolCall(
        id: 'tl-t1',
        name: 'grep',
        arguments: '{"pattern":"ActivityGroupRow","path":"lib/ui/chat"}',
        result: 'lib/ui/chat/chat_screen.dart:2811',
        status: ToolRunStatus.completed,
        startedAtEpochMs: now - 6000,
      ),
      TimelineToolCall(
        id: 'tl-t2',
        name: 'bash',
        arguments: '{"command":"flutter test app/test/ui/chat"}',
        status: ToolRunStatus.running,
        startedAtEpochMs: now - 3000,
      ),
    ],
  );
}

/// The transcript's one-line marker rows stacked in one column: a lone
/// context injection above the compaction, slash-command and tool rows it
/// shares a rhythm with. A drift in row height or label size between them
/// is only visible when they sit together, so they share one fixture.
ChatUiState markerRowsState() {
  final items = <TimelineItem>[
    const TimelineMessage(
      ChatMessage(
        id: 'mk_u1',
        sessionId: 's1',
        role: MessageRole.user,
        text: 'Pick the wire seam back up.',
        createdAtEpochMs: kNow,
        seq: 1,
      ),
    ),
    const TimelineContextInjection(
      id: 'mk_ctx',
      text: 'Earlier decision: the adapter owns every dsh type.',
      producerLabel: 'AGENTS.md',
      summary: 'workspace instructions',
    ),
    const TimelineCompaction(
      id: 'mk_cmp',
      shadowedCount: 12,
      shadowedTokens: 8400,
      summary: 'Earlier turns compacted into a summary.',
    ),
    const TimelineCommand(
      commandId: 'mk_cmd',
      name: 'compact',
      status: CommandRunStatus.success,
      text: 'Context compacted',
    ),
    // A phase of three members, so opening it puts the inline injection
    // row directly beside the thought and the tool call.
    const TimelineMessage(
      ChatMessage(
        id: 'mk_a1',
        sessionId: 's1',
        role: MessageRole.assistant,
        reasoning: 'Re-read the boundary note before touching the adapter.',
        reasoningDuration: Duration(seconds: 4),
        text: '',
        createdAtEpochMs: kNow + 1000,
        seq: 2,
      ),
    ),
    const TimelineContextInjection(
      id: 'mk_ctx2',
      text: 'Recall: the import boundary is absolute.',
      producerLabel: 'recall · wire seam',
      isRecall: true,
      summary: 'recalled 1 decision',
    ),
    const TimelineToolCall(
      id: 'mk_t1',
      name: 'read',
      arguments:
          '{"file_path":"packages/harness_adapter/lib/src/rpc_map.dart"}',
      result: '210 lines',
      status: ToolRunStatus.completed,
    ),
  ];

  return ChatUiState(
    sessions: kSessions,
    selectedSessionId: 's1',
    timeline: items,
  );
}

/// A `read_image` result: the row carries the durable reference, and the
/// card renders the picture plus the model-facing envelope beneath it.
ChatUiState toolImageState() {
  final items = <TimelineItem>[
    const TimelineMessage(
      ChatMessage(
        id: 'ti_u1',
        sessionId: 's1',
        role: MessageRole.user,
        text: 'What does this screenshot show?',
        createdAtEpochMs: kNow,
        seq: 1,
      ),
    ),
    const TimelineMessage(
      ChatMessage(
        id: 'ti_a1',
        sessionId: 's1',
        role: MessageRole.assistant,
        text: 'Opening the capture to read it.',
        createdAtEpochMs: kNow + 1000,
        seq: 2,
      ),
    ),
    const TimelineToolCall(
      id: 'ti_read',
      name: 'read_image',
      arguments: '{"file_path":"captures/launch.png"}',
      result:
          '<path>/home/user/captures/launch.png</path>\n<type>image</type>\n'
          '<content>\nimage/png image, 1280x800 px, 48213 bytes\n</content>',
      status: ToolRunStatus.completed,
      images: <AttachmentRef>[
        AttachmentRef(
          attachmentId: 'sha256:9f21c0',
          mediaType: 'image/png',
          bytes: 48213,
          width: 1280,
          height: 800,
          name: 'launch.png',
        ),
      ],
    ),
  ];

  return ChatUiState(
    sessions: kSessions,
    selectedSessionId: 's1',
    timeline: items,
  );
}
