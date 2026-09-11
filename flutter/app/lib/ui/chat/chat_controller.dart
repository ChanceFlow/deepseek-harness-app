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
import 'package:domain/model/chat_message.dart';
import 'package:domain/model/command.dart';
import 'package:domain/model/cordis.dart';
import 'package:domain/model/goal.dart';
import 'package:domain/model/jobs.dart';
import 'package:domain/model/model_catalog.dart';
import 'package:domain/model/todo.dart';
import 'package:domain/model/context_pressure.dart';
import 'package:domain/model/agent_preset.dart';
import 'package:domain/model/permission_select.dart';
import 'package:domain/model/plan.dart';
import 'package:domain/model/prompt.dart';
import 'package:domain/model/sandbox.dart';
import 'package:domain/model/schedule.dart';
import 'package:domain/model/session.dart';
import 'package:domain/model/session_window_stats.dart';
import 'package:domain/model/skills.dart';
import 'package:domain/model/timeline_item.dart';
import 'package:domain/model/timeline_window.dart';
import 'package:domain/model/workspace.dart';
import 'package:domain/model/workspace_file.dart';
import 'package:domain/repository/chat_repository.dart'
    show ChatRepository, QuestionEvidence;
import 'package:domain/repository/session_log_export_repository.dart'
    show SessionLogExportRepository;
import 'package:dev/dev.dart' show DebugTelemetry;

import '../../logging/error_log_collector.dart';
import '../../platform/session_log_saver.dart';
import '../state_stream.dart';
import 'command_roster.dart';
import 'chat_local_state.dart';
import 'chat_ui_state.dart';

/// Bounded attachment byte cache; decoded images are bounded by the same
/// count.
const int _attachmentCacheLimit = 24;

/// Frame-rate window for upstream-driven [ChatUiState] rebuilds: repository
/// stream events landing inside one window fold into a single publish at its
/// end (the app-side port of the adapter's `kStreamPublishWindow` in
/// `packages/harness_adapter/lib/src/harness_repository_impl.dart`; the web
/// client batches these per animation frame in its runtime Notifier, and the
/// import gate keeps `app` from importing the adapter constant, so the value
/// is restated here). Actions and one-shot RPC completions keep publishing
/// immediately; upstream stream facts land in `uiState` one window at most
/// behind arrival.
const Duration kUiPublishWindow = Duration(milliseconds: 16);

/// Pause between the latest keystroke and a Host content-search request
/// (matches reference `WorkspaceBrowser.tsx` line 35 `SEARCH_DEBOUNCE_MS`).
const Duration _searchDebounceDelay = Duration(milliseconds: 250);

/// `session.search` wire bound, measured in JavaScript UTF-16 code units
/// (matches reference `WorkspaceBrowser.tsx` line 37 `SEARCH_QUERY_MAX_CODE_UNITS`).
const int _searchQueryMaxCodeUnits = 500;

class ChatController {
  ChatController(
    this._repository, {
    Future<ModelPreferencePersistence?>? modelPreferences,
    Future<SessionSelectionPersistence?>? sessionSelection,
    this._sessionLogExport,
    this._saveSessionLog = saveSessionLogZip,
  }) {
    _refresh();
    _subscribeBaselines();
    _loadAgentPresets();
    _loadModelPreferences(modelPreferences);
    _loadSessionSelection(sessionSelection);
  }

  final ChatRepository _repository;

  /// The session-log archive seam; null when the deployment composed none,
  /// in which case the header action hides and `/export` reports failure
  /// instead of asking a host that only answers "download requested".
  final SessionLogExportRepository? _sessionLogExport;

  /// The platform write step, injected so tests drive the outcome without a
  /// method channel.
  final SessionLogSaver _saveSessionLog;

  /// Debug telemetry facade; null in release or when uninitialized, so
  /// every instrumentation site is a no-op outside debug builds.
  DebugTelemetry? get _telemetry => DebugTelemetry.instance;

  final AppStateStream<ChatUiState> _state = AppStateStream<ChatUiState>(
    const ChatUiState(),
  );
  final List<StreamSubscription<void>> _subs = <StreamSubscription<void>>[];

  List<SessionSummary> _sessions = const <SessionSummary>[];
  List<WorkspaceSummary> _workspaces = const <WorkspaceSummary>[];
  ImageLimits _imageLimits = const ImageLimits();
  String? _selectedSessionId;
  TimelineWindow _timelineWindow = const TimelineWindow();
  bool _isSending = false;
  String? _errorMessage;
  bool _commandFailed = false;
  bool _cordisAnswerFailed = false;
  List<ImageRejection> _imageRejections = const <ImageRejection>[];
  List<SessionSearchResult> _searchResults = const <SessionSearchResult>[];
  Timer? _searchTimer;

  /// Monotonic sequence counter for session searches.
  ///
  /// The controller cannot abort an in-flight HTTP request directly
  /// (Dart's repository interface does not take an AbortSignal/CancellationToken);
  /// this monotonic sequence guard is the semantic equivalent of the reference's
  /// per-query AbortController (WorkspaceBrowser.tsx lines 872 & 900), ensuring that
  /// only responses from the newest dispatched query may assign [_searchResults].
  int _searchSeq = 0;
  List<PendingImage> _pendingImages = const <PendingImage>[];
  PlanState? _plan;
  List<TodoItem>? _todos;
  List<SkillEntry> _skills = const <SkillEntry>[];
  List<CordisRunRequest> _cordisRunRequests = const <CordisRunRequest>[];
  SessionModels? _models;

  /// The session whose directory [_models] currently holds; the
  /// remembered-selection apply must not read a previous session's seat.
  String? _modelsSessionId;
  ModelSeatPreferences _modelPrefs = const ModelSeatPreferences();
  ModelPreferencePersistence? _modelPrefsStore;
  bool _prefsLoaded = false;
  String? _modelPrefsDecidedFor;
  SessionLogExportState? _sessionLogExportState;

  /// One export at a time: a second tap while the archive streams is
  /// ignored rather than starting a rival download.
  bool _exportInFlight = false;
  bool _disposed = false;

