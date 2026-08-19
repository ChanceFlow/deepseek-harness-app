/// ChatScreen widget parity tests — the legacy Compose screen behavior
/// this port must keep: banner labels, session list rules, timeline rows,
/// question drafts, queue actions, composer modes, and the outline.
library;

import 'package:domain/model/attachment.dart';
import 'package:domain/model/chat_message.dart';
import 'package:domain/model/connection_state.dart';
import 'package:domain/model/goal.dart';
import 'package:domain/model/model_catalog.dart';
import 'package:domain/model/skills.dart';
import 'package:domain/model/jobs.dart';
import 'package:domain/model/plan.dart';
import 'package:domain/model/prompt.dart';
import 'package:domain/model/session.dart';
import 'package:domain/model/timeline_item.dart';
import 'package:domain/model/workspace.dart';
import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_test/flutter_test.dart';

import 'dart:async';

import 'package:app/di/providers.dart';
import 'package:app/ui/chat/chat_screen.dart';
import 'package:app/ui/chat/chat_ui_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class _FakeRpc implements DshRpcClient {
  @override
  Future<RpcResult> call(
    String endpoint,
    String method,
    JsonMap payload,
  ) async {
    return RpcResult(ok: true, value: <String, Object?>{});
  }

  @override
  Future<void> respond(String rpcId, RpcResult result) async {}
}

class _NeverSocket implements DshEventSocket {
  final StreamController<ServerRequest> _frames =
      StreamController<ServerRequest>.broadcast();

  @override
  Stream<ServerRequest> connect(String path, {void Function()? onOpen}) {
    onOpen?.call();
    return _frames.stream;
  }
}

const _catalog = SessionModels(
  current: ModelSelection(
    provider: 'deepseek',
    model: 'glm-x',
    reasoningEffort: 'high',
  ),
  routable: true,
  groups: [
    ModelProviderGroup(
      id: 'deepseek',
      name: 'DeepSeek',
      models: [
        ModelCatalogModel(
          id: 'glm-x',
          name: 'GLM X',
          description: 'Fast reasoning model',
          reasoning: ModelReasoning(
            efforts: [
              ModelReasoningEffort(id: 'low', name: 'Low'),
              ModelReasoningEffort(id: 'high', name: 'High'),
            ],
            defaultEffort: 'high',
          ),
        ),
        ModelCatalogModel(id: 'glm-air', name: 'GLM Air'),
      ],
    ),
  ],
);

ChatUiState _state({
  ConnectionPhase phase = ConnectionPhase.connected,
  List<JobView> jobs = const <JobView>[],
  String version = '1.2.3',
  List<SessionSummary> sessions = const <SessionSummary>[],
  List<WorkspaceSummary> workspaces = const <WorkspaceSummary>[],
  List<TimelineItem> timeline = const <TimelineItem>[],
  List<SessionSearchResult> searchResults = const <SessionSearchResult>[],
  String? selectedSessionId,
  List<PendingImage> pendingImages = const <PendingImage>[],
  List<SkillEntry> skills = const <SkillEntry>[],
  bool isSending = false,
  String? errorMessage,
}) {
  return ChatUiState(
    connection: ConnectionState(
      phase: phase,
      hostDescription: HostDescription(version: version, cwd: '/tmp'),
    ),
    sessions: sessions,
    workspaces: workspaces,
    timeline: timeline,
    searchResults: searchResults,
    selectedSessionId: selectedSessionId,
    jobs: jobs,
    pendingImages: pendingImages,
    skills: skills,
    isSending: isSending,
    errorMessage: errorMessage,
  );
}

Future<void> _pump(
  WidgetTester tester,
  ChatUiState uiState,
  List<ChatAction> actions, {
  double width = 800,
}) {
  // Phone-scale logical surface so both panes and rows lay out naturally.
  tester.view.physicalSize = Size(width, 1280);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  return tester.pumpWidget(
    ProviderScope(
      overrides: [
        dshRpcClientProvider.overrideWithValue(_FakeRpc()),
        dshEventSocketProvider.overrideWithValue(_NeverSocket()),
      ],
      child: MaterialApp(
        home: ChatScreen(uiState: uiState, onAction: actions.add),
      ),
    ),
  );
}

