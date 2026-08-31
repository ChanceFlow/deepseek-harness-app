/// SubagentController tests. The catalog tree is a host-reported fact
/// (`subagent.list` reads durable state): the cold-seed tests pin that a
/// pre-selected parent's tree publishes without a user gesture, and the
/// event-refresh tests pin its upkeep — child rows in `session.list`
/// carry their `parentSessionId`, and a spawn or detachment under a
/// watched parent schedules one debounced catalog re-pull per parent.
/// History addressing pins the row's own mode on the `subagent.history`
/// request, and the sheet visibility pins the app-wide rule that
/// subagent children never surface as selectable parents.
library;

import 'package:app/ui/state_stream.dart';
import 'package:app/ui/subagents/subagent_controller.dart';
import 'package:app/ui/subagents/subagent_ui_state.dart';
import 'package:domain/model/plan.dart';
import 'package:domain/model/session.dart';
import 'package:domain/model/subagent.dart';
import 'package:domain/model/timeline_item.dart';
import 'package:domain/repository/chat_repository.dart';
import 'package:flutter_test/flutter_test.dart';

const _parent = SessionSummary(id: 'p1', title: 'Parent one', blank: false);
const _childRow = SessionSummary(
  id: 'child-1',
  title: 'Worker',
  blank: false,
  origin: 'subagent',
);

/// One attributed child row as the host's `session.list` answers it
/// (`sessionSummarySchema`: `parentSessionId` + `origin: 'subagent'`).
SessionSummary _childOf(String id, {bool running = false}) => SessionSummary(
  id: id,
  title: 'Child $id',
  blank: false,
  origin: 'subagent',
  parentSessionId: 'p1',
  running: running,
);

/// Waits past the controller's catalog-refresh debounce window and lets
/// the scheduled pulls settle.
Future<void> _pastDebounceWindow() async {
  await Future<void>.delayed(const Duration(milliseconds: 120));
  await pumpEventQueue();
}

const _worker = SubagentEntry(
  id: 'child-1',
  kind: 'child',
  mode: SubagentMode.continuable,
  activity: 'running',
  label: 'Worker',
);

const _seedCatalog = SubagentCatalog(
  parentSessionId: 'p1',
  entries: [_worker],
  parentAvailable: true,
);

