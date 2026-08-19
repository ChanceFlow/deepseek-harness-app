/// SubagentScreen widget parity tests — the web catalog semantics this
/// port must keep (reference/deepseek-harness/packages/client/
/// ui-subagent/src/client/): catalog tree rows with StateDot + secondary
/// line, branch expansion, diagnostic rows, the child detail view over
/// the real TimelineRow, read-only composers, and read-only queued
/// messages.
library;

import 'package:domain/model/chat_message.dart';
import 'package:domain/model/plan.dart';
import 'package:domain/model/session.dart';
import 'package:domain/model/subagent.dart';
import 'package:domain/model/timeline_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/ui/chat/chat_screen.dart'
    show MessageRow, PlanChip, TimelineRow, ToolCallRow;
import 'package:app/ui/subagents/subagent_screen.dart';
import 'package:app/ui/subagents/subagent_ui_state.dart';
import 'package:app/ui/theme/deepsuite_extension.dart';

const _workerId = 'child-12345678abcd';

const _catalog = SubagentCatalog(
  parentSessionId: 'p1',
  parentAvailable: true,
  entries: [
    SubagentEntry(
      id: _workerId,
      kind: 'child',
      mode: 'continuable',
      activity: 'running',
      hasChildren: true,
      label: 'Worker',
    ),
    SubagentEntry(
      id: 'one-shot-1',
      kind: 'child',
      mode: 'one-shot',
      activity: 'inactive',
    ),
    SubagentEntry(id: 'broken-1', kind: 'diagnostic', reason: 'corrupt'),
  ],
);

const _sessions = <SessionSummary>[
  SessionSummary(id: 'p1', title: 'Parent one', blank: false),
  SessionSummary(id: 'p2', title: 'Parent two', blank: false),
  SessionSummary(id: _workerId, title: 'Porting tests', blank: false),
];

