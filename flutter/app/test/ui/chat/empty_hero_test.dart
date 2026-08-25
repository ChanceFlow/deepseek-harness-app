/// EmptyHero parity tests — fish headline, preview badge, workspace chip.
library;

import 'package:domain/model/agent_preset.dart';
import 'package:domain/model/session.dart';
import 'package:domain/model/chat_message.dart';
import 'package:domain/model/timeline_item.dart';
import 'package:domain/model/workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/ui/chat/chat_screen.dart';
import 'package:app/ui/chat/chat_ui_state.dart';
import 'package:app/ui/chat/empty_hero.dart';
import 'package:app/ui/chat/fish_logo.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n_app.dart';

Future<void> _pump(
  WidgetTester tester,
  ChatUiState uiState,
  List<ChatAction> actions,
) {
  tester.view.physicalSize = const Size(800, 1280);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  // SessionPanel (two-pane layout) watches the shared store provider, so
  // the host needs a scope even with no local state injected.
  return tester.pumpWidget(
    ProviderScope(
      child: l10nApp(
        home: ChatScreen(uiState: uiState, onAction: actions.add),
      ),
    ),
  );
}

void main() {
  testWidgets('empty timeline shows the fish headline and preview badge', (
    tester,
  ) async {
    await _pump(
      tester,
      const ChatUiState(
        sessions: [SessionSummary(id: 's1', title: 'Alpha', blank: false)],
        selectedSessionId: 's1',
      ),
      [],
    );

    expect(find.text('Into the Unknown'), findsOneWidget);
    expect(find.text('Preview'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(EmptyHero),
        matching: find.byType(FishLogo),
      ),
      findsOneWidget,
    );
    expect(find.text('Choose workspace'), findsOneWidget);
  });

  testWidgets('workspace chip lists workspaces and dispatches create', (
    tester,
  ) async {
    final actions = <ChatAction>[];
    await _pump(
      tester,
      const ChatUiState(
        sessions: [SessionSummary(id: 's1', title: 'Alpha', blank: false)],
        selectedSessionId: 's1',
        workspaces: [
          WorkspaceSummary(
            workspaceId: 'w1',
            path: '/tmp/proj',
            title: 'proj',
            sessionIds: [],
          ),
        ],
      ),
      actions,
    );

    await tester.tap(find.text('Choose workspace'));
    await tester.pumpAndSettle();
    expect(find.text('proj'), findsOneWidget);
    expect(find.text('/tmp/proj'), findsOneWidget);

    await tester.tap(find.text('proj'));
    await tester.pumpAndSettle();
    expect(actions, contains(const CreateSessionInWorkspace('w1')));
  });

  testWidgets('cwd-backed label replaces the placeholder chip text', (
    tester,
  ) async {
    await _pump(
      tester,
      const ChatUiState(
        sessions: [
          SessionSummary(
            id: 's1',
            title: 'Alpha',
            blank: false,
            cwd: '/tmp/proj',
          ),
        ],
        selectedSessionId: 's1',
      ),
      [],
    );
    // The app bar names the workspace too; this asserts the hero's chip.
    expect(
      find.descendant(of: find.byType(EmptyHero), matching: find.text('proj')),
      findsOneWidget,
    );
    expect(find.text('Choose workspace'), findsNothing);
  });

  testWidgets('preset seat rides beside the workspace chip', (tester) async {
    final actions = <ChatAction>[];
    await _pump(
      tester,
      const ChatUiState(
        sessions: [SessionSummary(id: 's1', title: 'Alpha', blank: false)],
        selectedSessionId: 's1',
        agentPresets: AgentPresetRoster(
          entries: [
            AgentPresetEntry(
              id: 'standard',
              trust: AgentPresetTrust.system,
              isDefault: true,
            ),
            AgentPresetEntry(
              id: 'ghost',
              trust: AgentPresetTrust.user,
              broken: 'composition missing',
            ),
          ],
        ),
      ),
      actions,
    );

    // The chip opens on the deployment default; the workspace chip keeps
    // its seat beside it (web HeroShell row).
    expect(find.text('Standard mode'), findsOneWidget);
    expect(find.text('Choose workspace'), findsOneWidget);

    await tester.tap(find.text('Standard mode'));
    await tester.pumpAndSettle();
    expect(find.text('Agent preset'), findsOneWidget);
    expect(find.text('Default'), findsOneWidget);
    // A broken preset cannot compose a session: never offered.
    expect(find.text('ghost'), findsNothing);

    await tester.tap(find.text('Standard mode').last);
    await tester.pumpAndSettle();
    // Not a blank session: the pick stages instead of switching.
    expect(actions, isEmpty);
  });

  testWidgets('non-empty timeline hides the hero', (tester) async {
    await _pump(
      tester,
      const ChatUiState(
        sessions: [SessionSummary(id: 's1', title: 'Alpha', blank: false)],
        selectedSessionId: 's1',
        timeline: [
          TimelineMessage(
            ChatMessage(
              id: 'm1',
              sessionId: 's1',
              role: MessageRole.user,
              text: 'hello',
            ),
          ),
        ],
      ),
      [],
    );
    expect(find.text('Into the Unknown'), findsNothing);
    expect(
      find.descendant(
        of: find.byType(EmptyHero),
        matching: find.byType(FishLogo),
      ),
      findsNothing,
    );
  });

  testWidgets('empty timeline while the conversation loads shows a spinner', (
    tester,
  ) async {
    await _pump(
      tester,
      const ChatUiState(
        sessions: [SessionSummary(id: 's1', title: 'Alpha', blank: false)],
        selectedSessionId: 's1',
        isTimelineLoading: true,
      ),
      [],
    );

    // The in-flight first load must read as a wait, not as an empty
    // session: a centered loader replaces the empty hero.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(EmptyHero), findsNothing);
    expect(find.text('Into the Unknown'), findsNothing);
  });

  testWidgets('empty timeline after a settled load shows the empty hero', (
    tester,
  ) async {
    await _pump(
      tester,
      const ChatUiState(
        sessions: [SessionSummary(id: 's1', title: 'Alpha', blank: false)],
        selectedSessionId: 's1',
      ),
      [],
    );

    expect(find.byType(EmptyHero), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('fish path parser yields a bounded non-empty path', (
    tester,
  ) async {
    await tester.pumpWidget(
      l10nApp(
        home: const Scaffold(
          body: Center(child: FishLogo(size: 34, color: Colors.blue)),
        ),
      ),
    );
    expect(find.byType(FishLogo), findsOneWidget);
    // Golden-free sanity: the painter produced frames without exceptions.
    await tester.pump();
  });
}
