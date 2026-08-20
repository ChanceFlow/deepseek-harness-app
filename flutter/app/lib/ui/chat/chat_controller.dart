/// Chat screen controller — port of the legacy ChatViewModel (UDF).
///
/// Holds every UI-driving field privately and republishes a full
/// [ChatUiState] after each change; repository streams are folded into the
/// same state, mirroring the Kotlin combine chain semantics.
library;

import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'package:domain/model/attachment.dart';
import 'package:domain/model/connection_state.dart';
import 'package:domain/model/goal.dart';
import 'package:domain/model/jobs.dart';
import 'package:domain/model/model_catalog.dart';
import 'package:domain/model/todo.dart';
import 'package:domain/model/context_pressure.dart';
import 'package:domain/model/agent_preset.dart';
import 'package:domain/model/permission_select.dart';
import 'package:domain/model/plan.dart';
import 'package:domain/model/prompt.dart';
import 'package:domain/model/session.dart';
import 'package:domain/model/session_window_stats.dart';
import 'package:domain/model/skills.dart';
import 'package:domain/model/timeline_item.dart';
import 'package:domain/model/timeline_window.dart';
import 'package:domain/model/workspace.dart';
import 'package:domain/repository/chat_repository.dart'
    show ChatRepository, QuestionEvidence;

import '../state_stream.dart';
import 'chat_ui_state.dart';

/// Bounded attachment byte cache; decoded images are bounded by the same
/// count.
const int _attachmentCacheLimit = 24;

class ChatController {
  ChatController(this._repository, {this.onTurnComplete}) {
    _refresh();
    _subscribeBaselines();
    _observeSelectedSessionRemoval();
    _loadAgentPresets();
  }

  final ChatRepository _repository;

  /// Fired when the selected session's turn finishes (running → idle).
  final void Function(String sessionTitle)? onTurnComplete;
  final AppStateStream<ChatUiState> _state = AppStateStream<ChatUiState>(
    const ChatUiState(),
  );
  final List<StreamSubscription<void>> _subs = <StreamSubscription<void>>[];

  ConnectionState _connection = const ConnectionState();
  List<SessionSummary> _sessions = const <SessionSummary>[];
  List<WorkspaceSummary> _workspaces = const <WorkspaceSummary>[];
  ImageLimits _imageLimits = const ImageLimits();
  String? _selectedSessionId;
  TimelineWindow _timelineWindow = const TimelineWindow();
  bool _isSending = false;
  String? _errorMessage;
  List<SessionSearchResult> _searchResults = const <SessionSearchResult>[];
  List<PendingImage> _pendingImages = const <PendingImage>[];
  PlanState? _plan;
  List<TodoItem>? _todos;
  List<SkillEntry> _skills = const <SkillEntry>[];
  SessionModels? _models;
  ContextPressure? _contextPressure;
  ContextBreakdown? _contextBreakdown;
  GoalProjection? _goal;
  SessionWindowStats _sessionStats = const SessionWindowStats();
  PermissionSelect? _permissions;
  AgentPresetRoster? _agentPresets;

  /// One skill.list RPC per session, mirroring the Web catalog cache.
  final Map<String, List<SkillEntry>> _skillsBySession =
      <String, List<SkillEntry>>{};

  /// One session.models load per session (composer model seat); the seat
  /// refreshes on open like the web ModelSelect.
  final Map<String, SessionModels> _modelsBySession = <String, SessionModels>{};

  /// Decoded attachment bytes cache; scroll re-entry must not re-download.
  final LinkedHashMap<String, Uint8List> _attachmentBytes =
      LinkedHashMap<String, Uint8List>();
  Future<void> _attachmentLock = Future<void>.value();

  StreamSubscription<void>? _timelineSub;
  StreamSubscription<void>? _planSub;
  StreamSubscription<void>? _todosSub;
  StreamSubscription<void>? _contextSub;
  StreamSubscription<void>? _breakdownSub;
  StreamSubscription<void>? _statsSub;
  StreamSubscription<void>? _goalSub;
  StreamSubscription<void>? _permissionsSub;

