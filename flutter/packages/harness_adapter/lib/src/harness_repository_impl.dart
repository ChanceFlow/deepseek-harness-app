/// The one ChatRepository implementation that speaks dsh wire protocol.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io' show SocketException;
import 'dart:typed_data';

import 'package:domain/model/attachment.dart';
import 'package:domain/model/command.dart';
import 'package:domain/model/connection_state.dart';
import 'package:domain/model/context_pressure.dart';
import 'package:domain/model/session_window_stats.dart';
import 'package:domain/model/directory.dart';
import 'package:domain/model/goal.dart';
import 'package:domain/model/model_catalog.dart';
import 'package:domain/model/permission_select.dart';
import 'package:domain/model/plan.dart';
import 'package:domain/model/todo.dart';
import 'package:domain/model/prompt.dart';
import 'package:domain/model/session.dart';
import 'package:domain/model/settings.dart';
import 'package:domain/model/skills.dart';
import 'package:domain/model/subagent.dart';
import 'package:domain/model/timeline_item.dart';
import 'package:domain/model/timeline_window.dart';
import 'package:domain/model/workspace.dart';
import 'package:domain/model/agent_preset.dart';
import 'package:domain/repository/chat_repository.dart'
    show ChatRepository, QuestionEvidence;
import 'package:network/dsh_exceptions.dart';
import 'package:network/dsh_rpc_client.dart';
import 'package:network/rpc_envelope.dart';

import 'dsh_connection_manager.dart';
import 'context_pressure_fold.dart';
import 'session_stats_fold.dart';
import 'dsh_wire_types.dart';
import 'rpc_map.dart';
import 'state_stream.dart';
import 'timeline_reducer.dart';
import 'wire_json.dart';

/// Coalescing window for streaming-chunk timeline publishes: chunks that
/// land inside it collapse into one publish, capping the publish rate at
/// frame cadence (the reference web client's animation-frame flush).
const Duration kStreamPublishWindow = Duration(milliseconds: 16);

const String _sessionList = 'session.list';
const String _sessionCreate = 'session.create';
const String _sessionHistory = 'session.history';
const String _sessionPrompt = 'session.prompt';
const String _sessionAttachment = 'session.attachment';
const String _sessionCancel = 'session.cancel';
const String _sessionModels = 'session.models';
const String _sessionSelectModel = 'session.selectModel';
const String _sessionSearch = 'session.search';
const String _sessionRename = 'session.rename';
const String _sessionFork = 'session.fork';
const String _sessionUpdateQueue = 'session.updateQueue';
const String _workspaceList = 'workspace.list';
const String _workspaceCreate = 'workspace.create';
const String _workspaceRename = 'workspace.rename';
const String _workspaceDelete = 'workspace.delete';
const String _workspaceInsertBefore = 'workspace.insertBefore';
const String _workspaceInsertSessionBefore = 'workspace.insertSessionBefore';
const String _workspaceArchiveSession = 'workspace.archiveSession';
const String _hostListDirectory = 'host.listDirectory';
const String _hostCreateDirectory = 'host.createDirectory';
const String _settingsDescribe = 'settings.describe';
const String _settingsUpdate = 'settings.update';
const String _settingsReplace = 'settings.replace';
const String _settingsMutate = 'settings.mutate';
const String _credentialsDescribe = 'credentials.describe';
const String _credentialsSet = 'credentials.set';
const String _credentialsUnset = 'credentials.unset';
const int _credentialsMaxRefs = 64;
const String _skillList = 'skill.list';
const int _historyPageMessages = 50;
const String _subagentList = 'subagent.list';
const String _subagentInterrupt = 'subagent.interrupt';
const String _subagentHistory = 'subagent.history';
const String _subagentPrompt = 'subagent.prompt';
const String _goalCreate = 'goal.create';
const String _goalEdit = 'goal.edit';
const String _goalPause = 'goal.pause';
const String _goalResume = 'goal.resume';
const String _goalComplete = 'goal.complete';
const String _goalClear = 'goal.clear';
const String _commandsExecute = 'commands/execute';
const String _agentPresetList = 'agentPreset.list';
const String _agentPresetSelect = 'agentPreset.select';

final class _HistoryPage {
  _HistoryPage({required this.events, required this.hasMore});

  final List<JsonMap> events;
  final bool hasMore;
}

class HarnessRepositoryImpl implements ChatRepository {
  HarnessRepositoryImpl(this._rpcClient, this._connectionManager) {
    _connectionManager.start();
    _collectConnection();
    _collectMuxFrames();
    _collectHostFrames();
  }

  final DshRpcClient _rpcClient;
  final DshConnectionManager _connectionManager;

  final StateStream<int> _connectionGeneration = StateStream<int>(0);
  final StateStream<List<SessionSummary>> _sessions =
      StateStream<List<SessionSummary>>(<SessionSummary>[]);
  final StateStream<List<WorkspaceSummary>> _workspaces =
      StateStream<List<WorkspaceSummary>>(<WorkspaceSummary>[]);
  final StateStream<Set<String>> _archivedSessionIds = StateStream<Set<String>>(
    <String>{},
  );
  /// Registry-global pending-interaction mirror: session id -> the
  /// outstanding user-wait status (approval / plan-review / question).
  /// Fed from the raw approval/question frame stream BEFORE the per-session
  /// fan-out, so sessions never instantiated in the app still light the
  /// sidebar's amber dot and notification detection (web SessionManager
  /// parity). Cleared per
  /// connection generation — the reopen replay re-adds still-pending
  /// requests.
  final StateStream<Map<String, SessionPendingInteraction>>
      _pendingInteractions = StateStream<Map<String, SessionPendingInteraction>>(
    const <String, SessionPendingInteraction>{},
  );
  /// Session id -> per-key pending status (`a:<approvalId>` /
  /// `q:<rpcId>`); a session may wait on several interactions at once.
  /// [StateStream.value] of [_pendingInteractions] is the last-status-per-
  /// session projection of this map.
  final Map<String, Map<String, SessionPendingInteraction>> _pendingBySession =
      <String, Map<String, SessionPendingInteraction>>{};
  /// The session the app is currently viewing (last `openSession` target).
  /// The finished-but-unviewed reminder (green dot) is armed only when a
  /// session stops running while it is NOT this one (web SessionManager
  /// `completedNotifications`).
  String? _openSessionId;
  /// Last observed running bit per session, driving the true→false edge
  /// that arms the completion reminder.
  final Map<String, bool> _prevRunningBySession = <String, bool>{};
  final StateStream<ImageLimits?> _imageLimits = StateStream<ImageLimits?>(
    null,
  );
  final Map<String, _SessionState> _sessionStates = <String, _SessionState>{};
  /// Session id -> answerable live frames that arrived before the session's
  /// state was instantiated (web SessionManager `pendingBuffers` parity).
  /// `question/requested`, `approval/requested` and `session/queue` never
  /// land in session history — an open's backfill shows only the still-running
  /// tool call — so a frame dropped here would render the question/approval
  /// card forever absent while its tool spinner turns. Buffered frames are
  /// replayed into the state when `_sessionStateFor` first creates it (they
  /// enter `_pending` until `ensureLoaded`, which replays them after the
  /// history reset — the same ordering as a frame arriving live). Matching
  /// `* /resolved` frames compact the buffer so an already-answered request is
  /// never replayed.
  final Map<String, List<ServerRequest>> _pendingBuffers =
      <String, List<ServerRequest>>{};
  final Map<String, StateStream<GoalProjection?>> _goalProjections =
      <String, StateStream<GoalProjection?>>{};
  final Map<String, StateStream<PlanState?>> _planProjections =
      <String, StateStream<PlanState?>>{};
  final Map<String, StateStream<List<TodoItem>?>> _todoProjections =
      <String, StateStream<List<TodoItem>?>>{};
  final Map<String, StateStream<PermissionSelect?>> _permissionProjections =
      <String, StateStream<PermissionSelect?>>{};
  final Mutex _resyncMutex = Mutex();
  final List<StreamSubscription<void>> _subs = <StreamSubscription<void>>[];

  /// Releases stream subscriptions; tests call this to avoid leaks.
  Future<void> dispose() async {
    for (final sub in _subs) {
      await sub.cancel();
    }
    _subs.clear();
    for (final state in _sessionStates.values) {
      state.discard();
    }
  }

  @override
  Stream<ConnectionState> observeConnectionState() =>
      _connectionManager.state.stream;

  @override
  Stream<List<SessionSummary>> observeSessions() => combineLatest3(
    _sessions.stream,
    _archivedSessionIds.stream,
    _pendingInteractions.stream,
    (current, archived, pending) => current
        .where((item) => !archived.contains(item.id))
        .map((item) => _withPending(item, pending[item.id]))
        .toList(),
  );

  @override
  Future<void> refreshSessions() async {
    final current = await _loadSessions();
    _sessions.value = current;
  }

