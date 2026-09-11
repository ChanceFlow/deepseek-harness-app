/// Trajectory ledger widget tests.
///
/// The ledger is driven by a real `TrajectoryController` over the shared
/// `FakeChatRepository` seam (the same double `chat_controller_test.dart`
/// uses), so every assertion rides the production fold from `domain`
/// timeline items to ledger rows — no hand-built view model.
library;

import 'package:app/ui/trajectory/trajectory_controller.dart';
import 'package:app/ui/trajectory/trajectory_screen.dart';
import 'package:app/ui/trajectory/trajectory_ui_state.dart';
import 'package:domain/model/chat_message.dart';
import 'package:domain/model/session.dart';
import 'package:domain/model/timeline_item.dart';
import 'package:domain/model/timeline_window.dart';
import 'package:domain/model/token_usage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../l10n_app.dart';
import '../chat/chat_controller_test.dart';

/// The session the ledger is opened for; the double seeds it so the app bar
/// can show its title.
const _session = SessionSummary(id: 'session-1', title: 'Alpha', blank: false);

/// The ledger view under one controller, rebuilt from the controller's own
/// stream exactly as `TrajectorySessionRoute` does.
class _Harness extends StatelessWidget {
  const _Harness({required this.controller});

  final TrajectoryController controller;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<TrajectoryUiState>(
      stream: controller.uiState,
      initialData: controller.state,
      builder: (context, snapshot) => TrajectoryScreen(
        uiState: snapshot.data ?? const TrajectoryUiState(),
        onAction: controller.onAction,
      ),
    );
  }
}

/// The one record row whose id is [id].
Finder _record(String id) => find.byKey(ValueKey<String>('trajectory-row-$id'));

Future<TrajectoryController> _pumpLedger(
  WidgetTester tester,
  FakeChatRepository repository,
) async {
  // Phone-scale logical surface: the ledger is designed at 360dp.
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final controller = TrajectoryController(repository, sessionId: 'session-1');
  addTearDown(controller.dispose);
  await tester.pumpWidget(l10nApp(home: _Harness(controller: controller)));
  await tester.pumpAndSettle();
  return controller;
}

TimelineMessage _message(
  String id,
  MessageRole role,
  String text, {
  int step = 0,
  TokenUsage? usage,
  int? firstTokenAtEpochMs,
  int createdAtEpochMs = 0,
  String? reasoning,
}) => TimelineMessage(
  ChatMessage(
    id: id,
    sessionId: 'session-1',
    role: role,
    text: text,
    reasoning: reasoning,
    createdAtEpochMs: createdAtEpochMs,
  ),
  step: step,
  usage: usage,
  firstTokenAtEpochMs: firstTokenAtEpochMs,
);

