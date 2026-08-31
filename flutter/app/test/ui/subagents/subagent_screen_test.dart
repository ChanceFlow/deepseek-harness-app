/// SubagentScreen widget parity tests — the web catalog semantics this
/// port must keep (reference/deepseek-harness/packages/client/
/// ui-subagent/src/client/): catalog tree rows with StateDot + secondary
/// line, branch expansion, diagnostic rows, the child detail view over
/// the real TimelineRow, read-only composers, and read-only queued
/// messages. The design-language group pins the framework form: rows
/// render as `ListTile`s over the shared `StateDot`, the host failure
/// rides a native `MaterialBanner`, and the branch loading row wears the
/// timeline's activity language (`ActivityDot` + `SweepHighlight`) —
/// colors read back under both brightnesses.
library;

import 'package:domain/model/chat_message.dart';
import 'package:domain/model/plan.dart';
import 'package:domain/model/session.dart';
import 'package:domain/model/subagent.dart';
import 'package:domain/model/timeline_item.dart';
import 'package:domain/repository/chat_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/di/providers.dart';
import 'package:app/ui/chat/activity_dot.dart';
import 'package:app/ui/chat/chat_screen.dart'
    show MessageRow, PlanChip, TimelineRow, ToolCallRow;
import 'package:app/ui/chat/sweep_highlight.dart';
import 'package:app/ui/state_stream.dart';
import 'package:app/ui/shared/state_dot.dart';
import 'package:app/ui/subagents/subagent_controller.dart';
import 'package:app/ui/subagents/subagent_screen.dart';
import 'package:app/ui/subagents/subagent_ui_state.dart';
import 'package:app/ui/theme/theme.dart';

import '../../l10n_app.dart';

const _workerId = 'child-12345678abcd';

const _catalog = SubagentCatalog(
  parentSessionId: 'p1',
  parentAvailable: true,
  entries: [
    SubagentEntry(
      id: _workerId,
      kind: 'child',
      mode: SubagentMode.continuable,
      activity: 'running',
      hasChildren: true,
      label: 'Worker',
    ),
    SubagentEntry(
      id: 'one-shot-1',
      kind: 'child',
      mode: SubagentMode.oneShot,
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
      mode: SubagentMode.continuable,
      activity: 'running',
      hasChildren: true,
      label: 'Worker',
    ),
  ],
);

Future<void> _pump(
  WidgetTester tester,
  SubagentUiState uiState,
  List<SubagentAction> actions, {
  ThemeData? theme,
}) {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  return tester.pumpWidget(
    l10nApp(
      theme: theme,
      home: SubagentScreen(uiState: uiState, onAction: actions.add),
    ),
  );
}