  @override
  Future<SessionSummary> createSession(CreateSessionRequest request) async {
    final payload = <String, Object?>{
      if (request.sessionId != null) 'sessionId': request.sessionId,
      if (request.workspaceId != null) 'workspaceId': request.workspaceId,
      if (request.cwd != null) 'cwd': request.cwd,
      if (request.agentPreset != null) 'agentPreset': request.agentPreset,
    };
    final value = await _call(
      _sessionCreate,
      _sessionCreate,
      payload,
    ).valueOrThrow();
    final created = wireString(value, 'sessionId');
    if (created == null) {
      throw const FormatException('session.create missing sessionId');
    }
    _sessions.value = await _loadSessions();
    return SessionSummary(id: created, blank: true);
  }

  @override
  Future<AgentPresetRoster> listAgentPresets() async {
    final value = await _call(
      _agentPresetList,
      _agentPresetList,
      <String, Object?>{},
    ).valueOrThrow();
    final decoded = AgentPresetListValueWire.fromJson(value);
    return AgentPresetRoster(
      entries: decoded.presets.map(_toDomainAgentPresetEntry).toList(),
      authorable: decoded.authorable,
      hasDocument: decoded.hasDocument,
    );
  }

  @override
  Future<String> selectAgentPreset(String sessionId, String agentPreset) async {
    final value = await _call(_agentPresetSelect, _agentPresetSelect, {
      'sessionId': sessionId,
      'agentPreset': agentPreset,
    }).valueOrThrow();
    final echoed = wireString(value, 'agentPreset');
    if (echoed == null) {
      throw const FormatException('agentPreset.select missing agentPreset');
    }
    return echoed;
  }

  @override
  Future<DirectoryListing> listDirectory(String? path) async {
    final payload = <String, Object?>{if (path != null) 'path': path};
    final value = await _call(
      _hostListDirectory,
      _hostListDirectory,
      payload,
    ).valueOrThrow();
    return _toDomainDirectoryListing(DirectoryListingValueWire.fromJson(value));
  }

  @override
  Future<String> createDirectory(String parentPath, String name) async {
    final value = await _call(_hostCreateDirectory, _hostCreateDirectory, {
      'path': parentPath,
      'name': name,
    }).valueOrThrow();
    final path = wireString(value, 'path');
    if (path == null) {
      throw const FormatException('host.createDirectory missing path');
    }
    return path;
  }

  @override
  Future<SettingsSnapshot> describeSettings() async {
    final value = await _call(
      _settingsDescribe,
      _settingsDescribe,
      <String, Object?>{},
    ).valueOrThrow();
    final described = SettingsDescribeValueWire.fromJson(value);
    return SettingsSnapshot(
      writable: described.writable,
      hasDocument: described.hasDocument,
      namespaces: described.namespaces.map(_toDomainSettingsNamespace).toList(),
      credentialRefs: described.namespaces
          .expand((namespace) => namespace.credentialRefs)
          .toSet()
          .take(_credentialsMaxRefs)
          .toList(),
    );
  }

  @override
  Future<List<CredentialStatus>> describeCredentials(List<String> refs) async {
    if (refs.isEmpty) return const <CredentialStatus>[];
    final value = await _call(_credentialsDescribe, _credentialsDescribe, {
      'refs': refs.take(_credentialsMaxRefs).toList(),
    }).valueOrThrow();
    return decodeCredentialsDescribeValue(value);
  }

  @override
  Future<void> setCredential(String ref, String value) async {
    if (value.isEmpty) {
      throw ArgumentError('credential value must be non-empty');
    }
    await _call(_credentialsSet, _credentialsSet, {
      'ref': ref,
      'value': value,
    }).valueOrThrow();
  }

  @override
  Future<void> unsetCredential(String ref) async {
    await _call(_credentialsUnset, _credentialsUnset, {
      'ref': ref,
    }).valueOrThrow();
  }

  @override
  Future<SettingsNamespace> updateSetting(
    String ns,
    String key,
    String jsonValue, {
    int? expectedRevision,
  }) async {
    final value = await _call(_settingsUpdate, _settingsUpdate, {
      'ns': ns,
      'patch': {key: _parseJsonValue(jsonValue)},
      if (expectedRevision != null) 'expectedRevision': expectedRevision,
    }).valueOrThrow();
    return _toDomainSettingsNamespace(SettingsNamespaceWire.fromJson(value));
  }

  @override
  Future<SettingsNamespace> replaceSetting(
    String ns,
    String sectionJson, {
    int? expectedRevision,
  }) async {
    final decoded = jsonDecode(sectionJson);
    if (decoded is! Map) {
      throw ArgumentError('settings.replace section must be a JSON object');
    }
    final value = await _call(_settingsReplace, _settingsReplace, {
      'ns': ns,
      'section': decoded,
      if (expectedRevision != null) 'expectedRevision': expectedRevision,
    }).valueOrThrow();
    return _toDomainSettingsNamespace(SettingsNamespaceWire.fromJson(value));
  }

  @override
  Future<SettingsNamespace> mutateSetting(
    String ns,
    List<SettingPathOp> ops, {
    int? expectedRevision,
  }) async {
    final value = await _call(_settingsMutate, _settingsMutate, {
      'ns': ns,
      'ops': ops
          .map(
            (op) => <String, Object?>{
              'op': op.op,
              'path': op.path,
              if (op.jsonValue != null) 'value': _parseJsonValue(op.jsonValue!),
            },
          )
          .toList(),
      if (expectedRevision != null) 'expectedRevision': expectedRevision,
    }).valueOrThrow();
    return _toDomainSettingsNamespace(SettingsNamespaceWire.fromJson(value));
  }

  @override
  Future<void> openSession(String sessionId) async {
    final state = _sessionStateFor(sessionId);
    // Looking at the session consumes its completion reminder (dot clears)
    // and makes it the armed-selection for future running finishes.
    _openSessionId = sessionId;
    if (_prevRunningBySession[sessionId] == false ||
        _prevRunningBySession[sessionId] == null) {
      _setSessionCompleted(sessionId, false);
    }
    try {
      await state.ensureLoaded(
        (beforeSeq) => _loadHistory(sessionId, beforeSeq),
      );
    } catch (_) {
      // A failed first load stays pending; the next generation retries it.
    }
  }

  /// Rewrites one session's row with [completed], re-emitting the raw
  /// session list so `observeSessions` publishes the updated fact.
  void _setSessionCompleted(String sessionId, bool completed) {
    _sessions.value = _sessions.value
        .map((item) => item.id == sessionId
            ? _copySession(item, completed: completed)
            : item)
        .toList();
  }

  /// The session's current completed bit (the row the list holds).
  bool _isCompleted(String sessionId) {
    for (final item in _sessions.value) {
      if (item.id == sessionId) return item.completed;
    }
    return false;
  }

  @override
  Stream<List<TimelineItem>> observeTimeline(String sessionId) =>
      _sessionStateFor(sessionId).timeline.stream;

  @override
  Stream<Set<String>> observeArchivedSessionIds() => _archivedSessionIds.stream;

  @override
  Stream<TimelineWindow> observeTimelineWindow(String sessionId) =>
      _sessionStateFor(sessionId).window.stream;

  @override
  Future<bool> loadOlderHistory(String sessionId) async {
    final state = _sessionStates[sessionId];
    if (state == null) return false;
    return state.loadOlder((beforeSeq) => _loadHistory(sessionId, beforeSeq));
  }

  @override
  Future<void> sendMessage(SendMessageRequest request) async {
    final content = <Object?>[
      <String, Object?>{'type': 'text', 'text': request.text},
      for (final image in request.images)
        <String, Object?>{
          'type': 'image',
          'mediaType': image.mediaType,
          'data': image.base64Data,
          if (image.name != null) 'name': image.name,
        },
    ];
    final value = await _call(_sessionPrompt, _sessionPrompt, {
      'sessionId': request.sessionId,
      'mode': request.mode == PromptMode.queue ? 'queue' : 'steer',
      'content': content,
    }).valueOrThrow();
    if (wireBool(value, 'accepted') || !value.containsKey('accepted')) {
      // Web parity: a successful first prompt proves the user message is in
      // the host log, so the provisional blank session is retired without
      // waiting for the next list pull.
      _markSessionNoLongerBlank(request.sessionId);
    }
  }

  /// Retry budget for a detached command whose first dispatch died on the
  /// socket. The host aborts a command the moment its HTTP request ends, so
  /// an in-flight transport drop never settles a result — the retry is a
  /// clean re-run on a fresh connection, never a duplicate.
  static const int _commandMaxAttempts = 2;

  /// Pause before re-dispatching so the torn-down socket fully drains on
  /// both ends before the fresh connection is established.
  static const Duration _commandRetryBackoff = Duration(seconds: 1);