  ChatUiState get state => _state.value;

  /// Background jobs ride the timeline's TimelineJobs items (web keeps them
  /// in a session store; our reducer already folds them there).
  List<JobView> _timelineJobs() {
    final items = <JobView>[];
    for (final item in _timelineWindow.items) {
      if (item is TimelineJobs) items.addAll(item.jobs);
    }
    return List<JobView>.unmodifiable(items);
  }

  Stream<ChatUiState> get uiState => _state.stream;

  void dispose() {
    for (final sub in _subs) {
      unawaited(sub.cancel());
    }
    unawaited(_timelineSub?.cancel());
    unawaited(_planSub?.cancel());
    unawaited(_todosSub?.cancel());
    unawaited(_contextSub?.cancel());
    unawaited(_breakdownSub?.cancel());
    unawaited(_statsSub?.cancel());
    unawaited(_goalSub?.cancel());
    unawaited(_permissionsSub?.cancel());
    _subs.clear();
  }

  void _publish() {
    // Matches the Web client grouping rule: store keeps every row, while
    // list surfaces hide blank placeholders unless selected.
    final visibleSessions = _sessions
        .where((session) => !session.blank || session.id == _selectedSessionId)
        .toList();
    _state.value = ChatUiState(
      connection: _connection,
      sessions: visibleSessions,
      workspaces: _workspaces,
      selectedSessionId: _selectedSessionId,
      timeline: _timelineWindow.items,
      hasMoreOlder: _timelineWindow.hasMoreOlder,
      isLoadingOlder: _timelineWindow.isLoadingOlder,
      searchResults: _searchResults,
      isSending: _isSending,
      errorMessage: _errorMessage,
      pendingImages: _pendingImages,
      imageLimits: _imageLimits,
      plan: _plan,
      todos: _todos,
      skills: _skills,
      contextPressure: _contextPressure,
      contextBreakdown: _contextBreakdown,
      sessionStats: _sessionStats,
      goal: _goal,
      models: _models,
      jobs: _timelineJobs(),
      permissions: _permissions,
      agentPresets: _agentPresets,
    );
  }

  bool _selectedWasRunning = false;

  void _handleSessionsForTurns(List<SessionSummary> sessions) {
    final selectedId = _selectedSessionId;
    if (selectedId == null) {
      _selectedWasRunning = false;
      return;
    }
    final session = sessions.where((item) => item.id == selectedId).firstOrNull;
    final running = session?.running ?? false;
    if (_selectedWasRunning && !running && session != null) {
      onTurnComplete?.call(session.displayTitle);
    }
    _selectedWasRunning = running;
  }

  void _subscribeBaselines() {
    _subs.add(
      _repository.observeConnectionState().listen((connection) {
        _connection = connection;
        _publish();
      }),
    );
    _subs.add(
      _repository.observeSessions().listen((sessions) {
        _sessions = sessions;
        _handleSessionsForTurns(sessions);
        _publish();
      }),
    );
    _subs.add(
      _repository.observeWorkspaces().listen((workspaces) {
        _workspaces = workspaces;
        _publish();
      }),
    );
    _subs.add(
      _repository.observeImageLimits().listen((limits) {
        _imageLimits = limits ?? const ImageLimits();
        _publish();
      }),
    );
  }

