/// Subagents screen controller — catalog tree, child detail, and their
/// actions, mirroring the web subagent session services
/// (reference/deepseek-harness/packages/client/ui-subagent/src/client/):
/// `SubagentCatalogAction.tsx` branch expansion loads the child's own
/// catalog, and the child conversation binds the plan projection the same
/// way `ChatController` binds the selected session's.
///
/// The catalog tree is a host-reported fact: `subagent.list` reads durable
/// state, so a cold host answers the parent's complete child tree. The
/// controller seeds the pre-selected parent's tree once the host's
/// `session.list` includes that session; the newest landed snapshot owns
/// the tree (live events never merge catalog rows). Membership events keep
/// it current: child rows in `session.list` carry their `parentSessionId`,
/// and a child appearing or disappearing under the selected parent or an
/// expanded branch schedules one debounced catalog re-pull per parent
/// (web manager `scheduleCatalogRefresh`) — event re-pulls are independent
/// of the cold seed's once-per-parent suppression.
library;

import 'dart:async';

import 'package:domain/model/plan.dart';
import 'package:domain/model/session.dart';
import 'package:domain/model/subagent.dart';
import 'package:domain/model/timeline_item.dart';
import 'package:domain/repository/chat_repository.dart';

import '../shared/session_tree.dart';
import '../state_stream.dart';
import 'subagent_ui_state.dart';

class SubagentController {
  SubagentController(this._repository, {String? initialSessionId})
    : _selectedParentId = initialSessionId {
    _subs.add(
      _repository.observeSessions().listen((sessions) {
        _sessions = sessions;
        _coldSeedCatalog();
        _observeChildMembership();
        _publish();
      }),
    );
  }

  /// Web `SessionManager.scheduleCatalogRefresh` window: membership frames
  /// that land together pull the affected catalog once.
  static const Duration _catalogRefreshWindow = Duration(milliseconds: 50);

  final ChatRepository _repository;
  final AppStateStream<SubagentUiState> _state =
      AppStateStream<SubagentUiState>(const SubagentUiState());
  final List<StreamSubscription<void>> _subs = <StreamSubscription<void>>[];

  List<SessionSummary> _sessions = const <SessionSummary>[];
  String? _selectedParentId;
  SubagentCatalog _catalog = const SubagentCatalog();

  /// Parent whose cold-seed catalog load has been requested. `subagent.list`
  /// answers from durable state and every landed snapshot replaces the tree
  /// wholesale, so the seed requests a load once per selection event (cold
  /// seed, explicit select, refresh, post-action reload); later catalog
  /// upkeep rides child-membership events, which are not gated by this
  /// field (see `_observeChildMembership`).
  String? _catalogRequestedFor;
  final Map<String, SubagentCatalog> _branchCatalogs =
      <String, SubagentCatalog>{};
  final Set<String> _branchFailures = <String>{};
  String? _selectedChildId;

  /// Direct parent session id of the opened child (web
  /// `SubagentAddress.parentSessionId`).
  String? _selectedChildParentId;

  /// The opened child's catalog mode; `subagent.history` must request the
  /// child under its own mode (host `subagent-not-found` on mismatch).
  SubagentMode? _selectedChildMode;
  List<TimelineItem> _childTimeline = const <TimelineItem>[];
  StreamSubscription<void>? _planSub;
  PlanState? _childPlan;
  int _childLoadSeq = 0;
  int _catalogLoadSeq = 0;
  bool _isChildLoading = false;
  bool _isSendingChild = false;
  bool _isLoading = false;
  String? _errorMessage;

  /// Last-seen child rows (id → running) per watched parent, from the
  /// `session.list` publication — the membership-change diff baseline.
  final Map<String, Map<String, bool>> _childIdsByParent =
      <String, Map<String, bool>>{};

  /// Watched parents whose child membership changed since the last
  /// catalog load, awaiting the debounce window.
  final Set<String> _catalogRefreshPending = <String>{};
  Timer? _catalogRefreshTimer;

  SubagentUiState get state => _state.value;
  Stream<SubagentUiState> get uiState => _state.stream;