  /// Whether [error] is a mid-flight transport drop: a
  /// [DshTransportException] whose cause is a socket failure. package:http
  /// surfaces its own socket wraps through the same `SocketException` type,
  /// and `dart:io` raises the raw one; an HTTP-status or envelope-level
  /// failure (cause null) is a completed exchange and is never retried.
  static bool _isTransportDrop(Object error) =>
      error is DshTransportException && error.cause is SocketException;

  @override
  Future<CommandExecution?> executeCommand(
    String sessionId,
    String line,
    List<PendingImage> images, {
    bool retryOnTransportAbort = false,
  }) async {
    for (var attempt = 1; ; attempt++) {
      try {
        return await _executeCommandOnce(sessionId, line, images);
      } catch (error) {
        if (attempt >= _commandMaxAttempts ||
            !retryOnTransportAbort ||
            !_isTransportDrop(error)) {
          rethrow;
        }
        await Future<void>.delayed(_commandRetryBackoff);
      }
    }
  }

  Future<CommandExecution?> _executeCommandOnce(
    String sessionId,
    String line,
    List<PendingImage> images,
  ) async {
    // The typert remote envelope: the args carry the addressed agent (a
    // session id — sessions are agent-backed), the complete line, and
    // the base64-encoded composer images in submission order (the host
    // admission enforces the command's image-acceptance flag).
    final result = await _call(_commandsExecute, _commandsExecute, {
      'args': <String, Object?>{
        'agentId': sessionId,
        'line': line,
        'images': <Object?>[
          for (final image in images)
            <String, Object?>{
              'mediaType': image.mediaType,
              'data': image.base64Data,
              if (image.name != null) 'name': image.name,
            },
        ],
      },
    });
    if (!result.ok) {
      final failure = result.error;
      throw DshBusinessException(
        code: failure?.code ?? 'internal',
        message: failure?.message ?? 'unknown dsh error',
      );
    }
    // The unmatched case serializes as ok with no value slot (reference
    // CommandRuntime.execute returns undefined on a syntax or name miss).
    final value = result.value;
    if (value == null) return null;
    final wire = CommandExecutionWire.fromJson(value);
    final kind = switch (wire.result.kind) {
      'success' => CommandOutcomeKind.success,
      'error' => CommandOutcomeKind.error,
      _ => throw FormatException(
        'commands/execute: unknown result kind "${wire.result.kind}"',
      ),
    };
    return CommandExecution(
      commandId: wire.commandId,
      kind: kind,
      text: wire.result.text,
    );
  }

  @override
  Future<void> cancelTurn(String sessionId) async {
    await _call(_sessionCancel, _sessionCancel, {
      'sessionId': sessionId,
    }).valueOrThrow();
  }

  @override
  Future<AttachmentData> readAttachment(
    String sessionId,
    String attachmentId,
  ) async {
    final value = await _call(_sessionAttachment, _sessionAttachment, {
      'sessionId': sessionId,
      'attachmentId': attachmentId,
    }).valueOrThrow();
    final downloaded = SessionAttachmentValueWire.fromJson(value);
    return AttachmentData(
      ref: AttachmentRef(
        attachmentId: downloaded.attachment.attachmentId,
        mediaType: downloaded.attachment.mediaType,
        bytes: downloaded.attachment.bytes,
        width: downloaded.attachment.width,
        height: downloaded.attachment.height,
        name: downloaded.attachment.name,
      ),
      data: Uint8List.fromList(base64Decode(downloaded.data)),
    );
  }

  @override
  Stream<ImageLimits?> observeImageLimits() => _imageLimits.stream;

  @override
  Future<List<SkillEntry>> listSkills(String sessionId) async {
    final value = await _call(_skillList, _skillList, {
      'sessionId': sessionId,
    }).valueOrThrow();
    return decodeSkillListValue(value)
        .map(
          (wire) => SkillEntry(
            name: wire.name,
            description: wire.description,
            whenToUse: wire.whenToUse,
            modelInvocable: wire.modelInvocable,
          ),
        )
        .toList();
  }

  @override
  Future<void> respondToApproval(ApprovalAnswer answer) async {
    final value = <String, Object?>{
      'sessionId': answer.sessionId,
      'approvalId': answer.approvalId,
      'outcome': answer.allowed ? 'allowed-once' : 'rejected',
    };
    await _rpcClient.respond(
      answer.requestId,
      RpcResult(ok: true, value: value),
    );
  }

  @override
  Future<void> answerQuestions(
    String requestId,
    QuestionEvidence evidence,
  ) async {
    final value = <String, Object?>{
      'sessionId': evidence.sessionId,
      'answer': {
        'answers': evidence.answers
            .map(
              (answer) => <String, Object?>{
                'id': answer.questionId,
                'selected': answer.selectedOptions,
                if (answer.customText != null) 'custom': answer.customText,
              },
            )
            .toList(),
      },
    };
    await _rpcClient.respond(requestId, RpcResult(ok: true, value: value));
  }

  @override
  Future<void> cancelQuestions(String requestId, String sessionId) async {
    await _rpcClient.respond(
      requestId,
      RpcResult(
        ok: false,
        value: <String, Object?>{'sessionId': sessionId},
        error: RpcError(
          code: 'cancelled',
          message: 'the user closed this question request',
          details: <String, Object?>{},
        ),
      ),
    );
  }

  @override
  Future<String> renameSession(String sessionId, String title) async {
    final result = await _call(_sessionRename, _sessionRename, {
      'sessionId': sessionId,
      'title': title,
    }).valueOrThrow();
    final renamed = wireString(result, 'title');
    if (renamed == null) {
      throw const FormatException('session.rename missing title');
    }
    _sessions.value = await _loadSessions();
    return renamed;
  }

  @override
  Future<SessionSummary> forkSession(String sessionId, {int? atSeq}) async {
    final result = await _call(_sessionFork, _sessionFork, {
      'sessionId': sessionId,
      if (atSeq != null) 'atSeq': atSeq,
    }).valueOrThrow();
    final forked = wireString(result, 'sessionId');
    if (forked == null) {
      throw const FormatException('session.fork missing sessionId');
    }
    _sessions.value = await _loadSessions();
    return SessionSummary(id: forked, blank: false);
  }

  @override
  Future<void> updateQueue(QueueUpdateRequest request) async {
    final Object action;
    switch (request.kind) {
      case QueueUpdateKind.remove:
        action = <String, Object?>{'kind': 'remove'};
      case QueueUpdateKind.steer:
        action = <String, Object?>{'kind': 'steer'};
      case QueueUpdateKind.edit:
        action = <String, Object?>{
          'kind': 'edit',
          'content': <Object?>[
            <String, Object?>{'type': 'text', 'text': request.text ?? ''},
          ],
        };
    }
    try {
      await _call(_sessionUpdateQueue, _sessionUpdateQueue, {
        'sessionId': request.sessionId,
        'itemId': request.itemId,
        'action': action,
      }).valueOrThrow();
    } on DshBusinessException catch (error) {
      // Web parity (input hub): a turn closing mid-steer or a row already
      // settled is a benign race — the queue projection refreshes the dock,
      // so the failure never reaches the error surface.
      if (error.code == 'steer-unavailable' ||
          error.code == 'queue-item-not-found') {
        return;
      }
      rethrow;
    }
  }

  @override
  Future<SubagentCatalog> loadSubagents(String parentSessionId) async {
    final value = await _call(_subagentList, _subagentList, {
      'parentSessionId': parentSessionId,
    }).valueOrThrow();
    final wire = SubagentListValueWire.fromJson(value);
    return SubagentCatalog(
      parentSessionId: parentSessionId,
      entries: wire.entries
          .map(
            (entry) => SubagentEntry(
              id: entry.id,
              kind: entry.kind,
              mode: entry.mode,
              activity: entry.activity,
              hasChildren: entry.hasChildren,
              label: entry.label,
              reason: entry.reason,
            ),
          )
          .toList(),
      parentAvailable: wire.parentAvailable,
    );
  }

  @override
  Future<void> interruptSubagent(
    String parentSessionId,
    String childSessionId,
  ) async {
    await _call(_subagentInterrupt, _subagentInterrupt, {
      'parentSessionId': parentSessionId,
      'childSessionId': childSessionId,
      'mode': 'continuable',
    }).valueOrThrow();
  }

  @override
  Future<List<TimelineItem>> loadSubagentHistory(
    String parentSessionId,
    String childSessionId,
  ) async {
    final value = await _call(_subagentHistory, _subagentHistory, {
      'parentSessionId': parentSessionId,
      'childSessionId': childSessionId,
      'mode': 'continuable',
    }).valueOrThrow();
    final history = SessionHistoryValueWire.fromJson(value);
    final reducer = TimelineReducer(childSessionId);
    reducer.reset(history.events);
    return reducer.snapshot();
  }