void main() {
  testWidgets('connection banner shows phase and host version', (tester) async {
    final actions = <ChatAction>[];
    await _pump(
      tester,
      _state(
        sessions: const [SessionSummary(id: 's1', title: 'Alpha')],
      ),
      actions,
    );
    expect(find.text('connected 1.2.3'), findsOneWidget);

    await _pump(
      tester,
      _state(
        phase: ConnectionPhase.reconnecting,
        sessions: const [SessionSummary(id: 's1', title: 'Alpha')],
      ),
      actions,
    );
    expect(find.text('reconnecting'), findsOneWidget);
  });

  testWidgets('session list shows title, running dot, blank fallback', (
    tester,
  ) async {
    final actions = <ChatAction>[];
    await _pump(
      tester,
      _state(
        sessions: const [
          SessionSummary(id: 's1', title: 'Alpha', running: true, blank: false),
          SessionSummary(id: 's2', title: 'Beta', blank: false),
          SessionSummary(id: 's3', blank: true),
        ],
        selectedSessionId: 's1',
      ),
      actions,
    );
    // The grouped sidebar rows: the running dot is a state-dot widget (the
    // title stands alone), so scope the row text to the session panel.
    Finder panelText(String text) => find.descendant(
      of: find.byType(SessionPanel),
      matching: find.text(text),
    );
    expect(panelText('Alpha'), findsOneWidget);
    expect(panelText('Beta'), findsOneWidget);
    // Blank row + the panel's own "New session" button.
    expect(find.text('New session'), findsNWidgets(2));
    await tester.tap(panelText('Beta'));
    await tester.pump();
    expect(actions, contains(const SelectSession('s2')));
  });

  testWidgets('new session dialog offers workspaces and default', (
    tester,
  ) async {
    final actions = <ChatAction>[];
    await _pump(
      tester,
      _state(
        sessions: const [
          SessionSummary(id: 's1', title: 'Alpha', blank: false),
        ],
        workspaces: const [
          WorkspaceSummary(
            workspaceId: 'w1',
            path: '/tmp/proj',
            title: 'proj',
            sessionIds: <String>[],
          ),
        ],
      ),
      actions,
    );
    await tester.tap(find.text('New session'));
    await tester.pumpAndSettle();

    expect(
      find.text('Choose a workspace or keep the default.'),
      findsOneWidget,
    );
    expect(find.text('proj — /tmp/proj'), findsOneWidget);

    await tester.tap(find.text('proj — /tmp/proj'));
    await tester.pumpAndSettle();
    expect(actions, contains(const CreateSessionInWorkspace('w1')));

    await tester.tap(find.text('New session'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Default'));
    await tester.pumpAndSettle();
    expect(actions, contains(const CreateSessionInWorkspace(null)));
  });

  testWidgets('search dispatches query and lists result rows', (tester) async {
    final actions = <ChatAction>[];
    await _pump(
      tester,
      _state(
        sessions: const [
          SessionSummary(id: 's1', title: 'Alpha', blank: false),
          SessionSummary(id: 's9', title: 'Sigma', blank: false),
        ],
        searchResults: const [
          SessionSearchResult(sessionId: 's9', snippet: '…snippet…'),
        ],
      ),
      actions,
    );

    // The header search toggle opens the capsule; typing dispatches the
    // host content-search per keystroke (web WorkspaceBrowser).
    await tester.tap(find.byTooltip('Search sessions'));
    await tester.pumpAndSettle();
    final searchField = find
        .descendant(
          of: find.byType(SessionPanel),
          matching: find.byType(TextField),
        )
        .first;
    await tester.enterText(searchField, 'hello');
    await tester.pump();
    expect(actions.last, const SearchSessions('hello'));

    // While the query is live the flat result list replaces the tree:
    // title, workspace label, and the content snippet.
    expect(find.text('Sigma'), findsOneWidget);
    expect(find.text('…snippet…'), findsOneWidget);
    expect(find.text('Alpha'), findsNothing);

    await tester.tap(find.text('Sigma'));
    await tester.pump();
    expect(actions, contains(const SelectSession('s9')));
  });

  testWidgets('app bar shows session title, connection subtitle, actions', (
    tester,
  ) async {
    final actions = <ChatAction>[];
    await _pump(
      tester,
      _state(
        sessions: const [
          SessionSummary(id: 's1', title: 'Alpha', blank: false),
        ],
        selectedSessionId: 's1',
      ),
      actions,
    );

    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('Alpha')),
      findsOneWidget,
    );
    expect(find.text('connected 1.2.3'), findsOneWidget);
    expect(find.byTooltip('Rename session'), findsOneWidget);
    expect(find.byTooltip('Fork session'), findsOneWidget);
    expect(find.byTooltip('Archive session'), findsOneWidget);
    expect(find.byTooltip('Outline'), findsOneWidget);
    expect(find.byTooltip('Subagents'), findsOneWidget);
    // Web plan seat: the warn pill renders only while the plan target is
    // active (null plan here → nothing).
    expect(find.text('Plan'), findsNothing);
    // The old button soup is gone.
    expect(find.widgetWithText(OutlinedButton, 'Rename'), findsNothing);
    expect(find.widgetWithText(OutlinedButton, 'Fork'), findsNothing);

    await tester.tap(find.byTooltip('Fork session'));
    await tester.pump();
    expect(actions, contains(const ForkSession('s1')));
  });

  testWidgets(
    'context injections render as disclosure rows, not user bubbles',
    (tester) async {
      final actions = <ChatAction>[];
      await _pump(
        tester,
        _state(
          sessions: const [
            SessionSummary(id: 's1', title: 'Alpha', blank: false),
          ],
          selectedSessionId: 's1',
          timeline: const [
            TimelineContextInjection(
              id: 'ctx-1',
              text: 'goal objective: Ship the MVP',
              producerLabel: 'goal',
            ),
            TimelineContextInjection(
              id: 'ctx-2',
              text: 'recalled material',
              producerLabel: 'Yesterday debugging',
              isRecall: true,
            ),
            TimelineContextInjection(
              id: 'ctx-3',
              text: 'summary body',
              producerLabel: 'compact',
              summary: 'compacted 12 events',
            ),
          ],
        ),
        actions,
      );

      // Web ContextInjectionRow: the header names the role beside the
      // durable producer; the body stays collapsed until tapped.
      expect(find.text('Context injection'), findsNWidgets(2));
      expect(find.text('Recall'), findsOneWidget);
      expect(find.text('goal'), findsOneWidget);
      expect(find.text('Yesterday debugging'), findsOneWidget);
      expect(find.text('compacted 12 events'), findsOneWidget);
      expect(find.text('goal objective: Ship the MVP'), findsNothing);

      await tester.tap(find.text('Context injection').first);
      await tester.pumpAndSettle();
      expect(find.text('goal objective: Ship the MVP'), findsOneWidget);
    },
  );

  testWidgets('timeline renders rows and dispatches approvals', (tester) async {
    final actions = <ChatAction>[];
    await _pump(
      tester,
      _state(
        sessions: const [
          SessionSummary(id: 's1', title: 'Alpha', blank: false),
        ],
        selectedSessionId: 's1',
        jobs: const [
          JobView(
            id: 'j1',
            kind: 'build',
            label: 'assemble',
            status: JobStatus.running,
          ),
        ],
        timeline: const [
          TimelineTurnBoundary(1),
          TimelineMessage(
            ChatMessage(
              id: 'm1',
              sessionId: 's1',
              role: MessageRole.user,
              text: 'do the thing',
            ),
          ),
          TimelineMessage(
            ChatMessage(
              id: 'm2',
              sessionId: 's1',
              role: MessageRole.assistant,
              text: '**working** on it',
            ),
          ),
          TimelineToolCall(
            id: 'call-1',
            name: 'bash',
            arguments: 'ls -la',
            result: 'README.md',
            status: ToolRunStatus.completed,
          ),
          TimelineApprovalRequest(
            requestId: 'rpc-1',
            sessionId: 's1',
            approvalId: 'a-1',
            toolName: 'bash',
            reason: 'Would run a command',
          ),
          TimelineCompaction(id: 'c1', shadowedCount: 3),
          TimelineError(id: 'e1', message: 'boom'),
        ],
      ),
      actions,
    );

    expect(find.text('Turn 1'), findsOneWidget);
    // User text rides a plain bubble (no speaker label); assistant renders
    // flat markdown.
    expect(find.text('do the thing'), findsOneWidget);
    expect(find.text('working on it', findRichText: true), findsOneWidget);
    // Web tool row: single line — title + result-first-line summary; the
    // arguments live behind the expand affordance.
    expect(find.text('bash'), findsOneWidget);
    expect(find.text('README.md'), findsOneWidget);
    expect(find.text('ls -la'), findsNothing);

    await tester.tap(find.text('bash'));
    await tester.pumpAndSettle();
    expect(find.text('ls -la'), findsOneWidget);
    // Approval takes over the composer seat: web takeover card.
    expect(find.text('Waiting for approval'), findsOneWidget);
    expect(find.text('Would run a command'), findsOneWidget);
    expect(
      find.text('Tool bash requests privileged execution'),
      findsOneWidget,
    );
    expect(find.text('Message DeepSeek Harness'), findsNothing);
    // Web compaction row: dim title + count fragment.
    expect(find.text('Context compacted'), findsOneWidget);
    expect(find.text('Compacted 3 history items'), findsOneWidget);
    expect(find.text('boom'), findsOneWidget);
    // Jobs live in the session-header pill now, not the timeline.
    expect(find.text('Background jobs'), findsNothing);
    expect(find.text('1 background job running'), findsOneWidget);

    await tester.tap(find.text('Allow once'));
    await tester.pump();
    expect(
      actions,
      contains(
        const RespondApproval(
          requestId: 'rpc-1',
          approvalId: 'a-1',
          allowed: true,
        ),
      ),
    );
    await tester.tap(find.text('Reject'));
    await tester.pump();
    expect(
      actions,
      contains(
        const RespondApproval(
          requestId: 'rpc-1',
          approvalId: 'a-1',
          allowed: false,
        ),
      ),
    );
  });

  testWidgets('approval without reason falls back to the escalation title', (
    tester,
  ) async {
    final actions = <ChatAction>[];
    await _pump(
      tester,
      _state(
        sessions: const [
          SessionSummary(id: 's1', title: 'Alpha', blank: false),
        ],
        selectedSessionId: 's1',
        timeline: const [
          TimelineApprovalRequest(
            requestId: 'rpc-9',
            sessionId: 's1',
            approvalId: 'a-9',
            toolName: 'edit',
          ),
        ],
      ),
      actions,
    );

    expect(find.text('Approve tool: edit'), findsOneWidget);
    expect(find.text('Waiting for approval'), findsOneWidget);
    // Composer seat stays taken until answered.
    expect(find.byTooltip('Send'), findsNothing);

    await tester.tap(find.text('Reject'));
    await tester.pump();
    expect(
      actions,
      contains(
        const RespondApproval(
          requestId: 'rpc-9',
          approvalId: 'a-9',
          allowed: false,
        ),
      ),
    );
  });

  testWidgets('queue rows dispatch steer/remove and edit dialog saves', (
    tester,
  ) async {
    final actions = <ChatAction>[];
    await _pump(
      tester,
      _state(
        sessions: const [
          SessionSummary(id: 's1', title: 'Alpha', blank: false),
        ],
        selectedSessionId: 's1',
        timeline: const [
          TimelineQueue(
            items: [
              SessionQueueItem(
                itemId: 'q1',
                placement: QueuePlacement.queued,
                text: 'first',
              ),
              SessionQueueItem(
                itemId: 'q2',
                placement: QueuePlacement.context,
                text: 'context only',
              ),
            ],
          ),
        ],
      ),
      actions,
    );

    expect(find.text('Queued: first'), findsOneWidget);
    expect(find.text('Context: context only'), findsOneWidget);
    // Context items carry no actions (the composer Steer chip is the only
    // other Steer on screen).
    final queueRowSteer = find.descendant(
      of: find.byType(QueueRow),
      matching: find.text('Steer'),
    );
    expect(queueRowSteer, findsOneWidget);

    await tester.tap(
      find.descendant(of: find.byType(QueueRow), matching: find.text('Remove')),
    );
    await tester.pump();
    expect(
      actions,
      contains(
        const UpdateQueueAction(itemId: 'q1', kind: QueueUpdateKind.remove),
      ),
    );

    await tester.tap(queueRowSteer);
    await tester.pump();
    expect(
      actions,
      contains(
        const UpdateQueueAction(itemId: 'q1', kind: QueueUpdateKind.steer),
      ),
    );

    await tester.tap(
      find.descendant(of: find.byType(QueueRow), matching: find.text('Edit')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Edit queued message'), findsOneWidget);
    await tester.enterText(
      find.descendant(
        of: find.byType(QueueEditDialog),
        matching: find.byType(TextField),
      ),
      'revised',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(
      actions,
      contains(
        const UpdateQueueAction(
          itemId: 'q1',
          kind: QueueUpdateKind.edit,
          text: 'revised',
        ),
      ),
    );
  });

  testWidgets('question drafts collect options, custom text, skip', (
    tester,
  ) async {
    final actions = <ChatAction>[];
    await _pump(
      tester,
      _state(
        sessions: const [
          SessionSummary(id: 's1', title: 'Alpha', blank: false),
        ],
        selectedSessionId: 's1',
        timeline: const [
          TimelineQuestionRequest(
            requestId: 'rpc-2',
            questions: [
              QuestionItem(
                id: 'q1',
                question: 'Continue?',
                options: ['yes', 'no'],
              ),
            ],
          ),
        ],
      ),
      actions,
    );

    // Nothing drafted yet: Answer stays disabled.
    final answerButton = find.widgetWithText(FilledButton, 'Answer').first;
    expect(tester.widget<FilledButton>(answerButton).onPressed, isNull);

    await tester.tap(find.text('yes'));
    await tester.pump();
    expect(tester.widget<FilledButton>(answerButton).onPressed, isNotNull);

    await tester.tap(answerButton);
    await tester.pump();
    expect(
      actions,
      contains(
        const AnswerQuestionAction(
          requestId: 'rpc-2',
          answers: [
            QuestionAnswer(questionId: 'q1', selectedOptions: ['yes']),
          ],
        ),
      ),
    );

    // Skip answers with empty selections.
    actions.clear();
    await tester.tap(find.text('Skip'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Answer').first);
    await tester.pump();
    expect(
      actions,
      contains(
        const AnswerQuestionAction(
          requestId: 'rpc-2',
          answers: [QuestionAnswer(questionId: 'q1', selectedOptions: [])],
        ),
      ),
    );
    expect(find.text('Skipped'), findsOneWidget);

    // "Answer instead" clears the skip.
    await tester.tap(find.text('Answer instead'));
    await tester.pump();
    expect(find.text('Skipped'), findsNothing);
  });

  testWidgets('idle composer sends queue; plan pill stays hidden while off', (
    tester,
  ) async {
    final actions = <ChatAction>[];
    await _pump(
      tester,
      _state(
        sessions: const [
          SessionSummary(id: 's1', title: 'Alpha', blank: false),
        ],
        selectedSessionId: 's1',
      ),
      actions,
    );

    // Web composer seats: attach circle, plan pill (off → hidden), model
    // circle, ring, primary Send circle.
    expect(find.byTooltip('Commands'), findsOneWidget);
    expect(find.byTooltip('Model: Model'), findsOneWidget);
    expect(find.text('Plan'), findsNothing);
    expect(find.widgetWithText(OutlinedButton, 'Steer'), findsNothing);
    expect(find.text('Delivery'), findsNothing);

    final composerField = find
        .descendant(
          of: find.byType(ComposerBar),
          matching: find.byType(TextField),
        )
        .first;
    await tester.enterText(composerField, 'hello world');
    await tester.pump();
    await tester.tap(find.byTooltip('Send'));
    await tester.pump();
    expect(
      actions,
      contains(const SendPrompt('hello world', mode: PromptMode.queue)),
    );
  });

  testWidgets('running session: primary becomes Stop; submit queues', (
    tester,
  ) async {
    final actions = <ChatAction>[];
    await _pump(
      tester,
      _state(
        sessions: const [
          SessionSummary(id: 's1', title: 'Alpha', running: true, blank: false),
        ],
        selectedSessionId: 's1',
      ),
      actions,
    );

    // Web primary semantics: while the turn runs the button IS Stop.
    expect(find.byTooltip('Stop'), findsOneWidget);
    expect(find.byTooltip('Send'), findsNothing);

    await tester.tap(find.byTooltip('Stop'));
    await tester.pump();
    expect(actions, contains(const CancelTurnAction()));

    // Enter/IME submit while running still queues the draft (web Enter).
    final composerField = find
        .descendant(
          of: find.byType(ComposerBar),
          matching: find.byType(TextField),
        )
        .first;
    await tester.enterText(composerField, 'queued while running');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump();
    expect(
      actions,
      contains(
        const SendPrompt('queued while running', mode: PromptMode.queue),
      ),
    );
  });

  testWidgets('goal strip renders phases and dispatches pause/open', (
    tester,
  ) async {
    final actions = <ChatAction>[];
    await _pump(
      tester,
      _state(
        sessions: const [
          SessionSummary(id: 's1', title: 'Alpha', blank: false),
        ],
        selectedSessionId: 's1',
      ),
      actions,
    );

    // No goal → no strip.
    expect(find.text('Active'), findsNothing);

    await _pump(
      tester,
      const ChatUiState(
        sessions: [SessionSummary(id: 's1', title: 'Alpha', blank: false)],
        selectedSessionId: 's1',
        goal: GoalProjection(
          goal: GoalSnapshot(
            id: 'g1',
            revision: 3,
            objective: 'Ship the MVP',
            phase: GoalPhase.active,
            maxGoalRounds: 10,
          ),
          roundsStarted: 2,
          createdAt: 0,
          updatedAt: 0,
        ),
      ),
      actions,
    );

    expect(find.text('Active'), findsOneWidget);
    expect(find.text('Ship the MVP'), findsOneWidget);
    expect(find.byTooltip('Pause goal'), findsOneWidget);
    expect(find.byTooltip('Open goal'), findsOneWidget);

    await tester.tap(find.byTooltip('Pause goal'));
    await tester.pump();
    expect(actions, contains(const ToggleGoalPause()));

    // Web GoalBar ships the trash action beside pause/resume: clearing
    // works from any phase.
    expect(find.byTooltip('Clear goal'), findsOneWidget);
    await tester.tap(find.byTooltip('Clear goal'));
    await tester.pump();
    expect(actions, contains(const ClearGoal()));
  });

  testWidgets('jobs pill opens the ordered sheet with durations', (
    tester,
  ) async {
    final actions = <ChatAction>[];
    final now = DateTime.now().millisecondsSinceEpoch;
    await _pump(
      tester,
      _state(
        sessions: const [
          SessionSummary(id: 's1', title: 'Alpha', blank: false),
        ],
        selectedSessionId: 's1',
        jobs: [
          JobView(
            id: 'j1',
            kind: 'build',
            label: 'assemble',
            status: JobStatus.completed,
            startedAt: now - 90000,
            finishedAt: now - 30000,
          ),
          JobView(
            id: 'j2',
            kind: 'watch',
            label: 'logs',
            status: JobStatus.running,
            startedAt: now - 150000,
          ),
        ],
      ),
      actions,
    );

    // Live count leads the pill label.
    expect(find.text('1 background job running'), findsOneWidget);

    await tester.tap(find.text('1 background job running'));
    await tester.pumpAndSettle();

    // Sheet header + both rows; the live row sorts first.
    expect(find.text('Background jobs'), findsOneWidget);
    expect(find.text('watch'), findsOneWidget);
    expect(find.text('build'), findsOneWidget);
    // Settled duration: 90s → 30s = 1m 0s; detail falls back to status word.
    expect(find.text('1m 0s'), findsOneWidget);
    expect(find.text('completed'), findsOneWidget);
  });

  testWidgets('plus opens the command sheet and inserts the command', (
    tester,
  ) async {
    final actions = <ChatAction>[];
    await _pump(
      tester,
      const ChatUiState(
        sessions: [SessionSummary(id: 's1', title: 'Alpha', blank: false)],
        selectedSessionId: 's1',
        skills: [
          SkillEntry(name: 'review', description: 'Review conversations'),
          SkillEntry(name: 'rust', description: 'Rust toolchain hints'),
        ],
      ),
      actions,
    );

    await tester.tap(find.byTooltip('Commands'));
    await tester.pumpAndSettle();

    // Web slash-menu form: search field, the host command roster (real
    // commands, not just skills), then skills, with the mobile-only
    // attach row demoted to the tail.
    final searchField = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.hintText == 'Search commands',
    );
    expect(searchField, findsOneWidget);
    expect(find.text('/plan'), findsOneWidget);
    expect(find.text('/goal'), findsOneWidget);
    expect(find.text('/compact'), findsOneWidget);
    expect(find.text('/permission'), findsOneWidget);
    expect(find.text('/feedback'), findsOneWidget);
    expect(find.text('/review'), findsOneWidget);
    expect(find.text('/rust'), findsOneWidget);
    expect(find.text('Attach images'), findsOneWidget);
    expect(find.text('Pick from gallery'), findsOneWidget);

    // Typing filters the roster locally (web search input).
    await tester.enterText(searchField, 'rust');
    await tester.pump();
    expect(find.text('/review'), findsNothing);
    expect(find.text('/plan'), findsNothing);
    expect(find.text('/rust'), findsOneWidget);
    await tester.enterText(searchField, '');
    await tester.pump();

    // Picking a host command lands the literal text like a skill does.
    await tester.tap(find.text('/plan'));
    await tester.pumpAndSettle();
    expect(find.text('Attach images'), findsNothing);

    final composerField = find
        .descendant(
          of: find.byType(ComposerBar),
          matching: find.byType(TextField),
        )
        .first;
    expect(tester.widget<TextField>(composerField).controller?.text, '/plan ');
  });

  testWidgets('composer model seat shows the current model and menu', (
    tester,
  ) async {
    final actions = <ChatAction>[];
    await _pump(
      tester,
      const ChatUiState(
        sessions: [SessionSummary(id: 's1', title: 'Alpha', blank: false)],
        selectedSessionId: 's1',
        models: _catalog,
      ),
      actions,
    );

    // Mobile trigger: a compact circle button (tooltip carries the model).
    expect(find.byTooltip('Model: GLM X'), findsOneWidget);

    await tester.tap(find.byTooltip('Model: GLM X'));
    await tester.pumpAndSettle();

    // Root pane: the Model / Effort row pair.
    expect(find.text('Model'), findsWidgets);
    expect(find.text('Effort'), findsOneWidget);

    // Drill into the model list and pick the other model.
    await tester.tap(find.text('Model').last);
    await tester.pumpAndSettle();
    expect(find.text('DeepSeek'), findsWidgets);

    await tester.tap(find.text('GLM Air'));
    await tester.pumpAndSettle();
    expect(
      actions,
      contains(
        const SelectModelSeat(
          ModelSelection(provider: 'deepseek', model: 'glm-air'),
        ),
      ),
    );
    // Sheet closes on selection.
    expect(find.text('GLM Air'), findsNothing);
  });

  testWidgets('pending images render chips with remove buttons', (
    tester,
  ) async {
    final actions = <ChatAction>[];
    await _pump(
      tester,
      _state(
        sessions: const [
          SessionSummary(id: 's1', title: 'Alpha', blank: false),
        ],
        selectedSessionId: 's1',
        pendingImages: const [
          PendingImage(
            id: 'file:///tmp/a.png',
            mediaType: 'image/png',
            base64Data: 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
            name: 'a.png',
            byteSize: 12,
          ),
        ],
      ),
      actions,
    );
    expect(find.text('a.png'), findsOneWidget);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Remove a.png'));
    await tester.pump();
    expect(actions, contains(const RemovePendingImage('file:///tmp/a.png')));
  });

  testWidgets('slash skill candidates filter and land /name text', (
    tester,
  ) async {
    final actions = <ChatAction>[];
    await _pump(
      tester,
      _state(
        sessions: const [
          SessionSummary(id: 's1', title: 'Alpha', blank: false),
        ],
        selectedSessionId: 's1',
        skills: const [
          SkillEntry(
            name: 'review',
            description: 'Review recent conversations',
          ),
          SkillEntry(name: 'rust', description: 'Rust toolchain hints'),
        ],
      ),
      actions,
    );

    final composerField = find
        .descendant(
          of: find.byType(ComposerBar),
          matching: find.byType(TextField),
        )
        .first;
    await tester.enterText(composerField, '/re');
    await tester.pump();
    expect(find.text('/review'), findsOneWidget);
    expect(find.text('/rust'), findsNothing);

    await tester.tap(find.text('/review'));
    await tester.pump();
    expect(
      tester.widget<TextField>(composerField).controller?.text,
      '/review ',
    );
  });

  testWidgets('outline groups turns, collapses, and expands all', (
    tester,
  ) async {
    final actions = <ChatAction>[];
    Future<void> pump([bool withOutline = false]) async {
      // Outline toggle is local state; pump once, then toggle.
      await _pump(
        tester,
        _state(
          sessions: const [
            SessionSummary(id: 's1', title: 'Alpha', blank: false),
          ],
          selectedSessionId: 's1',
          timeline: const [
            TimelineTurnBoundary(1),
            TimelineMessage(
              ChatMessage(
                id: 'm1',
                sessionId: 's1',
                role: MessageRole.user,
                text: 'first prompt',
              ),
            ),
            TimelineToolCall(
              id: 'call-1',
              name: 'bash',
              status: ToolRunStatus.completed,
            ),
            TimelineToolCall(
              id: 'call-2',
              name: 'bash',
              status: ToolRunStatus.failed,
            ),
            TimelineToolCall(
              id: 'call-3',
              name: 'edit',
              status: ToolRunStatus.completed,
            ),
          ],
        ),
        actions,
      );
      if (withOutline) {
        await tester.tap(find.byTooltip('Outline'));
        await tester.pumpAndSettle();
      }
    }

    await pump(true);
    expect(find.text('▾ Turn 1 · 1 messages · 3 tools'), findsOneWidget);
    expect(find.text('“first prompt”'), findsOneWidget);
    expect(find.text('bash 1✓ 1✗ · edit 1✓'), findsOneWidget);

    // Collapse hides the group rows.
    await tester.tap(find.text('▾ Turn 1 · 1 messages · 3 tools'));
    await tester.pumpAndSettle();
    expect(find.text('▸ Turn 1 · 1 messages · 3 tools'), findsOneWidget);
    // The header echo stays; the collapsed body rows disappear.
    expect(find.text('first prompt', findRichText: true), findsNothing);

    // Expand all restores them.
    await tester.tap(find.text('Expand all'));
    await tester.pumpAndSettle();
    expect(find.text('first prompt', findRichText: true), findsOneWidget);

    // Outline off returns the plain ledger.
    await tester.tap(find.byTooltip('Outline'));
    await tester.pumpAndSettle();
    expect(find.text('Turn 1'), findsOneWidget);
  });

  testWidgets('attachment placeholder shows metadata and retries', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1280);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final loaded = <AttachmentRef>[];
    const ref = AttachmentRef(
      attachmentId: 'att-1',
      mediaType: 'image/png',
      bytes: 20480,
      width: 640,
      height: 480,
      name: 'screenshot.png',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ChatScreen(
          uiState: _state(
            sessions: const [
              SessionSummary(id: 's1', title: 'Alpha', blank: false),
            ],
            selectedSessionId: 's1',
            timeline: const [
              TimelineMessage(
                ChatMessage(
                  id: 'm1',
                  sessionId: 's1',
                  role: MessageRole.user,
                  text: 'shot',
                  images: [ref],
                ),
              ),
            ],
          ),
          onAction: (_) {},
          loadAttachment: (sessionId, ref) async {
            loaded.add(ref);
            return null; // fail to decode → placeholder
          },
        ),
      ),
    );

    expect(
      find.text('image 640×480 (20480 bytes) · screenshot.png'),
      findsOneWidget,
    );
    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(loaded, hasLength(2));
  });

  testWidgets(
    'plan pill renders only the active target and exits via /plan off',
    (tester) async {
      final actions = <ChatAction>[];
      Future<void> pump(bool active, bool pending) async {
        tester.view.physicalSize = const Size(800, 1280);
        tester.view.devicePixelRatio = 1.0;
        await tester.pumpWidget(
          MaterialApp(
            home: ChatScreen(
              uiState: ChatUiState(
                sessions: const [
                  SessionSummary(id: 's1', title: 'Alpha', blank: false),
                ],
                selectedSessionId: 's1',
                plan: PlanState(active: active, pending: pending),
              ),
              onAction: actions.add,
            ),
          ),
        );
      }

      // Target on (settled active, or switching on): the warn pill shows.
      await pump(true, false);
      expect(find.text('Plan'), findsOneWidget);
      // Exiting executes /plan off — never a `/plan` toggle.
      await tester.tap(find.text('Plan'));
      await tester.pump();
      expect(actions, contains(const SendPrompt('/plan off')));
      expect(actions.where((a) => a == const SendPrompt('/plan')), isEmpty);

      await pump(false, true);
      expect(find.text('Plan'), findsOneWidget);

      // Target off (settled off, or switching off): nothing renders.
      await pump(true, true);
      expect(find.text('Plan'), findsNothing);
      await pump(false, false);
      expect(find.text('Plan'), findsNothing);
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    },
  );

  testWidgets('timeline follows streaming output while pinned', (tester) async {
    tester.view.physicalSize = const Size(800, 1280);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    String tail(int lines) => List<String>.generate(
      lines,
      (i) => 'stream line $i keeps growing',
    ).join('\n');
    ChatUiState stateFor(String assistantText, {bool withFollowUp = false}) =>
        ChatUiState(
          sessions: const [
            SessionSummary(id: 's1', title: 'Alpha', blank: false),
          ],
          selectedSessionId: 's1',
          timeline: [
            const TimelineTurnBoundary(1),
            const TimelineMessage(
              ChatMessage(
                id: 'm1',
                sessionId: 's1',
                role: MessageRole.user,
                text: 'go',
              ),
            ),
            TimelineMessage(
              ChatMessage(
                id: 'm2',
                sessionId: 's1',
                role: MessageRole.assistant,
                text: assistantText,
                streaming: true,
              ),
            ),
            if (withFollowUp)
              const TimelineMessage(
                ChatMessage(
                  id: 'm3',
                  sessionId: 's1',
                  role: MessageRole.user,
                  text: 'follow-up',
                ),
              ),
          ],
        );
    Widget host(ChatUiState ui) => MaterialApp(
      home: ChatScreen(uiState: ui, onAction: (_) {}),
    );

    Finder timelineList() => find.descendant(
      of: find.byType(ChatPanel),
      matching: find.byType(ListView),
    );
    ScrollPosition position() => tester
        .state<ScrollableState>(
          find
              .descendant(of: timelineList(), matching: find.byType(Scrollable))
              .first,
        )
        .position;

    // Initial mount lands at the bottom (web restore-or-bottom).
    await tester.pumpWidget(host(stateFor(tail(60))));
    await tester.pump();
    expect(position().maxScrollExtent, greaterThan(0));
    expect(position().pixels, position().maxScrollExtent);

    // Streaming growth follows while pinned. The driven glide's ticker
    // establishes its start at the first tick, so frames advance in two
    // steps; the streaming sweep repeats forever (no pumpAndSettle).
    Future<void> settle() async {
      await tester.pump(const Duration(milliseconds: 40));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 50));
    }

    await tester.pumpWidget(host(stateFor(tail(120))));
    await settle();
    expect(position().pixels, position().maxScrollExtent);

    // The reader leaves the bottom: pinning releases. The drag stays small
    // so the lazy tail stays materialized and the extent estimate honest.
    await tester.drag(timelineList(), const Offset(0, 150));
    await settle();
    expect(position().maxScrollExtent - position().pixels, greaterThan(24));

    // Growth while unpinned does NOT follow (the reader keeps their place).
    final readerOffset = position().pixels;
    await tester.pumpWidget(host(stateFor(tail(121))));
    await settle();
    expect(position().pixels, readerOffset);

    // A new trailing user message force-scrolls (own words must be visible).
    await tester.pumpWidget(host(stateFor(tail(121), withFollowUp: true)));
    await settle();
    expect(position().pixels, position().maxScrollExtent);
  });

  group('compact drawer layout', () {
    Future<void> pumpCompact(
      WidgetTester tester,
      ChatUiState uiState,
      List<ChatAction> actions,
    ) {
      tester.view.physicalSize = const Size(600, 1280);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      return tester.pumpWidget(
        MaterialApp(
          home: ChatScreen(uiState: uiState, onAction: actions.add),
        ),
      );
    }

    testWidgets('session panel hides behind the drawer on narrow screens', (
      tester,
    ) async {
      final actions = <ChatAction>[];
      await pumpCompact(
        tester,
        _state(
          sessions: const [
            SessionSummary(id: 's1', title: 'Alpha', blank: false),
          ],
          selectedSessionId: 's1',
        ),
        actions,
      );

      // No stacked 160px strip: the panel content is offstage in the drawer.
      expect(find.byTooltip('Search sessions'), findsNothing);
      expect(find.text('DeepSeek Harness'), findsOneWidget);

      await tester.tap(find.byTooltip('Open navigation menu'));
      await tester.pumpAndSettle();
      expect(find.text('New session'), findsOneWidget);
      expect(find.byTooltip('Search sessions'), findsOneWidget);
      expect(find.text('Alpha'), findsOneWidget);
    });

    testWidgets('selecting a session closes the drawer and dispatches', (
      tester,
    ) async {
      final actions = <ChatAction>[];
      await pumpCompact(
        tester,
        _state(
          sessions: const [
            SessionSummary(id: 's1', title: 'Alpha', blank: false),
            SessionSummary(id: 's2', title: 'Beta', blank: false),
          ],
          selectedSessionId: 's1',
        ),
        actions,
      );

      await tester.tap(find.byTooltip('Open navigation menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Beta'));
      await tester.pumpAndSettle();

      expect(actions, contains(const SelectSession('s2')));
      expect(find.byTooltip('Search sessions'), findsNothing); // drawer closed
    });

    testWidgets('rail collapse shrinks the pane, not the chat', (tester) async {
      final actions = <ChatAction>[];
      await _pump(
        tester,
        _state(
          sessions: const [
            SessionSummary(id: 's1', title: 'Alpha', blank: false),
          ],
          selectedSessionId: 's1',
        ),
        actions,
      );

      final chatFinder = find.byType(ChatPanel);
      final wideWidth = tester.getSize(chatFinder).width;
      expect(find.byTooltip('Search sessions'), findsOneWidget);

      await tester.tap(find.byTooltip('Collapse sidebar'));
      await tester.pumpAndSettle();

      // The pane really gives its width back to the chat column.
      expect(tester.getSize(chatFinder).width, greaterThan(wideWidth + 200));
      // The rail keeps a search entry but no capsule field.
      expect(find.byTooltip('Search sessions'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(SessionPanel),
          matching: find.byType(TextField),
        ),
        findsNothing,
      );
      // Rail still offers session shortcuts.
      expect(find.byTooltip('Alpha'), findsOneWidget);

      await tester.tap(find.byTooltip('Alpha'));
      await tester.pumpAndSettle();
      expect(actions, contains(const SelectSession('s1')));
    });

    testWidgets('two-pane keeps the docked panel at wide widths', (
      tester,
    ) async {
      final actions = <ChatAction>[];
      await _pump(
        tester,
        _state(
          sessions: const [
            SessionSummary(id: 's1', title: 'Alpha', blank: false),
          ],
          selectedSessionId: 's1',
        ),
        actions,
      );
      expect(find.byTooltip('Search sessions'), findsOneWidget);
      expect(find.byTooltip('Open navigation menu'), findsNothing);
    });
  });
}