  void dispose() {
    _catalogRefreshTimer?.cancel();
    _catalogRefreshTimer = null;
    for (final sub in _subs) {
      unawaited(sub.cancel());
    }
    _subs.clear();
    unawaited(_planSub?.cancel());
    _planSub = null;
  }

  void _publish() {
    // App-wide session rule (web tree.ts `sessionVisible`): subagent
    // children never surface in the parent-picking sheet either — the
    // sidebar hides them, this sheet must not offer them as parents.
    final visible = _sessions
        .where((session) => sessionVisible(session, _selectedParentId))
        .toList();
    _state.value = SubagentUiState(
      sessions: visible,
      selectedParentId: _selectedParentId,
      catalog: _catalog,
      branchCatalogs: Map.unmodifiable(_branchCatalogs),
      branchFailures: Set.unmodifiable(_branchFailures),
      selectedChildId: _selectedChildId,
      selectedChildParentId: _selectedChildParentId,
      childTimeline: _childTimeline,
      childPlan: _childPlan,
      isChildLoading: _isChildLoading,
      isSendingChild: _isSendingChild,
      isLoading: _isLoading,
      errorMessage: _errorMessage,
    );
  }

  void onAction(SubagentAction action) {
    switch (action) {
      case SelectParent():
        _selectParent(action.sessionId);
      case OpenChild():
        _openChild(action.childSessionId, action.mode, action.parentSessionId);
      case SendSubagentPrompt():
        _sendPrompt(action.text);
      case InterruptSubagent():
        _interrupt(action.childSessionId, action.parentSessionId);
      case LoadSubagentBranch():
        unawaited(_loadBranch(action.childSessionId));
      case CloseChildView():
        _closeChild();
      case RefreshSubagentsAction():
        _refresh();
      case DismissSubagentError():
        _errorMessage = null;
        _publish();
    }
  }

  /// Cold seed: the catalog tree is a host-reported fact. `subagent.list`
  /// reads durable session state, so a pre-selected parent's children must
  /// be on screen without a user gesture. The seed waits for a session
  /// publication that actually contains the selected parent — that proves
  /// the host answered `session.list` — so an offline launch surfaces no
  /// spurious catalog failure.
  void _coldSeedCatalog() {
    final parentId = _selectedParentId;
    if (parentId == null || _catalogRequestedFor == parentId) return;
    if (!_sessions.any((session) => session.id == parentId)) return;
    unawaited(_loadCatalog(parentId));
  }

  /// Membership upkeep against the `session.list` publication
  /// (web `SessionManager.handleHostEnvelope` parity): a child appearing
  /// under a watched parent schedules that parent's catalog re-pull
  /// (`scheduleCatalogRefresh`), a child leaving it folds the row's
  /// activity locally first and also re-pulls, and a running-state flip
  /// only folds the local dot either way (`updateCatalogActivity`) — the
  /// durable catalog row survives its session's removal and the host
  /// re-reads it per pull. Watched parents are the selected root and the
  /// expanded branches. The first observation of a parent records the
  /// baseline without scheduling: the cold seed or the explicit select
  /// already pulled that tree. Event re-pulls bypass the cold seed's
  /// once-per-parent suppression.
  void _observeChildMembership() {
    final watched = <String>{
      if (_selectedParentId != null) _selectedParentId!,
      ..._branchCatalogs.keys,
    };
    _childIdsByParent.removeWhere((parent, _) => !watched.contains(parent));
    for (final parent in watched) {
      // The same host-answered gate as the cold seed: a publication that
      // does not carry the parent's own row is pre-`session.list`, and
      // must not seed the baseline (the cold open's children belong to
      // the seed pull, not to an event refresh).
      if (!_sessions.any((session) => session.id == parent)) {
        _childIdsByParent.remove(parent);
        continue;
      }
      final current = <String, bool>{
        for (final session in _sessions)
          if (session.parentSessionId == parent) session.id: session.running,
      };
      final previous = _childIdsByParent[parent];
      _childIdsByParent[parent] = current;
      if (previous == null) continue;
      var membershipChanged = false;
      for (final entry in current.entries) {
        final wasRunning = previous[entry.key];
        if (wasRunning == null) {
          membershipChanged = true;
        } else if (wasRunning != entry.value) {
          _foldChildActivity(
            parent,
            entry.key,
            entry.value ? 'running' : 'inactive',
          );
        }
      }
      for (final childId in previous.keys) {
        if (current.containsKey(childId)) continue;
        membershipChanged = true;
        _foldChildActivity(parent, childId, 'inactive');
      }
      if (membershipChanged) _scheduleCatalogRefresh(parent);
    }
  }

