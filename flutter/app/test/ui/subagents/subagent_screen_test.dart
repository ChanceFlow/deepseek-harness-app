/// SubagentScreen widget parity tests.
library;

import 'package:domain/model/chat_message.dart';
import 'package:domain/model/session.dart';
import 'package:domain/model/subagent.dart';
import 'package:domain/model/timeline_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/ui/subagents/subagent_screen.dart';
import 'package:app/ui/subagents/subagent_ui_state.dart';

const _catalog = SubagentCatalog(
  parentSessionId: 'p1',
  parentAvailable: true,
  entries: [
    SubagentEntry(
      id: 'child-12345678abcd',
      kind: 'child',
      mode: 'continuable',
      activity: 'running',
      hasChildren: true,
      label: 'Worker',
      reason: 'Porting tests',
    ),
    SubagentEntry(
      id: 'other-9999',
      kind: 'self',
      mode: 'archived',
      activity: 'idle',
      hasChildren: false,
    ),
  ],
);

Future<void> _pump(
  WidgetTester tester,
  SubagentUiState uiState,
  List<SubagentAction> actions,
) {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  return tester.pumpWidget(
    MaterialApp(
      home: SubagentScreen(uiState: uiState, onAction: actions.add),
    ),
  );
}

void main() {
  testWidgets('renders parent picker and child rows with metadata',
      (tester) async {
    await _pump(
      tester,
      const SubagentUiState(
        sessions: [
          SessionSummary(id: 'p1', title: 'Parent session', blank: false),
        ],
        selectedParentId: 'p1',
        catalog: _catalog,
      ),
      [],
    );

    expect(find.text('Subagents'), findsOneWidget);
    // Section label + the selected session row share the string.
    expect(find.text('Parent session'), findsNWidgets(2));
    expect(find.text('child child-12'), findsOneWidget);
    expect(
      find.text(
          'kind=child mode=continuable activity=running children=true'),
      findsOneWidget,
    );
    expect(find.text('label=Worker'), findsOneWidget);
    expect(find.text('Porting tests'), findsOneWidget);
    // Non-child rows carry no Open/Stop buttons.
    expect(find.widgetWithText(FilledButton, 'Open'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Stop'), findsOneWidget);
  });

  testWidgets('parent picker disables the selected parent and dispatches',
      (tester) async {
    final actions = <SubagentAction>[];
    await _pump(
      tester,
      const SubagentUiState(
        sessions: [
          SessionSummary(id: 'p1', title: 'Parent one', blank: false),
          SessionSummary(id: 'p2', title: 'Parent two', blank: false),
        ],
        selectedParentId: 'p1',
      ),
      actions,
    );

    final one = find.widgetWithText(OutlinedButton, 'Parent one');
    expect(tester.widget<OutlinedButton>(one).onPressed, isNull);
    await tester.tap(find.text('Parent two'));
    await tester.pump();
    expect(actions, contains(const SelectParent('p2')));
  });

  testWidgets('open and stop dispatch child actions; unavailable parent warns',
      (tester) async {
    final actions = <SubagentAction>[];
    await _pump(
      tester,
      const SubagentUiState(
        selectedParentId: 'p1',
        catalog: _catalog,
      ),
      actions,
    );

    await tester.tap(find.text('Open'));
    await tester.pump();
    expect(
        actions, contains(const OpenChild('child-12345678abcd')));

    await tester.tap(find.text('Stop'));
    await tester.pump();
    expect(actions,
        contains(const InterruptSubagent('child-12345678abcd')));

    await _pump(
      tester,
      const SubagentUiState(
        selectedParentId: 'p1',
        catalog: SubagentCatalog(
          parentSessionId: 'p1',
          parentAvailable: false,
        ),
      ),
      actions,
    );
    expect(find.text('Parent is not available for continuation.'),
        findsOneWidget);
  });

  testWidgets('child timeline renders plain rows and composer sends',
      (tester) async {
    final actions = <SubagentAction>[];
    await _pump(
      tester,
      const SubagentUiState(
        selectedParentId: 'p1',
        selectedChildId: 'child-12345678abcd',
        catalog: _catalog,
        childTimeline: [
          TimelineMessage(ChatMessage(
            id: 'm1',
            sessionId: 'child-12345678abcd',
            role: MessageRole.assistant,
            text: 'working on it',
          )),
          TimelineTurnBoundary(2),
          TimelineError(id: 'e1', message: 'boom'),
        ],
      ),
      actions,
    );

    expect(find.text('Child timeline'), findsOneWidget);
    expect(find.text('assistant: working on it'), findsOneWidget);
    expect(find.text('Turn 2'), findsOneWidget);
    expect(find.text('boom'), findsOneWidget);

    final field = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.hintText == 'Message selected subagent',
    );
    await tester.enterText(field, 'keep going');
    await tester.pump();
    await tester.tap(find.text('Send'));
    await tester.pump();
    expect(
        actions, contains(const SendSubagentPrompt('keep going')));
  });
}