  @override
  Future<String> sendSubagentPrompt(
    String parentSessionId,
    String childSessionId,
    String text,
  ) async {
    final value = await _call(_subagentPrompt, _subagentPrompt, {
      'parentSessionId': parentSessionId,
      'childSessionId': childSessionId,
      'mode': 'continuable',
      'content': <Object?>[
        <String, Object?>{'type': 'text', 'text': text},
      ],
    }).valueOrThrow();
    final messageId = wireString(value, 'messageId');
    if (messageId == null) {
      throw const FormatException('subagent.prompt missing messageId');
    }
    return messageId;
  }

  @override
  Stream<GoalProjection?> observeGoal(String sessionId) =>
      _goalProjectionStateFor(sessionId).stream;

  @override
  Stream<PlanState?> observePlan(String sessionId) =>
      _planProjectionStateFor(sessionId).stream;

  @override
  Stream<List<TodoItem>?> observeTodos(String sessionId) =>
      _todoProjectionStateFor(sessionId).stream;

  @override
  Stream<ContextPressure?> observeContextPressure(String sessionId) =>
      _sessionStateFor(sessionId).contextPressure.stream;

  @override
  Stream<ContextBreakdown?> observeContextBreakdown(String sessionId) =>
      _sessionStateFor(sessionId).contextBreakdown.stream;

  @override
  Stream<PermissionSelect?> observePermissions(String sessionId) =>
      _permissionProjectionStateFor(sessionId).stream;

  @override
  Stream<SessionWindowStats> observeSessionStats(String sessionId) =>
      _sessionStateFor(sessionId).sessionStats.stream;

  @override
  Future<GoalRef> createGoal(
    String sessionId,
    String objective, {
    int? maxGoalRounds,
  }) async {
    final value = await _call(_goalCreate, _goalCreate, {
      'sessionId': sessionId,
      'objective': objective,
      if (maxGoalRounds != null) 'maxGoalRounds': maxGoalRounds,
    }).valueOrThrow();
    final ref = decodeGoalRefValue(value);
    return GoalRef(id: ref.id, revision: ref.revision);
  }

  @override
  Future<GoalRef> editGoal(String sessionId, GoalRef ref, String objective) =>
      _goalMutation(_goalEdit, sessionId, ref, objective);

  @override
  Future<GoalRef> pauseGoal(String sessionId, GoalRef ref) =>
      _goalMutation(_goalPause, sessionId, ref);

  @override
  Future<GoalRef> resumeGoal(String sessionId, GoalRef ref) =>
      _goalMutation(_goalResume, sessionId, ref);

  @override
  Future<GoalRef> completeGoal(String sessionId, GoalRef ref) =>
      _goalMutation(_goalComplete, sessionId, ref);

  @override
  Future<void> clearGoal(String sessionId, GoalRef ref) async {
    await _call(
      _goalClear,
      _goalClear,
      _goalPayload(sessionId, ref),
    ).valueOrThrow();
    _goalProjections[sessionId]?.value = null;
  }

  Future<GoalRef> _goalMutation(
    String endpoint,
    String sessionId,
    GoalRef ref, [
    String? objective,
  ]) async {
    final value = await _call(
      endpoint,
      endpoint,
      _goalPayload(sessionId, ref, objective),
    ).valueOrThrow();
    final decoded = decodeGoalRefValue(value);
    return GoalRef(id: decoded.id, revision: decoded.revision);
  }

  JsonMap _goalPayload(String sessionId, GoalRef ref, [String? objective]) => {
    'sessionId': sessionId,
    'ref': <String, Object?>{'id': ref.id, 'revision': ref.revision},
    if (objective != null) 'objective': objective,
  };

  @override
  Stream<List<WorkspaceSummary>> observeWorkspaces() => _workspaces.stream;

  @override
  Future<void> refreshWorkspaces() async {
    _applyWorkspaceListing(await _loadWorkspaceListing());
  }

  Future<WorkspaceListValueWire> _loadWorkspaceListing() async {
    final result = await _call(
      _workspaceList,
      _workspaceList,
      <String, Object?>{},
    ).valueOrThrow();
    return WorkspaceListValueWire.fromJson(result);
  }

  void _applyWorkspaceListing(WorkspaceListValueWire listing) {
    _workspaces.value = listing.items.map(_toDomainWorkspace).toList();
    _archivedSessionIds.value = listing.archivedSessionIds.toSet();
  }

  @override
  Future<WorkspaceSummary> createWorkspace(String path) async {
    final result = await _call(_workspaceCreate, _workspaceCreate, {
      'path': path,
    }).valueOrThrow();
    final created = _toDomainWorkspace(_workspaceFromJson(result, 'workspace'));
    _applyWorkspaceListing(await _loadWorkspaceListing());
    return created;
  }

  @override
  Future<WorkspaceSummary> renameWorkspace(
    String workspaceId,
    String title,
  ) async {
    final result = await _call(_workspaceRename, _workspaceRename, {
      'workspaceId': workspaceId,
      'title': title,
    }).valueOrThrow();
    final renamed = _toDomainWorkspace(_workspaceFromJson(result, 'workspace'));
    _applyWorkspaceListing(await _loadWorkspaceListing());
    return renamed;
  }

  @override
  Future<void> archiveSession(String sessionId) async {
    final result = await _call(
      _workspaceArchiveSession,
      _workspaceArchiveSession,
      {'sessionId': sessionId},
    ).valueOrThrow();
    _archivedSessionIds.value = _stringSet(result['archivedSessionIds']);
  }

  @override
  Future<void> deleteWorkspace(String workspaceId) async {
    await _call(_workspaceDelete, _workspaceDelete, {
      'workspaceId': workspaceId,
    }).valueOrThrow();
    _applyWorkspaceListing(await _loadWorkspaceListing());
  }

  @override
  Future<List<String>> moveWorkspace(
    String workspaceId,
    String? beforeWorkspaceId,
  ) async {
    final value = await _call(_workspaceInsertBefore, _workspaceInsertBefore, {
      'workspaceId': workspaceId,
      if (beforeWorkspaceId != null) 'beforeWorkspaceId': beforeWorkspaceId,
    }).valueOrThrow();
    final orderedIds = _stringList(value['workspaceIds']);
    _applyWorkspaceOrder(orderedIds);
    return orderedIds;
  }

  @override
  Future<WorkspaceSummary> moveSession(
    String workspaceId,
    String sessionId,
    String? beforeSessionId,
  ) async {
    final value = await _call(
      _workspaceInsertSessionBefore,
      _workspaceInsertSessionBefore,
      {
        'workspaceId': workspaceId,
        'sessionId': sessionId,
        if (beforeSessionId != null) 'beforeSessionId': beforeSessionId,
      },
    ).valueOrThrow();
    final updated = _toDomainWorkspace(_workspaceFromJson(value, 'workspace'));
    _workspaces.value = _workspaces.value
        .map((item) => item.workspaceId == workspaceId ? updated : item)
        .toList();
    return updated;
  }

  @override
  Future<SessionModels> loadModels(String sessionId) async {
    final result = await _call(_sessionModels, _sessionModels, {
      'sessionId': sessionId,
    }).valueOrThrow();
    return _toDomainSessionModels(SessionModelsValueWire.fromJson(result));
  }

  @override
  Future<ModelSelection> selectModel(
    String sessionId,
    ModelSelection selection,
  ) async {
    final result = await _call(_sessionSelectModel, _sessionSelectModel, {
      'sessionId': sessionId,
      'provider': selection.provider,
      'model': selection.model,
      if (selection.reasoningEffort != null)
        'reasoningEffort': selection.reasoningEffort,
    }).valueOrThrow();
    final selectedObj = asJsonObject(result['selected']);
    if (selectedObj == null) {
      throw const FormatException('session.selectModel missing selected');
    }
    final selected = ModelSelectionWire.fromJson(selectedObj);
    return ModelSelection(
      provider: selected.provider,
      model: selected.model,
      reasoningEffort: selected.reasoningEffort,
    );
  }

  @override
  Future<List<SessionSearchResult>> searchSessions(String query) async {
    final result = await _call(_sessionSearch, _sessionSearch, {
      'query': query,
    }).valueOrThrow();
    return (asJsonArray(result['items']) ?? const <Object?>[])
        .map(asJsonObject)
        .whereType<JsonMap>()
        .map(
          (item) => SessionSearchResult(
            sessionId: wireString(item, 'sessionId') ?? '',
            snippet: wireString(item, 'snippet') ?? '',
          ),
        )
        .toList();
  }

  // -----------------------------------------------------------------------
  // Frame collection
  // -----------------------------------------------------------------------

  void _collectConnection() {
    _subs.add(
      _connectionManager.state.stream.listen((connection) {
        if (connection.phase == ConnectionPhase.connected &&
            connection.generation != _connectionGeneration.value) {
          _connectionGeneration.value = connection.generation;
          unawaited(_resync(connection));
        }
      }),
    );
  }