  /// Rewrites one loaded catalog row's activity in place (the web
  /// `updateCatalogActivity` local fold): the catalog is a snapshot, so
  /// live session facts merge into the rows while their tree is watched.
  void _foldChildActivity(String parentId, String childId, String activity) {
    SubagentCatalog fold(SubagentCatalog catalog) {
      var changed = false;
      final entries = <SubagentEntry>[];
      for (final entry in catalog.entries) {
        if (entry.id == childId &&
            entry.kind == 'child' &&
            entry.activity != activity) {
          changed = true;
          entries.add(
            SubagentEntry(
              id: entry.id,
              kind: entry.kind,
              mode: entry.mode,
              activity: activity,
              hasChildren: entry.hasChildren,
              label: entry.label,
              reason: entry.reason,
            ),
          );
        } else {
          entries.add(entry);
        }
      }
      return changed
          ? SubagentCatalog(
              parentSessionId: catalog.parentSessionId,
              entries: entries,
              parentAvailable: catalog.parentAvailable,
            )
          : catalog;
    }

    if (parentId == _selectedParentId) {
      _catalog = fold(_catalog);
    } else if (_branchCatalogs.containsKey(parentId)) {
      _branchCatalogs[parentId] = fold(_branchCatalogs[parentId]!);
    }
  }

  /// Collapses the membership events that land inside the window into one
  /// pull per watched parent (web `scheduleCatalogRefresh` debounce).
  void _scheduleCatalogRefresh(String parentId) {
    _catalogRefreshPending.add(parentId);
    if (_catalogRefreshTimer?.isActive ?? false) return;
    _catalogRefreshTimer = Timer(_catalogRefreshWindow, () {
      final pending = _catalogRefreshPending.toList();
      _catalogRefreshPending.clear();
      for (final parent in pending) {
        if (parent == _selectedParentId) {
          unawaited(_loadCatalog(parent));
        } else if (_branchCatalogs.containsKey(parent)) {
          unawaited(_loadBranch(parent));
        }
      }
    });
  }

  void _selectParent(String sessionId) {
    if (_selectedParentId == sessionId) return;
    _selectedParentId = sessionId;
    _selectedChildId = null;
    _selectedChildParentId = null;
    _selectedChildMode = null;
    _childTimeline = const <TimelineItem>[];
    _isChildLoading = false;
    ++_childLoadSeq;
    _branchCatalogs.clear();
    _branchFailures.clear();
    _childIdsByParent.clear();
    _catalogRefreshPending.clear();
    _catalogRefreshTimer?.cancel();
    _catalogRefreshTimer = null;
    _bindChildPlan(null);
    _publish();
    unawaited(_loadCatalog(sessionId));
  }

  void _openChild(
    String childSessionId,
    SubagentMode mode, [
    String? parentSessionId,
  ]) {
    final directParentId = parentSessionId ?? _selectedParentId;
    if (directParentId == null) return;
    _selectedChildId = childSessionId;
    _selectedChildParentId = directParentId;
    _selectedChildMode = mode;
    _childTimeline = const <TimelineItem>[];
    _bindChildPlan(childSessionId);
    _publish();
    // History loads are superseded by a later open of another child; only
    // the newest request may land its timeline.
    final seq = ++_childLoadSeq;
    unawaited(() async {
      _isChildLoading = true;
      _publish();
      try {
        final result = await _runCatchingForUi(
          () => _repository.loadSubagentHistory(
            directParentId,
            childSessionId,
            mode,
          ),
        );
        if (seq != _childLoadSeq) return;
        if (result == null) {
          // A failed record load never renders as a fake-empty
          // transcript: the host failure is on the error banner, and
          // the view returns to the catalog.
          _closeChild();
          return;
        }
        _childTimeline = result;
      } finally {
        if (seq == _childLoadSeq) {
          _isChildLoading = false;
          _publish();
        }
      }
    }());
  }