  /// Selected-session persistence (web `dsh.sessions.current` parity);
  /// resolves asynchronously with the store.
  SessionSelectionPersistence? _selectionStore;
  String? _restoreSessionId;
  bool _restoreGivenUp = false;
  bool _sessionsRefreshed = false;
  ContextPressure? _contextPressure;
  ContextBreakdown? _contextBreakdown;
  GoalProjection? _goal;
  SessionWindowStats _sessionStats = const SessionWindowStats();
  PermissionSelect? _permissions;
  AgentPresetRoster? _agentPresets;

  /// The selected session's durable sandbox-mode fact; null until a
  /// `sandbox/mode` event folds for it (the deployment default applies and
  /// stays unnamed here).
  SandboxModeFact? _sandboxMode;

  /// The selected session's active durable reminders; null until the
  /// `schedule/change` fold publishes for it.
  List<ScheduleReminder>? _schedules;

  /// One skill.list RPC per session, mirroring the Web catalog cache.
  final Map<String, List<SkillEntry>> _skillsBySession =
      <String, List<SkillEntry>>{};

  /// Live command roster of the selected session (`commands/list`); null
  /// until the first pull settles and again after a failed one, in which
  /// case the static roster stands in as the pre-first-pull fallback. A
  /// non-null value — including an empty list — is the host's own roster.
  List<CommandDescriptor>? _commands;

  /// One `commands/list` pull per session, invalidated wholesale by
  /// `commands/change` (the web live directory's `invalidateAll`).
  final Map<String, List<CommandDescriptor>> _commandsBySession =
      <String, List<CommandDescriptor>>{};

  /// One session.models load per session (composer model seat); the seat
  /// refreshes on open like the web ModelSelect.
  final Map<String, SessionModels> _modelsBySession = <String, SessionModels>{};

  /// Decoded attachment bytes cache; scroll re-entry must not re-download.
  final LinkedHashMap<String, Uint8List> _attachmentBytes =
      LinkedHashMap<String, Uint8List>();
  Future<void> _attachmentLock = Future<void>.value();

  /// Pending upstream-driven publish ([kUiPublishWindow] trailing edge);
  /// null when the next publish goes out immediately.
  Timer? _upstreamPublish;

  /// [_timelineJobs] memo: the scan result for the cached timeline item
  /// list, reused while the same window instance is current (a publish
  /// driven by any other field must not rescan the whole table).
  List<TimelineItem>? _jobsSourceItems;
  List<JobView>? _jobsCache;

  StreamSubscription<void>? _timelineSub;
  StreamSubscription<void>? _planSub;
  StreamSubscription<void>? _todosSub;
  StreamSubscription<void>? _contextSub;
  StreamSubscription<void>? _breakdownSub;
  StreamSubscription<void>? _statsSub;
  StreamSubscription<void>? _goalSub;
  StreamSubscription<void>? _permissionsSub;
  StreamSubscription<void>? _sandboxSub;
  StreamSubscription<void>? _schedulesSub;

  ChatUiState get state => _state.value;

  /// Background jobs ride the timeline's TimelineJobs items (web keeps them
  /// in a session store; our reducer already folds them there). The scan is
  /// memoized on the timeline list instance: the same window snapshot
  /// yields the same job roster, so publishes driven by other fields reuse
  /// the previous result instead of rescanning every item.
  List<JobView> _timelineJobs() {
    final source = _timelineWindow.items;
    if (identical(_jobsSourceItems, source) && _jobsCache != null) {
      return _jobsCache!;
    }
    final items = <JobView>[];
    for (final item in source) {
      if (item is TimelineJobs) items.addAll(item.jobs);
    }
    final jobs = List<JobView>.unmodifiable(items);
    _jobsSourceItems = source;
    _jobsCache = jobs;
    return jobs;
  }

  Stream<ChatUiState> get uiState => _state.stream;

  void dispose() {
    _disposed = true;
    _searchTimer?.cancel();
    _searchTimer = null;
    _upstreamPublish?.cancel();
    _upstreamPublish = null;
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
    unawaited(_sandboxSub?.cancel());
    unawaited(_schedulesSub?.cancel());
    _subs.clear();
  }

  void _publish() {
    // Matches the Web client grouping rule: store keeps every row, while
    // list surfaces hide blank placeholders unless selected.
    final visibleSessions = _sessions
        .where((session) => !session.blank || session.id == _selectedSessionId)
        .toList();
    _state.value = ChatUiState(
      sessions: visibleSessions,
      workspaces: _workspaces,
      selectedSessionId: _selectedSessionId,
      timeline: _timelineWindow.items,
      hasMoreOlder: _timelineWindow.hasMoreOlder,
      isLoadingOlder: _timelineWindow.isLoadingOlder,
      isTimelineLoading: _timelineWindow.isLoading,
      searchResults: _searchResults,
      isSending: _isSending,
      errorMessage: _errorMessage,
      commandFailed: _commandFailed,
      imageRejections: _imageRejections,
      pendingImages: _pendingImages,
      imageLimits: _imageLimits,
      plan: _plan,
      todos: _todos,
      skills: _skills,
      cordisRunRequests: _cordisRunRequests,
      cordisAnswerFailed: _cordisAnswerFailed,
      commands: _commands,
      contextPressure: _contextPressure,
      contextBreakdown: _contextBreakdown,
      sessionStats: _sessionStats,
      goal: _goal,
      models: _models,
      jobs: _timelineJobs(),
      permissions: _permissions,
      agentPresets: _agentPresets,
      modelPrefs: _prefsLoaded ? _modelPrefs : null,
      sessionLogExport: _sessionLogExportState,
      canExportSessionLog: _sessionLogExport != null,
      sandboxMode: _sandboxMode,
      schedules: _schedules,
    );
  }

  /// Publish triggered by an upstream repository stream: the rebuild folds
  /// into the current frame window ([kUiPublishWindow] trailing edge). The
  /// flush reads the fields as they are then, so no state is ever lost —
  /// an approval, question or plan landing in a window is in `uiState` at
  /// the window's end, one window behind arrival at the latest. Actions and
  /// one-shot completions keep calling [_publish] directly.
  void _publishUpstream() {
    _upstreamPublish ??= Timer(kUiPublishWindow, () {
      _upstreamPublish = null;
      if (_disposed) return;
      _publish();
    });
  }

