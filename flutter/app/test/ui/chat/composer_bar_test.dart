/// Composer mobile-parity tests — the keyboard newline gesture,
/// send-while-running delivery mode, and draft persistence, all driven
/// through the real ChatScreen entry path.
library;

import 'dart:io';

import 'package:app/local_state/local_state_store.dart';
import 'package:domain/model/chat_message.dart';
import 'package:domain/model/prompt.dart';
import 'package:domain/model/session.dart';
import 'package:domain/model/timeline_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/ui/chat/chat_screen.dart';
import 'package:app/ui/chat/chat_ui_state.dart';
import 'package:app/ui/chat/chat_local_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'chat_local_state_fake.dart';
import '../../l10n_app.dart';

const SessionSummary _session = SessionSummary(
  id: 's1',
  title: 'Draft session',
  blank: false,
);

Future<void> _pump(
  WidgetTester tester,
  ChatUiState uiState,
  List<ChatAction> actions, {
  FakeChatLocalState? localState,
}) {
  tester.view.physicalSize = const Size(800, 1280);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  return tester.pumpWidget(
    ProviderScope(
      child: l10nApp(
        home: ChatScreen(
          uiState: uiState,
          onAction: actions.add,
          localState: localState,
        ),
      ),
    ),
  );
}

void main() {
  test('store-backed seam reads the shared busy-send key and drafts', () async {
    final dir = await Directory.systemTemp.createTemp('chat-local-state');
    addTearDown(() => dir.delete(recursive: true));
    final store = LocalStateStore(File('${dir.path}/local_state.json'));
    await store.load();
    final seam = StoreChatLocalState(store);

    // Default and stored forms of the shared preference key.
    expect(await seam.busyEnterBehavior(), 'queue');
    store.write(chatBusyEnterBehaviorKey, 'steer');
    expect(await seam.busyEnterBehavior(), 'steer');

    final session = seam.forSession('s1');
    await session.writeDraft('half-written');
    expect(await session.readDraft(), 'half-written');
    // An empty draft is the cleared marker: the key goes away.
    await session.writeDraft('');
    expect(await session.readDraft(), isNull);
  });

  testWidgets('keyboard action key does not submit the draft', (tester) async {
    final actions = <ChatAction>[];
    await _pump(
      tester,
      const ChatUiState(sessions: [_session], selectedSessionId: 's1'),
      actions,
    );
    await tester.enterText(find.byType(TextField), 'hello');

    await tester.testTextInput.receiveAction(TextInputAction.newline);
    await tester.pump();

    expect(actions.whereType<SendPrompt>(), isEmpty);
  });

  testWidgets('send button sends, clears, and clears the saved draft', (
    tester,
  ) async {
    final actions = <ChatAction>[];
    final localState = FakeChatLocalState();
    await _pump(
      tester,
      const ChatUiState(sessions: [_session], selectedSessionId: 's1'),
      actions,
      localState: localState,
    );

    await tester.enterText(find.byType(TextField), 'hello');
    await tester.pump();
    expect(localState.values[chatDraftKey('s1')], 'hello');

    await tester.tap(find.byTooltip('Send'));
    await tester.pump();

    expect(
      actions,
      contains(const SendPrompt('hello', mode: PromptMode.queue)),
    );
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).controller.text,
      '',
    );
    expect(localState.values.containsKey(chatDraftKey('s1')), isFalse);
  });

  testWidgets('send button follows the busy preference while running', (
    tester,
  ) async {
    final actions = <ChatAction>[];
    final localState = FakeChatLocalState(busyEnter: kBusyEnterSteer);
    const running = SessionSummary(
      id: 's1',
      title: 'Running',
      blank: false,
      running: true,
    );
    await _pump(
      tester,
      const ChatUiState(sessions: [running], selectedSessionId: 's1'),
      actions,
      localState: localState,
    );

    await tester.enterText(find.byType(TextField), 'follow-up');
    await tester.pump();

    // Running: Stop keeps its seat and an explicit send control appears.
    expect(find.byTooltip('Stop'), findsOneWidget);
    expect(find.byTooltip('Send'), findsOneWidget);

    await tester.tap(find.byTooltip('Send'));
    await tester.pump();

    expect(
      actions,
      contains(const SendPrompt('follow-up', mode: PromptMode.steer)),
    );
  });

  testWidgets('busy preference defaults to queue', (tester) async {
    final actions = <ChatAction>[];
    final localState = FakeChatLocalState();
    const running = SessionSummary(
      id: 's1',
      title: 'Running',
      blank: false,
      running: true,
    );
    await _pump(
      tester,
      const ChatUiState(sessions: [running], selectedSessionId: 's1'),
      actions,
      localState: localState,
    );

    await tester.enterText(find.byType(TextField), 'follow-up');
    await tester.pump();
    await tester.tap(find.byTooltip('Send'));
    await tester.pump();

    expect(
      actions,
      contains(const SendPrompt('follow-up', mode: PromptMode.queue)),
    );
  });

  testWidgets('composer controls are native components', (tester) async {
    final actions = <ChatAction>[];
    await _pump(
      tester,
      const ChatUiState(sessions: [_session], selectedSessionId: 's1'),
      actions,
    );
    await tester.pump();

    // Empty draft: the send seat is a disabled FAB (idle, no draft) and
    // the ➕ tool is a standard IconButton.
    final idleFab = tester.widget<FloatingActionButton>(
      find.descendant(
        of: find.byTooltip('Send'),
        matching: find.byType(FloatingActionButton),
      ),
    );
    expect(idleFab.onPressed, isNull);
    expect(find.byIcon(Icons.add), findsOneWidget);
    expect(
      find.ancestor(
        of: find.byIcon(Icons.add),
        matching: find.byType(IconButton),
      ),
      findsOneWidget,
    );

    // A ready draft arms the FAB (hero disabled so sibling send/stop
    // FABs never collide).
    await tester.enterText(find.byType(TextField), 'hello');
    await tester.pump();
    final readyFab = tester.widget<FloatingActionButton>(
      find.descendant(
        of: find.byTooltip('Send'),
        matching: find.byType(FloatingActionButton),
      ),
    );
    expect(readyFab.onPressed, isNotNull);
    expect(readyFab.heroTag, isNull);
  });

  testWidgets('saved draft restores on mount and swaps per session', (
    tester,
  ) async {
    final actions = <ChatAction>[];
    final localState = FakeChatLocalState();
    await localState.forSession('s1').writeDraft('first draft');
    await localState.forSession('s2').writeDraft('second draft');
    const sessions = [
      _session,
      SessionSummary(id: 's2', title: 'Other', blank: false),
    ];

    await _pump(
      tester,
      const ChatUiState(sessions: sessions, selectedSessionId: 's1'),
      actions,
      localState: localState,
    );
    await tester.pump();
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).controller.text,
      'first draft',
    );

    await _pump(
      tester,
      const ChatUiState(sessions: sessions, selectedSessionId: 's2'),
      actions,
      localState: localState,
    );
    await tester.pump();
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).controller.text,
      'second draft',
    );
  });

  testWidgets('tool-row expansion persists and restores', (tester) async {
    final actions = <ChatAction>[];
    final localState = FakeChatLocalState();
    await _pump(
      tester,
      const ChatUiState(
        sessions: [_session],
        selectedSessionId: 's1',
        timeline: [
          TimelineToolCall(
            id: 't1',
            name: 'bash',
            arguments: 'echo args-marker',
            result: 'result-marker-789',
            status: ToolRunStatus.completed,
          ),
        ],
      ),
      actions,
      localState: localState,
    );
    await tester.pump();

    // The settled result rides only the expanded body (web ToolRow).
    expect(find.text('result-marker-789'), findsNothing);
    await tester.tap(find.text('Bash'));
    await tester.pumpAndSettle();
    expect(find.text('result-marker-789'), findsOneWidget);
    expect(
      localState.values[chatExpandedToolsKey('s1')],
      contains('tool:t1:ToolRunStatus.completed'),
    );

    // A remount with the saved key restores the expansion.
    await _pump(
      tester,
      const ChatUiState(
        sessions: [_session],
        selectedSessionId: 's1',
        timeline: [
          TimelineToolCall(
            id: 't1',
            name: 'bash',
            arguments: 'echo args-marker',
            result: 'result-marker-789',
            status: ToolRunStatus.completed,
          ),
        ],
      ),
      actions,
      localState: localState,
    );
    await tester.pump();
    expect(find.text('result-marker-789'), findsOneWidget);
  });

  testWidgets('reading position restores instead of bottom when idle', (
    tester,
  ) async {
    final actions = <ChatAction>[];
    final localState = FakeChatLocalState();
    await localState.forSession('s1').writeReadOffset(0);
    final timeline = <TimelineItem>[
      for (var i = 0; i < 30; i++)
        TimelineMessage(
          ChatMessage(
            id: 'm$i',
            sessionId: 's1',
            role: MessageRole.user,
            text: 'message number $i ' * 12,
          ),
        ),
    ];

    await _pump(
      tester,
      ChatUiState(
        sessions: const [_session],
        selectedSessionId: 's1',
        timeline: timeline,
      ),
      actions,
      localState: localState,
    );
    await tester.pumpAndSettle();

    // The lazy list builds only the visible slice; any built message
    // locates the timeline's own scrollable (the session panel beside it
    // owns another).
    final timelineScrollable = find
        .ancestor(
          of: find.textContaining(RegExp(r'message number')),
          matching: find.byType(Scrollable),
        )
        .first;
    final position = tester.state<ScrollableState>(timelineScrollable).position;
    expect(position.pixels, 0);
    expect(position.maxScrollExtent, greaterThan(0));
  });

  testWidgets('running session lands at the bottom and follows', (
    tester,
  ) async {
    final actions = <ChatAction>[];
    final localState = FakeChatLocalState();
    await localState.forSession('s1').writeReadOffset(0);
    const running = SessionSummary(
      id: 's1',
      title: 'Running',
      blank: false,
      running: true,
    );
    final timeline = <TimelineItem>[
      for (var i = 0; i < 30; i++)
        TimelineMessage(
          ChatMessage(
            id: 'm$i',
            sessionId: 's1',
            role: MessageRole.user,
            text: 'message number $i ' * 12,
          ),
        ),
    ];

    await _pump(
      tester,
      ChatUiState(
        sessions: const [running],
        selectedSessionId: 's1',
        timeline: timeline,
      ),
      actions,
      localState: localState,
    );
    await tester.pumpAndSettle();

    // The lazy list builds only the visible slice; any built message
    // locates the timeline's own scrollable (the session panel beside it
    // owns another).
    final timelineScrollable = find
        .ancestor(
          of: find.textContaining(RegExp(r'message number')),
          matching: find.byType(Scrollable),
        )
        .first;
    final position = tester.state<ScrollableState>(timelineScrollable).position;
    expect(position.pixels, position.maxScrollExtent);
  });

  testWidgets('outline collapse persists and restores', (tester) async {
    final actions = <ChatAction>[];
    final localState = FakeChatLocalState();
    await localState.forSession('s1').writeCollapsedTurns(const <int>{1});
    final timeline = <TimelineItem>[
      const TimelineTurnBoundary(1),
      const TimelineMessage(
        ChatMessage(
          id: 'm1',
          sessionId: 's1',
          role: MessageRole.user,
          text: 'inside turn one',
        ),
      ),
    ];

    // Outline mode comes from ChatScreen's header toggle.
    await _pump(
      tester,
      ChatUiState(
        sessions: const [_session],
        selectedSessionId: 's1',
        timeline: timeline,
      ),
      actions,
      localState: localState,
    );
    await tester.tap(find.byTooltip('Outline'));
    await tester.pumpAndSettle();

    // Restored collapsed turn 1 hides its rows.
    expect(find.text('inside turn one'), findsNothing);
    expect(find.textContaining('▸ Turn 1'), findsOneWidget);

    await tester.tap(find.textContaining('▸ Turn 1'));
    await tester.pumpAndSettle();
    expect(find.text('inside turn one'), findsOneWidget);
    expect(localState.values[chatCollapsedTurnsKey('s1')], isEmpty);
  });
}
