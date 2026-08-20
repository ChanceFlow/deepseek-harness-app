/// ChatScreen widget parity tests — the legacy Compose screen behavior
/// this port must keep: banner labels, session list rules, timeline rows,
/// question drafts, queue actions, composer modes, and the outline.
library;

import 'package:domain/model/attachment.dart';
import 'package:domain/model/chat_message.dart';
import 'package:domain/model/context_pressure.dart';
import 'package:domain/model/goal.dart';
import 'package:domain/model/model_catalog.dart';
import 'package:domain/model/skills.dart';
import 'package:domain/model/jobs.dart';
import 'package:domain/model/plan.dart';
import 'package:domain/model/prompt.dart';
import 'package:domain/model/session.dart';
import 'package:domain/model/timeline_item.dart';
import 'package:domain/model/workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'dart:async';

import 'package:app/config.dart';
import 'package:app/di/providers.dart';
import 'package:app/ui/chat/chat_screen.dart';
import 'package:app/ui/chat/chat_ui_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n_app.dart';

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
  List<JobView> jobs = const <JobView>[],
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
        // Family seams keyed by the seed backend's URL (the store seeds
        // from kDshBaseUrl).
        dshRpcClientProvider(Uri.parse(kDshBaseUrl))
            .overrideWithValue(_FakeRpc()),
        dshEventSocketProvider(Uri.parse(kDshBaseUrl))
            .overrideWithValue(_NeverSocket()),
      ],
      child: l10nApp(
        home: ChatScreen(uiState: uiState, onAction: actions.add),
      ),
    ),
  );
}