Finder _dot(StateDotState state) => find.byWidgetPredicate(
  (widget) => widget is StateDot && widget.state == state,
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
    expect(_dot(StateDotState.ongoing), findsOneWidget);
    expect(_dot(StateDotState.done), findsOneWidget);
    expect(_dot(StateDotState.error), findsOneWidget);
  });

  group('design language', () {
    testWidgets('catalog, diagnostic, and selector rows ride ListTile', (
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

      // Every row is a framework ListTile — no hand-built InkWell rows.
      for (final label in ['Worker', 'one-shot-1', 'broken-1', 'Parent one']) {
        expect(
          find.ancestor(of: find.text(label), matching: find.byType(ListTile)),
          findsOneWidget,
          reason: '"$label" should render inside a ListTile',
        );
      }
    });

    testWidgets('the expanded branch loads in the timeline activity '
        'language, never an inline spinner', (tester) async {
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
      expect(find.byType(ActivityDot), findsOneWidget);
      final loadingRow = find
          .ancestor(
            of: find.text('Loading subagents…'),
            matching: find.byType(ListTile),
          )
          .first;
      expect(loadingRow, findsOneWidget);
      expect(
        find
            .descendant(of: loadingRow, matching: find.byType(SweepHighlight))
            .first,
        findsOneWidget,
      );
      expect(find.byType(CircularProgressIndicator), findsNothing);
      // Disclosure is the icon swap (right → down), not a hand-rolled
      // rotation curve.
      expect(find.byIcon(Icons.expand_more), findsWidgets);
      expect(find.byIcon(Icons.chevron_right), findsNothing);
    });

    testWidgets('reduce-motion hands the sweep a null controller', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        l10nApp(
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: SubagentScreen(
                uiState: const SubagentUiState(
                  sessions: _sessions,
                  selectedParentId: 'p1',
                  catalog: _catalog,
                ),
                onAction: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byIcon(Icons.chevron_right));
      await tester.pump();
      final sweep = tester.widget<SweepHighlight>(
        find.byType(SweepHighlight).first,
      );
      expect(sweep.controller, isNull);
      expect(find.text('Loading subagents…'), findsOneWidget);
    });

    testWidgets('the parent sheet lists session rows as ListTiles', (
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
      expect(
        find.ancestor(
          of: find.text('Parent two'),
          matching: find.byType(ListTile),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a host failure rides the native MaterialBanner under both '
        'brightnesses', (tester) async {
      for (final theme in [DshTheme.light(), DshTheme.dark()]) {
        final actions = <SubagentAction>[];
        await _pump(
          tester,
          const SubagentUiState(
            sessions: _sessions,
            selectedParentId: 'p1',
            catalog: _catalog,
            errorMessage: 'subagent.prompt rejected by host',
          ),
          actions,
          theme: theme,
        );
        await tester.pump(const Duration(milliseconds: 400));

        final banner = tester.widget<MaterialBanner>(
          find.byType(MaterialBanner),
        );
        expect(find.text('subagent.prompt rejected by host'), findsOneWidget);
        expect(banner.backgroundColor, theme.colorScheme.errorContainer);
        expect(
          tester
              .widget<Text>(
                find.descendant(
                  of: find.byType(MaterialBanner),
                  matching: find.byType(Text),
                ),
              )
              .style!
              .color,
          theme.colorScheme.onErrorContainer,
        );

        await tester.tap(find.byTooltip('Dismiss'));
        await tester.pump();
        expect(actions, contains(const DismissSubagentError()));
      }
    });

    testWidgets('the selector caption and row dots read their theme roles', (
      tester,
    ) async {
      for (final theme in [DshTheme.light(), DshTheme.dark()]) {
        await _pump(
          tester,
          const SubagentUiState(
            sessions: _sessions,
            selectedParentId: 'p1',
            catalog: _catalog,
          ),
          [],
          theme: theme,
        );
        await tester.pump(const Duration(milliseconds: 400));

        // outline was the violation; metadata rides onSurfaceVariant.
        expect(
          tester.widget<Text>(find.text('Parent session')).style?.color,
          theme.colorScheme.onSurfaceVariant,
        );
        // The shared StateDot core runs on the primary role while a child
        // is active — no call-site blue.
        final core = tester.widget<Container>(
          find
              .descendant(
                of: _dot(StateDotState.ongoing),
                matching: find.byType(Container),
              )
              .last,
        );
        expect(
          (core.decoration! as BoxDecoration).color,
          theme.colorScheme.primary,
        );
      }
    });

    testWidgets('the read-only notice is a borderless card on the shape '
        'scale', (tester) async {
      await _pump(
        tester,
        const SubagentUiState(
          sessions: _sessions,
          selectedParentId: 'p1',
          catalog: _catalog,
          selectedChildId: 'one-shot-1',
        ),
        [],
      );

      final card = tester.widget<Container>(
        find
            .ancestor(
              of: find.text('One-shot subagent record'),
              matching: find.byType(Container),
            )
            .first,
      );
      final decoration = card.decoration! as BoxDecoration;
      expect(decoration.borderRadius, BorderRadius.circular(kShapeCard));
      expect(decoration.border, isNull);
    });
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
    expect(
      actions,
      contains(
        const OpenChild(
          _workerId,
          SubagentMode.continuable,
          parentSessionId: 'p1',
        ),
      ),
    );
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
                mode: SubagentMode.continuable,
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
    // The user message renders as the transcript bubble, tinted with the
    // scheme's secondary container rather than painted flat.
    final bubbleColor = Theme.of(tester.element(find.text('do the thing')))
        .colorScheme
        .secondaryContainer;
    final bubble = find.byWidgetPredicate(
      (widget) => widget is Material && widget.color == bubbleColor,
    );
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
    expect(find.text('queued work'), findsOneWidget);
    // queueMutable = false on a child view: no edit/steer/remove controls.
    expect(find.byTooltip('Edit queued message'), findsNothing);
    expect(find.byTooltip('Steer'), findsNothing);
    expect(find.byTooltip('Remove queued message'), findsNothing);
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
    expect(
      actions,
      contains(const InterruptSubagent(_workerId, parentSessionId: 'p1')),
    );

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pump();
    expect(actions, contains(const CloseChildView()));
    // The catalog is back.
    expect(find.text('Worker'), findsOneWidget);
  });

  testWidgets(
    'tapping nested (grandchild) row dispatches OpenChild with direct parent id',
    (tester) async {
      const rootCatalog = SubagentCatalog(
        parentSessionId: 'p1',
        parentAvailable: true,
        entries: [
          SubagentEntry(
            id: 'child-1',
            kind: 'child',
            mode: SubagentMode.continuable,
            activity: 'running',
            hasChildren: true,
            label: 'Branch Child',
          ),
        ],
      );
      const branchCatalog = SubagentCatalog(
        parentSessionId: 'child-1',
        parentAvailable: true,
        entries: [
          SubagentEntry(
            id: 'grand-1',
            kind: 'child',
            mode: SubagentMode.continuable,
            activity: 'running',
            label: 'Grandchild Worker',
          ),
        ],
      );

      final actions = <SubagentAction>[];
      await _pump(
        tester,
        const SubagentUiState(
          sessions: _sessions,
          selectedParentId: 'p1',
          catalog: rootCatalog,
          branchCatalogs: {'child-1': branchCatalog},
        ),
        actions,
      );

      // Expand branch child-1
      await tester.tap(find.byIcon(Icons.chevron_right));
      await tester.pump();

      // Grandchild is now visible
      expect(find.text('Grandchild Worker'), findsOneWidget);

      // Tap grandchild row
      await tester.tap(find.text('Grandchild Worker'));
      await tester.pump();

      expect(
        actions,
        contains(
          const OpenChild(
            'grand-1',
            SubagentMode.continuable,
            parentSessionId: 'child-1',
          ),
        ),
      );
    },
  );

  testWidgets(
    'opened grandchild detail stop button dispatches InterruptSubagent with direct parent',
    (tester) async {
      const rootCatalog = SubagentCatalog(
        parentSessionId: 'p1',
        parentAvailable: true,
        entries: [
          SubagentEntry(
            id: 'child-1',
            kind: 'child',
            mode: SubagentMode.continuable,
            activity: 'running',
            hasChildren: true,
            label: 'Branch Child',
          ),
        ],
      );
      const branchCatalog = SubagentCatalog(
        parentSessionId: 'child-1',
        parentAvailable: true,
        entries: [
          SubagentEntry(
            id: 'grand-1',
            kind: 'child',
            mode: SubagentMode.continuable,
            activity: 'running',
            label: 'Grandchild Worker',
          ),
        ],
      );

      final actions = <SubagentAction>[];
      await _pump(
        tester,
        const SubagentUiState(
          sessions: _sessions,
          selectedParentId: 'p1',
          catalog: rootCatalog,
          branchCatalogs: {'child-1': branchCatalog},
          selectedChildId: 'grand-1',
          selectedChildParentId: 'child-1',
        ),
        actions,
      );

      await tester.tap(find.byIcon(Icons.stop_circle_outlined));
      await tester.pump();
      expect(
        actions,
        contains(
          const InterruptSubagent('grand-1', parentSessionId: 'child-1'),
        ),
      );
    },
  );

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

  testWidgets(
    'route cold-open with a pre-selected parent shows the host rows',
    (tester) async {
      // The reported defect: the screen opened for a session that had
      // subagents rendered its "No subagents" empty state until the user
      // pressed refresh. Drives the real SubagentRoute → real
      // SubagentController over a repository whose `subagent.list`-equivalent
      // answers the host-reported tree; no user gesture.
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repository = _HostCatalogRepository();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            subagentControllerProvider('b1').overrideWith(
              (ref) => SubagentController(repository, initialSessionId: 'p1'),
            ),
          ],
          child: l10nApp(home: const SubagentRoute(backendId: 'b1')),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Worker'), findsOneWidget);
      expect(find.text('No subagents'), findsNothing);
      // The parent selector row resolves the pre-selected session.
      expect(find.text('Parent one'), findsOneWidget);
    },
  );
}

/// Serves the host-reported tree through the cold-seed path: sessions and
/// the catalog both answer for `p1` with the same rows the catalog tree
/// tests render from a pre-built state.
class _HostCatalogRepository implements ChatRepository {
  final AppStateStream<List<SessionSummary>> _sessions =
      AppStateStream<List<SessionSummary>>(const <SessionSummary>[
        SessionSummary(id: 'p1', title: 'Parent one', blank: false),
      ]);

  @override
  Stream<List<SessionSummary>> observeSessions() => _sessions.stream;

  @override
  Future<SubagentCatalog> loadSubagents(String parentSessionId) async =>
      _catalog;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('${invocation.memberName}');
}