  void _subscribeBaselines() {
    _subs.add(
      _repository.observeSessions().listen((sessions) {
        _sessions = sessions;
        _publishUpstream();
        // The restore pass waits on the stored id resolving together with
        // a session list that either contains it or rules it out.
        _maybeRestoreSelectedSession();
        // A blank session's summary can land after its model directory;
        // the remembered-selection apply waits on both.
        _maybeApplyModelPreferences();
        // A selected session vanishing from the list unbinds it (same
        // listener: one combine-latest chain over the roster, never a
        // second subscription re-folding the same three sources).
        final selected = _selectedSessionId;
        if (selected == null) return;
        if (!sessions.any((session) => session.id == selected)) {
          _selectedSessionId = null;
          _rememberSelectedSession(null);
          _timelineWindow = const TimelineWindow();
          _bindSelected(null);
          _publishUpstream();
        }
      }),
    );
    _subs.add(
      _repository.observeWorkspaces().listen((workspaces) {
        _workspaces = workspaces;
        _publishUpstream();
      }),
    );
    _subs.add(
      _repository.observeImageLimits().listen((limits) {
        _imageLimits = limits ?? const ImageLimits();
        _publishUpstream();
      }),
    );
    // Pending dynamic-Cordis activations are registry-global (the request
    // carries its own session): one subscription feeds every session's
    // surface, and the host's `cordis/request-run-resolved` broadcast drops
    // a request out of the list — the settled state.
    _subs.add(
      _repository.observeCordisRunRequests().listen((requests) {
        _cordisRunRequests = requests;
        _publishUpstream();
      }),
    );
    // `commands/change` invalidates every session's cached roster (the web
    // live directory's `invalidateAll`); the selected session re-pulls
    // immediately, other sessions on their next select.
    _subs.add(
      _repository.observeCommandRosterChanges().listen((_) {
        _commandsBySession.clear();
        final sessionId = _selectedSessionId;
        if (sessionId != null) _loadCommands(sessionId);
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
        _commandFailed = false;
        _cordisAnswerFailed = false;
        _imageRejections = const <ImageRejection>[];
        _publish();
      case RetrySessions():
        _refresh();
      case LoadOlderHistoryAction():
        _loadOlderHistory();
      case RespondApproval():
        _respondApproval(action);
      case RejectCordisRun():
        _rejectCordisRun(action);
      case AnswerQuestionAction():
        _answerQuestion(action);
      case DismissQuestionAction():
        _dismissQuestion(action);
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
        _forkSession(action.sessionId, action.atSeq);
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
      case EditGoal():
        _editGoal(action.objective);
      case ImagePickError():
        _errorMessage = action.message;
        ErrorLogCollector.instance.addBreadcrumb(
          'Image pick error: ${action.message}',
          level: 'warning',
        );
        _publish();
      case CommandImageRefusal():
        _errorMessage = action.message;
        ErrorLogCollector.instance.addBreadcrumb(
          'Command image refusal: ${action.message}',
          level: 'warning',
        );
        _publish();
      case SelectAgentPreset():
        _selectAgentPreset(action);
      case ExportSessionLog():
        unawaited(_exportSessionLog(action.sessionId));
    }
  }

  /// Downloads one session's log archive and writes it through the platform
  /// save step, publishing progress for the header action.
  ///
  /// The archive is buffered before anything touches the filesystem, so a
  /// truncated download never leaves a partial file behind. A second request
  /// while one is streaming is ignored; a failure is recorded for the error
  /// log and published as [SessionLogExportPhase.failed] for the localized
  /// notice.
  Future<void> _exportSessionLog(String sessionId) async {
    final export = _sessionLogExport;
    if (_exportInFlight) return;
    _exportInFlight = true;
    _sessionLogExportState = const SessionLogExportState.exporting();
    _publish();
    _telemetry?.count('chat.session_log_export');
    _telemetry?.event(
      'chat.session_log_export',
      attributes: {'sessionId': sessionId},
    );
    try {
      if (export == null) {
        throw UnsupportedError('exportSessionLog: no export seam composed');
      }
      final archive = await export.exportSessionLog(sessionId);
      final location = await _saveSessionLog(
        filename: archive.filename,
        bytes: archive.bytes,
      );
      _sessionLogExportState = SessionLogExportState.saved(location);
    } catch (error, stackTrace) {
      _sessionLogExportState = const SessionLogExportState.failed();
      _telemetry?.count('chat.session_log_export_failed');
      ErrorLogCollector.instance.captureError(
        error,
        stackTrace: stackTrace,
        context: <String, Object?>{
          'controller': 'ChatController',
          'action': 'exportSessionLog',
          'sessionId': sessionId,
        },
      );
    } finally {
      _exportInFlight = false;
      if (!_disposed) _publish();
    }
  }

  void _selectSession(String sessionId) {
    _selectedSessionId = sessionId;
    _rememberSelectedSession(sessionId);
    _timelineWindow = const TimelineWindow();
    _bindSelected(sessionId);
    _loadSkills(sessionId);
    _loadCommands(sessionId);
    _loadModels(sessionId);
    _publish();
    unawaited(_runCatchingForUi(() => _repository.openSession(sessionId)));
    _telemetry?.count('chat.session.select');
    _telemetry?.event(
      'chat.session.select',
      attributes: {'sessionId': sessionId},
    );
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
    unawaited(_sandboxSub?.cancel());
    unawaited(_schedulesSub?.cancel());
    if (sessionId == null) {
      _timelineWindow = const TimelineWindow();
      _plan = null;
      _contextPressure = null;
      _contextBreakdown = null;
      _sessionStats = const SessionWindowStats();
      _goal = null;
      _models = null;
      _modelsSessionId = null;
      _permissions = null;
      _commands = null;
      _sandboxMode = null;
      _schedules = null;
      _timelineSub = null;
      _planSub = null;
      _todosSub = null;
      _contextSub = null;
      _breakdownSub = null;
      _statsSub = null;
      _goalSub = null;
      _permissionsSub = null;
      _sandboxSub = null;
      _schedulesSub = null;
      return;
    }
    // Session-scoped projections reset on rebind: the leaving
    // session's values never flash under the entering one's header.
    // The model directory also unbinds — the remembered-selection apply
    // must never read the leaving session's seat as the entering one's.
    _timelineWindow = const TimelineWindow();
    _plan = null;
    _todos = null;
    _contextPressure = null;
    _contextBreakdown = null;
    _sessionStats = const SessionWindowStats();
    _goal = null;
    _models = null;
    _modelsSessionId = null;
    _skills = const <SkillEntry>[];
    _commands = null;
    _permissions = null;
    _sandboxMode = null;
    _schedules = null;
    _timelineSub = _repository.observeTimelineWindow(sessionId).listen((
      window,
    ) {
      _timelineWindow = window;
      _publishUpstream();
    });
    _planSub = _repository.observePlan(sessionId).listen((plan) {
      _plan = plan;
      _publishUpstream();
    });
    _todosSub = _repository.observeTodos(sessionId).listen((todos) {
      _todos = todos;
      _publishUpstream();
    });
    _contextSub = _repository.observeContextPressure(sessionId).listen((
      pressure,
    ) {
      _contextPressure = pressure;
      _publishUpstream();
    });
    _breakdownSub = _repository.observeContextBreakdown(sessionId).listen((
      breakdown,
    ) {
      _contextBreakdown = breakdown;
      _publishUpstream();
    });
    _statsSub = _repository.observeSessionStats(sessionId).listen((stats) {
      _sessionStats = stats;
      _publishUpstream();
    });
    _goalSub = _repository.observeGoal(sessionId).listen((goal) {
      _goal = goal;
      _publishUpstream();
    });
    _permissionsSub = _repository.observePermissions(sessionId).listen((
      permissions,
    ) {
      _permissions = permissions;
      _publishUpstream();
    });
    // The sandbox-mode override and the durable reminder set are
    // log-only session facts with no `session/*` projection at the pin:
    // they arrive only from these streams, so an unreported value stays
    // null and renders as unknown rather than as a default.
    _sandboxSub = _repository.observeSandboxMode(sessionId).listen((fact) {
      _sandboxMode = fact;
      _publishUpstream();
    });
    _schedulesSub = _repository.observeSchedules(sessionId).listen((reminders) {
      _schedules = reminders;
      _publishUpstream();
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
      } catch (e) {
        _agentPresets = null;
        ErrorLogCollector.instance.addBreadcrumb(
          'Failed to load agent presets: $e',
          level: 'warn',
        );
      }
      _publish();
    }());
  }

  /// Blank-session preset switch (web AgentPresetSeat select); host
  /// refusals (`agent-preset-locked`) surface through the error strip.
  void _selectAgentPreset(SelectAgentPreset action) {
    unawaited(
      _runCatchingForUi(
        () =>
            _repository.selectAgentPreset(action.sessionId, action.agentPreset),
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
      } catch (e) {
        ErrorLogCollector.instance.addBreadcrumb(
          'Failed to load skills for $sessionId: $e',
          level: 'warn',
        );
        if (_selectedSessionId == sessionId) {
          _skills = const <SkillEntry>[];
          _publish();
        }
      }
    }());
  }