/// Same tree as [_catalog] with the parent marked offline.
const _offlineCatalog = SubagentCatalog(
  parentSessionId: 'p1',
  parentAvailable: false,
  entries: [
    SubagentEntry(
      id: _workerId,
      kind: 'child',
      mode: 'continuable',
      activity: 'running',
      hasChildren: true,
      label: 'Worker',
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

Finder _dot(SubagentDotState state) => find.byWidgetPredicate(
  (widget) => widget is SubagentStateDot && widget.state == state,
);

void main() {
  testWidgets('catalog rows show state dot, label, and secondary line', (
    tester,
  ) async {
    await _pump(
      tester,
      const SubagentUiState(
        sessions: _sessions,
        selectedParentId: 'p1',
        catalog: _catalog,
      ),
      [],
    );

    // Label (entry.label ?? id) and web secondary
    // ([title, mode, activity].join(' · ') — parts only when known).
    expect(find.text('Worker'), findsOneWidget);
    expect(find.text('Porting tests · continuable · running'), findsOneWidget);
    expect(find.text('one-shot-1'), findsOneWidget);
    expect(find.text('one-shot · not running'), findsOneWidget);
    // StateDot: running = ongoing, inactive = done, diagnostic = error.
    expect(_dot(SubagentDotState.ongoing), findsOneWidget);
    expect(_dot(SubagentDotState.done), findsOneWidget);
    expect(_dot(SubagentDotState.error), findsOneWidget);
  });

  testWidgets('diagnostic entries render disabled and never open', (
    tester,
  ) async {
    final actions = <SubagentAction>[];
    await _pump(
      tester,
      const SubagentUiState(
        sessions: _sessions,
        selectedParentId: 'p1',
        catalog: _catalog,
      ),
      actions,
    );

    expect(find.text('broken-1'), findsOneWidget);
    expect(find.text('corrupted session record'), findsOneWidget);
    await tester.tap(find.text('broken-1'));
    await tester.pump();
    expect(actions, isEmpty);
  });

  testWidgets('tapping a child row opens it; the app bar follows', (
    tester,
  ) async {
    final actions = <SubagentAction>[];
    await _pump(
      tester,
      const SubagentUiState(
        sessions: _sessions,
        selectedParentId: 'p1',
        catalog: _catalog,
      ),
      actions,
    );

    await tester.tap(find.text('Worker'));
    await tester.pump();
    expect(actions, contains(const OpenChild(_workerId)));
  });

  testWidgets('parent picker sheet selects and marks the current parent', (
    tester,
  ) async {
    final actions = <SubagentAction>[];
    await _pump(
      tester,
      const SubagentUiState(sessions: _sessions, selectedParentId: 'p1'),
      actions,
    );

    await tester.tap(find.text('Parent one'));
    await tester.pumpAndSettle();
    // 44px rows; the selected parent carries the check affordance.
    expect(find.byIcon(Icons.check), findsOneWidget);
    await tester.tap(find.text('Parent two'));
    await tester.pumpAndSettle();
    expect(actions, contains(const SelectParent('p2')));
  });

  testWidgets('empty states: no parent, then no subagents', (tester) async {
    await _pump(tester, const SubagentUiState(sessions: _sessions), []);

    // Selector row and the body prompt share the copy.
    expect(find.text('Select a parent session'), findsNWidgets(2));

    await _pump(
      tester,
      const SubagentUiState(
        sessions: _sessions,
        selectedParentId: 'p1',
        catalog: SubagentCatalog(parentSessionId: 'p1'),
      ),
      [],
    );
    expect(find.text('No subagents'), findsOneWidget);
  });

  testWidgets('branch expansion loads, renders, and retries', (tester) async {
    final actions = <SubagentAction>[];
    await _pump(
      tester,
      const SubagentUiState(
        sessions: _sessions,
        selectedParentId: 'p1',
        catalog: _catalog,
      ),
      actions,
    );

    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pump();
    expect(actions, contains(const LoadSubagentBranch(_workerId)));
    // Web CatalogLoadingRows placeholder while the branch hydrates.
    expect(find.text('Loading subagents…'), findsOneWidget);

    await _pump(
      tester,
      const SubagentUiState(
        sessions: _sessions,
        selectedParentId: 'p1',
        catalog: _catalog,
        branchCatalogs: {
          _workerId: SubagentCatalog(
            parentSessionId: _workerId,
            parentAvailable: true,
            entries: [
              SubagentEntry(
                id: 'grand-1',
                kind: 'child',
                mode: 'continuable',
                activity: 'inactive',
              ),
            ],
          ),
        },
      ),
      actions,
    );
    expect(find.text('grand-1'), findsOneWidget);
    expect(find.text('continuable · not running'), findsOneWidget);

    // A failed branch shows the web error row and retries.
    await _pump(
      tester,
      const SubagentUiState(
        sessions: _sessions,
        selectedParentId: 'p1',
        catalog: _catalog,
        branchFailures: {_workerId},
      ),
      actions,
    );
    expect(find.text('Unable to load subagents'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(
      actions.whereType<LoadSubagentBranch>(),
      contains(const LoadSubagentBranch(_workerId)),
    );
  });

  testWidgets('child detail renders real timeline rows', (tester) async {
    await _pump(
      tester,
      const SubagentUiState(
        sessions: _sessions,
        selectedParentId: 'p1',
        catalog: _catalog,
        selectedChildId: _workerId,
        childTimeline: [
          TimelineMessage(
            ChatMessage(
              id: 'm1',
              sessionId: _workerId,
              role: MessageRole.user,
              text: 'do the thing',
            ),
          ),
          TimelineToolCall(
            id: 't1',
            name: 'bash',
            arguments: '{"command":"ls"}',
            status: ToolRunStatus.completed,
          ),
        ],
      ),
      [],
    );

    // Real chat rows, not the raw per-kind text switch.
    expect(find.byType(TimelineRow), findsNWidgets(2));
    expect(find.byType(MessageRow), findsOneWidget);
    // The user message renders as the bubble (ds.bubble fill).
    final bubble = find.byWidgetPredicate((widget) {
      if (widget is! Container) return false;
      final decoration = widget.decoration;
      return decoration is BoxDecoration &&
          decoration.color == DeepSuiteColors.light().bubble;
    });
    expect(bubble, findsOneWidget);
    expect(find.byType(ToolCallRow), findsOneWidget);
    expect(find.text('Bash'), findsOneWidget);
  });

  testWidgets('continuable child with parent online keeps the composer', (
    tester,
  ) async {
    final actions = <SubagentAction>[];
    await _pump(
      tester,
      const SubagentUiState(
        sessions: _sessions,
        selectedParentId: 'p1',
        catalog: _catalog,
        selectedChildId: _workerId,
      ),
      actions,
    );

    final field = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.hintText == 'Message selected subagent',
    );
    expect(field, findsOneWidget);
    await tester.enterText(field, 'keep going');
    await tester.pump();
    await tester.tap(find.text('Send'));
    await tester.pump();
    expect(actions, contains(const SendSubagentPrompt('keep going')));
  });

  testWidgets('one-shot child shows the read-only notice, no message field', (
    tester,
  ) async {
    final actions = <SubagentAction>[];
    await _pump(
      tester,
      const SubagentUiState(
        sessions: _sessions,
        selectedParentId: 'p1',
        catalog: _catalog,
        selectedChildId: 'one-shot-1',
      ),
      actions,
    );

    expect(find.text('One-shot subagent record'), findsOneWidget);
    expect(
      find.text(
        'One-shot tasks do not accept follow-ups; '
        'review the full execution record here.',
      ),
      findsOneWidget,
    );
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Send'), findsNothing);
  });

  testWidgets('parent-offline child shows the parent-unavailable notice', (
    tester,
  ) async {
    await _pump(
      tester,
      const SubagentUiState(
        sessions: _sessions,
        selectedParentId: 'p1',
        catalog: _offlineCatalog,
        selectedChildId: _workerId,
      ),
      [],
    );

    expect(find.text('This subagent is read-only for now'), findsOneWidget);
    expect(
      find.text(
        'The parent session is offline; reopen it to continue sending '
        'messages.',
      ),
      findsOneWidget,
    );
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('queued messages render read-only previews', (tester) async {
    await _pump(
      tester,
      const SubagentUiState(
        sessions: _sessions,
        selectedParentId: 'p1',
        catalog: _catalog,
        selectedChildId: _workerId,
        childTimeline: [
          TimelineMessage(
            ChatMessage(
              id: 'm1',
              sessionId: _workerId,
              role: MessageRole.assistant,
              text: 'working on it',
            ),
          ),
          TimelineQueue(
            items: [
              SessionQueueItem(
                itemId: 'q1',
                placement: QueuePlacement.queued,
                text: 'queued work',
              ),
            ],
          ),
        ],
      ),
      [],
    );

    // The queue rides the dock above the composer, not a timeline row.
    expect(find.byType(TimelineRow), findsOneWidget);
    expect(find.text('Queued: queued work'), findsOneWidget);
    // queueMutable = false on a child view: no edit/steer/remove controls.
    expect(find.text('Edit'), findsNothing);
    expect(find.text('Steer'), findsNothing);
    expect(find.text('Remove'), findsNothing);
  });

  testWidgets('child plan rides the read-only plan chip', (tester) async {
    await _pump(
      tester,
      const SubagentUiState(
        sessions: _sessions,
        selectedParentId: 'p1',
        catalog: _catalog,
        selectedChildId: _workerId,
        childPlan: PlanState(active: true, pending: false),
      ),
      [],
    );

    // Warn pill only while the target is plan mode; tap stays disabled.
    expect(find.byType(PlanChip), findsOneWidget);
    expect(tester.widget<PlanChip>(find.byType(PlanChip)).locked, isTrue);
    expect(find.text('Plan'), findsOneWidget);

    await _pump(
      tester,
      const SubagentUiState(
        sessions: _sessions,
        selectedParentId: 'p1',
        catalog: _catalog,
        selectedChildId: _workerId,
        childPlan: PlanState(active: false, pending: false),
      ),
      [],
    );
    expect(find.text('Plan'), findsNothing);
  });

  testWidgets('running continuable child offers stop; back closes the record', (
    tester,
  ) async {
    final actions = <SubagentAction>[];
    await _pump(
      tester,
      const SubagentUiState(
        sessions: _sessions,
        selectedParentId: 'p1',
        catalog: _catalog,
        selectedChildId: _workerId,
      ),
      actions,
    );

    await tester.tap(find.byIcon(Icons.stop_circle_outlined));
    await tester.pump();
    expect(actions, contains(const InterruptSubagent(_workerId)));

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pump();
    expect(actions, contains(const CloseChildView()));
    // The catalog is back.
    expect(find.text('Worker'), findsOneWidget);
  });

  testWidgets('catalog refresh dispatches from the app bar', (tester) async {
    final actions = <SubagentAction>[];
    await _pump(
      tester,
      const SubagentUiState(
        sessions: _sessions,
        selectedParentId: 'p1',
        catalog: _catalog,
      ),
      actions,
    );

    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pump();
    expect(actions, contains(const RefreshSubagentsAction()));
  });
}