void main() {
  testWidgets('renders turn rules, step markers, and record rows', (
    tester,
  ) async {
    final repository = FakeChatRepository(
      initialSessions: const <SessionSummary>[_session],
      initialTimeline: <TimelineItem>[
        const TimelineTurnBoundary(
          1,
          usage: TokenUsage(inputTokens: 1500, outputTokens: 40),
        ),
        _message('u1', MessageRole.user, 'do the thing'),
        _message('a1', MessageRole.assistant, 'working on it', step: 1),
        const TimelineToolCall(
          id: 'call-1',
          name: 'bash',
          arguments: 'ls -la',
          result: 'README.md',
          status: ToolRunStatus.completed,
          step: 1,
          startedAtEpochMs: 1700000000000,
        ),
        _message('a2', MessageRole.assistant, 'second step', step: 2),
      ],
    );

    await _pumpLedger(tester, repository);

    // The turn rule names the turn and totals the steps' token accounting.
    expect(find.text('Turn 1'), findsOneWidget);
    expect(find.text('4 records · 1 tool'), findsOneWidget);
    // The compact turn usage line carries the billed input and output.
    expect(find.textContaining('in 1.5K'), findsOneWidget);
    // Inline step markers separate the two steps inside the turn.
    expect(find.text('Step 1'), findsOneWidget);
    expect(find.text('Step 2'), findsOneWidget);
    // Every record is a selectable row: prompt, assistant, tool name+args.
    expect(_record('u1'), findsOneWidget);
    expect(find.text('do the thing'), findsOneWidget);
    expect(find.text('working on it'), findsOneWidget);
    expect(_record('call-1'), findsOneWidget);
    expect(find.textContaining('bash'), findsOneWidget);
    expect(find.textContaining('ls -la'), findsOneWidget);
    expect(_record('a2'), findsOneWidget);
    expect(find.text('second step'), findsOneWidget);
  });

  testWidgets('selecting a record opens the inspector with its real values', (
    tester,
  ) async {
    final repository = FakeChatRepository(
      initialSessions: const <SessionSummary>[_session],
      initialTimeline: <TimelineItem>[
        const TimelineTurnBoundary(1),
        _message(
          'a1',
          MessageRole.assistant,
          'answer body',
          step: 2,
          createdAtEpochMs: 1700000000000,
          firstTokenAtEpochMs: 1700000000250,
          usage: const TokenUsage(
            inputTokens: 1200,
            outputTokens: 340,
            cacheReadTokens: 150,
            cacheWriteTokens: 20,
            reasoningTokens: 90,
          ),
        ),
      ],
    );

    final controller = await _pumpLedger(tester, repository);

    // The full text is inspector material: the scan line shows it too, but
    // the sheet is where the exact figures live.
    controller.onAction(const SelectTrajectoryRecord('a1'));
    await tester.pumpAndSettle();

    final inspector = find.byType(TrajectoryInspector);
    expect(inspector, findsOneWidget);
    // The billed input is the disjoint sum (1200 + 150 + 20), never a
    // cached-inclusive total, and it rides the inspector.
    Finder inInspector(String text) =>
        find.descendant(of: inspector, matching: find.text(text));
    expect(inInspector('1370 tok'), findsOneWidget);
    expect(inInspector('340 tok'), findsOneWidget);
    expect(inInspector('90 tok'), findsOneWidget);
    expect(inInspector('Step 2'), findsOneWidget);
    // A provider figure the log never carried (duration) is stated as
    // unavailable rather than estimated.
    expect(find.text('Unavailable'), findsWidgets);
    expect(
      find.text('The session log carries no settle timestamp for this record.'),
      findsOneWidget,
    );
  });

  testWidgets('the inspector reports usage the host never sent as absent', (
    tester,
  ) async {
    final repository = FakeChatRepository(
      initialSessions: const <SessionSummary>[_session],
      initialTimeline: <TimelineItem>[
        const TimelineToolCall(
          id: 'call-1',
          name: 'read',
          arguments: 'a.txt',
          result: 'body',
          status: ToolRunStatus.completed,
          step: 1,
        ),
      ],
    );

    final controller = await _pumpLedger(tester, repository);
    controller.onAction(const SelectTrajectoryRecord('call-1'));
    await tester.pumpAndSettle();

    expect(
      find.text('The host reported no usage for this record.'),
      findsOneWidget,
    );
    expect(find.text('Input'), findsWidgets);
    expect(find.text('body'), findsWidgets);
  });

  testWidgets('search filters the loaded window', (tester) async {
    final repository = FakeChatRepository(
      initialSessions: const <SessionSummary>[_session],
      initialTimeline: <TimelineItem>[
        const TimelineTurnBoundary(1),
        _message('u1', MessageRole.user, 'alpha request'),
        _message('a1', MessageRole.assistant, 'beta answer', step: 1),
        const TimelineToolCall(
          id: 'call-1',
          name: 'bash',
          arguments: 'git status',
          status: ToolRunStatus.completed,
          step: 1,
        ),
      ],
    );

    await _pumpLedger(tester, repository);
    final searchField = find.byType(TextField).first;

    await tester.enterText(searchField, 'beta');
    await tester.pumpAndSettle();

    // Only the matching record survives, and the match count reports the
    // window it searched.
    expect(_record('a1'), findsOneWidget);
    expect(_record('u1'), findsNothing);
    expect(_record('call-1'), findsNothing);
    expect(find.text('1 of 3'), findsOneWidget);

    // Space-separated terms are AND-ed over one record's haystack.
    await tester.enterText(searchField, 'beta alpha');
    await tester.pumpAndSettle();
    expect(
      find.text('No records match this search in the loaded window.'),
      findsOneWidget,
    );

    // Clearing restores the whole structural ledger.
    await tester.enterText(searchField, '');
    await tester.pumpAndSettle();
    expect(find.text('Turn 1'), findsOneWidget);
    expect(find.text('Step 1'), findsWidgets);
    expect(_record('u1'), findsOneWidget);
    expect(_record('a1'), findsOneWidget);
  });

  testWidgets('a load in flight shows a spinner, not the empty hero', (
    tester,
  ) async {
    final repository = FakeChatRepository(
      initialSessions: const <SessionSummary>[_session],
    );
    repository.windowSource = (_) =>
        Stream<TimelineWindow>.value(const TimelineWindow(isLoading: true));

    // The spinner animates forever, so this test pumps a frame instead of
    // settling.
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = TrajectoryController(repository, sessionId: 'session-1');
    addTearDown(controller.dispose);
    await tester.pumpWidget(l10nApp(home: _Harness(controller: controller)));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
      find.text('This session has no trajectory records yet.'),
      findsNothing,
    );
  });

  testWidgets('a settled empty window states the empty ledger', (tester) async {
    final repository = FakeChatRepository(
      initialSessions: const <SessionSummary>[_session],
    );

    await _pumpLedger(tester, repository);

    expect(
      find.text('This session has no trajectory records yet.'),
      findsOneWidget,
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('older history offers a paging control and reports the count', (
    tester,
  ) async {
    final repository = FakeChatRepository(
      initialSessions: const <SessionSummary>[_session],
    );
    repository.windowSource = (_) => Stream<TimelineWindow>.value(
      TimelineWindow(
        items: <TimelineItem>[
          const TimelineTurnBoundary(2),
          _message('u2', MessageRole.user, 'later prompt'),
        ],
        hasMoreOlder: true,
      ),
    );

    await _pumpLedger(tester, repository);
    expect(find.text('Load older history'), findsOneWidget);

    await tester.tap(find.text('Load older history'));
    await tester.pumpAndSettle();
    // The request rides the repository's shared paging path.
    expect(repository.olderHistorySessionIds, <String>['session-1']);
  });

  testWidgets('a nested code-dispatch call expands under its root', (
    tester,
  ) async {
    final repository = FakeChatRepository(
      initialSessions: const <SessionSummary>[_session],
      initialTimeline: <TimelineItem>[
        const TimelineTurnBoundary(1),
        const TimelineToolCall(
          id: 'root-1',
          name: 'run_code',
          arguments: '{"code":"x"}',
          status: ToolRunStatus.completed,
          step: 1,
          children: <TimelineToolCall>[
            TimelineToolCall(
              id: 'root-1:ptc:1',
              name: 'read',
              arguments: '{"file_path":"a.txt"}',
              result: 'body',
              status: ToolRunStatus.completed,
              step: 1,
              parentCallId: 'root-1',
            ),
          ],
        ),
      ],
    );

    final controller = await _pumpLedger(tester, repository);
    // A nested call is inspector material until its root is expanded.
    expect(_record('root-1:ptc:1'), findsNothing);

    controller.onAction(const ToggleTrajectoryExpansion('root-1'));
    await tester.pumpAndSettle();

    expect(_record('root-1:ptc:1'), findsOneWidget);
    expect(find.textContaining('read'), findsWidgets);
  });
}