  /// Live host-command roster for the `/` composer source and the submit
  /// decision table: one `commands/list` pull per session, cached until
  /// `commands/change` invalidates every entry. A pull failure — a
  /// subagent-owned session answers `session/agent-busy`, and a bare test
  /// double may not implement the route at all — leaves the static roster
  /// standing in rather than emptying the menu.
  void _loadCommands(String sessionId) {
    final cached = _commandsBySession[sessionId];
    if (cached != null) {
      _commands = cached;
      _publish();
      return;
    }
    unawaited(() async {
      try {
        final roster = await _repository.listCommands(sessionId);
        _commandsBySession[sessionId] = roster;
        if (_selectedSessionId == sessionId) {
          _commands = roster;
          _publish();
        }
      } catch (e) {
        ErrorLogCollector.instance.addBreadcrumb(
          'Failed to load commands for $sessionId: $e',
          level: 'warn',
        );
        if (_selectedSessionId == sessionId) {
          _commands = null;
          _publish();
        }
      }
    }());
  }

  /// The host-command facts a submit consults: the selected session's live
  /// roster once a pull settled, the static built-ins before that.
  List<HostCommand> get _commandRoster =>
      _commands == null ? kHostCommandNames : hostCommandFacts(_commands!);

  void _loadOlderHistory() {
    final sessionId = _selectedSessionId;
    if (sessionId == null) return;
    unawaited(_runCatchingForUi(() => _repository.loadOlderHistory(sessionId)));
  }

  void _refresh() {
    unawaited(() async {
      await _runCatchingForUi(_repository.refreshSessions);
      await _runCatchingForUi(_repository.refreshWorkspaces);
      _sessionsRefreshed = true;
      _maybeRestoreSelectedSession();
    }());
  }