  void _collectMuxFrames() {
    _subs.add(
      _connectionManager.muxFrames.listen((frame) {
        final type = wireString(frame.payload, 'type');
        if (type == 'session/projection') {
          _handleProjection(frame);
          return;
        }
        // Registry-global pending-interaction fold: tracked for every
        // session, instantiated or not, before the per-session fan-out
        // (web SessionManager parity — the sidebar's amber dot and
        // approval/plan-review alerts must fire for sessions never opened
        // here). Stable keys make replays
        // idempotent.
        _foldPendingFrame(frame);
        final sessionId = _frameSessionId(frame);
        if (sessionId == null) return;
        final state = _sessionStates[sessionId];
        if (state == null) {
          // Web SessionManager parity: answerable live frames (approval/
          // question requested, queue) that reach an uninstantiated session
          // are buffered, not dropped — a later open replays them, so the
          // question/approval card still renders even though the transcript
          // backfill only carries the running tool call.
          _bufferPendingFrame(sessionId, frame);
          return;
        }
        unawaited(state.handleFrame(frame));
      }),
    );
  }

  /// Web SessionManager list-level pending fold: `approval/requested`
  /// tracks `a:<approvalId>`, `question/requested` tracks `q:<rpcId>`
  /// with the plan-review/question classification, and the matching
  /// `* /resolved` frames drop the key. Replays are idempotent by key.
  void _foldPendingFrame(ServerRequest envelope) {
    final frame = envelope.payload;
    switch (wireString(frame, 'type')) {
      case 'approval/requested':
        final sessionId = wireString(frame, 'sessionId');
        final approvalId = wireString(frame, 'approvalId');
        if (sessionId == null || approvalId == null) return;
        _trackPending(
          sessionId,
          'a:$approvalId',
          SessionPendingInteraction.approval,
        );
      case 'approval/resolved':
        final sessionId = wireString(frame, 'sessionId');
        final approvalId = wireString(frame, 'approvalId');
        if (sessionId == null || approvalId == null) return;
        _dropPending(sessionId, 'a:$approvalId');
      case 'question/requested':
        final sessionId = wireString(frame, 'sessionId');
        if (sessionId == null) return;
        _trackPending(
          sessionId,
          'q:${envelope.rpcId}',
          _questionInteractionStatus(asJsonArray(frame['questions'])),
        );
      case 'question/resolved':
        final sessionId = wireString(frame, 'sessionId');
        final questionRpcId = wireString(frame, 'questionRpcId');
        if (sessionId == null || questionRpcId == null) return;
        _dropPending(sessionId, 'q:$questionRpcId');
    }
  }

  /// Web SessionManager `questionInteractionStatus`: a single binary
  /// plan-review intent routes to `plan-review`, everything else is a
  /// plain `question`.
  SessionPendingInteraction _questionInteractionStatus(
    List<Object?>? questionArray,
  ) {
    if (questionArray == null || questionArray.length != 1) {
      return SessionPendingInteraction.question;
    }
    final question = asJsonObject(questionArray[0]);
    if (question == null) return SessionPendingInteraction.question;
    final intent = asJsonObject(question['intent']);
    final kind = intent == null ? null : wireString(intent, 'kind');
    if (kind != 'plan-review' ||
        wireString(question, 'detail') == null ||
        wireBool(question, 'multiSelect') == true) {
      return SessionPendingInteraction.question;
    }
    final options = asJsonArray(question['options']) ?? const <Object?>[];
    if (options.length > 2) return SessionPendingInteraction.question;
    final approve = intent == null ? null : wireString(intent, 'approve');
    for (final option in options) {
      final optionObj = asJsonObject(option);
      if (optionObj == null) continue;
      if (wireString(optionObj, 'label') == approve) {
        return SessionPendingInteraction.planReview;
      }
    }
    return SessionPendingInteraction.question;
  }

  void _trackPending(
    String sessionId,
    String key,
    SessionPendingInteraction status,
  ) {
    final keys = _pendingBySession.putIfAbsent(
      sessionId,
      () => <String, SessionPendingInteraction>{},
    );
    if (keys[key] == status) return;
    keys[key] = status;
    _publishPending();
  }

  void _dropPending(String sessionId, String key) {
    final keys = _pendingBySession[sessionId];
    if (keys == null || keys.remove(key) == null) return;
    if (keys.isEmpty) _pendingBySession.remove(sessionId);
    _publishPending();
  }

  /// Re-derives the per-session last-status projection from the key map
  /// and publishes it (list rows read the per-session status).
  void _publishPending() {
    _pendingInteractions.value = _projectPending();
  }

  SessionSummary _withPending(
    SessionSummary session,
    SessionPendingInteraction? pending,
  ) => SessionSummary(
    id: session.id,
    title: session.title,
    running: session.running,
    blank: session.blank,
    updatedAtEpochMs: session.updatedAtEpochMs,
    cwd: session.cwd,
    agentPreset: session.agentPreset,
    origin: session.origin,
    pendingInteraction: pending ?? session.pendingInteraction,
    completed: session.completed,
  );

  void _handleProjection(ServerRequest frame) {
    final sessionId = _frameSessionId(frame);
    if (sessionId == null) return;
    switch (wireString(frame.payload, 'key')) {
      case 'title':
        final title = wireString(frame.payload, 'value');
        if (title != null && title != 'null') {
          _sessions.value = _sessions.value
              .map(
                (item) => item.id == sessionId
                    ? _copySession(item, title: title)
                    : item,
              )
              .toList();
        } else {
          _sessions.value = _sessions.value
              .map(
                (item) => item.id == sessionId
                    ? _copySession(item, title: null)
                    : item,
              )
              .toList();
        }
      case 'goal':
        final value = frame.payload['value'];
        GoalProjection? projection;
        if (value != null && value != 'null') {
          projection = _tryDecode(() {
            final obj = asJsonObject(value);
            if (obj == null) throw const FormatException('not an object');
            return _toDomainGoalProjection(GoalProjectionWire.fromJson(obj));
          });
        }
        _goalProjectionStateFor(sessionId).value = projection;
      case 'plan':
        final value = frame.payload['value'];
        PlanState? projection;
        if (value != null && value != 'null') {
          projection = _tryDecode(() {
            final decoded = decodePlanProjection(value);
            if (decoded == null) throw const FormatException('not an object');
            return PlanState(active: decoded.active, pending: decoded.pending);
          });
        }
        _planProjectionStateFor(sessionId).value = projection;
      case 'todos':
        _todoProjectionStateFor(sessionId).value = _parseTodosProjection(
          frame.payload['value'],
        );
      case 'permissions':
        // The value is the interaction/permission-presets select; a
        // malformed frame decodes to null — the composer chip hides,
        // the same posture as a host that composes no permission
        // service.
        final value = frame.payload['value'];
        PermissionSelect? select;
        if (value != null && value != 'null') {
          select = _tryDecode(() {
            final obj = asJsonObject(value);
            if (obj == null) {
              throw const FormatException('permissions: not an object');
            }
            return _toDomainPermissionSelect(
              PermissionSelectWire.fromJson(obj),
            );
          });
        }
        _permissionProjectionStateFor(sessionId).value = select;
    }
  }

  /// Wire `permissions` projection payload
  /// (interaction/permission-presets types.ts): the option table plus the
  /// effective current value.
  PermissionSelect _toDomainPermissionSelect(PermissionSelectWire wire) {
    if (wire.currentValue.isEmpty) {
      throw const FormatException('permissions: currentValue is empty');
    }
    return PermissionSelect(
      options: wire.options
          .map(
            (option) => PermissionPresetOption(
              value: option.value,
              name: option.name,
              description: option.description,
            ),
          )
          .toList(),
      currentValue: wire.currentValue,
    );
  }

  /// Wire roster row (`agent-presets.schema.ts` AgentPresetEntry): trust
  /// maps onto the domain enum and any other value fails loud.
  AgentPresetEntry _toDomainAgentPresetEntry(AgentPresetEntryWire wire) {
    final trust = switch (wire.trust) {
      'system' => AgentPresetTrust.system,
      'user' => AgentPresetTrust.user,
      _ => throw FormatException('agentPreset.list: bad trust ${wire.trust}'),
    };
    return AgentPresetEntry(
      id: wire.id,
      trust: trust,
      isDefault: wire.isDefault,
      name: wire.name,
      description: wire.description,
      broken: wire.broken,
    );
  }

  /// Wire `todos` projection payload: the whole list, or null before the
  /// first write / after a later turn begins.
  List<TodoItem>? _parseTodosProjection(Object? value) {
    if (value == null || value == 'null') return null;
    return _tryDecode(() {
      final list = asJsonArray(value);
      if (list == null) throw const FormatException('todos: not an array');
      return <TodoItem>[
        for (final raw in list)
          () {
            final obj = asJsonObject(raw);
            if (obj == null) throw const FormatException('todos: bad item');
            final content = wireString(obj, 'content');
            final status = wireString(obj, 'status');
            if (content == null || status == null) {
              throw const FormatException('todos: missing content/status');
            }
            return TodoItem(
              content: content,
              status: todoStatusFromWire(status),
            );
          }(),
      ];
    });
  }