void main() {
  testWidgets('chat surface shows no persistent connection status', (
    tester,
  ) async {
    final actions = <ChatAction>[];
    await _pump(
      tester,
      _state(
        sessions: const [SessionSummary(id: 's1', title: 'Alpha')],
      ),
      actions,
    );
    // Connection state and host version live in the Settings Backends
    // rows, not as a persistent line on the chat surface.
    expect(find.textContaining('connected'), findsNothing);
    expect(find.textContaining('connecting'), findsNothing);
    expect(find.textContaining('v1.2.3'), findsNothing);
  });

  testWidgets(
    'session list shows titles, hides subagents and unselected blanks',
    (tester) async {
      final actions = <ChatAction>[];
      await _pump(
        tester,
        _state(
          sessions: const [
            SessionSummary(
              id: 's1',
              title: 'Alpha',
              running: true,
              blank: false,
            ),
            SessionSummary(id: 's2', title: 'Beta', blank: false),
            // Web tree.ts sessionVisible: the subagent child (s4) browses
            // through its parent's catalog; among blank sessions only the
            // selected one (s5) shows.
            SessionSummary(id: 's3', blank: true),
            SessionSummary(
              id: 's4',
              title: 'Child',
              blank: false,
              origin: 'subagent',
            ),
            SessionSummary(id: 's5', blank: true),
          ],
          selectedSessionId: 's5',
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
      // The subagent child never becomes a top-level row.
      expect(panelText('Child'), findsNothing);
      // The selected blank row (s5) + the panel's "New session" button; the
      // unselected blank (s3) stays hidden.
      expect(find.text('New session'), findsNWidgets(2));
      await tester.tap(panelText('Beta'));
      await tester.pump();
      expect(actions, contains(const SelectSession('s2')));

      // Rail form: avatars follow the same rule — root sessions and the
      // selected blank keep their seat; the subagent child and the
      // unselected blank never get one.
      await tester.tap(find.byTooltip('Collapse sidebar'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Alpha'), findsOneWidget);
      expect(find.byTooltip('s5'), findsOneWidget);
      expect(find.byTooltip('Child'), findsNothing);
      expect(find.byTooltip('s3'), findsNothing);
    },
  );

  testWidgets('sessions group under workspaces by account membership', (
    tester,
  ) async {
    final actions = <ChatAction>[];
    await _pump(
      tester,
      _state(
        sessions: const [
          SessionSummary(id: 's1', title: 'Alpha', blank: false),
          SessionSummary(id: 's2', title: 'Beta', blank: false),
          SessionSummary(id: 's9', title: 'Loose', blank: false),
        ],
        workspaces: const [
          // Web groupByWorkspace: membership is the Workspace's sessionIds
          // (the wire session summary carries no workspace field); members
          // render in the account's stored order.
          WorkspaceSummary(
            workspaceId: 'w1',
            path: '/tmp/proj',
            title: 'proj',
            sessionIds: ['s2', 's1'],
          ),
        ],
        selectedSessionId: 's1',
      ),
      actions,
    );

    Finder panelText(String text) => find.descendant(
      of: find.byType(SessionPanel),
      matching: find.text(text),
    );
    // The selected session's account auto-expands: both members show
    // under the workspace header. The Ungrouped bucket stays folded until
    // tapped (only the current group auto-expands).
    expect(panelText('proj'), findsOneWidget);
    expect(panelText('Alpha'), findsOneWidget);
    expect(panelText('Beta'), findsOneWidget);
    expect(panelText('Ungrouped'), findsOneWidget);
    expect(panelText('Loose'), findsNothing);
    await tester.tap(panelText('Ungrouped'));
    await tester.pumpAndSettle();
    // The session no account names trails in the Ungrouped bucket.
    expect(panelText('Loose'), findsOneWidget);
    // A no-account group header only renders when it has visible members.
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
            sessionIds: ['s1'],
          ),
        ],
        selectedSessionId: 's1',
      ),
      actions,
    );
    expect(panelText('Ungrouped'), findsNothing);
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

  testWidgets('app bar shows session title, actions', (tester) async {
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
      expect(find.text('Session recall'), findsOneWidget);
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
    // Web tool row: figma variant title + ARGS-derived summary; the
    // settled result lives behind the expand affordance.
    expect(find.text('Bash'), findsOneWidget);
    expect(find.text('ls -la'), findsOneWidget);
    expect(find.text('README.md'), findsNothing);

    await tester.tap(find.text('Bash'));
    await tester.pumpAndSettle();
    expect(find.text('README.md'), findsOneWidget);
    // Expanded details ride the IN/OUT card: gutter labels beside the
    // arguments and the settled result.
    expect(find.text('Input'), findsOneWidget);
    expect(find.text('Output'), findsOneWidget);
    // Approval takes over the composer seat: web takeover card.
    expect(find.text('Waiting for approval'), findsOneWidget);
    expect(find.text('Would run a command'), findsOneWidget);
    expect(
      find.text('Tool bash requests privileged execution'),
      findsOneWidget,
    );
    expect(find.text('Message the agent'), findsNothing);
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

  testWidgets('queue dock: single row, inline edit, steer gating', (
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
              // Only queued-placement rows ride the dock (web rule);
              // context material is not a queued message.
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

    // Single queued message renders directly and carries the queue glyph
    // (no count header).
    expect(find.text('first'), findsOneWidget);
    expect(find.text('context only'), findsNothing);
    expect(find.textContaining('queued messages'), findsNothing);

    // Remove dispatches.
    await tester.tap(find.byTooltip('Remove queued message'));
    await tester.pump();
    expect(
      actions,
      contains(
        const UpdateQueueAction(itemId: 'q1', kind: QueueUpdateKind.remove),
      ),
    );

    // Steer needs the running window: the idle session disables it.
    await tester.tap(find.byTooltip('Steer'));
    await tester.pump();
    expect(
      actions.where(
        (action) =>
            action is UpdateQueueAction && action.kind == QueueUpdateKind.steer,
      ),
      isEmpty,
    );

    // Edit swaps the preview for the inline editor; save dispatches the
    // revision.
    await tester.tap(find.byTooltip('Edit queued message'));
    await tester.pump();
    // The inline editor takes the preview's seat (seeded with the text).
    expect(
      find.descendant(
        of: find.byType(QueueDock),
        matching: find.byType(TextField),
      ),
      findsOneWidget,
    );
    await tester.enterText(
      find.descendant(
        of: find.byType(QueueDock),
        matching: find.byType(TextField),
      ),
      'revised',
    );
    await tester.tap(find.byTooltip('Save queued message'));
    await tester.pump();
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

  testWidgets('multiple queued messages collapse behind the count header', (
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
                placement: QueuePlacement.queued,
                text: 'second',
              ),
            ],
          ),
        ],
      ),
      actions,
    );

    // Collapsed by default: the count header, not the rows.
    expect(find.text('2 queued messages'), findsOneWidget);
    expect(find.text('first'), findsNothing);
    expect(find.text('second'), findsNothing);

    await tester.tap(find.text('2 queued messages'));
    await tester.pumpAndSettle();
    expect(find.text('first'), findsOneWidget);
    expect(find.text('second'), findsOneWidget);

    // Running session: steer dispatches.
    await tester.tap(find.byTooltip('Steer').first);
    await tester.pump();
    expect(
      actions,
      contains(
        const UpdateQueueAction(itemId: 'q1', kind: QueueUpdateKind.steer),
      ),
    );
  });

  testWidgets('question card collects options, custom text, skip, submit', (
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

    // Nothing drafted yet: Submit stays disabled.
    final submitButton = find.widgetWithText(FilledButton, 'Submit').first;
    expect(tester.widget<FilledButton>(submitButton).onPressed, isNull);

    // A single-select tap enables Submit and, as the last question, does not
    // advance the pager (progress stays 1 / 1).
    await tester.tap(find.text('yes'));
    await tester.pump();
    expect(find.text('1 / 1'), findsOneWidget);
    expect(tester.widget<FilledButton>(submitButton).onPressed, isNotNull);

    await tester.tap(submitButton);
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

    // Skip on the last question answers with empty selections.
    actions.clear();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Skip'));
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
  });

  testWidgets('question card pages through a batch with a recommended badge', (
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
            requestId: 'rpc-3',
            questions: [
              QuestionItem(
                id: 'q1',
                question: 'Pick a target',
                options: ['Code（推荐）', 'Docs'],
                optionDescriptions: {'Docs': 'documentation'},
              ),
              QuestionItem(
                id: 'q2',
                question: 'Anything else?',
                multiSelect: true,
                options: ['a', 'b'],
              ),
            ],
          ),
        ],
      ),
      actions,
    );

    // First page: the recommended suffix renders as a badge, the option
    // number chip leads, and the pager reads 1 / 2.
    expect(find.text('Pick a target'), findsOneWidget);
    expect(find.text('1 / 2'), findsOneWidget);
    expect(find.text('Recommended'), findsOneWidget);
    expect(find.text('documentation'), findsOneWidget);
    expect(find.text('Code'), findsOneWidget);
    expect(find.text('Code（推荐）'), findsNothing);

    // Single-select choose on a non-last question advances to page 2.
    await tester.tap(find.text('Code'));
    await tester.pump();
    expect(find.text('2 / 2'), findsOneWidget);
    expect(find.text('Anything else?'), findsOneWidget);

    // Multi-select keeps both options; custom text preserves selections.
    await tester.tap(find.text('a'));
    await tester.pump();
    await tester.tap(find.text('b'));
    await tester.pump();
    final customField = find.descendant(
      of: find.byType(QuestionRow),
      matching: find.byType(TextField),
    );
    await tester.enterText(customField, 'extra');
    await tester.pump();

    await tester.tap(find.widgetWithText(FilledButton, 'Submit'));
    await tester.pump();
    expect(
      actions,
      contains(
        const AnswerQuestionAction(
          requestId: 'rpc-3',
          answers: [
            QuestionAnswer(questionId: 'q1', selectedOptions: ['Code（推荐）']),
            QuestionAnswer(
              questionId: 'q2',
              selectedOptions: ['a', 'b'],
              customText: 'extra',
            ),
          ],
        ),
      ),
    );
  });

  testWidgets('optionless question answers through the free-form field', (
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
            requestId: 'rpc-4',
            questions: [
              QuestionItem(
                id: 'q1',
                question: 'Describe it',
                detail: 'details here',
              ),
            ],
          ),
        ],
      ),
      actions,
    );

    expect(find.text('Describe it'), findsOneWidget);
    expect(find.text('details here'), findsOneWidget);
    final submitButton = find.widgetWithText(FilledButton, 'Submit');
    expect(tester.widget<FilledButton>(submitButton).onPressed, isNull);

    final field = find.descendant(
      of: find.byType(QuestionRow),
      matching: find.byType(TextField),
    );
    await tester.enterText(field, 'my answer');
    await tester.pump();
    await tester.tap(submitButton);
    await tester.pump();
    expect(
      actions,
      contains(
        const AnswerQuestionAction(
          requestId: 'rpc-4',
          answers: [
            QuestionAnswer(
              questionId: 'q1',
              selectedOptions: [],
              customText: 'my answer',
            ),
          ],
        ),
      ),
    );
  });

  testWidgets('question card dismisses the whole batch', (tester) async {
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
            requestId: 'rpc-5',
            questions: [
              QuestionItem(
                id: 'q1',
                question: 'Pick',
                options: ['a', 'b'],
              ),
            ],
          ),
        ],
      ),
      actions,
    );

    await tester.tap(find.byTooltip('Dismiss all questions'));
    await tester.pump();
    expect(
      actions,
      contains(const DismissQuestionAction(requestId: 'rpc-5')),
    );
  });

  testWidgets('plan review renders a decision card with approve/decline/discuss',
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
            TimelineQuestionRequest(
              requestId: 'rpc-6',
              questions: [
                QuestionItem(
                  id: 'plan-1',
                  question: 'Approve this plan?',
                  detail: '## Plan\n\nStep one.',
                  options: ['Approve', 'Keep planning'],
                  intent: QuestionIntent(
                    kind: 'plan-review',
                    approve: 'Approve',
                  ),
                ),
              ],
            ),
          ],
        ),
        actions,
      );

      // The strip header reads "Plan review"; the plan renders as markdown.
      expect(find.text('Plan review'), findsOneWidget);
      expect(find.textContaining('Step one'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Approve'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Refuse'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Chat about it'), findsOneWidget);

      // Approve answers with the asker's approve label.
      await tester.tap(find.widgetWithText(FilledButton, 'Approve'));
      await tester.pump();
      expect(
        actions,
        contains(
          const AnswerQuestionAction(
            requestId: 'rpc-6',
            answers: [
              QuestionAnswer(
                questionId: 'plan-1',
                selectedOptions: ['Approve'],
              ),
            ],
          ),
        ),
      );

      // Decline answers with the other option label.
      actions.clear();
      await tester.tap(find.widgetWithText(OutlinedButton, 'Refuse'));
      await tester.pump();
      expect(
        actions,
        contains(
          const AnswerQuestionAction(
            requestId: 'rpc-6',
            answers: [
              QuestionAnswer(
                questionId: 'plan-1',
                selectedOptions: ['Keep planning'],
              ),
            ],
          ),
        ),
      );

      // Discuss dismisses the request without answering.
      actions.clear();
      await tester.tap(find.widgetWithText(TextButton, 'Chat about it'));
      await tester.pump();
      expect(
        actions,
        contains(const DismissQuestionAction(requestId: 'rpc-6')),
      );
    });

  testWidgets('a non-binary question batch stays in the generic flow', (
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
            requestId: 'rpc-7',
            questions: [
              QuestionItem(
                id: 'plan-1',
                question: 'Pick one',
                options: ['Approve', 'Maybe', 'No'],
                intent: QuestionIntent(
                  kind: 'plan-review',
                  approve: 'Approve',
                ),
              ),
            ],
          ),
        ],
      ),
      actions,
    );

    // Three options: the plan-review card cannot express them, so the
    // generic card owns the request.
    expect(find.text('Plan review'), findsNothing);
    expect(find.text('Pick one'), findsOneWidget);
    expect(find.text('Approve'), findsOneWidget);
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

  testWidgets('context ring prefers the projected sample for occupancy', (
    tester,
  ) async {
    final actions = <ChatAction>[];
    await _pump(
      tester,
      const ChatUiState(
        sessions: [SessionSummary(id: 's1', title: 'Alpha', blank: false)],
        selectedSessionId: 's1',
        contextPressure: ContextPressure(
          pressureTokens: 5000,
          projectedTokens: 9000,
          contextWindow: 30000,
        ),
      ),
      actions,
    );

    // Web StatsLine contextOccupancy: the numerator is projectedTokens —
    // the sample carried forward over the surface's movement since — so
    // the ring reads 30% (9000/30000), not the stale sample's 17%.
    expect(find.bySemanticsLabel('30% of context used'), findsOneWidget);
    expect(find.bySemanticsLabel('17% of context used'), findsNothing);
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

    // A ready draft while running surfaces the explicit send control
    // beside Stop; soft keyboards have no Enter-as-send (the keyboard
    // action is newline), so the control queues the draft (web Enter
    // semantics, busy preference default).
    final composerField = find
        .descendant(
          of: find.byType(ComposerBar),
          matching: find.byType(TextField),
        )
        .first;
    await tester.enterText(composerField, 'queued while running');
    await tester.pump();
    expect(find.byTooltip('Send'), findsOneWidget);
    await tester.tap(find.byTooltip('Send'));
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

  testWidgets('a submission with images refuses non-image commands', (
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

    final composerField = find
        .descendant(
          of: find.byType(ComposerBar),
          matching: find.byType(TextField),
        )
        .first;
    await tester.enterText(composerField, '/compact');
    await tester.pump();
    await tester.tap(find.byTooltip('Send'));
    await tester.pump();

    // Nothing was sent; the refusal surfaced and the draft and image
    // chips stay in place (web envelope policy).
    expect(
      actions.where((a) => a is SendPrompt || a is CommandImageRefusal),
      contains(
        isA<CommandImageRefusal>().having(
          (a) => a.message,
          'message',
          contains('/compact does not accept image attachments'),
        ),
      ),
    );
    expect(
      actions.whereType<SendPrompt>(),
      isEmpty,
    );
    expect(find.text('a.png'), findsOneWidget);
    expect(
      tester.widget<TextField>(composerField).controller?.text,
      '/compact',
    );
  });

  testWidgets('a submission with images still sends image-accepting commands',
      (tester) async {
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

    final composerField = find
        .descendant(
          of: find.byType(ComposerBar),
          matching: find.byType(TextField),
        )
        .first;
    await tester.enterText(composerField, '/goal Ship the MVP');
    await tester.pump();
    await tester.tap(find.byTooltip('Send'));
    await tester.pump();

    expect(
      actions,
      contains(const SendPrompt('/goal Ship the MVP', mode: PromptMode.queue)),
    );
    expect(
      actions.whereType<CommandImageRefusal>(),
      isEmpty,
    );
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

  testWidgets('outline scrolls lazily to later turns', (tester) async {
    final actions = <ChatAction>[];
    final items = <TimelineItem>[
      for (var turn = 1; turn <= 5; turn++) ...[
        TimelineTurnBoundary(turn),
        TimelineMessage(
          ChatMessage(
            id: 'm$turn',
            sessionId: 's1',
            role: MessageRole.user,
            text: 'prompt $turn',
          ),
        ),
      ],
    ];
    await _pump(
      tester,
      _state(
        sessions: const [
          SessionSummary(id: 's1', title: 'Alpha', blank: false),
        ],
        selectedSessionId: 's1',
        timeline: items,
      ),
      actions,
    );
    await tester.tap(find.byTooltip('Outline'));
    await tester.pumpAndSettle();

    // Shrink the viewport height so the outline must actually scroll;
    // keep the width wide enough for the app bar title.
    tester.view.physicalSize = const Size(600, 320);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpAndSettle();

    // The first turn header is visible; later turns are reachable by
    // scrolling the outline's own scroll surface.
    expect(find.textContaining('▾ Turn 1'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('prompt 5', findRichText: true),
      200,
      scrollable: find.descendant(
        of: find.byType(CustomScrollView),
        matching: find.byType(Scrollable),
      ),
    );
    expect(find.text('prompt 5', findRichText: true), findsOneWidget);
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
      ProviderScope(
        child: l10nApp(
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
          ProviderScope(
            child: l10nApp(
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
    Widget host(ChatUiState ui) => ProviderScope(
      child: l10nApp(
        home: ChatScreen(uiState: ui, onAction: (_) {}),
      ),
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
    // Streaming assistant text ends in the blinking caret, not the
    // pre-first-token loader.
    expect(find.byKey(const ValueKey('streaming-caret')), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

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
        ProviderScope(
          child: l10nApp(
            home: ChatScreen(uiState: uiState, onAction: actions.add),
          ),
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
      expect(find.text('DSH Mobile'), findsOneWidget);

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
