/// ChatScreen widget parity tests — the legacy Compose screen behavior
/// this port must keep: banner labels, session list rules, timeline rows,
/// question drafts, queue actions, composer modes, and the outline.
library;

import 'package:domain/model/attachment.dart';
import 'package:domain/model/chat_message.dart';
import 'package:domain/model/connection_state.dart';
import 'package:domain/model/jobs.dart';
import 'package:domain/model/plan.dart';
import 'package:domain/model/prompt.dart';
import 'package:domain/model/session.dart';
import 'package:domain/model/skills.dart';
import 'package:domain/model/timeline_item.dart';
import 'package:domain/model/workspace.dart';
import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_test/flutter_test.dart';

import 'package:app/ui/chat/chat_screen.dart';
import 'package:app/ui/chat/chat_ui_state.dart';

ChatUiState _state({
  ConnectionPhase phase = ConnectionPhase.connected,
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
    pendingImages: pendingImages,
    skills: skills,
    isSending: isSending,
    errorMessage: errorMessage,
  );
}

Future<void> _pump(
  WidgetTester tester,
  ChatUiState uiState,
  List<ChatAction> actions,
) {
  // Phone-scale logical surface so both panes and rows lay out naturally.
  tester.view.physicalSize = const Size(800, 1280);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  return tester.pumpWidget(
    MaterialApp(
      home: ChatScreen(uiState: uiState, onAction: actions.add),
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
    expect(find.text('Alpha ●'), findsOneWidget);
    expect(find.text('Beta'), findsOneWidget);
    // Blank row + the panel's own "New session" button.
    expect(find.text('New session'), findsNWidgets(2));
    await tester.tap(find.text('Beta'));
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
        ],
        searchResults: const [
          SessionSearchResult(sessionId: 's9', snippet: '…snippet…'),
        ],
      ),
      actions,
    );
    expect(find.text('Search: …snippet…'), findsOneWidget);
    await tester.tap(find.text('Search: …snippet…'));
    await tester.pump();
    expect(actions, contains(const SelectSession('s9')));

    final searchField = find
        .descendant(
          of: find.byType(SessionPanel),
          matching: find.byType(TextField),
        )
        .first;
    await tester.enterText(searchField, 'hello');
    await tester.pump();
    await tester.tap(find.text('Go'));
    await tester.pump();
    expect(actions.last, const SearchSessions('hello'));
  });

  testWidgets('timeline renders rows and dispatches approvals', (tester) async {
    final actions = <ChatAction>[];
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
          TimelineJobs(
            jobs: [
              JobView(
                id: 'j1',
                kind: 'build',
                label: 'assemble',
                status: JobStatus.running,
              ),
            ],
          ),
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
    expect(find.text('Background jobs'), findsOneWidget);
    expect(find.text('build · assemble · running'), findsOneWidget);

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
    expect(find.text('Send'), findsNothing);

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

  testWidgets('composer sends queue by default and steer while running', (
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

    final composerField = find
        .descendant(
          of: find.byType(ComposerBar),
          matching: find.byType(TextField),
        )
        .first;
    await tester.enterText(composerField, 'hello world');
    await tester.pump();
    await tester.tap(find.text('Send'));
    await tester.pump();
    expect(
      actions,
      contains(const SendPrompt('hello world', mode: PromptMode.queue)),
    );

    // Idle session: Steer stays disabled even when picked.
    final steerChip = find.widgetWithText(OutlinedButton, 'Steer');
    expect(tester.widget<OutlinedButton>(steerChip).onPressed, isNull);
  });

  testWidgets('running session enables steer mode and placeholder', (
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

    expect(find.text('Queue'), findsOneWidget);
    expect(find.text('Message DeepSeek Harness'), findsOneWidget);

    await tester.tap(find.text('Steer'));
    await tester.pump();
    expect(find.text('Steer the running turn'), findsOneWidget);

    final composerField = find
        .descendant(
          of: find.byType(ComposerBar),
          matching: find.byType(TextField),
        )
        .first;
    await tester.enterText(composerField, 'nudge');
    await tester.pump();
    await tester.tap(find.text('Send'));
    await tester.pump();
    expect(
      actions,
      contains(const SendPrompt('nudge', mode: PromptMode.steer)),
    );

    // Stop cancels the running turn.
    await tester.tap(find.text('Stop'));
    await tester.pump();
    expect(actions, contains(const CancelTurnAction()));
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
        await tester.tap(find.text('Outline: off'));
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
    await tester.tap(find.text('Outline: on'));
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

  testWidgets('plan chip reflects active and pending states', (tester) async {
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
            onAction: (_) {},
          ),
        ),
      );
    }

    await pump(true, false);
    expect(find.text('Plan: active'), findsOneWidget);

    await pump(false, true);
    expect(find.text('Plan: switching…'), findsOneWidget);

    await pump(false, false);
    expect(find.text('Plan: off'), findsOneWidget);
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}
