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
import 'package:domain/model/context_pressure.dart';
import 'package:domain/model/plan.dart';
import 'package:domain/model/prompt.dart';
import 'package:domain/model/session.dart';
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
  ChatController(this._repository) {
    _refresh();
    _subscribeBaselines();
    _observeSelectedSessionRemoval();
  }

  final ChatRepository _repository;
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
  List<SkillEntry> _skills = const <SkillEntry>[];
  ContextPressure? _contextPressure;

  /// One skill.list RPC per session, mirroring the Web catalog cache.
  final Map<String, List<SkillEntry>> _skillsBySession =
      <String, List<SkillEntry>>{};

  /// Decoded attachment bytes cache; scroll re-entry must not re-download.
  final LinkedHashMap<String, Uint8List> _attachmentBytes =
      LinkedHashMap<String, Uint8List>();
  Future<void> _attachmentLock = Future<void>.value();

  StreamSubscription<void>? _timelineSub;
  StreamSubscription<void>? _planSub;
  StreamSubscription<void>? _contextSub;

  ChatUiState get state => _state.value;
  Stream<ChatUiState> get uiState => _state.stream;

  void dispose() {
    for (final sub in _subs) {
      unawaited(sub.cancel());
    }
    unawaited(_timelineSub?.cancel());
    unawaited(_planSub?.cancel());
    unawaited(_contextSub?.cancel());
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
      skills: _skills,
      contextPressure: _contextPressure,
    );
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
        _createSession(workspaceId: action.workspaceId);
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
      case ImagePickError():
        _errorMessage = action.message;
        _publish();
    }
  }

  void _selectSession(String sessionId) {
    _selectedSessionId = sessionId;
    _timelineWindow = const TimelineWindow();
    _bindSelected(sessionId);
    _loadSkills(sessionId);
    _publish();
    unawaited(_runCatchingForUi(() => _repository.openSession(sessionId)));
  }

  /// Re-subscribes the selected-session timeline and plan streams (the
  /// Kotlin flatMapLatest equivalent).
  void _bindSelected(String? sessionId) {
    unawaited(_timelineSub?.cancel());
    unawaited(_planSub?.cancel());
    unawaited(_contextSub?.cancel());
    if (sessionId == null) {
      _timelineWindow = const TimelineWindow();
      _plan = null;
      _contextPressure = null;
      _timelineSub = null;
      _planSub = null;
      _contextSub = null;
      return;
    }
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
    _contextSub = _repository.observeContextPressure(sessionId).listen((
      pressure,
    ) {
      _contextPressure = pressure;
      _publish();
    });
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

  void _cancelTurn() {
    final sessionId = _selectedSessionId;
    if (sessionId == null) return;
    unawaited(_runCatchingForUi(() => _repository.cancelTurn(sessionId)));
  }

  void _createSession({String? workspaceId}) {
    unawaited(() async {
      // Web parity: a workspace's blank session is the provisional New
      // Session row. Reuse it instead of minting another hidden row.
      String? sessionId;
      if (workspaceId != null) {
        sessionId = _reusableBlankSessionId(workspaceId);
      }
      sessionId ??= (await _runCatchingForUi(
        () => _repository.createSession(
          CreateSessionRequest(workspaceId: workspaceId),
        ),
      ))?.id;
      final resolved = sessionId;
      if (resolved == null) return;
      _selectedSessionId = resolved;
      _timelineWindow = const TimelineWindow();
      _bindSelected(resolved);
      _publish();
      await _runCatchingForUi(() => _repository.openSession(resolved));
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