  void _collectHostFrames() {
    _subs.add(
      _connectionManager.hostFrames.listen((frame) {
        final type = wireString(frame.payload, 'type');
        if (type == null) return;
        final sessionId = wireString(frame.payload, 'sessionId');
        switch (type) {
          case 'host/session-status':
            if (sessionId == null) return;
            final running =
                frame.payload['running'] == 'true' ||
                frame.payload['running'] == true;
            // Finished-but-unviewed fold (web SessionManager
            // `syncCompletedNotifications`): the true→false edge while the
            // session is not the one being viewed arms the green dot;
            // running again clears it. The first observation of a session
            // seeds prev-running without arming anything.
            final wasRunning = _prevRunningBySession[sessionId];
            _prevRunningBySession[sessionId] = running;
            if (running) {
              // Running again clears the completion reminder; a first
              // sight of a running session arms nothing.
              if (_isCompleted(sessionId)) {
                _setSessionCompleted(sessionId, false);
              }
            } else if (wasRunning == true) {
              _setSessionCompleted(sessionId, sessionId != _openSessionId);
            }
            _sessions.value = _sessions.value.map((item) {
              if (item.id != sessionId) return item;
              // Web parity: a blank session never runs; the first running:true
              // is the cross-client flip that clears the placeholder locally.
              return _copySession(
                item,
                running: running,
                blank: item.blank && !running,
              );
            }).toList();
          case 'host/session-added':
          case 'host/session-removed':
            unawaited(refreshSessions().catchError((_) {}));
          case 'host/workspace-changed':
            _applyWorkspaceChanged(frame);
          case 'host/workspace-removed':
            _applyWorkspaceRemoved(frame);
          case 'host/workspace-order-changed':
            _applyWorkspaceOrderFrame(frame);
          case 'host/archived-sessions-changed':
            final archived = _stringSet(frame.payload['archivedSessionIds']);
            _archivedSessionIds.value = archived;
          case 'host/remote-event':
            _applyRemoteEvent(frame);
        }
      }),
    );
  }

  /// One allowlisted host cordis event forwarded verbatim
  /// (`host/remote-event`, events.ts: `event` + `args`). Only events this
  /// client folds are read; the rest are ignored silently — the forwarded
  /// set is open and owned by the host's allowlist.
  void _applyRemoteEvent(ServerRequest frame) {
    final event = wireString(frame.payload, 'event');
    if (event != 'agent-preset/selected') return;
    final args = asJsonArray(frame.payload['args']) ?? const <Object?>[];
    if (args.length < 2) return;
    final sessionId = args[0];
    final agentPreset = args[1];
    if (sessionId is! String || agentPreset is! String) return;
    _sessions.value = _sessions.value
        .map(
          (item) => item.id == sessionId
              ? _copySession(item, agentPreset: agentPreset)
              : item,
        )
        .toList();
  }

  /// Full-snapshot increment carried by `host/workspace-changed`: upsert one
  /// workspace without an extra `workspace.list` round-trip.
  void _applyWorkspaceChanged(ServerRequest frame) {
    final element = frame.payload['workspace'];
    if (element == null) return;
    final wire = _tryDecode(
      () => WorkspaceWire.fromJson(
        asJsonObject(element) ?? const <String, Object?>{},
      ),
    );
    if (wire == null) return;
    final workspace = _toDomainWorkspace(wire);
    final current = _workspaces.value;
    final index = current.indexWhere(
      (item) => item.workspaceId == workspace.workspaceId,
    );
    if (index < 0) {
      _workspaces.value = List.of(current)..add(workspace);
    } else {
      _workspaces.value = List.of(current)..[index] = workspace;
    }
  }

  void _applyWorkspaceRemoved(ServerRequest frame) {
    final workspaceId = wireString(frame.payload, 'workspaceId');
    if (workspaceId == null) return;
    _workspaces.value = _workspaces.value
        .where((item) => item.workspaceId != workspaceId)
        .toList();
  }

  /// `host/workspace-order-changed` carries the full durable registry
  /// order. Unknown workspaces append behind known ones rather than
  /// disappearing.
  void _applyWorkspaceOrderFrame(ServerRequest frame) {
    final orderedIds = _stringList(frame.payload['workspaceIds']);
    if (orderedIds.isEmpty) return;
    _applyWorkspaceOrder(orderedIds);
  }

  /// The response order is authoritative; unknown rows keep relative order
  /// at the end.
  void _applyWorkspaceOrder(List<String> orderedIds) {
    final current = _workspaces.value;
    _workspaces.value = stableSortedBy(current, (workspace) {
      final orderedIndex = orderedIds.indexOf(workspace.workspaceId);
      return orderedIndex >= 0
          ? orderedIndex
          : orderedIds.length + current.indexOf(workspace);
    });
  }

  Future<void> _resync(ConnectionState connection) async {
    await _resyncMutex.synchronized(() async {
      for (final state in _sessionStates.values) {
        state.prepareResync();
      }
      // New connection generation: the reopen replay re-adds still-pending
      // approval/question frames, so the old mirror is dropped first (web
      // SessionManager parity).
      _pendingBySession.clear();
      _pendingInteractions.value = const <String, SessionPendingInteraction>{};
      // Same re-baseline for the frame buffer: the new generation replays a
      // fresh queue snapshot, so a stale buffered `session/queue` must not
      // survive (web `session/subscribed` truncates it there). Pending
      // approval/question frames are re-pushed by the mux-open replay and
      // re-buffered by `_bufferPendingFrame`.
      for (final entry in _pendingBuffers.entries.toList()) {
        final kept = entry.value
            .where((frame) => wireString(frame.payload, 'type') != 'session/queue')
            .toList();
        if (kept.isEmpty) {
          _pendingBuffers.remove(entry.key);
        } else {
          _pendingBuffers[entry.key] = kept;
        }
      }
      try {
        await refreshSessions();
        await refreshWorkspaces();
      } catch (_) {
        // List failure does not block timeline recovery.
      }
      for (final state in _sessionStates.values) {
        try {
          await state.ensureLoaded(
            (beforeSeq) => _loadHistory(state.sessionId, beforeSeq),
          );
        } catch (_) {
          // Pending state retries on the next generation.
        }
      }
    });
  }

  // -----------------------------------------------------------------------
  // Wire helpers
  // -----------------------------------------------------------------------

  Future<RpcResult> _call(String endpoint, String method, JsonMap payload) {
    return _rpcClient.call(endpoint, method, payload);
  }

  Future<List<SessionSummary>> _loadSessions() async {
    final value = await _call(
      _sessionList,
      _sessionList,
      <String, Object?>{},
    ).valueOrThrow();
    final listing = decodeSessionListValue(value);
    for (final session in listing) {
      final parsed = _imageLimitsFromProjections(session);
      if (parsed != null && _imageLimits.value != parsed) {
        _imageLimits.value = parsed;
        break;
      }
    }
    // A session dropped from the list cannot wait on the user anymore
    // (web manager removes pending on session-removed); its prev-running
    // edge and completion reminder die with it.
    final liveIds = <String>{for (final session in listing) session.sessionId};
    var pendingChanged = false;
    for (final sessionId in _pendingBySession.keys.toList()) {
      if (!liveIds.contains(sessionId)) {
        _pendingBySession.remove(sessionId);
        pendingChanged = true;
      }
    }
    _prevRunningBySession.removeWhere((sessionId, _) => !liveIds.contains(sessionId));
    if (pendingChanged) {
      _pendingInteractions.value = _projectPending();
    }
    // A list refresh rebuilds from the wire summaries, which carry no
    // completion fact — preserve the folded bit for sessions that still
    // hold it (web SessionManager keeps completedNotifications across
    // list pulls).
    final completedById = <String, bool>{
      for (final item in _sessions.value)
        if (item.completed) item.id: true,
    };
    final result = listing.map((wire) {
      final session = _toDomainSession(wire);
      final completed = completedById[session.id] ?? false;
      return completed ? _copySession(session, completed: true) : session;
    }).toList();
    return result;
  }

  /// Re-derives the per-session last-status projection from the key map.
  Map<String, SessionPendingInteraction> _projectPending() {
    final next = <String, SessionPendingInteraction>{};
    for (final entry in _pendingBySession.entries) {
      if (entry.value.isEmpty) continue;
      next[entry.key] = entry.value.values.last;
    }
    return next;
  }

  SessionSummary _toDomainSession(SessionWire wire) => SessionSummary(
    id: wire.sessionId,
    title: wireString(
      wire.projectionValues ?? const <String, Object?>{},
      'title',
    ),
    running: wire.running,
    blank: wire.blank,
    updatedAtEpochMs: wire.updatedAt,
    cwd: wire.cwd,
    agentPreset: wire.agentPreset,
    origin: wire.origin,
  );

