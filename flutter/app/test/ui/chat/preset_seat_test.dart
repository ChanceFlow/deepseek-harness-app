/// Agent-preset seat tests — hero chip staging, blank-session switching,
/// the read-only header label, and broken-preset exclusion, driven
/// through the real ChatScreen entry path.
library;

import 'package:domain/model/agent_preset.dart';
import 'package:domain/model/chat_message.dart';
import 'package:domain/model/session.dart';
import 'package:domain/model/timeline_item.dart';
import 'package:domain/model/workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:app/ui/chat/chat_screen.dart';
import 'package:app/ui/chat/chat_ui_state.dart';
import 'package:app/ui/chat/preset_seat.dart';

import '../../l10n_app.dart';

/// Roster fixture: the web client's four shipped ids plus one broken
/// user row (ui-agent-preset locales.ts + agent-presets.schema semantics).
const AgentPresetRoster _roster = AgentPresetRoster(
  entries: [
    AgentPresetEntry(
      id: 'standard',
      trust: AgentPresetTrust.system,
      isDefault: true,
    ),
    AgentPresetEntry(id: 'code', trust: AgentPresetTrust.system),
    AgentPresetEntry(id: 'minimal', trust: AgentPresetTrust.system),
    AgentPresetEntry(
      id: 'ghost',
      trust: AgentPresetTrust.user,
      broken: 'composition missing',
    ),
  ],
);

Future<void> _pump(
  WidgetTester tester,
  ChatUiState uiState,
  List<ChatAction> actions,
) {
  tester.view.physicalSize = const Size(800, 1280);
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

void main() {
  testWidgets('hero chip shows the deployment default', (tester) async {
    await _pump(
      tester,
      const ChatUiState(
        sessions: [SessionSummary(id: 's1', blank: true)],
        selectedSessionId: 's1',
        agentPresets: _roster,
      ),
      [],
    );
    expect(find.byType(AgentPresetSeat), findsOneWidget);
    expect(find.text('Standard mode'), findsOneWidget);
  });

  testWidgets('a blank session composition outranks the default', (
    tester,
  ) async {
    await _pump(
      tester,
      const ChatUiState(
        sessions: [
          SessionSummary(id: 's1', blank: true, agentPreset: 'minimal'),
        ],
        selectedSessionId: 's1',
        agentPresets: _roster,
      ),
      [],
    );
    // Both the hero chip and the session-header label carry it.
    expect(find.text('Minimal mode'), findsWidgets);
  });

  testWidgets('picker offers selectable presets only, default marked', (
    tester,
  ) async {
    await _pump(
      tester,
      const ChatUiState(
        sessions: [SessionSummary(id: 's1', blank: true)],
        selectedSessionId: 's1',
        agentPresets: _roster,
      ),
      [],
    );

    await tester.tap(find.byType(AgentPresetSeat));
    await tester.pumpAndSettle();
    expect(find.text('Agent preset'), findsOneWidget);
    expect(find.text('Standard mode'), findsWidgets);
    expect(find.text('Code mode'), findsOneWidget);
    expect(find.text('Minimal mode'), findsOneWidget);
    expect(find.text('Default'), findsOneWidget);
    // A broken preset cannot compose a session: never offered.
    expect(find.text('ghost'), findsNothing);
    expect(find.text('composition missing'), findsNothing);
  });

  testWidgets('picking with a blank session switches its preset', (
    tester,
  ) async {
    final actions = <ChatAction>[];
    await _pump(
      tester,
      const ChatUiState(
        sessions: [SessionSummary(id: 's1', blank: true)],
        selectedSessionId: 's1',
        agentPresets: _roster,
      ),
      actions,
    );

    await tester.tap(find.byType(AgentPresetSeat));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Minimal mode'));
    await tester.pumpAndSettle();

    expect(
      actions,
      contains(
        const SelectAgentPreset(sessionId: 's1', agentPreset: 'minimal'),
      ),
    );
  });

  testWidgets('picking without a session stages the next create', (
    tester,
  ) async {
    final actions = <ChatAction>[];
    await _pump(
      tester,
      const ChatUiState(
        workspaces: [
          WorkspaceSummary(
            workspaceId: 'w1',
            path: '/tmp/proj',
            title: 'proj',
            sessionIds: [],
          ),
        ],
        agentPresets: _roster,
      ),
      actions,
    );

    await tester.tap(find.byType(AgentPresetSeat));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Code mode'));
    await tester.pumpAndSettle();
    // The chip now shows the staged choice.
    expect(find.text('Code mode'), findsOneWidget);

    // The stage rides the session the workspace pick creates.
    await tester.tap(find.text('Choose workspace'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('proj — /tmp/proj'));
    await tester.pumpAndSettle();
    expect(
      actions,
      contains(const CreateSessionInWorkspace('w1', agentPreset: 'code')),
    );
  });

  testWidgets('header label names the running session preset', (tester) async {
    await _pump(
      tester,
      const ChatUiState(
        sessions: [
          SessionSummary(
            id: 's1',
            title: 'Started',
            blank: false,
            agentPreset: 'minimal',
          ),
        ],
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
        agentPresets: _roster,
      ),
      [],
    );
    expect(find.byType(AgentPresetHeaderLabel), findsOneWidget);
    expect(find.text('Minimal mode'), findsOneWidget);
    // The hero seat never renders for a session with history.
    expect(find.byType(AgentPresetSeat), findsNothing);
  });

  testWidgets('an empty roster hides every preset surface', (tester) async {
    await _pump(
      tester,
      const ChatUiState(
        sessions: [
          SessionSummary(
            id: 's1',
            title: 'Started',
            blank: false,
            agentPreset: 'minimal',
          ),
        ],
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
        agentPresets: AgentPresetRoster(),
      ),
      [],
    );
    expect(find.byType(AgentPresetSeat), findsNothing);
    // The header label renders nothing (a collapsed SizedBox).
    expect(find.text('Minimal mode'), findsNothing);
  });
}