  void _closeChild() {
    if (_selectedChildId == null) return;
    _selectedChildId = null;
    _selectedChildParentId = null;
    _selectedChildMode = null;
    _childTimeline = const <TimelineItem>[];
    _isChildLoading = false;
    // A closed record is no longer the newest request; its in-flight
    // history load must not land.
    ++_childLoadSeq;
    _bindChildPlan(null);
    _publish();
  }

  /// Re-subscribes the opened child's plan projection (the ChatController
  /// `_bindSelected` plan seat, aimed at the child session id).
  void _bindChildPlan(String? childSessionId) {
    unawaited(_planSub?.cancel());
    _planSub = null;
    _childPlan = null;
    if (childSessionId == null) return;
    _planSub = _repository.observePlan(childSessionId).listen((plan) {
      _childPlan = plan;
      _publish();
    });
  }

  void _sendPrompt(String text) {
    final directParentId = _selectedChildParentId ?? _selectedParentId;
    final childId = _selectedChildId;
    final mode = _selectedChildMode;
    if (directParentId == null || childId == null || mode == null) return;
    if (text.trim().isEmpty) return;
    unawaited(() async {
      _isSendingChild = true;
      _publish();
      try {
        await _runCatchingForUi(
          () => _repository.sendSubagentPrompt(
            directParentId,
            childId,
            text.trim(),
          ),
        );
        final reloaded = await _runCatchingForUi(
          () => _repository.loadSubagentHistory(directParentId, childId, mode),
        );
        if (reloaded != null && _selectedChildId == childId) {
          _childTimeline = reloaded;
        }
      } finally {
        _isSendingChild = false;
        _publish();
      }
    }());
  }

  void _interrupt(String childSessionId, [String? parentSessionId]) {
    final directParentId =
        parentSessionId ?? _selectedChildParentId ?? _selectedParentId;
    if (directParentId == null) return;
    unawaited(() async {
      await _runCatchingForUi(
        () => _repository.interruptSubagent(directParentId, childSessionId),
      );
      if (directParentId == _selectedParentId) {
        await _loadCatalog(directParentId);
      } else if (_branchCatalogs.containsKey(directParentId)) {
        await _loadBranch(directParentId);
      }
    }());
  }

  /// Loads the catalog one expanded branch node owns as its children
  /// (web `setCatalogOpen(childSessionId, true)` refresh). A failed load
  /// marks the branch so the tree shows the error + retry instead of a
  /// permanent loading row. Results from a tree the user has already left
  /// (parent switched mid-flight) are dropped.
  Future<void> _loadBranch(String branchParentId) async {
    final treeRoot = _selectedParentId;
    _branchFailures.remove(branchParentId);
    _publish();
    final loaded = await _runCatchingForUi(
      () => _repository.loadSubagents(branchParentId),
    );
    if (_selectedParentId != treeRoot) return;
    if (loaded != null) {
      _branchCatalogs[branchParentId] = loaded;
    } else {
      _branchFailures.add(branchParentId);
    }
    _publish();
  }

  void _refresh() {
    final parentId = _selectedParentId;
    if (parentId == null) return;
    unawaited(_loadCatalog(parentId));
  }

  Future<void> _loadCatalog(String parentId) async {
    _catalogRequestedFor = parentId;
    // Catalog loads are superseded by selecting another parent; only the
    // newest request may land its catalog or clear the loading flag.
    final seq = ++_catalogLoadSeq;
    _isLoading = true;
    _publish();
    try {
      final loaded = await _runCatchingForUi(
        () => _repository.loadSubagents(parentId),
      );
      if (seq != _catalogLoadSeq) return;
      if (loaded != null) {
        _catalog = loaded;
      }
    } finally {
      if (seq == _catalogLoadSeq) {
        _isLoading = false;
        _publish();
      }
    }
  }

  Future<T?> _runCatchingForUi<T>(Future<T> Function() block) async {
    try {
      _errorMessage = null;
      _publish();
      return await block();
    } catch (error) {
      _errorMessage = error.toString();
      _publish();
      return null;
    }
  }
}
