/// GoalScreen widget parity tests.
library;

import 'package:domain/model/goal.dart';
import 'package:domain/model/session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/ui/goal/goal_screen.dart';
import 'package:app/ui/goal/goal_ui_state.dart';

GoalProjection _projection(GoalPhase phase, {int revision = 3}) {
  return GoalProjection(
    goal: GoalSnapshot(
      id: 'goal-1',
      revision: revision,
      objective: 'Finish the Android MVP',
      phase: phase,
      maxGoalRounds: 10,
    ),
    roundsStarted: 2,
    createdAt: 0,
    updatedAt: 0,
  );
}

Future<void> _pump(
  WidgetTester tester,
  GoalUiState uiState,
  List<GoalAction> actions,
) {
  tester.view.physicalSize = const Size(800, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  return tester.pumpWidget(
    MaterialApp(
      home: GoalScreen(uiState: uiState, onAction: actions.add),
    ),
  );
}

void main() {
  testWidgets('no goal: create form gates on objective and session',
      (tester) async {
    final actions = <GoalAction>[];
    await _pump(
      tester,
      const GoalUiState(
        sessions: [
          SessionSummary(id: 's1', title: 'Goal session', blank: false),
        ],
      ),
      actions,
    );

    expect(find.text('No current goal'), findsOneWidget);
    expect(find.text('Create'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Create'))
          .onPressed,
      isNull, // no selected session yet
    );

    await tester.enterText(
      find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.hintText == 'Goal objective',
      ),
      'Ship it',
    );
    await tester.pump();
    await tester.tap(find.text('Goal session'));
    await tester.pump();
    expect(actions, contains(const SelectGoalSession('s1')));
  });

  testWidgets('create dispatches with parsed max rounds',
      (tester) async {
    final actions = <GoalAction>[];
    await _pump(
      tester,
      const GoalUiState(selectedSessionId: 's1'),
      actions,
    );

    await tester.enterText(
      find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.hintText == 'Goal objective',
      ),
      'Ship it',
    );
    await tester.enterText(
      find.byWidgetPredicate(
        (w) =>
            w is TextField &&
            w.decoration?.hintText == 'Max goal rounds (optional)',
      ),
      '12x', // digits only
    );
    await tester.pump();
    await tester.tap(find.text('Create'));
    await tester.pump();
    expect(
        actions, contains(const CreateGoalAction('Ship it', 12)));
  });

  testWidgets('active goal offers Pause/Complete/Edit; edit saves',
      (tester) async {
    final actions = <GoalAction>[];
    await _pump(
      tester,
      GoalUiState(selectedSessionId: 's1', goal: _projection(GoalPhase.active)),
      actions,
    );

    expect(find.text('Finish the Android MVP'), findsOneWidget);
    expect(
      find.text('ACTIVE · revision 3 · rounds 2/10'),
      findsOneWidget,
    );

    await tester.tap(find.text('Pause'));
    await tester.pump();
    expect(actions, contains(const PauseGoalAction()));

    await tester.tap(find.text('Complete'));
    await tester.pump();
    expect(actions, contains(const CompleteGoalAction()));

    await tester.tap(find.text('Edit'));
    await tester.pump();
    await tester.enterText(
      find.widgetWithText(TextField, 'Finish the Android MVP').first,
      'Revised objective',
    );
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(
        actions, contains(const EditGoalAction('Revised objective')));
  });

  testWidgets('paused/blocked goals resume; complete goals clear',
      (tester) async {
    final actions = <GoalAction>[];
    await _pump(
      tester,
      GoalUiState(
          selectedSessionId: 's1', goal: _projection(GoalPhase.paused)),
      actions,
    );
    await tester.tap(find.text('Resume'));
    await tester.pump();
    expect(actions, contains(const ResumeGoalAction()));

    await _pump(
      tester,
      GoalUiState(
          selectedSessionId: 's1', goal: _projection(GoalPhase.blocked)),
      actions,
    );
    await tester.tap(find.text('Resume'));
    await tester.pump();
    expect(actions.length, 2);

    await _pump(
      tester,
      GoalUiState(
          selectedSessionId: 's1', goal: _projection(GoalPhase.complete)),
      actions,
    );
    expect(find.text('Resume'), findsNothing);
    expect(find.text('Edit'), findsNothing);
    await tester.tap(find.text('Clear'));
    await tester.pump();
    expect(actions, contains(const ClearGoalAction()));
  });

  testWidgets('refresh dispatches only with a selected session',
      (tester) async {
    final actions = <GoalAction>[];
    await _pump(tester, const GoalUiState(), actions);
    expect(
      tester
          .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Refresh'))
          .onPressed,
      isNull,
    );

    await _pump(
      tester,
      const GoalUiState(selectedSessionId: 's1'),
      actions,
    );
    await tester.tap(find.text('Refresh'));
    await tester.pump();
    expect(actions, contains(const RefreshGoalAction()));
  });
}