  void _sendPrompt(SendPrompt action) {
    final sessionId = _selectedSessionId;
    if (sessionId == null) {
      action.onSettled?.call(false);
      return;
    }
    final images = _pendingImages;
    if (action.text.trim().isEmpty && images.isEmpty) {
      action.onSettled?.call(false);
      return;
    }
    // Web CommandUiRuntime submit table: a submitted line whose leading
    // token names a known host command routes through `commands/execute`
    // — never the prompt channel (the host does not parse commands out of
    // prompts; the model would receive the text as ordinary content).
    // Input-hinted commands take args; bare-only commands (no hint)
    // execute only without args; skills and unknown names fall through
    // to the prompt channel (the model serves them).
    //
    // `/export` is the exception: the host's handler only answers
    // "Session log download requested." because the browser owns the
    // transfer. On the phone the client owns it, so a bare `/export` runs
    // the download here instead of round-tripping.
    final submitted = action.text.trim();
    if (isBareSessionLogExport(submitted)) {
      unawaited(_exportSessionLog(sessionId));
      action.onSettled?.call(true);
      return;
    }
    final commandLine = hostCommandLineFor(submitted, _commandRoster);
    if (commandLine != null) {
      unawaited(() async {
        final accepted = await _executeHostCommand(
          sessionId,
          commandLine,
          images,
          detached: hostCommandIsBare(action.text.trim(), _commandRoster),
        );
        action.onSettled?.call(accepted);
      }());
      return;
    }
    final prompt = action.text.trim();
    _telemetry?.count('chat.message.send');
    _telemetry?.event(
      'chat.message.send',
      attributes: {
        'sessionId': sessionId,
        'mode': action.mode.name,
        'textLength': prompt.length,
        'images': images.length,
      },
    );
    // Optimistic user message for immediate visual feedback before network roundtrip
    if (prompt.isNotEmpty || images.isNotEmpty) {
      final optimisticMessage = TimelineMessage(
        ChatMessage(
          id: 'optimistic-${DateTime.now().microsecondsSinceEpoch}',
          sessionId: sessionId,
          role: MessageRole.user,
          text: prompt,
          images: [
            for (final img in images)
              AttachmentRef(
                attachmentId: img.id,
                name: img.name,
                mediaType: img.mediaType,
                bytes: img.byteSize,
                width: 0,
                height: 0,
              ),
          ],
          createdAtEpochMs: DateTime.now().millisecondsSinceEpoch,
          streaming: false,
        ),
      );
      final currentItems = List<TimelineItem>.of(_timelineWindow.items)
        ..add(optimisticMessage);
      _timelineWindow = TimelineWindow(
        items: currentItems,
        hasMoreOlder: _timelineWindow.hasMoreOlder,
        isLoadingOlder: _timelineWindow.isLoadingOlder,
        isLoading: _timelineWindow.isLoading,
      );
    }
    unawaited(() async {
      _isSending = true;
      _publish();
      final bool sent;
      try {
        sent =
            await _runCatchingForUi<bool>(() async {
              await _repository.sendMessage(
                SendMessageRequest(
                  sessionId: sessionId,
                  text: prompt,
                  mode: action.mode,
                  images: images,
                ),
              );
              return true;
            }) !=
            null;
        // Keep the draft's material only on failure: the composer clears
        // it (and writes the cleared marker) on the acceptance notice
        // below, mirroring the web input machine's "restore while
        // untouched" on a failed submit.
        if (sent) {
          _pendingImages = const <PendingImage>[];
        } else {
          _telemetry?.count('chat.message.send_failed');
          _telemetry?.event(
            'chat.message.send_failed',
            attributes: {'sessionId': sessionId, 'mode': action.mode.name},
          );
        }
      } finally {
        _isSending = false;
        _publish();
      }
      action.onSettled?.call(sent);
    }());
  }

  /// Executes one slash-command line. The images ride the command's
  /// admission (a command that does not declare image acceptance
  /// settles as an error result). An unmatched name (null execution)
  /// falls back to the ordinary prompt send — the web live-directory
  /// miss; an error result keeps the pending images and surfaces the
  /// command's text (the web keeps the submission for correction);
  /// success clears them (the state projections — plan chip, goal bar —
  /// carry the feedback). A dispatch failure (transport abort, business
  /// error) never re-routes the line to the prompt channel: the roster
  /// already adjudicated it as a host command, and the web's `execute()`
  /// reports such failures to the composer notice instead of submitting
  /// the line — re-sending it would hand the model the literal command
  /// text.
  ///
  /// A [detached] dispatch (a bare-only command like `/compact` — web
  /// `runDetached`) never holds the composer's sending state: the
  /// command runs server-side for as long as its HTTP request survives,
  /// and the outcome renders as the timeline command card folded from
  /// `command/run` + `command/done`. Only an immediate failure — a
  /// transport abort or an admission error that never entered a handler —
  /// surfaces in the error strip; the line is not re-sent either way.
  ///
  /// A detached dispatch also retries its transport once (see
  /// `ChatRepository.executeCommand`): the host aborts a command the
  /// moment its HTTP request dies, so a socket drop mid-compaction
  /// leaves the session untouched and a fresh-connection re-dispatch is
  /// a clean re-run. The first attempt's aborted `command/done` still
  /// folds into its card; the retry's success folds into a second one.
  ///
  /// The result is the acceptance notice a composer dispatch waits on:
  /// true when the command settled without an error outcome, false on a
  /// dispatch failure or an error result — anything else keeps the
  /// reader's draft.
  Future<bool> _executeHostCommand(
    String sessionId,
    String line,
    List<PendingImage> images, {
    bool detached = false,
  }) async {
    if (!detached) {
      _isSending = true;
      _publish();
    }
    _telemetry?.count('chat.command.execute');
    _telemetry?.event(
      'chat.command.execute',
      attributes: {'sessionId': sessionId, 'command': line},
    );
    try {
      _errorMessage = null;
      _commandFailed = false;
      final CommandExecution? execution;
      try {
        execution = await _repository.executeCommand(
          sessionId,
          line,
          images,
          retryOnTransportAbort: detached,
        );
      } catch (error, stackTrace) {
        _errorMessage = _formatUiError(error);
        ErrorLogCollector.instance.captureError(
          error,
          stackTrace: stackTrace,
          context: <String, Object?>{
            'controller': 'ChatController',
            'action': 'executeCommand',
            'sessionId': sessionId,
            'command': line,
          },
        );
        // A detached dispatch never holds the composer, but an immediate
        // transport/admission failure still surfaces in the error strip —
        // there is no `command/done` to fold into a command card.
        if (detached) {
          _publish();
        }
        _telemetry?.event(
          'chat.command.error',
          attributes: {
            'sessionId': sessionId,
            'command': line,
            'error': error.toString(),
          },
        );
        return false;
      }
      if (execution == null) {
        final sent =
            await _runCatchingForUi<bool>(() async {
              await _repository.sendMessage(
                SendMessageRequest(
                  sessionId: sessionId,
                  text: line,
                  mode: PromptMode.queue,
                ),
              );
              return true;
            }) !=
            null;
        _pendingImages = const <PendingImage>[];
        return sent;
      }
      if (execution.kind == CommandOutcomeKind.error) {
        _errorMessage = execution.text;
        _commandFailed = execution.text == null;
        ErrorLogCollector.instance.addBreadcrumb(
          'Command execution failed ($sessionId): ${execution.text}',
          level: 'warning',
        );
        _telemetry?.event(
          'chat.command.error',
          attributes: {
            'sessionId': sessionId,
            'command': line,
            'result': execution.text ?? '',
          },
        );
        return false;
      }
      _pendingImages = const <PendingImage>[];
      return true;
    } finally {
      if (!detached) {
        _isSending = false;
        _publish();
      }
    }
  }