  /// `imageLimits` is a host-config projection; one value serves all
  /// sessions.
  ImageLimits? _imageLimitsFromProjections(SessionWire wire) {
    final value = wire.projectionValues?['imageLimits'];
    if (value == null) return null;
    return _tryDecode(
      () => decodeImageLimitsWire(
        asJsonObject(value) ?? const <String, Object?>{},
      ),
    );
  }

  Future<_HistoryPage> _loadHistory(String sessionId, [int? beforeSeq]) async {
    final value = await _call(_sessionHistory, _sessionHistory, {
      'sessionId': sessionId,
      if (beforeSeq != null) 'beforeSeq': beforeSeq,
      'maxMessages': _historyPageMessages,
    }).valueOrThrow();
    final history = SessionHistoryValueWire.fromJson(value);
    final goalValue = history.projectionValues?['goal'];
    if (goalValue != null) {
      _goalProjectionStateFor(sessionId).value = _parseGoalProjection(
        goalValue,
      );
    }
    final planValue = history.projectionValues?['plan'];
    if (planValue != null) {
      _planProjectionStateFor(sessionId).value = _parsePlanProjection(
        planValue,
      );
    }
    final todosValue = history.projectionValues?['todos'];
    if (todosValue != null) {
      _todoProjectionStateFor(sessionId).value = _parseTodosProjection(
        todosValue,
      );
    }
    return _HistoryPage(events: history.events, hasMore: history.hasMore);
  }

  GoalProjection? _parseGoalProjection(Object? value) {
    if (value == null || value == 'null') return null;
    return _tryDecode(() {
      final obj = asJsonObject(value);
      if (obj == null) throw const FormatException('not an object');
      return _toDomainGoalProjection(GoalProjectionWire.fromJson(obj));
    });
  }

  PlanState? _parsePlanProjection(Object? value) {
    if (value == null) return null;
    if (value == 'null') return null;
    return _tryDecode(() {
      final decoded = decodePlanProjection(value);
      if (decoded == null) throw const FormatException('not an object');
      return PlanState(active: decoded.active, pending: decoded.pending);
    });
  }

  GoalProjection _toDomainGoalProjection(GoalProjectionWire wire) =>
      GoalProjection(
        goal: GoalSnapshot(
          id: wire.goal.id,
          revision: wire.goal.revision,
          objective: wire.goal.objective,
          phase: switch (wire.goal.phase) {
            'paused' => GoalPhase.paused,
            'blocked' => GoalPhase.blocked,
            'complete' => GoalPhase.complete,
            _ => GoalPhase.active,
          },
          blockedReason: wire.goal.blockedReasonMessage,
          maxGoalRounds: wire.goal.maxGoalRounds,
        ),
        roundsStarted: wire.roundsStarted,
        createdAt: wire.createdAt,
        updatedAt: wire.updatedAt,
      );

  DirectoryListing _toDomainDirectoryListing(DirectoryListingValueWire wire) =>
      DirectoryListing(
        path: wire.path,
        home: wire.home,
        crumbs: wire.crumbs
            .map(
              (entry) => DirectoryEntry(
                name: entry.name,
                path: entry.path,
                hidden: entry.hidden,
              ),
            )
            .toList(),
        entries: wire.entries
            .map(
              (entry) => DirectoryEntry(
                name: entry.name,
                path: entry.path,
                hidden: entry.hidden,
              ),
            )
            .toList(),
        truncated: wire.truncated,
      );

  SettingsNamespace _toDomainSettingsNamespace(SettingsNamespaceWire wire) =>
      SettingsNamespace(
        ns: wire.ns,
        applies: decodeApplies(wire.applies),
        revision: wire.revision,
        hasUserLayer: wire.hasUserLayer,
        secretCount: wire.secretCount,
      );

  WorkspaceWire _workspaceFromJson(JsonMap value, String key) =>
      WorkspaceWire.fromJson(
        asJsonObject(value[key]) ?? const <String, Object?>{},
      );

  WorkspaceSummary _toDomainWorkspace(WorkspaceWire wire) => WorkspaceSummary(
    workspaceId: wire.workspaceId,
    path: wire.path,
    title: wire.title,
    sessionIds: wire.sessionIds,
    createdAt: wire.createdAt,
    updatedAt: wire.updatedAt,
  );

  SessionModels _toDomainSessionModels(SessionModelsValueWire wire) =>
      SessionModels(
        current: ModelSelection(
          provider: wire.current.provider,
          model: wire.current.model,
          reasoningEffort: wire.current.reasoningEffort,
        ),
        routable: wire.routable,
        groups: wire.groups
            .map(
              (group) => ModelProviderGroup(
                id: group.id,
                name: group.name,
                models: group.models
                    .map(
                      (model) => ModelCatalogModel(
                        id: model.id,
                        name: model.name,
                        description: model.description,
                        reasoning: model.reasoning == null
                            ? null
                            : ModelReasoning(
                                efforts: model.reasoning!.efforts
                                    .map(
                                      (effort) => ModelReasoningEffort(
                                        id: effort.id,
                                        name: effort.name,
                                        description: effort.description,
                                      ),
                                    )
                                    .toList(),
                                defaultEffort: model.reasoning!.defaultEffort,
                              ),
                      ),
                    )
                    .toList(),
              ),
            )
            .toList(),
        failures: wire.failures
            .map(
              (failure) => ModelCatalogFailure(
                id: failure.id,
                name: failure.name,
                message: failure.message,
              ),
            )
            .toList(),
      );

  String? _frameSessionId(ServerRequest frame) =>
      wireString(frame.payload, 'sessionId');

  void _markSessionNoLongerBlank(String sessionId) {
    _sessions.value = _sessions.value
        .map(
          (session) => session.id == sessionId
              ? _copySession(session, blank: false)
              : session,
        )
        .toList();
  }

  SessionSummary _copySession(
    SessionSummary session, {
    String? title,
    bool? running,
    bool? blank,
    String? agentPreset,
    bool? completed,
  }) => SessionSummary(
    id: session.id,
    title: title ?? session.title,
    running: running ?? session.running,
    blank: blank ?? session.blank,
    updatedAtEpochMs: session.updatedAtEpochMs,
    cwd: session.cwd,
    agentPreset: agentPreset ?? session.agentPreset,
    origin: session.origin,
    completed: completed ?? session.completed,
  );

  _SessionState _sessionStateFor(String sessionId) {
    final existing = _sessionStates[sessionId];
    if (existing != null) return existing;
    final state = _SessionState(sessionId);
    _sessionStates[sessionId] = state;
    // Replay frames buffered before instantiation (web `pendingBuffers`
    // replay on `get()`). While the state is not yet loaded, `handleFrame`
    // parks them in `_pending`; `ensureLoaded` replays them after the history
    // reset, so the buffered question/approval/queue lands in the reducer.
    final buffered = _pendingBuffers.remove(sessionId);
    if (buffered != null) {
      for (final frame in buffered) {
        unawaited(state.handleFrame(frame));
      }
    }
    return state;
  }

  /// Web SessionManager `pendingBuffers` switch: answerable live frames for an
  /// uninstantiated session are retained (compacting duplicates by their stable
  /// key), their `* /resolved` frames remove the matching entry, and everything
  /// else is dropped because an open backfills it from history.
  void _bufferPendingFrame(String sessionId, ServerRequest frame) {
    final payload = frame.payload;
    switch (wireString(payload, 'type')) {
      case 'approval/requested':
      case 'question/requested':
      case 'session/queue':
        final buffer = _pendingBuffers.putIfAbsent(sessionId, () => <ServerRequest>[]);
        final key = switch (wireString(payload, 'type')) {
          'approval/requested' => 'a:${wireString(payload, 'approvalId')}',
          'question/requested' => 'q:${frame.rpcId}',
          _ => 'queue',
        };
        final prior = buffer.indexWhere((item) => _bufferedKey(item) == key);
        if (prior == -1) {
          buffer.add(frame);
        } else {
          buffer[prior] = frame;
        }
      case 'approval/resolved':
      case 'question/resolved':
        final key = wireString(payload, 'type') == 'approval/resolved'
            ? 'a:${wireString(payload, 'approvalId')}'
            : 'q:${wireString(payload, 'questionRpcId')}';
        final buffer = _pendingBuffers[sessionId];
        if (buffer == null) return;
        buffer.removeWhere((item) => _bufferedKey(item) == key);
        if (buffer.isEmpty) _pendingBuffers.remove(sessionId);
    }
  }

  /// The stable buffer key of a buffered frame (`a:<approvalId>` /
  /// `q:<rpcId>` / `queue`), mirroring `_itemKey` on the reducer side.
  String? _bufferedKey(ServerRequest frame) {
    final payload = frame.payload;
    return switch (wireString(payload, 'type')) {
      'approval/requested' => 'a:${wireString(payload, 'approvalId')}',
      'question/requested' => 'q:${frame.rpcId}',
      'session/queue' => 'queue',
      _ => null,
    };
  }