void main() {
  test(
    'cold open with a pre-selected parent seeds the host catalog once',
    () async {
      final repository = _FakeRepository(catalog: _seedCatalog);
      final controller = SubagentController(repository, initialSessionId: 'p1');
      addTearDown(controller.dispose);

      repository.sessions.value = const <SessionSummary>[_parent, _childRow];
      await pumpEventQueue();

      expect(repository.catalogRequests, <String>['p1']);
      expect(controller.state.selectedParentId, 'p1');
      expect(controller.state.catalog.entries, const <SubagentEntry>[_worker]);
      expect(controller.state.isLoading, isFalse);
      expect(controller.state.errorMessage, isNull);

      // A further session publication without a child-membership change
      // re-seeds nothing: upkeep flows through the membership-event
      // refresh below and the explicit refresh action.
      repository.sessions.value = const <SessionSummary>[_parent];
      await pumpEventQueue();
      expect(repository.catalogRequests, <String>['p1']);
    },
  );

  // ---------------------------------------------------------------------
  // Event-driven catalog upkeep (web manager `scheduleCatalogRefresh`):
  // session.added/removed frames repull `session.list`, whose child rows
  // carry `parentSessionId` — the controller turns those membership
  // changes into debounced catalog re-pulls, independent of the cold
  // seed's once-per-parent suppression.
  // ---------------------------------------------------------------------

  test('a spawned child triggers one debounced catalog re-pull', () async {
    final repository = _FakeRepository(catalog: _seedCatalog);
    final controller = SubagentController(repository, initialSessionId: 'p1');
    addTearDown(controller.dispose);

    repository.sessions.value = <SessionSummary>[
      _parent,
      _childOf('child-1', running: true),
    ];
    await pumpEventQueue();
    // The cold seed owns the first pull; the baseline alone schedules
    // nothing.
    expect(repository.catalogRequests, <String>['p1']);

    // A new spawn lands in the host's list.
    repository.sessions.value = <SessionSummary>[
      _parent,
      _childOf('child-1', running: true),
      _childOf('child-2'),
    ];
    await pumpEventQueue();
    // Still inside the debounce window: no second pull yet.
    expect(repository.catalogRequests, <String>['p1']);

    // A burst of publications inside the same window merges into one
    // re-pull.
    repository.sessions.value = <SessionSummary>[
      _parent,
      _childOf('child-1', running: true),
      _childOf('child-2'),
      _childOf('child-3'),
    ];
    await _pastDebounceWindow();

    // The event re-pull runs despite the cold seed having already
    // requested this parent: the seed gate suppresses seeds, not upkeep.
    expect(repository.catalogRequests, <String>['p1', 'p1']);
  });

  test('a detached child dims its row at once and re-pulls the tree', () async {
    final repository = _FakeRepository(catalog: _seedCatalog);
    final controller = SubagentController(repository, initialSessionId: 'p1');
    addTearDown(controller.dispose);

    repository.sessions.value = <SessionSummary>[
      _parent,
      _childOf('child-1', running: true),
    ];
    await pumpEventQueue();
    expect(controller.state.catalog.entries.single.activity, 'running');

    // session-removed: the child leaves the host's list. Its loaded
    // catalog row folds to inactive locally (web
    // `updateCatalogActivity`) before the pull lands, so the status
    // dot never outlives the child.
    repository.sessions.value = <SessionSummary>[_parent];
    await pumpEventQueue();
    expect(controller.state.catalog.entries.single.activity, 'inactive');

    await _pastDebounceWindow();
    expect(repository.catalogRequests, <String>['p1', 'p1']);
  });

  test('a stopped-but-listed child folds the dot without a re-pull', () async {
    final repository = _FakeRepository(catalog: _seedCatalog);
    final controller = SubagentController(repository, initialSessionId: 'p1');
    addTearDown(controller.dispose);

    repository.sessions.value = <SessionSummary>[
      _parent,
      _childOf('child-1', running: true),
    ];
    await pumpEventQueue();

    // running→stopped with the row still listed: membership is stable,
    // so only the local activity fold runs (web session-status parity).
    repository.sessions.value = <SessionSummary>[_parent, _childOf('child-1')];
    await _pastDebounceWindow();
    expect(controller.state.catalog.entries.single.activity, 'inactive');

    // A resumed child relights its dot the same way — the fold is
    // symmetric and still pulls nothing.
    repository.sessions.value = <SessionSummary>[
      _parent,
      _childOf('child-1', running: true),
    ];
    await _pastDebounceWindow();
    expect(controller.state.catalog.entries.single.activity, 'running');
    expect(repository.catalogRequests, <String>['p1']);
  });

  // ---------------------------------------------------------------------
  // History addressing: `subagent.history` carries the row's own mode;
  // the host answers a mismatch with `subagent-not-found`.
  // ---------------------------------------------------------------------

  test(
    'opening a child requests history under the catalog mode it carries',
    () async {
      final repository = _FakeRepository(catalog: _seedCatalog);
      final controller = SubagentController(repository, initialSessionId: 'p1');
      addTearDown(controller.dispose);

      repository.sessions.value = const <SessionSummary>[_parent];
      await pumpEventQueue();
      controller.onAction(const OpenChild('child-2', SubagentMode.oneShot));
      await pumpEventQueue();

      final call = repository.historyRequests.single;
      expect(
        (call.parentSessionId, call.childSessionId, call.mode),
        ('p1', 'child-2', SubagentMode.oneShot),
      );
      expect(controller.state.selectedChildId, 'child-2');
    },
  );

  test(
    'a failed child history surfaces, never a fake-empty transcript',
    () async {
      final repository = _FakeRepository(catalog: _seedCatalog)
        ..failHistoryWith = StateError(
          'subagent-not-found: session "child-2" is not a continuable '
          'direct child of "p1"',
        );
      final controller = SubagentController(repository, initialSessionId: 'p1');
      addTearDown(controller.dispose);

      repository.sessions.value = const <SessionSummary>[_parent];
      await pumpEventQueue();
      controller.onAction(const OpenChild('child-2', SubagentMode.continuable));
      await pumpEventQueue();

      expect(controller.state.errorMessage, contains('subagent-not-found'));
      // The record view closes instead of holding the child open on an
      // empty transcript that reads as "no messages".
      expect(controller.state.selectedChildId, isNull);
      expect(controller.state.isChildLoading, isFalse);
    },
  );

  test(
    'a branch child gates the composer on its own level availability',
    () async {
      const rootCatalog = SubagentCatalog(
        parentSessionId: 'p1',
        parentAvailable: true,
        entries: [
          SubagentEntry(
            id: 'child-1',
            kind: 'child',
            mode: SubagentMode.continuable,
            activity: 'inactive',
            hasChildren: true,
          ),
        ],
      );
      const branchCatalog = SubagentCatalog(
        parentSessionId: 'child-1',
        parentAvailable: false,
        entries: [
          SubagentEntry(
            id: 'grand-1',
            kind: 'child',
            mode: SubagentMode.continuable,
            activity: 'inactive',
          ),
        ],
      );
      final repository = _FakeRepository(catalog: rootCatalog)
        ..branchCatalog = (parent) =>
            parent == 'child-1' ? branchCatalog : null;
      final controller = SubagentController(repository, initialSessionId: 'p1');
      addTearDown(controller.dispose);

      repository.sessions.value = <SessionSummary>[
        _parent,
        _childOf('child-1'),
      ];
      await pumpEventQueue();
      controller.onAction(const LoadSubagentBranch('child-1'));
      await pumpEventQueue();
      controller.onAction(
        const OpenChild(
          'grand-1',
          SubagentMode.continuable,
          parentSessionId: 'child-1',
        ),
      );
      await pumpEventQueue();

      // The root tree reports its parent online; grand-1's owning level
      // (child-1 offline) is what gates the composer.
      expect(controller.state.selectedChildEntry?.id, 'grand-1');
      expect(
        controller.state.childReadOnlyReason,
        SubagentReadOnlyReason.parentUnavailable,
      );
    },
  );

  test(
    'opening a nested (grandchild) row requests history under direct parent id',
    () async {
      const rootCatalog = SubagentCatalog(
        parentSessionId: 'p1',
        parentAvailable: true,
        entries: [
          SubagentEntry(
            id: 'child-1',
            kind: 'child',
            mode: SubagentMode.continuable,
            activity: 'inactive',
            hasChildren: true,
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
          ),
        ],
      );
      final repository = _FakeRepository(catalog: rootCatalog)
        ..branchCatalog = (parent) =>
            parent == 'child-1' ? branchCatalog : null;
      final controller = SubagentController(repository, initialSessionId: 'p1');
      addTearDown(controller.dispose);

      repository.sessions.value = <SessionSummary>[
        _parent,
        _childOf('child-1'),
      ];
      await pumpEventQueue();
      controller.onAction(const LoadSubagentBranch('child-1'));
      await pumpEventQueue();
      controller.onAction(
        const OpenChild(
          'grand-1',
          SubagentMode.continuable,
          parentSessionId: 'child-1',
        ),
      );
      await pumpEventQueue();

      final call = repository.historyRequests.single;
      expect(
        (call.parentSessionId, call.childSessionId, call.mode),
        ('child-1', 'grand-1', SubagentMode.continuable),
      );
      expect(controller.state.selectedChildId, 'grand-1');
      expect(controller.state.selectedChildParentId, 'child-1');
    },
  );

  test(
    'prompt and interrupt on a nested (grandchild) address the direct parent',
    () async {
      const rootCatalog = SubagentCatalog(
        parentSessionId: 'p1',
        parentAvailable: true,
        entries: [
          SubagentEntry(
            id: 'child-1',
            kind: 'child',
            mode: SubagentMode.continuable,
            activity: 'inactive',
            hasChildren: true,
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
          ),
        ],
      );
      final repository = _FakeRepository(catalog: rootCatalog)
        ..branchCatalog = (parent) =>
            parent == 'child-1' ? branchCatalog : null;
      final controller = SubagentController(repository, initialSessionId: 'p1');
      addTearDown(controller.dispose);

      repository.sessions.value = <SessionSummary>[
        _parent,
        _childOf('child-1'),
      ];
      await pumpEventQueue();
      controller.onAction(const LoadSubagentBranch('child-1'));
      await pumpEventQueue();
      controller.onAction(
        const OpenChild(
          'grand-1',
          SubagentMode.continuable,
          parentSessionId: 'child-1',
        ),
      );
      await pumpEventQueue();

      // Sending a prompt uses the direct parent 'child-1', NOT root 'p1'.
      controller.onAction(const SendSubagentPrompt('hello grandchild'));
      await pumpEventQueue();
      final promptCall = repository.promptRequests.single;
      expect(
        (
          promptCall.parentSessionId,
          promptCall.childSessionId,
          promptCall.text,
        ),
        ('child-1', 'grand-1', 'hello grandchild'),
      );
      // History reload following prompt also uses direct parent 'child-1'.
      expect(
        repository.historyRequests
            .map((c) => (c.parentSessionId, c.childSessionId, c.mode))
            .toList(),
        <(String, String, SubagentMode)>[
          ('child-1', 'grand-1', SubagentMode.continuable),
          ('child-1', 'grand-1', SubagentMode.continuable),
        ],
      );

      // Interrupt uses the direct parent 'child-1', NOT root 'p1'.
      controller.onAction(
        const InterruptSubagent('grand-1', parentSessionId: 'child-1'),
      );
      await pumpEventQueue();
      final interruptCall = repository.interruptRequests.single;
      expect(
        (interruptCall.parentSessionId, interruptCall.childSessionId),
        ('child-1', 'grand-1'),
      );
      // Interrupt reloads the branch catalog for 'child-1'.
      expect(repository.catalogRequests, contains('child-1'));
    },
  );

  test(
    're-opening a different child rebinds both child and direct parent',
    () async {
      const rootCatalog = SubagentCatalog(
        parentSessionId: 'p1',
        parentAvailable: true,
        entries: [
          SubagentEntry(
            id: 'child-1',
            kind: 'child',
            mode: SubagentMode.continuable,
            activity: 'inactive',
            hasChildren: true,
          ),
          SubagentEntry(
            id: 'child-2',
            kind: 'child',
            mode: SubagentMode.continuable,
            activity: 'running',
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
          ),
        ],
      );
      final repository = _FakeRepository(catalog: rootCatalog)
        ..branchCatalog = (parent) =>
            parent == 'child-1' ? branchCatalog : null;
      final controller = SubagentController(repository, initialSessionId: 'p1');
      addTearDown(controller.dispose);

      repository.sessions.value = <SessionSummary>[
        _parent,
        _childOf('child-1'),
        _childOf('child-2'),
      ];
      await pumpEventQueue();
      controller.onAction(const LoadSubagentBranch('child-1'));
      await pumpEventQueue();

      // Open grandchild first: direct parent is 'child-1'
      controller.onAction(
        const OpenChild(
          'grand-1',
          SubagentMode.continuable,
          parentSessionId: 'child-1',
        ),
      );
      await pumpEventQueue();
      expect(controller.state.selectedChildId, 'grand-1');
      expect(controller.state.selectedChildParentId, 'child-1');

      // Now open depth-1 child-2: direct parent is 'p1'
      controller.onAction(
        const OpenChild(
          'child-2',
          SubagentMode.continuable,
          parentSessionId: 'p1',
        ),
      );
      await pumpEventQueue();
      expect(controller.state.selectedChildId, 'child-2');
      expect(controller.state.selectedChildParentId, 'p1');

      // Send prompt targets 'p1', 'child-2'
      controller.onAction(const SendSubagentPrompt('for child 2'));
      await pumpEventQueue();
      final promptCall = repository.promptRequests.single;
      expect(
        (
          promptCall.parentSessionId,
          promptCall.childSessionId,
          promptCall.text,
        ),
        ('p1', 'child-2', 'for child 2'),
      );
    },
  );

  // ---------------------------------------------------------------------
  // Sheet visibility: the app-wide rule (web tree.ts `sessionVisible`)
  // keeps subagent children off every session list — including the
  // parent picker.
  // ---------------------------------------------------------------------

  test('the parent sheet never lists a subagent child as a parent', () async {
    final repository = _FakeRepository(catalog: _seedCatalog);
    final controller = SubagentController(repository, initialSessionId: 'p1');
    addTearDown(controller.dispose);

    repository.sessions.value = <SessionSummary>[
      _parent,
      _childOf('child-1', running: true),
      const SessionSummary(id: 'p2', title: 'Parent two', blank: false),
      const SessionSummary(id: 'blank-1', blank: true),
    ];
    await pumpEventQueue();

    expect(controller.state.sessions.map((session) => session.id), <String>[
      'p1',
      'p2',
    ]);
  });

  test(
    'no catalog load is requested before the host reports the parent',
    () async {
      final repository = _FakeRepository(catalog: _seedCatalog);
      final controller = SubagentController(repository, initialSessionId: 'p1');
      addTearDown(controller.dispose);

      // The seed publication omits the selected parent: nothing to seed on.
      repository.sessions.value = const <SessionSummary>[_childRow];
      await pumpEventQueue();
      expect(repository.catalogRequests, isEmpty);

      repository.sessions.value = const <SessionSummary>[_parent, _childRow];
      await pumpEventQueue();
      expect(repository.catalogRequests, <String>['p1']);
    },
  );

  test('no auto-load without a pre-selected parent', () async {
    final repository = _FakeRepository(catalog: _seedCatalog);
    final controller = SubagentController(repository);
    addTearDown(controller.dispose);

    repository.sessions.value = const <SessionSummary>[_parent];
    await pumpEventQueue();

    expect(repository.catalogRequests, isEmpty);
    expect(controller.state.selectedParentId, isNull);
    expect(controller.state.catalog.entries, isEmpty);
  });

  test('an explicit selection supersedes the pending cold seed', () async {
    final repository = _FakeRepository(catalog: _seedCatalog);
    final controller = SubagentController(repository, initialSessionId: 'p1');
    addTearDown(controller.dispose);

    controller.onAction(const SelectParent('p2'));
    await pumpEventQueue();
    expect(repository.catalogRequests, <String>['p2']);

    repository.sessions.value = const <SessionSummary>[
      _parent,
      SessionSummary(id: 'p2', title: 'Parent two', blank: false),
    ];
    await pumpEventQueue();
    // p1 arrived late but the tree belongs to the explicit selection.
    expect(repository.catalogRequests, <String>['p2']);
    expect(controller.state.selectedParentId, 'p2');
  });

  test('a failed seed surfaces, never a silent empty tree', () async {
    final repository = _FakeRepository(catalog: _seedCatalog)
      ..failCatalogWith = StateError('subagent catalog unavailable');
    final controller = SubagentController(repository, initialSessionId: 'p1');
    addTearDown(controller.dispose);

    repository.sessions.value = const <SessionSummary>[_parent];
    await pumpEventQueue();

    expect(
      controller.state.errorMessage,
      contains('subagent catalog unavailable'),
    );
    expect(controller.state.isLoading, isFalse);
  });
}