  /// Validate picked images against the host limits, then queue the rest.
  void _admitPendingImages(List<PendingImage> images) {
    if (images.isEmpty) return;
    final limits = _imageLimits;
    final admitted = <PendingImage>[];
    final rejected = <ImageRejection>[];
    for (final image in images) {
      if (!limits.mediaTypes.contains(image.mediaType)) {
        rejected.add(UnsupportedImageType(image.name, image.mediaType));
      } else if (image.byteSize > limits.maxImageBytes) {
        rejected.add(ImageTooLarge(image.name, limits.maxImageBytes));
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
      rejected.add(NoImageRoom(room));
    }
    // Admission facts ride the state stream for the UI layer to localize;
    // they clear on the next pass (an empty list reads as "no new
    // rejections", distinct from the shared error strip).
    _imageRejections = rejected;
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
    } catch (e) {
      ErrorLogCollector.instance.addBreadcrumb(
        'Failed to read attachment ${ref.attachmentId} for $sessionId: $e',
        level: 'warning',
      );
      return null;
    }
  }

  /// Reads a text window of a workspace file for the file-preview sheet
  /// (`workspaceFiles/read`). The controller stays locale-free: a failure
  /// propagates to the sheet, which renders the localized message.
  Future<WorkspaceFileContent> readWorkspaceFile(
    String sessionId,
    String path,
  ) => _repository.readWorkspaceFile(sessionId, path);

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
      _modelsSessionId = sessionId;
      _publish();
      _maybeApplyModelPreferences();
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
          _modelsSessionId = sessionId;
          _publish();
          _maybeApplyModelPreferences();
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
        _rememberModelSelection(updated);
        _applySelectedModel(sessionId, updated);
      }
    }());
  }

  /// Patch the cached directory's current selection in place (the host
  /// validated the route before accepting it).
  void _applySelectedModel(String sessionId, ModelSelection updated) {
    final models = _models;
    if (models == null) return;
    final patched = SessionModels(
      current: updated,
      routable: models.routable,
      groups: models.groups,
      failures: models.failures,
    );
    _modelsBySession[sessionId] = patched;
    if (_selectedSessionId == sessionId) {
      _models = patched;
      _modelsSessionId = sessionId;
      _publish();
    }
  }

  /// Resolve the selected-session seam once it settles, then arm the
  /// cold-start restore (web `dsh.sessions.current` parity: the surface
  /// reopens the session it had open when the app last ran). A failed
  /// seam (unreadable documents directory) leaves restore off — the
  /// surface opens on no selection, exactly as before the feature.
  void _loadSessionSelection(Future<SessionSelectionPersistence?>? source) {
    if (source == null) return;
    unawaited(
      source
          .then((store) async {
            if (_disposed || store == null) return;
            _selectionStore = store;
            final stored = await store.readSelectedSession();
            if (_disposed) return;
            _restoreSessionId = stored;
            _maybeRestoreSelectedSession();
          })
          .catchError((Object e) {
            ErrorLogCollector.instance.addBreadcrumb(
              'Session selection restore failed: $e',
              level: 'warn',
            );
          }),
    );
  }

  /// Restore the stored selection once the session list can adjudicate
  /// it: select when the session exists, give up when a non-empty list
  /// proves it gone (archived or deleted). A session selected in the
  /// meantime wins and cancels the restore.
  void _maybeRestoreSelectedSession() {
    if (_restoreGivenUp || _restoreSessionId == null) return;
    if (_selectedSessionId != null) {
      // The reader (or another restore) already selected; nothing to do.
      _restoreSessionId = null;
      return;
    }
    final target = _restoreSessionId!;
    final present = _sessions.any((session) => session.id == target);
    if (!present) {
      // An empty list can still be the pre-load state; only a settled,
      // non-empty one proves the stored session gone.
      if (_sessionsRefreshed && _sessions.isNotEmpty) {
        _restoreSessionId = null;
        _restoreGivenUp = true;
      }
      return;
    }
    _restoreSessionId = null;
    _telemetry?.count('chat.session.restore');
    _selectSession(target);
  }

  /// Persist one selection change through the seam; a write failure only
  /// costs the next cold start's restore (the selection still works).
  void _rememberSelectedSession(String? sessionId) {
    final store = _selectionStore;
    if (store == null) return;
    unawaited(() async {
      try {
        await store.writeSelectedSession(sessionId);
      } catch (e) {
        ErrorLogCollector.instance.addBreadcrumb(
          'Failed to persist selected session: $e',
          level: 'warn',
        );
      }
    }());
  }

  /// Resolve the model-preference seam once it settles (the store loads
  /// asynchronously); the remembered values then arm the apply pass. A
  /// failed seam (unreadable documents directory) keeps remembering off —
  /// the seat behaves exactly as before the feature.
  void _loadModelPreferences(Future<ModelPreferencePersistence?>? source) {
    if (source == null) return;
    unawaited(
      source
          .then((store) async {
            if (_disposed || store == null) return;
            _modelPrefsStore = store;
            final preferences = await store.read();
            if (_disposed) return;
            _modelPrefs = preferences;
            _prefsLoaded = true;
            // The apply pass may already have decided "nothing remembered"
            // against the empty default; re-arm it with the loaded values.
            _modelPrefsDecidedFor = null;
            _publish();
            _maybeApplyModelPreferences();
          })
          .catchError((Object e) {
            ErrorLogCollector.instance.addBreadcrumb(
              'Model preferences restore failed: $e',
              level: 'warn',
            );
          }),
    );
  }

  /// Remember one committed selection: it becomes the last selection and
  /// overwrites its route's remembered effort.
  void _rememberModelSelection(ModelSelection selection) {
    final next = _modelPrefs.remembering(selection);
    _modelPrefs = next;
    _publish();
    final store = _modelPrefsStore;
    if (store == null) return;
    unawaited(() async {
      try {
        await store.write(next);
      } catch (e) {
        ErrorLogCollector.instance.addBreadcrumb(
          'Failed to persist model selection: $e',
          level: 'warn',
        );
      }
    }());
  }

  /// Apply the remembered selection to the selected session's seat. Only
  /// a blank session takes the remembered model (web agent-default-model
  /// parity: a session that already ran keeps the selection the host
  /// logged for it); the decision is made once per session selection.
  void _maybeApplyModelPreferences() {
    final sessionId = _selectedSessionId;
    if (sessionId == null || _modelPrefsDecidedFor == sessionId) return;
    if (!_prefsLoaded || _modelsSessionId != sessionId) return;
    final session = _sessions.where((item) => item.id == sessionId).firstOrNull;
    if (session == null) return;
    _modelPrefsDecidedFor = sessionId;
    final remembered = _modelPrefs.lastSelection;
    if (remembered == null || !session.blank) return;
    final current = _models?.current;
    if (current == null || remembered == current) return;
    _telemetry?.count('chat.model.prefs.apply');
    unawaited(() async {
      try {
        final updated = await _repository.selectModel(sessionId, remembered);
        if (_disposed || _selectedSessionId != sessionId) return;
        _applySelectedModel(sessionId, updated);
      } catch (error) {
        // A remembered route the host can no longer serve stays
        // unapplied; the seat keeps the host's own current selection.
        ErrorLogCollector.instance.addBreadcrumb(
          'Failed to apply model preferences for $sessionId: $error',
          level: 'warning',
        );
        _telemetry?.count('chat.model.prefs.apply_failed');
        _telemetry?.event(
          'chat.model.prefs.apply_failed',
          attributes: {'sessionId': sessionId, 'error': error.toString()},
        );
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

  /// GoalBar strip action: edit the objective of the current goal
  /// (web GoalBar inline edit).
  void _editGoal(String objective) {
    final sessionId = _selectedSessionId;
    if (sessionId == null) return;
    final goal = _goal?.goal;
    if (goal == null) return;
    final ref = GoalRef(id: goal.id, revision: goal.revision);
    unawaited(
      _runCatchingForUi(() => _repository.editGoal(sessionId, ref, objective)),
    );
  }

  void _cancelTurn() {
    final sessionId = _selectedSessionId;
    if (sessionId == null) return;
    _telemetry?.count('chat.turn.cancel');
    _telemetry?.event('chat.turn.cancel', attributes: {'sessionId': sessionId});
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
      _rememberSelectedSession(resolved);
      _timelineWindow = const TimelineWindow();
      _bindSelected(resolved);
      _loadModels(resolved);
      _loadSkills(resolved);
      _loadCommands(resolved);
      _publish();
      await _runCatchingForUi(() => _repository.openSession(resolved));
      _telemetry?.count('chat.session.create');
      _telemetry?.event(
        'chat.session.create',
        attributes: {
          'sessionId': resolved,
          'workspaceId': workspaceId ?? '',
          'agentPreset': agentPreset ?? '',
        },
      );
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
    _telemetry?.count('chat.approval.respond');
    _telemetry?.event(
      'chat.approval.respond',
      attributes: {'sessionId': sessionId, 'allowed': action.allowed},
    );
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

  /// Reject one pending dynamic-Cordis activation request
  /// (`dynamicCordisRunner/resolveRequestRun`).
  ///
  /// Rejection is the only decision this client can deliver honestly: an
  /// approval names the exact Client activation a browser plugin runtime
  /// created, and this client has none. A rejection refuses both halves and
  /// is what releases the blocked `cordis_run` tool call. A refusal of the
  /// answer itself (the request already settled, the host rejected the
  /// resolution, transport) raises [ChatUiState.cordisAnswerFailed] for the
  /// localized sentence; the raw host detail goes to the error log, where
  /// it is actionable, rather than to the reader.
  void _rejectCordisRun(RejectCordisRun action) {
    _telemetry?.count('chat.cordis.reject');
    _telemetry?.event(
      'chat.cordis.reject',
      attributes: {'requestId': action.requestId},
    );
    unawaited(() async {
      _errorMessage = null;
      _commandFailed = false;
      _cordisAnswerFailed = false;
      _publish();
      try {
        await _repository.resolveCordisRunRequest(
          action.requestId,
          const CordisRunRejected(),
        );
      } catch (error, stackTrace) {
        _cordisAnswerFailed = true;
        _publish();
        ErrorLogCollector.instance.captureError(
          error,
          stackTrace: stackTrace,
          context: <String, Object?>{
            'controller': 'ChatController',
            'action': 'resolveCordisRunRequest',
            'requestId': action.requestId,
          },
        );
        _telemetry?.count('chat.cordis.reject_failed');
        _telemetry?.event(
          'chat.cordis.reject_failed',
          attributes: {
            'requestId': action.requestId,
            'error': error.toString(),
          },
        );
      }
    }());
  }

  void _answerQuestion(AnswerQuestionAction action) {
    final sessionId = _selectedSessionId;
    if (sessionId == null) return;
    _telemetry?.count('chat.question.answer');
    _telemetry?.event(
      'chat.question.answer',
      attributes: {'sessionId': sessionId, 'answers': action.answers.length},
    );
    unawaited(
      _runCatchingForUi(
        () => _repository.answerQuestions(
          action.requestId,
          QuestionEvidence(sessionId: sessionId, answers: action.answers),
        ),
      ),
    );
  }

  void _dismissQuestion(DismissQuestionAction action) {
    final sessionId = _selectedSessionId;
    if (sessionId == null) return;
    unawaited(
      _runCatchingForUi(
        () => _repository.cancelQuestions(action.requestId, sessionId),
      ),
    );
  }

  String _workspaceLabelForSession(SessionSummary session) {
    for (final workspace in _workspaces) {
      if (workspace.sessionIds.contains(session.id)) {
        return workspace.title;
      }
    }
    final cwd = session.cwd;
    if (cwd != null && cwd.isNotEmpty) {
      final segments = cwd.split(RegExp(r'[/\\]+'));
      for (final segment in segments.reversed) {
        if (segment.isNotEmpty) return segment;
      }
      return cwd;
    }
    return '';
  }

  /// Merges client-side metadata matches (session title and workspace label/title substring
  /// match, case-insensitive, ranked by recency) ahead of host content-search results
  /// de-duplicated by sessionId (matches reference `tree.ts` lines 321-393
  /// `deriveSearchResults`).
  List<SessionSearchResult> _mergeSearchResults(
    String normalizedQuery,
    List<SessionSearchResult> hostResults,
  ) {
    final q = normalizedQuery.toLowerCase();
    if (q.isEmpty) return const <SessionSearchResult>[];

    final hostSnippetBySession = <String, String>{};
    for (final item in hostResults) {
      hostSnippetBySession.putIfAbsent(item.sessionId, () => item.snippet);
    }

    final sessionsById = <String, SessionSummary>{
      for (final s in _sessions) s.id: s,
    };

    final localSessions = <SessionSummary>[];
    for (final session in _sessions) {
      // Mirroring reference tree.ts sessionVisible & deriveSearchResults:
      // blank placeholders and subagent children never enter search.
      if (session.blank || session.origin == 'subagent') {
        continue;
      }
      final titleMatch = session.displayTitle.toLowerCase().contains(q);
      final workspaceMatch = _workspaceLabelForSession(session)
          .toLowerCase()
          .contains(q);
      if (titleMatch || workspaceMatch) {
        localSessions.add(session);
      }
    }

    // Rank local matches by recency (newest first, tie-break by id)
    // matching reference tree.ts line 107 `byRecency`.
    localSessions.sort((a, b) {
      final delta = b.updatedAtEpochMs - a.updatedAtEpochMs;
      if (delta != 0) return delta;
      return a.id.compareTo(b.id);
    });

    final results = <SessionSearchResult>[];
    final includedSessionIds = <String>{};

    // 1. Client-side local matches first
    for (final session in localSessions) {
      includedSessionIds.add(session.id);
      final snippet = hostSnippetBySession[session.id] ?? '';
      results.add(SessionSearchResult(sessionId: session.id, snippet: snippet));
    }

    // 2. Host content search matches
    for (final item in hostResults) {
      if (includedSessionIds.contains(item.sessionId)) continue;
      final session = sessionsById[item.sessionId];
      if (session == null || (!session.blank && session.origin != 'subagent')) {
        includedSessionIds.add(item.sessionId);
        results.add(item);
      }
    }

    return results;
  }

  void _searchSessions(String query) {
    _searchTimer?.cancel();
    _searchTimer = null;
    final seq = ++_searchSeq;

    final sanitized = _sanitizeSearchQuery(query).trim();
    if (sanitized.isEmpty) {
      _searchResults = const <SessionSearchResult>[];
      _publish();
      return;
    }

    // Surface local matches immediately while debounce / network request is pending.
    _searchResults = _mergeSearchResults(
      sanitized,
      const <SessionSearchResult>[],
    );
    _publish();

    _searchTimer = Timer(_searchDebounceDelay, () {
      _searchTimer = null;
      if (_disposed) return;
      _telemetry?.count('chat.session.search');
      unawaited(() async {
        final results = await _runCatchingForUi(
          () => _repository.searchSessions(sanitized),
        );
        // Latest-wins sequence guard: the controller cannot abort the in-flight HTTP
        // call directly (no AbortController on Dart HTTP repo interface); this monotonic
        // sequence check is the semantic equivalent of the reference's per-query
        // AbortController (WorkspaceBrowser.tsx lines 872 & 900), ensuring that
        // only responses from the newest dispatched query may assign [_searchResults].
        if (_disposed || seq != _searchSeq) return;
        _searchResults = _mergeSearchResults(
          sanitized,
          results ?? const <SessionSearchResult>[],
        );
        _publish();
      }());
    });
  }

  void _forkSession(String sessionId, int? atSeq) {
    unawaited(() async {
      final forked = await _runCatchingForUi(
        () => _repository.forkSession(sessionId, atSeq: atSeq),
      );
      if (forked == null) return;
      _selectedSessionId = forked.id;
      _rememberSelectedSession(forked.id);
      _timelineWindow = const TimelineWindow();
      _bindSelected(forked.id);
      _loadModels(forked.id);
      _loadSkills(forked.id);
      _loadCommands(forked.id);
      _publish();
      await _runCatchingForUi(() => _repository.openSession(forked.id));
      _telemetry?.count('chat.session.fork');
      _telemetry?.event(
        'chat.session.fork',
        attributes: {'fromSessionId': sessionId, 'sessionId': forked.id},
      );
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
      _commandFailed = false;
      _cordisAnswerFailed = false;
      _publish();
      return await block();
    } catch (error, stackTrace) {
      _errorMessage = _formatUiError(error);
      _publish();
      ErrorLogCollector.instance.captureError(
        error,
        stackTrace: stackTrace,
        context: const <String, Object?>{'controller': 'ChatController'},
      );
      _telemetry?.count('chat.error');
      _telemetry?.event(
        'chat.error',
        attributes: {
          'type': error.runtimeType.toString(),
          'message': error.toString(),
        },
      );
      return null;
    }
  }

  static String _formatUiError(Object error) {
    final str = error.toString();
    if (str.contains('session-persistence/already-owned') ||
        str.contains('SessionAlreadyOwned')) {
      return 'SESSION_ALREADY_OWNED';
    }
    return str;
  }
}

/// Keep controlled input and RPC payload inside the session.search wire contract
/// (matches reference `WorkspaceBrowser.tsx` lines 42-50 `sanitizeSearchQuery`).
String _sanitizeSearchQuery(String value) {
  final withoutNul = value.replaceAll('\x00', '');
  if (withoutNul.length <= _searchQueryMaxCodeUnits) {
    return withoutNul;
  }
  var end = _searchQueryMaxCodeUnits;
  final last = withoutNul.codeUnitAt(end - 1);
  final next = withoutNul.codeUnitAt(end);
  if (last >= 0xD800 && last <= 0xDBFF && next >= 0xDC00 && next <= 0xDFFF) {
    end--;
  }
  return withoutNul.substring(0, end);
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