  void onAction(ChatAction action) {
    switch (action) {
      case SelectSession():
        _selectSession(action.sessionId);
      case SendPrompt():
        _sendPrompt(action);
      case CancelTurnAction():
        _cancelTurn();
      case CreateSessionAction():
        _createSession(workspaceId: null);
      case CreateSessionInWorkspace():
        _createSession(
          workspaceId: action.workspaceId,
          agentPreset: action.agentPreset,
        );
      case DismissError():
        _errorMessage = null;
        _publish();
      case RetrySessions():
        _refresh();
      case LoadOlderHistoryAction():
        _loadOlderHistory();
      case RespondApproval():
        _respondApproval(action);
      case AnswerQuestionAction():
        _answerQuestion(action);
      case SearchSessions():
        _searchSessions(action.query);
      case ArchiveSession():
        unawaited(
          _runCatchingForUi(() => _repository.archiveSession(action.sessionId)),
        );
      case RenameSession():
        if (action.title.trim().isNotEmpty) {
          unawaited(
            _runCatchingForUi(
              () => _repository.renameSession(action.sessionId, action.title),
            ),
          );
        }
      case ForkSession():
        _forkSession(action.sessionId);
      case UpdateQueueAction():
        _updateQueue(action.itemId, action.kind, action.text);
      case ImagesLoaded():
        _admitPendingImages(action.images);
      case RemovePendingImage():
        _pendingImages = _pendingImages
            .where((image) => image.id != action.id)
            .toList();
        _publish();
      case SelectModelSeat():
        _selectModel(action.selection);
      case ToggleGoalPause():
        _toggleGoalPause();
      case ClearGoal():
        _clearGoal();
      case ImagePickError():
        _errorMessage = action.message;
        _publish();
      case SelectAgentPreset():
        _selectAgentPreset(action);
    }
  }

  void _selectSession(String sessionId) {
    _selectedSessionId = sessionId;
    _timelineWindow = const TimelineWindow();
    _bindSelected(sessionId);
    _loadSkills(sessionId);
    _loadModels(sessionId);
    _publish();
    unawaited(_runCatchingForUi(() => _repository.openSession(sessionId)));
  }

  /// Re-subscribes the selected-session timeline and plan streams (the
  /// Kotlin flatMapLatest equivalent).
  void _bindSelected(String? sessionId) {
    unawaited(_timelineSub?.cancel());
    unawaited(_planSub?.cancel());
    unawaited(_todosSub?.cancel());
    unawaited(_contextSub?.cancel());
    unawaited(_breakdownSub?.cancel());
    unawaited(_statsSub?.cancel());
    unawaited(_goalSub?.cancel());
    unawaited(_permissionsSub?.cancel());
    if (sessionId == null) {
      _timelineWindow = const TimelineWindow();
      _plan = null;
      _contextPressure = null;
      _contextBreakdown = null;
      _sessionStats = const SessionWindowStats();
      _goal = null;
      _models = null;
      _permissions = null;
      _timelineSub = null;
      _planSub = null;
      _todosSub = null;
      _contextSub = null;
      _breakdownSub = null;
      _statsSub = null;
      _goalSub = null;
      _permissionsSub = null;
      return;
    }
    // Session-scoped projections reset on rebind: the leaving
    // session's values never flash under the entering one's header.
    _permissions = null;
    _timelineSub = _repository.observeTimelineWindow(sessionId).listen((
      window,
    ) {
      _timelineWindow = window;
      _publish();
    });
    _planSub = _repository.observePlan(sessionId).listen((plan) {
      _plan = plan;
      _publish();
    });
    _todosSub = _repository.observeTodos(sessionId).listen((todos) {
      _todos = todos;
      _publish();
    });
    _contextSub = _repository.observeContextPressure(sessionId).listen((
      pressure,
    ) {
      _contextPressure = pressure;
      _publish();
    });
    _statsSub = _repository.observeSessionStats(sessionId).listen((stats) {
      _sessionStats = stats;
      _publish();
    });
    _goalSub = _repository.observeGoal(sessionId).listen((goal) {
      _goal = goal;
      _publish();
    });
    _permissionsSub = _repository.observePermissions(sessionId).listen((
      permissions,
    ) {
      _permissions = permissions;
      _publish();
    });
  }

  /// Agent-preset roster for the hero chip, blank-session switch, and
  /// header label: one load for the controller's lifetime (web
  /// re-reads on settings/changed; the roster here is refreshed with the
  /// controller). A load failure keeps every preset surface hidden.
  void _loadAgentPresets() {
    unawaited(() async {
      try {
        final roster = await _repository.listAgentPresets();
        _agentPresets = roster;
      } catch (_) {
        _agentPresets = null;
      }
      _publish();
    }());
  }