  StateStream<GoalProjection?> _goalProjectionStateFor(String sessionId) =>
      _goalProjections.putIfAbsent(
        sessionId,
        () => StateStream<GoalProjection?>(null),
      );

  StateStream<PlanState?> _planProjectionStateFor(String sessionId) =>
      _planProjections.putIfAbsent(
        sessionId,
        () => StateStream<PlanState?>(null),
      );

  StateStream<List<TodoItem>?> _todoProjectionStateFor(String sessionId) =>
      _todoProjections.putIfAbsent(
        sessionId,
        () => StateStream<List<TodoItem>?>(null),
      );

  StateStream<PermissionSelect?> _permissionProjectionStateFor(
    String sessionId,
  ) => _permissionProjections.putIfAbsent(
    sessionId,
    () => StateStream<PermissionSelect?>(null),
  );

  Object _parseJsonValue(String text) {
    final Object? decoded = jsonDecode(text);
    if (decoded == null) {
      throw const FormatException('invalid JSON value: null');
    }
    return decoded;
  }

  T? _tryDecode<T>(T Function() decode) {
    try {
      return decode();
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  List<String> _stringList(Object? json) =>
      (asJsonArray(json) ?? const <Object?>[])
          .map((entry) => entry is String ? entry : null)
          .whereType<String>()
          .toList();

  Set<String> _stringSet(Object? json) => _stringList(json).toSet();
}

extension on Future<RpcResult> {
  Future<JsonMap> valueOrThrow() async {
    final result = await this;
    if (result.ok) {
      final value = result.value;
      if (value == null) {
        throw DshBusinessException(
          code: 'bad-response',
          message: 'missing result value',
        );
      }
      return value;
    }
    final failure = result.error;
    throw DshBusinessException(
      code: failure?.code ?? 'internal',
      message: failure?.message ?? 'unknown dsh error',
    );
  }
}

// ---------------------------------------------------------------------------
// Per-session state machine
// ---------------------------------------------------------------------------

final class _SessionState {
  _SessionState(this.sessionId);

  final String sessionId;
  final StateStream<List<TimelineItem>> timeline =
      StateStream<List<TimelineItem>>(<TimelineItem>[]);
  final StateStream<TimelineWindow> window = StateStream<TimelineWindow>(
    const TimelineWindow(),
  );
  final StateStream<ContextPressure?> contextPressure =
      StateStream<ContextPressure?>(null);
  final StateStream<ContextBreakdown?> contextBreakdown =
      StateStream<ContextBreakdown?>(null);
  final StateStream<SessionWindowStats> sessionStats =
      const SessionWindowStats() == const SessionWindowStats()
      ? StateStream<SessionWindowStats>(const SessionWindowStats())
      : StateStream<SessionWindowStats>(const SessionWindowStats());
  final SessionStatsFold _statsFold = SessionStatsFold();
  final ContextPressureFold _contextFold = ContextPressureFold();
  final Mutex _mutex = Mutex();
  TimelineReducer _reducer = TimelineReducer('');
  bool _ready = false;
  bool _loading = false;
  bool _hasMoreOlder = false;
  bool _loadingOlder = false;
  List<JsonMap> _history = <JsonMap>[];
  List<ServerRequest> _pending = <ServerRequest>[];
  List<ServerRequest> _framesAfterOpen = <ServerRequest>[];

  /// Pending frame-cadence publish (streaming chunks); null when the next
  /// publish goes out immediately.
  Timer? _coalescedPublish;

  Future<void> ensureLoaded(
    Future<_HistoryPage> Function(int? beforeSeq) loader,
  ) {
    return _mutex.synchronized(() async {
      if (_ready) return;
      // Surface the first-load (or resync) wait to observers: an empty
      // timeline that is still loading must not read as an empty session.
      _loading = true;
      _publish();
      try {
        final page = await loader(null);
        _history = stableSortedBy(page.events, (event) => wireLong(event, 'seq'));
        _hasMoreOlder = page.hasMore;
        _reducer = TimelineReducer(sessionId);
        _reducer.reset(_history);
        _contextFold.reset(_history);
        _statsFold.reset(_history);
        _framesAfterOpen = List.of(_pending);
        for (final frame in _pending) {
          _reducer.ingestFrame(frame);
          if (wireType(frame.payload) == 'session/event') {
            _contextFold.ingestEvent(frame.payload['event']);
            _statsFold.ingestEvent(frame.payload['event']);
          }
        }
        contextPressure.value = _contextFold.value;
        contextBreakdown.value = _contextFold.breakdown;
        sessionStats.value = _statsFold.value;
        _pending = <ServerRequest>[];
        _ready = true;
      } finally {
        _loading = false;
        _publish();
      }
    });
  }

  void prepareResync() {
    _ready = false;
    _loading = false;
    _loadingOlder = false;
    _hasMoreOlder = false;
    _framesAfterOpen = <ServerRequest>[];
  }

  Future<void> handleFrame(ServerRequest frame) {
    return _mutex.synchronized<void>(() async {
      if (!_ready) {
        _pending.add(frame);
        return;
      }
      _reducer.ingestFrame(frame);
      if (wireType(frame.payload) == 'session/event') {
        _contextFold.ingestEvent(frame.payload['event']);
        _statsFold.ingestEvent(frame.payload['event']);
        contextPressure.value = _contextFold.value;
        contextBreakdown.value = _contextFold.breakdown;
        sessionStats.value = _statsFold.value;
      }
      _framesAfterOpen.add(frame);
      _publish(coalescable: _isStreamingChunk(frame));
    });
  }

  /// Streaming token chunks publish at frame cadence (the reference web
  /// client's `markFrameDirty` / `'animation-frame'` publication rank:
  /// every assistant chunk except `finish`/`usage` coalesces into one
  /// notification per frame); everything else — turn boundaries, tool
  /// calls, approvals, queue and job frames — publishes immediately.
  static bool _isStreamingChunk(ServerRequest frame) {
    if (wireType(frame.payload) != 'session/event') return false;
    final event = asJsonObject(frame.payload['event']);
    if (event == null || wireType(event) != 'assistant/chunk') return false;
    final chunk = asJsonObject(
      (asJsonObject(event['data']) ?? const <String, Object?>{})['chunk'],
    );
    final type = chunk == null ? null : wireType(chunk);
    return type != null && type != 'finish' && type != 'usage';
  }

  Future<bool> loadOlder(Future<_HistoryPage> Function(int beforeSeq) loader) {
    return _mutex.synchronized(() async {
      if (!_ready || !_hasMoreOlder || _loadingOlder) return false;
      if (_history.isEmpty) return false;
      final baseSeq = wireLong(_history.first, 'seq');
      _loadingOlder = true;
      _publish();
      try {
        final page = await loader(baseSeq);
        if (page.events.isEmpty) {
          _hasMoreOlder = page.hasMore;
          return true;
        }
        final older = stableSortedBy(
          page.events,
          (event) => wireLong(event, 'seq'),
        );
        final tailSeq = wireLong(older.last, 'seq');
        if (tailSeq + 1 != baseSeq) {
          _hasMoreOlder = false;
          return false;
        }
        _history = List.of(older)..addAll(_history);
        _hasMoreOlder = page.hasMore;
        _rebuild();
        return true;
      } finally {
        _loadingOlder = false;
        _publish();
      }
    });
  }

  void _rebuild() {
    _reducer = TimelineReducer(sessionId);
    _reducer.reset(_history);
    _contextFold.reset(_history);
    _statsFold.reset(_history);
    for (final frame in _framesAfterOpen) {
      _reducer.ingestFrame(frame);
      if (wireType(frame.payload) == 'session/event') {
        _contextFold.ingestEvent(frame.payload['event']);
        _statsFold.ingestEvent(frame.payload['event']);
      }
    }
    contextPressure.value = _contextFold.value;
    contextBreakdown.value = _contextFold.breakdown;
    sessionStats.value = _statsFold.value;
  }

  void _publish({bool coalescable = false}) {
    if (coalescable) {
      // N chunks inside one window collapse into one publish of the
      // freshest state (the web's markFrameDirty→rAF flush); the first
      // publish carries whatever landed before the timer fires.
      _coalescedPublish ??= Timer(kStreamPublishWindow, _flushCoalesced);
      return;
    }
    _flushCoalesced();
  }

  void _flushCoalesced() {
    _coalescedPublish?.cancel();
    _coalescedPublish = null;
    final items = _reducer.snapshot();
    timeline.value = items;
    window.value = TimelineWindow(
      items: items,
      hasMoreOlder: _hasMoreOlder,
      isLoadingOlder: _loadingOlder,
      isLoading: _loading,
    );
  }

  /// Cancel a still-pending coalesced publish (repository dispose).
  void discard() {
    _coalescedPublish?.cancel();
    _coalescedPublish = null;
  }
}