class _HistoryCall {
  _HistoryCall(this.parentSessionId, this.childSessionId, this.mode);

  final String parentSessionId;
  final String childSessionId;
  final SubagentMode mode;
}

class _PromptCall {
  _PromptCall(this.parentSessionId, this.childSessionId, this.text);

  final String parentSessionId;
  final String childSessionId;
  final String text;
}

class _InterruptCall {
  _InterruptCall(this.parentSessionId, this.childSessionId);

  final String parentSessionId;
  final String childSessionId;
}

class _FakeRepository implements ChatRepository {
  _FakeRepository({required this.catalog});

  SubagentCatalog catalog;
  SubagentCatalog? Function(String parentSessionId)? branchCatalog;
  final AppStateStream<List<SessionSummary>> sessions =
      AppStateStream<List<SessionSummary>>(const <SessionSummary>[]);
  final List<String> catalogRequests = <String>[];
  final List<_HistoryCall> historyRequests = <_HistoryCall>[];
  final List<_PromptCall> promptRequests = <_PromptCall>[];
  final List<_InterruptCall> interruptRequests = <_InterruptCall>[];
  Object? failCatalogWith;
  Object? failHistoryWith;

  @override
  Stream<List<SessionSummary>> observeSessions() => sessions.stream;

  @override
  Future<SubagentCatalog> loadSubagents(String parentSessionId) async {
    catalogRequests.add(parentSessionId);
    final failure = failCatalogWith;
    if (failure != null) throw failure;
    return branchCatalog?.call(parentSessionId) ?? catalog;
  }

  @override
  Future<List<TimelineItem>> loadSubagentHistory(
    String parentSessionId,
    String childSessionId,
    SubagentMode mode,
  ) async {
    historyRequests.add(_HistoryCall(parentSessionId, childSessionId, mode));
    final failure = failHistoryWith;
    if (failure != null) throw failure;
    return const <TimelineItem>[];
  }

  @override
  Future<String> sendSubagentPrompt(
    String parentSessionId,
    String childSessionId,
    String text,
  ) async {
    promptRequests.add(_PromptCall(parentSessionId, childSessionId, text));
    return 'msg-1';
  }

  @override
  Future<void> interruptSubagent(
    String parentSessionId,
    String childSessionId,
  ) async {
    interruptRequests.add(_InterruptCall(parentSessionId, childSessionId));
  }

  @override
  Stream<PlanState?> observePlan(String sessionId) => Stream.value(null);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('${invocation.memberName}');
}