  /// Blank-session preset switch (web AgentPresetSeat select); host
  /// refusals (`agent-preset-locked`) surface through the error strip.
  void _selectAgentPreset(SelectAgentPreset action) {
    unawaited(
      _runCatchingForUi(
        () => _repository.selectAgentPreset(
          action.sessionId,
          action.agentPreset,
        ),
      ),
    );
  }

  /// Skill catalog for the `/` composer source: one fetch per session,
  /// cached like the Web client. Failures stay silent — the composer just
  /// offers no candidates.
  void _loadSkills(String sessionId) {
    final cached = _skillsBySession[sessionId];
    if (cached != null) {
      _skills = cached;
      _publish();
      return;
    }
    unawaited(() async {
      try {
        final catalog = await _repository.listSkills(sessionId);
        _skillsBySession[sessionId] = catalog;
        if (_selectedSessionId == sessionId) {
          _skills = catalog;
          _publish();
        }
      } catch (_) {
        if (_selectedSessionId == sessionId) {
          _skills = const <SkillEntry>[];
          _publish();
        }
      }
    }());
  }

  void _loadOlderHistory() {
    final sessionId = _selectedSessionId;
    if (sessionId == null) return;
    unawaited(_runCatchingForUi(() => _repository.loadOlderHistory(sessionId)));
  }

  void _refresh() {
    unawaited(() async {
      await _runCatchingForUi(_repository.refreshSessions);
      await _runCatchingForUi(_repository.refreshWorkspaces);
    }());
  }

  void _observeSelectedSessionRemoval() {
    _subs.add(
      _repository.observeSessions().listen((sessions) {
        final selected = _selectedSessionId;
        if (selected == null) return;
        if (!sessions.any((session) => session.id == selected)) {
          _selectedSessionId = null;
          _timelineWindow = const TimelineWindow();
          _bindSelected(null);
          _publish();
        }
      }),
    );
  }

  void _sendPrompt(SendPrompt action) {
    final sessionId = _selectedSessionId;
    if (sessionId == null) return;
    final images = _pendingImages;
    if (action.text.trim().isEmpty && images.isEmpty) return;
    // Web GoalCommandInput parity: `/goal <objective>` creates the goal
    // instead of riding the prompt. Control words (clear/pause/resume,
    // edit) are the host command's own grammar — they fall through and
    // execute as ordinary slash commands.
    final command = RegExp(
      r'^/goal(?:\s+(.+))?$',
      caseSensitive: false,
    ).firstMatch(action.text.trim());
    if (command != null) {
      final objective = command.group(1)?.trim() ?? '';
      final control = objective.toLowerCase();
      final isControlWord =
          objective.isEmpty ||
          control == 'clear' ||
          control == 'pause' ||
          control == 'resume' ||
          control == 'show' ||
          control.startsWith('edit');
      if (objective.isNotEmpty && !isControlWord) {
        unawaited(
          _runCatchingForUi(() => _repository.createGoal(sessionId, objective)),
        );
        return;
      }
    }
    unawaited(() async {
      _isSending = true;
      _publish();
      try {
        final sent = await _runCatchingForUi<bool>(() async {
          await _repository.sendMessage(
            SendMessageRequest(
              sessionId: sessionId,
              text: action.text.trim(),
              mode: action.mode,
              images: images,
            ),
          );
          return true;
        });
        // Keep drafts only on failure, mirroring the text composer.
        if (sent != null) {
          _pendingImages = const <PendingImage>[];
        }
      } finally {
        _isSending = false;
        _publish();
      }
    }());
  }

  /// Validate picked images against the host limits, then queue the rest.
  void _admitPendingImages(List<PendingImage> images) {
    if (images.isEmpty) return;
    final limits = _imageLimits;
    final admitted = <PendingImage>[];
    final rejected = <String>[];
    for (final image in images) {
      if (!limits.mediaTypes.contains(image.mediaType)) {
        rejected.add(
          '${image.name ?? image.id}: unsupported type ${image.mediaType}',
        );
      } else if (image.byteSize > limits.maxImageBytes) {
        rejected.add(
          '${image.name ?? image.id}: exceeds ${limits.maxImageBytes} bytes',
        );
      } else {
        admitted.add(image);
      }
    }
    final room = (limits.maxImagesPerMessage - _pendingImages.length) < 0
        ? 0
        : (limits.maxImagesPerMessage - _pendingImages.length);
    final keep = admitted.take(room).toList();
    final overflow = admitted.skip(room).toList();
    if (keep.isNotEmpty) {
      _pendingImages = List.of(_pendingImages)..addAll(keep);
    }
    if (overflow.isNotEmpty) {
      rejected.add('only $room more image(s) allowed per message');
    }
    if (rejected.isNotEmpty) {
      _errorMessage = rejected.join('; ');
    }
    _publish();
  }

  /// Download one durable image through `session.attachment`, caching bytes
  /// per attachment id. Returns null on failure; the UI shows a
  /// placeholder.
  Future<Uint8List?> loadAttachmentBytes(
    String sessionId,
    AttachmentRef ref,
  ) async {
    final cached = await _locked(
      () async => _attachmentBytes[ref.attachmentId],
    );
    if (cached != null) return cached;
    try {
      final downloaded = await _repository.readAttachment(
        sessionId,
        ref.attachmentId,
      );
      await _locked(() async {
        if (_attachmentBytes.length >= _attachmentCacheLimit) {
          _attachmentBytes.remove(_attachmentBytes.keys.first);
        }
        _attachmentBytes[ref.attachmentId] = downloaded.data;
      });
      return downloaded.data;
    } catch (_) {
      return null;
    }
  }

  Future<T> _locked<T>(Future<T> Function() action) {
    final run = _attachmentLock.then((_) => action());
    _attachmentLock = run.then((_) {}, onError: (_) {});
    return run;
  }

  /// Composer model seat: load the session's model directory (web reloads
  /// on every open; we cache per session and refresh on demand).
  void _loadModels(String sessionId) {
    final cached = _modelsBySession[sessionId];
    if (cached != null) {
      _models = cached;
      _publish();
      return;
    }
    refreshModels();
  }

  /// Re-pull the selected session's model directory (seat open).
  void refreshModels() {
    final sessionId = _selectedSessionId;
    if (sessionId == null) return;
    unawaited(() async {
      final models = await _runCatchingForUi(
        () => _repository.loadModels(sessionId),
      );
      if (models != null) {
        _modelsBySession[sessionId] = models;
        if (_selectedSessionId == sessionId) {
          _models = models;
          _publish();
        }
      }
    }());
  }

  void _selectModel(ModelSelection selection) {
    final sessionId = _selectedSessionId;
    if (sessionId == null) return;
    unawaited(() async {
      final updated = await _runCatchingForUi(
        () => _repository.selectModel(sessionId, selection),
      );
      if (updated != null) {
        // Patch the cached directory's current selection in place.
        final models = _models;
        if (models != null) {
          final patched = SessionModels(
            current: updated,
            routable: models.routable,
            groups: models.groups,
            failures: models.failures,
          );
          _modelsBySession[sessionId] = patched;
          _models = patched;
          _publish();
        }
      }
    }());
  }

  /// GoalBar strip action: pause an active goal, resume a held one.
  void _toggleGoalPause() {
    final sessionId = _selectedSessionId;
    if (sessionId == null) return;
    final goal = _goal?.goal;
    if (goal == null) return;
    final ref = GoalRef(id: goal.id, revision: goal.revision);
    unawaited(
      _runCatchingForUi(
        () => goal.phase == GoalPhase.active
            ? _repository.pauseGoal(sessionId, ref)
            : _repository.resumeGoal(sessionId, ref),
      ),
    );
  }

  /// GoalBar strip action: delete the goal from any phase (web GoalBar
  /// clear — `/goal clear` semantics).
  void _clearGoal() {
    final sessionId = _selectedSessionId;
    if (sessionId == null) return;
    final goal = _goal?.goal;
    if (goal == null) return;
    final ref = GoalRef(id: goal.id, revision: goal.revision);
    unawaited(_runCatchingForUi(() => _repository.clearGoal(sessionId, ref)));
  }

  void _cancelTurn() {
    final sessionId = _selectedSessionId;
    if (sessionId == null) return;
    unawaited(_runCatchingForUi(() => _repository.cancelTurn(sessionId)));
  }

  void _createSession({String? workspaceId, String? agentPreset}) {
    unawaited(() async {
      // Web parity: a workspace's blank session is the provisional New
      // Session row. Reuse it instead of minting another hidden row.
      String? sessionId;
      if (workspaceId != null) {
        sessionId = _reusableBlankSessionId(workspaceId);
      }
      sessionId ??= (await _runCatchingForUi(
        () => _repository.createSession(
          CreateSessionRequest(
            workspaceId: workspaceId,
            agentPreset: agentPreset,
          ),
        ),
      ))?.id;
      final resolved = sessionId;
      if (resolved == null) return;
      _selectedSessionId = resolved;
      _timelineWindow = const TimelineWindow();
      _bindSelected(resolved);
      _publish();
      await _runCatchingForUi(() => _repository.openSession(resolved));
      // A reused blank session was created without the staged preset;
      // the blank-session switch carries it (web stage semantics: the
      // stage reaches a session that is still blank, created or reused).
      final existing = _sessions
          .where((session) => session.id == resolved)
          .firstOrNull;
      final preset = agentPreset;
      if (preset != null &&
          existing != null &&
          existing.blank &&
          existing.agentPreset != preset) {
        await _runCatchingForUi(
          () => _repository.selectAgentPreset(resolved, preset),
        );
      }
    }());
  }

  String? _reusableBlankSessionId(String workspaceId) {
    final workspace = _workspaces
        .where((item) => item.workspaceId == workspaceId)
        .firstOrNull;
    if (workspace == null) return null;
    for (final session in _sessions) {
      if (session.blank &&
          session.cwd == workspace.path &&
          workspace.sessionIds.contains(session.id)) {
        return session.id;
      }
    }
    return null;
  }

  void _respondApproval(RespondApproval action) {
    final sessionId = _selectedSessionId;
    if (sessionId == null) return;
    unawaited(
      _runCatchingForUi(
        () => _repository.respondToApproval(
          ApprovalAnswer(
            requestId: action.requestId,
            sessionId: sessionId,
            approvalId: action.approvalId,
            allowed: action.allowed,
          ),
        ),
      ),
    );
  }

  void _answerQuestion(AnswerQuestionAction action) {
    final sessionId = _selectedSessionId;
    if (sessionId == null) return;
    unawaited(
      _runCatchingForUi(
        () => _repository.answerQuestions(
          action.requestId,
          QuestionEvidence(sessionId: sessionId, answers: action.answers),
        ),
      ),
    );
  }

  void _searchSessions(String query) {
    if (query.trim().isEmpty) {
      _searchResults = const <SessionSearchResult>[];
      _publish();
      return;
    }
    unawaited(() async {
      final results = await _runCatchingForUi(
        () => _repository.searchSessions(query),
      );
      _searchResults = results ?? const <SessionSearchResult>[];
      _publish();
    }());
  }

  void _forkSession(String sessionId) {
    unawaited(() async {
      final forked = await _runCatchingForUi(
        () => _repository.forkSession(sessionId),
      );
      if (forked == null) return;
      _selectedSessionId = forked.id;
      _timelineWindow = const TimelineWindow();
      _bindSelected(forked.id);
      _publish();
      await _runCatchingForUi(() => _repository.openSession(forked.id));
    }());
  }

  void _updateQueue(String itemId, QueueUpdateKind kind, String? text) {
    final sessionId = _selectedSessionId;
    if (sessionId == null) return;
    if (kind == QueueUpdateKind.edit && (text == null || text.trim().isEmpty)) {
      return;
    }
    unawaited(
      _runCatchingForUi(
        () => _repository.updateQueue(
          QueueUpdateRequest(
            sessionId: sessionId,
            itemId: itemId,
            kind: kind,
            text: text,
          ),
        ),
      ),
    );
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

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
