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

import 'adapter_diagnostics.dart';
import 'dsh_connection_manager.dart';
import 'dsh_remote_invoker.dart';
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

const int _credentialsMaxRefs = 64;
const int _historyPageMessages = 50;

final class _HistoryPage {
  _HistoryPage({required this.events, required this.hasMore});

  final List<JsonMap> events;
  final bool hasMore;
}

class HarnessRepositoryImpl implements ChatRepository {
  HarnessRepositoryImpl(
    this._rpcClient,
    this._connectionManager, {
    this._onDiagnostic,
  }) {
    _invoker = DshRemoteInvoker(_rpcClient);
    _connectionManager.start();
    _collectConnection();
    _collectMuxFrames();
    _collectHostFrames();
  }

  final DshRpcClient _rpcClient;
  final DshConnectionManager _connectionManager;
  final AdapterDiagnosticListener? _onDiagnostic;
  late final DshRemoteInvoker _invoker;

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
  /// parity). A session's statuses re-baseline in-band on its
  /// `session/subscribed` frame — the generation's replay re-adds
  /// still-pending requests after it.
  final StateStream<Map<String, SessionPendingInteraction>>
  _pendingInteractions = StateStream<Map<String, SessionPendingInteraction>>(
    const <String, SessionPendingInteraction>{},
  );

  /// Session id -> per-key pending status (`a:<approvalId>` /
  /// `q:<rpcId>`); a session may wait on several interactions at once.
  /// [StateStream.value] of [_pendingInteractions] is the priority
  /// projection of this map (web SessionManager: a non-approval
  /// interaction — question or plan-review — outranks an approval).
  /// A session's keys drop when its new mux generation's
  /// `session/subscribed` frame lands — in-band, because that frame
  /// precedes the generation's replayed requested frames on the same
  /// stream; dropping them on the connected publish would race the burst.
  final Map<String, Map<String, SessionPendingInteraction>> _pendingBySession =
      <String, Map<String, SessionPendingInteraction>>{};

  /// The session the app is currently viewing (last `openSession` target).
  /// The finished-but-unviewed reminder (green dot) is armed only when a
  /// session stops running while it is NOT this one (web SessionManager
  /// `completedNotifications`).
  String? _openSessionId;
  String? _followedSessionId;

  void _followSession(String sessionId) {
    if (_followedSessionId == sessionId) return;
    if (_followedSessionId != null) {
      _connectionManager.sendMuxMessage(
        jsonEncode(<String, Object?>{
          'type': 'cancel',
          'streamId': 'session-follow-$_followedSessionId',
        }),
      );
    }
    _followedSessionId = sessionId;
    _connectionManager.sendMuxMessage(
      jsonEncode(<String, Object?>{
        'type': 'open',
        'streamId': 'session-follow-$sessionId',
        'endpoint': 'session/follow',
        'payload': <String, Object?>{
          'args': <String, Object?>{
            'request': <String, Object?>{
              'address': <String, Object?>{
                'kind': 'session',
                'sessionId': sessionId,
              },
            },
          },
        },
      }),
    );
  }

  void _updateSessionRunning(String sessionId, bool running) {
    _prevRunningBySession[sessionId] = running;
    _sessions.value = _sessions.value.map((item) {
      if (item.id != sessionId) return item;
      return _copySession(
        item,
        running: running,
        blank: item.blank && !running,
      );
    }).toList();
  }

  /// Last observed running bit per session, driving the true→false edge
  /// that arms the completion reminder.
  final Map<String, bool> _prevRunningBySession = <String, bool>{};
  final StateStream<ImageLimits?> _imageLimits = StateStream<ImageLimits?>(
    null,
  );
  final Map<String, _SessionState> _sessionStates = <String, _SessionState>{};
  final Map<String, int> _sessionCursors = <String, int>{};

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
  /// never replayed, and a session's buffered `session/queue` entry is
  /// truncated in-band by its next `session/subscribed` frame (web
  /// manager.ts:714-732): the host omits the baseline for an emptied queue.
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
      DshRpcEndpoints.sessionCreate,
      DshRpcEndpoints.sessionCreate,
      payload,
    ).valueOrThrow();
    final created = wireString(value, 'sessionId');
    if (created == null) {
      throw const FormatException('session/create missing sessionId');
    }
    _sessions.value = await _loadSessions();
    return SessionSummary(id: created, blank: true);
  }

  @override
  Future<AgentPresetRoster> listAgentPresets() async {
    final value = await _call(
      DshRpcEndpoints.agentPresetsList,
      DshRpcEndpoints.agentPresetsList,
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
    final value = await _call(
      DshRpcEndpoints.agentPresetsSelect,
      DshRpcEndpoints.agentPresetsSelect,
      {'agentId': sessionId, 'agentPreset': agentPreset},
    ).valueOrThrow();
    final echoed =
        wireString(value, 'value') ??
        wireString(value, 'agentPreset') ??
        (value is String ? value as String : null);
    if (echoed == null) {
      throw const FormatException('agentPresets.select missing agentPreset');
    }
    return echoed;
  }

  @override
  Future<DirectoryListing> listDirectory(String? path) async {
    final payload = <String, Object?>{if (path != null) 'path': path};
    final value = await _call(
      DshRpcEndpoints.directoryPickerList,
      DshRpcEndpoints.directoryPickerList,
      payload,
    ).valueOrThrow();
    return _toDomainDirectoryListing(DirectoryListingValueWire.fromJson(value));
  }

  @override
  Future<String> createDirectory(String parentPath, String name) async {
    final value = await _call(
      DshRpcEndpoints.directoryPickerCreate,
      DshRpcEndpoints.directoryPickerCreate,
      {'path': parentPath, 'name': name},
    ).valueOrThrow();
    final path = wireString(value, 'path') ?? (value['value'] as String?);
    if (path == null) {
      throw const FormatException(
        'directoryPicker.createDirectory missing path',
      );
    }
    return path;
  }

  @override
  Future<SettingsSnapshot> describeSettings() async {
    final value = await _call(
      DshRpcEndpoints.settingsDescribe,
      DshRpcEndpoints.settingsDescribe,
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
    final value = await _call(
      DshRpcEndpoints.credentialsDescribe,
      DshRpcEndpoints.credentialsDescribe,
      {'refs': refs.take(_credentialsMaxRefs).toList()},
    ).valueOrThrow();
    return decodeCredentialsDescribeValue(value);
  }

  @override
  Future<void> setCredential(String ref, String value) async {
    if (value.isEmpty) {
      throw ArgumentError('credential value must be non-empty');
    }
    await _call(
      DshRpcEndpoints.credentialsSet,
      DshRpcEndpoints.credentialsSet,
      {'ref': ref, 'value': value},
    ).valueOrThrow();
  }

  @override
  Future<void> unsetCredential(String ref) async {
    await _call(
      DshRpcEndpoints.credentialsUnset,
      DshRpcEndpoints.credentialsUnset,
      {'ref': ref},
    ).valueOrThrow();
  }

  @override
  Future<SettingsNamespace> updateSetting(
    String ns,
    String key,
    String jsonValue, {
    int? expectedRevision,
  }) async {
    final value = await _call(
      DshRpcEndpoints.settingsUpdate,
      DshRpcEndpoints.settingsUpdate,
      {
        'ns': ns,
        'patch': {key: _parseJsonValue(jsonValue)},
        if (expectedRevision != null) 'expectedRevision': expectedRevision,
      },
    ).valueOrThrow();
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
    final value = await _call(
      DshRpcEndpoints.settingsReplace,
      DshRpcEndpoints.settingsReplace,
      {
        'ns': ns,
        'section': decoded,
        if (expectedRevision != null) 'expectedRevision': expectedRevision,
      },
    ).valueOrThrow();
    return _toDomainSettingsNamespace(SettingsNamespaceWire.fromJson(value));
  }

  @override
  Future<SettingsNamespace> mutateSetting(
    String ns,
    List<SettingPathOp> ops, {
    int? expectedRevision,
  }) async {
    final value = await _call(
      DshRpcEndpoints.settingsMutate,
      DshRpcEndpoints.settingsMutate,
      {
        'ns': ns,
        'ops': ops
            .map(
              (op) => <String, Object?>{
                'op': op.op,
                'path': op.path,
                if (op.jsonValue != null)
                  'value': _parseJsonValue(op.jsonValue!),
              },
            )
            .toList(),
        if (expectedRevision != null) 'expectedRevision': expectedRevision,
      },
    ).valueOrThrow();
    return _toDomainSettingsNamespace(SettingsNamespaceWire.fromJson(value));
  }

  @override
  Future<void> openSession(String sessionId) async {
    final state = _sessionStateFor(sessionId);
    // Looking at the session consumes its completion reminder (dot clears)
    // and makes it the armed-selection for future running finishes.
    _openSessionId = sessionId;
    _followSession(sessionId);
    if (_prevRunningBySession[sessionId] == false ||
        _prevRunningBySession[sessionId] == null) {
      _setSessionCompleted(sessionId, false);
    }
    try {
      await state.ensureLoaded(
        (beforeSeq) => _loadHistory(sessionId, beforeSeq),
      );
    } catch (e, st) {
      _onDiagnostic?.call(
        AdapterDiagnostic(
          message: 'openSession history load failed for $sessionId: $e',
          level: AdapterDiagnosticLevel.warning,
          context: 'session.open',
          error: e,
          stackTrace: st,
          metadata: <String, Object?>{'sessionId': sessionId},
        ),
      );
      // A failed first load stays pending; the next generation retries it.
    }
  }

  /// Rewrites one session's row with [completed], re-emitting the raw
  /// session list so `observeSessions` publishes the updated fact.
  void _setSessionCompleted(String sessionId, bool completed) {
    _sessions.value = _sessions.value
        .map(
          (item) => item.id == sessionId
              ? _copySession(item, completed: completed)
              : item,
        )
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
    final value = await _call(
      DshRpcEndpoints.sessionPrompt,
      DshRpcEndpoints.sessionPrompt,
      {
        'requestId': 'req-${DateTime.now().microsecondsSinceEpoch}',
        'sessionId': request.sessionId,
        'mode': request.mode == PromptMode.queue ? 'queue' : 'steer',
        'content': content,
      },
    ).valueOrThrow();
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
    final result = await _call(
      DshRpcEndpoints.commandsExecute,
      DshRpcEndpoints.commandsExecute,
      <String, Object?>{
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
    );
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
    await _call(DshRpcEndpoints.sessionCancel, DshRpcEndpoints.sessionCancel, {
      'sessionId': sessionId,
    }).valueOrThrow();
  }

  @override
  Future<AttachmentData> readAttachment(
    String sessionId,
    String attachmentId,
  ) async {
    final value = await _call(
      DshRpcEndpoints.sessionAttachment,
      DshRpcEndpoints.sessionAttachment,
      {'sessionId': sessionId, 'attachmentId': attachmentId},
    ).valueOrThrow();
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
    final value = await _call(
      DshRpcEndpoints.skillsList,
      DshRpcEndpoints.skillsList,
      {'sessionId': sessionId},
    ).valueOrThrow();
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
    final result = await _call(
      DshRpcEndpoints.sessionRename,
      DshRpcEndpoints.sessionRename,
      {'sessionId': sessionId, 'title': title},
    ).valueOrThrow();
    final renamed = wireString(result, 'title');
    if (renamed == null) {
      throw const FormatException('session/rename missing title');
    }
    _sessions.value = await _loadSessions();
    return renamed;
  }

  @override
  Future<SessionSummary> forkSession(String sessionId, {int? atSeq}) async {
    final result = await _call(
      DshRpcEndpoints.sessionFork,
      DshRpcEndpoints.sessionFork,
      {'sessionId': sessionId, if (atSeq != null) 'atSeq': atSeq},
    ).valueOrThrow();
    final forked = wireString(result, 'sessionId');
    if (forked == null) {
      throw const FormatException('session/fork missing sessionId');
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
      await _call(
        DshRpcEndpoints.sessionUpdateQueue,
        DshRpcEndpoints.sessionUpdateQueue,
        {
          'sessionId': request.sessionId,
          'itemId': request.itemId,
          'action': action,
        },
      ).valueOrThrow();
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
    final value = await _call(
      DshRpcEndpoints.subagentsList,
      DshRpcEndpoints.subagentsList,
      {'parentSessionId': parentSessionId},
    ).valueOrThrow();
    final wire = SubagentListValueWire.fromJson(value);
    return SubagentCatalog(
      parentSessionId: parentSessionId,
      entries: wire.entries
          .map(
            (entry) => SubagentEntry(
              id: entry.id,
              kind: entry.kind,
              mode: _subagentModeFromWire(entry),
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

  /// Maps one catalog row's `mode` onto the domain enum. Child rows carry
  /// it per `subagentListEntrySchema` (only `'one-shot'` /
  /// `'continuable'`); a child row with a missing or unknown mode fails
  /// loud naming the field. Diagnostic rows carry none and map to null.
  SubagentMode? _subagentModeFromWire(SubagentEntryWire entry) {
    if (entry.kind != 'child') return null;
    return switch (entry.mode) {
      'one-shot' => SubagentMode.oneShot,
      'continuable' => SubagentMode.continuable,
      null => throw FormatException(
        'required field "mode" missing or mistyped in ${entry.id}',
      ),
      final other => throw FormatException(
        'field "mode" has unknown value "$other" for subagent child '
        '${entry.id}',
      ),
    };
  }

  /// The `subagent.history` request carries the addressed row's own mode:
  /// the host matches it against the durable entry (`catalogChild`,
  /// api-proxy.ts) and answers a mismatch with `subagent-not-found`. The
  /// prompt and interrupt verbs are pinned to `'continuable'` by the wire
  /// schema (`subagentPromptRequestSchema`, `subagentInterruptRequestSchema`);
  /// the UI surfaces those controls only for continuable rows.
  static String _subagentModeToWire(SubagentMode mode) =>
      mode == SubagentMode.oneShot ? 'one-shot' : 'continuable';

  @override
  Future<void> interruptSubagent(
    String parentSessionId,
    String childSessionId,
  ) async {
    await _call(
      DshRpcEndpoints.subagentsInterrupt,
      DshRpcEndpoints.subagentsInterrupt,
      {
        'parentSessionId': parentSessionId,
        'childSessionId': childSessionId,
        'mode': _subagentModeToWire(SubagentMode.continuable),
      },
    ).valueOrThrow();
  }

  @override
  Future<List<TimelineItem>> loadSubagentHistory(
    String parentSessionId,
    String childSessionId,
    SubagentMode mode,
  ) async {
    final throughSeq = _sessionCursors[childSessionId] ?? 999999999;
    final value = await _call(
      DshRpcEndpoints.sessionPage,
      DshRpcEndpoints.sessionPage,
      {
        'request': <String, Object?>{
          'address': <String, Object?>{
            'kind': 'subagent',
            'parentSessionId': parentSessionId,
            'childSessionId': childSessionId,
            'mode': _subagentModeToWire(mode),
          },
          'throughSeq': throughSeq,
          'maxMessages': _historyPageMessages,
        },
      },
    ).valueOrThrow();
    final history = SessionHistoryValueWire.fromJson(value);
    if (history.events.isNotEmpty) {
      final lastSeq = wireLong(history.events.last, 'seq');
      _sessionCursors[childSessionId] = lastSeq;
    } else {
      _sessionCursors[childSessionId] = -1;
    }
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
    final promptPayload = <String, Object?>{
      'parentSessionId': parentSessionId,
      'childSessionId': childSessionId,
      'requestId': 'req-${DateTime.now().microsecondsSinceEpoch}',
      'mode': _subagentModeToWire(SubagentMode.continuable),
      'content': <Object?>[
        <String, Object?>{'type': 'text', 'text': text},
      ],
    };
    JsonMap value;
    try {
      value = await _invoker.invoke(
        DshRpcEndpoints.subagentsPrompt,
        promptPayload,
      );
    } catch (_) {
      value = await _invoker.invoke('subagent.prompt', promptPayload);
    }
    final messageId = wireString(value, 'messageId') ?? 'accepted';
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
    final value = await _call(
      DshRpcEndpoints.goalsCreate,
      DshRpcEndpoints.goalsCreate,
      {
        'agentId': sessionId,
        'request': <String, Object?>{
          'objective': objective,
          if (maxGoalRounds != null) 'maxGoalRounds': maxGoalRounds,
        },
      },
    ).valueOrThrow();
    final ref = decodeGoalRefValue(value);
    return GoalRef(id: ref.id, revision: ref.revision);
  }

  @override
  Future<GoalRef> editGoal(String sessionId, GoalRef ref, String objective) =>
      _goalMutation(DshRpcEndpoints.goalsEdit, sessionId, ref, objective);

  @override
  Future<GoalRef> pauseGoal(String sessionId, GoalRef ref) =>
      _goalMutation(DshRpcEndpoints.goalsPause, sessionId, ref);

  @override
  Future<GoalRef> resumeGoal(String sessionId, GoalRef ref) =>
      _goalMutation(DshRpcEndpoints.goalsResume, sessionId, ref);

  @override
  Future<GoalRef> completeGoal(String sessionId, GoalRef ref) =>
      _goalMutation(DshRpcEndpoints.goalsComplete, sessionId, ref);

  @override
  Future<void> clearGoal(String sessionId, GoalRef ref) async {
    await _call(
      DshRpcEndpoints.goalsClear,
      DshRpcEndpoints.goalsClear,
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
    'agentId': sessionId,
    'ref': <String, Object?>{'id': ref.id, 'revision': ref.revision},
    if (objective != null) 'request': <String, Object?>{'objective': objective},
  };

  @override
  Stream<List<WorkspaceSummary>> observeWorkspaces() => _workspaces.stream;

  @override
  Future<void> refreshWorkspaces() async {
    final listing = await _loadWorkspaceListing();
    if (listing != null) {
      _applyWorkspaceListing(listing);
    }
  }

  Future<WorkspaceListValueWire?> _loadWorkspaceListing() async {
    final value = await _invoker.invokeOrNullOnNotFound(
      DshRpcEndpoints.workspaceList,
      <String, Object?>{},
    );
    if (value == null) return null;
    return WorkspaceListValueWire.fromJson(value);
  }

  void _applyWorkspaceListing(WorkspaceListValueWire listing) {
    _workspaces.value = listing.items.map(_toDomainWorkspace).toList();
    _archivedSessionIds.value = listing.archivedSessionIds.toSet();
  }

  @override
  Future<WorkspaceSummary> createWorkspace(String path) async {
    final result = await _call(
      DshRpcEndpoints.workspaceCreate,
      DshRpcEndpoints.workspaceCreate,
      {'path': path},
    ).valueOrThrow();
    final created = _toDomainWorkspace(_workspaceFromJson(result, 'workspace'));
    final current = _workspaces.value;
    final index = current.indexWhere(
      (item) => item.workspaceId == created.workspaceId,
    );
    if (index < 0) {
      _workspaces.value = List.of(current)..add(created);
    } else {
      _workspaces.value = List.of(current)..[index] = created;
    }
    final listing = await _loadWorkspaceListing();
    if (listing != null) {
      _applyWorkspaceListing(listing);
    }
    return created;
  }

  @override
  Future<WorkspaceSummary> renameWorkspace(
    String workspaceId,
    String title,
  ) async {
    final result = await _call(
      DshRpcEndpoints.workspaceRename,
      DshRpcEndpoints.workspaceRename,
      {'workspaceId': workspaceId, 'title': title},
    ).valueOrThrow();
    final renamed = _toDomainWorkspace(_workspaceFromJson(result, 'workspace'));
    final current = _workspaces.value;
    final index = current.indexWhere(
      (item) => item.workspaceId == renamed.workspaceId,
    );
    if (index >= 0) {
      _workspaces.value = List.of(current)..[index] = renamed;
    }
    final listing = await _loadWorkspaceListing();
    if (listing != null) {
      _applyWorkspaceListing(listing);
    }
    return renamed;
  }

  @override
  Future<void> archiveSession(String sessionId) async {
    final result = await _call(
      DshRpcEndpoints.workspaceArchiveSession,
      DshRpcEndpoints.workspaceArchiveSession,
      {'sessionId': sessionId},
    ).valueOrThrow();
    _archivedSessionIds.value = _stringSet(result['archivedSessionIds']);
  }

  @override
  Future<void> deleteWorkspace(String workspaceId) async {
    await _call(
      DshRpcEndpoints.workspaceDelete,
      DshRpcEndpoints.workspaceDelete,
      {'workspaceId': workspaceId},
    ).valueOrThrow();
    _workspaces.value = _workspaces.value
        .where((item) => item.workspaceId != workspaceId)
        .toList();
    final listing = await _loadWorkspaceListing();
    if (listing != null) {
      _applyWorkspaceListing(listing);
    }
  }

  @override
  Future<List<String>> moveWorkspace(
    String workspaceId,
    String? beforeWorkspaceId,
  ) async {
    final value = await _call(
      DshRpcEndpoints.workspaceInsertBefore,
      DshRpcEndpoints.workspaceInsertBefore,
      {
        'workspaceId': workspaceId,
        if (beforeWorkspaceId != null) 'beforeWorkspaceId': beforeWorkspaceId,
      },
    ).valueOrThrow();
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
      DshRpcEndpoints.workspaceInsertSessionBefore,
      DshRpcEndpoints.workspaceInsertSessionBefore,
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
    final result = await _call(
      DshRpcEndpoints.sessionModelCatalog,
      DshRpcEndpoints.sessionModelCatalog,
      <String, Object?>{},
    ).valueOrThrow();
    return _toDomainSessionModels(SessionModelsValueWire.fromJson(result));
  }

  @override
  Future<ModelSelection> selectModel(
    String sessionId,
    ModelSelection selection,
  ) async {
    final result = await _call(
      DshRpcEndpoints.sessionSelectModel,
      DshRpcEndpoints.sessionSelectModel,
      {
        'sessionId': sessionId,
        'provider': selection.provider,
        'model': selection.model,
        if (selection.reasoningEffort != null)
          'reasoningEffort': selection.reasoningEffort,
      },
    ).valueOrThrow();
    final selectedObj = asJsonObject(result['selected']);
    if (selectedObj == null) {
      throw const FormatException('session/selectModel missing selected');
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
    final result = await _call(
      DshRpcEndpoints.sessionSearch,
      DshRpcEndpoints.sessionSearch,
      {'query': query},
    ).valueOrThrow();
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
          if (_openSessionId != null) {
            _followedSessionId = null;
            _followSession(_openSessionId!);
          }
          unawaited(_resync(connection));
        }
      }),
    );
  }

  void _collectMuxFrames() {
    _subs.add(
      _connectionManager.muxFrames.listen((frame) {
        final type = wireString(frame.payload, 'type');
        if (frame.rpcId == 'session-control' ||
            (type == 'baseline' &&
                (frame.payload.containsKey('projections') ||
                    frame.payload.containsKey('queues') ||
                    asJsonObject(frame.payload['value'])
                            ?.containsKey('projections') ==
                        true))) {
          if (type == 'baseline') {
            _handleControlBaseline(frame);
            return;
          }
          if (type == 'projection' || type == 'session/projection') {
            _handleProjection(frame);
            return;
          }
        }
        if (frame.rpcId == 'workspace-follow' ||
            type == 'baseline' ||
            type == 'upsert' ||
            type == 'remove' ||
            type == 'order' ||
            type == 'archived') {
          _handleWorkspaceFollowFrame(frame);
          return;
        }
        if (type == 'session/projection' || type == 'projection') {
          _handleProjection(frame);
          return;
        }
        if (frame.rpcId.startsWith('session-follow-')) {
          final streamSessionId = frame.rpcId.substring(
            'session-follow-'.length,
          );
          if (type == 'snapshot') {
            final cursor = wireLong(frame.payload, 'cursor');
            if (cursor >= 0) _sessionCursors[streamSessionId] = cursor;
            final projections = asJsonObject(frame.payload['projections']);
            if (projections != null) {
              final values = asJsonObject(projections['values']);
              if (values != null) {
                _applySessionProjectionValues(
                  streamSessionId,
                  values,
                  wireLong(projections, 'asOfSeq'),
                );
              }
            }
            return;
          }
          if (type == 'event' || type == 'session/event') {
            final event = asJsonObject(frame.payload['event']);
            if (event != null) {
              final eventType = wireString(event, 'type');
              if (eventType == 'turn/start') {
                _updateSessionRunning(streamSessionId, true);
              } else if (eventType == 'turn/end') {
                _updateSessionRunning(streamSessionId, false);
                unawaited(refreshSessions().catchError((_) {}));
              }
            }
          }
        }
        final sessionId = _frameSessionId(frame);
        if (type == 'session/subscribed' && sessionId != null) {
          // New mux-generation baseline, in-band: this frame precedes the
          // generation's replayed requested/queue frames on the same stream
          // (reference api-proxy.ts mux burst), so the previous generation's
          // mirrors drop here — never on the connected publish, which the
          // burst outruns (web SessionManager `session/subscribed` parity).
          _dropGenerationMirrors(sessionId);
        }
        // Registry-global pending-interaction fold: tracked for every
        // session, instantiated or not, before the per-session fan-out
        // (web SessionManager parity — the sidebar's amber dot and
        // approval/plan-review alerts must fire for sessions never opened
        // here). Stable keys make replays
        // idempotent.
        _foldPendingFrame(frame);
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

  /// Drops one session's stale live mirrors at its new generation's
  /// `session/subscribed` boundary: the sidebar pending-status keys (the
  /// burst re-pushes still-pending requests after this frame, so replays
  /// re-track them), and the buffered `session/queue` snapshot — the host
  /// omits the baseline when the queue emptied, so a mirror kept across the
  /// gap would replay stale work on instantiation (web manager.ts:714-732).
  void _dropGenerationMirrors(String sessionId) {
    final hadPending = _pendingBySession.remove(sessionId) != null;
    final buffer = _pendingBuffers[sessionId];
    if (buffer != null) {
      final kept = buffer
          .where((frame) => wireType(frame.payload) != 'session/queue')
          .toList();
      if (kept.isEmpty) {
        _pendingBuffers.remove(sessionId);
      } else if (kept.length != buffer.length) {
        _pendingBuffers[sessionId] = kept;
      }
    }
    if (hadPending) _publishPending();
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

  /// Re-derives the per-session status projection from the key map and
  /// publishes it (list rows read the per-session status).
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
    parentSessionId: session.parentSessionId,
    pendingInteraction: pending ?? session.pendingInteraction,
    completed: session.completed,
  );

  void _handleProjection(ServerRequest frame) {
    final sessionId = _frameSessionId(frame);
    if (sessionId == null) return;
    final seq = wireLong(frame.payload, 'seq');
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
      case 'contextPressure':
        final value = frame.payload['value'];
        ContextPressure? pressure;
        if (value != null && value != 'null') {
          pressure = _parseContextPressureProjection(value);
        }
        _sessionStateFor(sessionId).updateContextPressure(pressure, seq);
      case 'contextBreakdown':
        final value = frame.payload['value'];
        ContextBreakdown? breakdown;
        if (value != null && value != 'null') {
          breakdown = _parseContextBreakdownProjection(value);
        }
        _sessionStateFor(sessionId).updateContextBreakdown(breakdown, seq);
      case 'agentPreset':
        final preset = wireString(frame.payload, 'value');
        _sessions.value = _sessions.value
            .map(
              (item) => item.id == sessionId
                  ? _copySession(item, agentPreset: preset)
                  : item,
            )
            .toList();
      default:
        _onDiagnostic?.call(
          AdapterDiagnostic(
            message: 'Unhandled projection key: ${frame.payload['key']}',
            level: AdapterDiagnosticLevel.debug,
            context: 'mux.projection',
            metadata: <String, Object?>{
              'key': frame.payload['key'],
              'sessionId': sessionId,
            },
          ),
        );
    }
  }

  void _handleControlBaseline(ServerRequest frame) {
    final rawBaseline = asJsonObject(frame.payload['value']) ?? frame.payload;
    final projections = asJsonObject(rawBaseline['projections']);
    if (projections != null) {
      for (final entry in projections.entries) {
        final sessionId = entry.key;
        final block = asJsonObject(entry.value);
        if (block == null) continue;
        final asOfSeq = wireLong(block, 'asOfSeq');
        final values = asJsonObject(block['values']);
        if (values != null) {
          _applySessionProjectionValues(sessionId, values, asOfSeq);
        }
      }
    }
    final queues = asJsonObject(rawBaseline['queues']);
    if (queues != null) {
      for (final entry in queues.entries) {
        final sessionId = entry.key;
        final items = asJsonArray(entry.value);
        if (items != null) {
          final queueFrame = ServerRequest(
            rpcId: 'session-control',
            method: 'session/queue',
            payload: <String, Object?>{
              'type': 'queue',
              'sessionId': sessionId,
              'items': items,
            },
          );
          unawaited(
            _sessionStates[sessionId]?.handleFrame(queueFrame) ??
                Future<void>.value(),
          );
        }
      }
    }
    final jobs = asJsonObject(rawBaseline['jobs']);
    if (jobs != null) {
      for (final entry in jobs.entries) {
        final sessionId = entry.key;
        final jobsList = asJsonArray(entry.value);
        if (jobsList != null) {
          final jobsFrame = ServerRequest(
            rpcId: 'session-control',
            method: 'session/jobs',
            payload: <String, Object?>{
              'type': 'jobs',
              'sessionId': sessionId,
              'jobs': jobsList,
            },
          );
          unawaited(
            _sessionStates[sessionId]?.handleFrame(jobsFrame) ??
                Future<void>.value(),
          );
        }
      }
    }
  }

  void _applySessionProjectionValues(
    String sessionId,
    JsonMap values,
    int seq,
  ) {
    final pressureValue = values['contextPressure'];
    if (pressureValue != null && pressureValue != 'null') {
      final pressure = _parseContextPressureProjection(pressureValue);
      _sessionStateFor(sessionId).updateContextPressure(pressure, seq);
    }
    final breakdownValue = values['contextBreakdown'];
    if (breakdownValue != null && breakdownValue != 'null') {
      final breakdown = _parseContextBreakdownProjection(breakdownValue);
      _sessionStateFor(sessionId).updateContextBreakdown(breakdown, seq);
    }
    if (values.containsKey('plan')) {
      final planValue = values['plan'];
      _planProjectionStateFor(sessionId)
          .value = (planValue != null && planValue != 'null')
          ? _parsePlanProjection(planValue)
          : null;
    }
    if (values.containsKey('todos')) {
      final todosValue = values['todos'];
      _todoProjectionStateFor(sessionId)
          .value = (todosValue != null && todosValue != 'null')
          ? _parseTodosProjection(todosValue)
          : const <TodoItem>[];
    }
    if (values.containsKey('goal')) {
      final goalValue = values['goal'];
      _goalProjectionStateFor(sessionId)
          .value = (goalValue != null && goalValue != 'null')
          ? _parseGoalProjection(goalValue)
          : null;
    }
    final permValue = values['permissions'];
    if (permValue != null && permValue != 'null') {
      final obj = asJsonObject(permValue);
      if (obj != null) {
        final select = _tryDecode(
          () => _toDomainPermissionSelect(PermissionSelectWire.fromJson(obj)),
          'permissions',
        );
        _permissionProjectionStateFor(sessionId).value = select;
      }
    }
    final titleValue = wireString(values, 'title');
    if (titleValue != null && titleValue != 'null') {
      _sessions.value = _sessions.value
          .map(
            (item) => item.id == sessionId
                ? _copySession(item, title: titleValue)
                : item,
          )
          .toList();
    }
    final presetValue = wireString(values, 'agentPreset');
    if (presetValue != null && presetValue != 'null') {
      _sessions.value = _sessions.value
          .map(
            (item) => item.id == sessionId
                ? _copySession(item, agentPreset: presetValue)
                : item,
          )
          .toList();
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

  void _handleWorkspaceFollowFrame(ServerRequest frame) {
    final type = wireString(frame.payload, 'type');
    switch (type) {
      case 'baseline':
        final value = asJsonObject(frame.payload['value']) ?? frame.payload;
        final listing = WorkspaceListValueWire.fromJson(value);
        _applyWorkspaceListing(listing);
      case 'upsert':
        _applyWorkspaceChanged(frame);
        unawaited(refreshSessions().catchError((_) {}));
      case 'remove':
        _applyWorkspaceRemoved(frame);
        unawaited(refreshSessions().catchError((_) {}));
      case 'order':
        _applyWorkspaceOrderFrame(frame);
      case 'archived':
        final archived = _stringSet(frame.payload['archivedSessionIds']);
        _archivedSessionIds.value = archived;
    }
  }

  void _inferWorkspacesFromSessionsIfEmpty(List<SessionWire> listing) {
    if (_workspaces.value.isNotEmpty) return;
    final map = <String, List<String>>{};
    for (final s in listing) {
      final cwd = s.cwd;
      if (cwd != null && cwd.isNotEmpty) {
        map.putIfAbsent(cwd, () => <String>[]).add(s.sessionId);
      }
    }
    if (map.isEmpty) return;
    final inferred = map.entries.map((entry) {
      final path = entry.key;
      final segments = path
          .split(RegExp(r'[/\\]'))
          .where((s) => s.isNotEmpty)
          .toList();
      final title = segments.isNotEmpty ? segments.last : path;
      return WorkspaceSummary(
        workspaceId: 'ws-inferred-${path.hashCode}',
        title: title,
        path: path,
        sessionIds: entry.value,
      );
    }).toList();
    _workspaces.value = inferred;
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
      // The only out-of-band prep left is the per-session window re-arm.
      // Every live mirror (pending statuses, the queue projection and the
      // queue entries in the frame buffer) re-baselines in-band on the
      // generation's `session/subscribed` frames: `DshConnectionManager`
      // forwards the mux-open burst before this connected publish, so
      // clearing here would race — and wipe — a baseline that already
      // landed (web author comment, reference session.ts:419-426).
      for (final state in _sessionStates.values) {
        state.prepareResync();
      }
      // Web SessionManager `handleConnected` parity: the list pull and every
      // opened window's rebuild fire concurrently, so a slow history load on
      // one session no longer holds back the roster or the other sessions'
      // re-release from `_pending`. The generation snapshot is taken up
      // front: a session instantiated during recovery loads through its own
      // `openSession`, never through this loop. Each per-session load stays
      // on that session's `_mutex`; the resync mutex still serializes
      // generations, and this action awaits the whole batch, so a following
      // generation's prep never overlaps an in-flight branch.
      final states = _sessionStates.values.toList();
      await Future.wait<void>(<Future<void>>[
        () async {
          try {
            await refreshSessions();
            await refreshWorkspaces();
          } catch (_) {
            // List failure does not block timeline recovery.
          }
        }(),
        for (final state in states)
          () async {
            try {
              await state.ensureLoaded(
                (beforeSeq) => _loadHistory(state.sessionId, beforeSeq),
              );
            } catch (_) {
              // Pending state retries on the next generation.
            }
          }(),
      ]);
    });
  }

  // -----------------------------------------------------------------------
  // Wire helpers
  // -----------------------------------------------------------------------

  Future<RpcResult> _call(String endpoint, String method, JsonMap payload) {
    return _invoker.call(endpoint, payload);
  }

  Future<List<SessionSummary>> _loadSessions() async {
    final value = await _call(
      DshRpcEndpoints.sessionList,
      DshRpcEndpoints.sessionList,
      <String, Object?>{},
    ).valueOrThrow();
    final listing = decodeSessionListValue(value);
    _inferWorkspacesFromSessionsIfEmpty(listing);
    for (final session in listing) {
      if (session.asOfSeq >= 0) {
        _sessionCursors[session.sessionId] = session.asOfSeq;
      }
      final values = session.projectionValues;
      if (values != null) {
        _applySessionProjectionValues(
          session.sessionId,
          values,
          session.asOfSeq,
        );
      }
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
    _prevRunningBySession.removeWhere(
      (sessionId, _) => !liveIds.contains(sessionId),
    );
    if (pendingChanged) {
      _pendingInteractions.value = _projectPending();
    }
    // Web SessionManager `syncCompletedNotifications` parity: the
    // running→idle edge folds on every observation source, not only on
    // `host/session-status` frames. A pull arriving after the turn
    // finished (WS gap, app process death) arms the reminder, and a
    // session running at the first observation records its baseline so
    // its later completion frame arms. The first observation seeds only.
    final armedByPull = <String>{};
    for (final session in listing) {
      final wasRunning = _prevRunningBySession[session.sessionId];
      if (wasRunning == null) {
        _prevRunningBySession[session.sessionId] = session.running;
        continue;
      }
      if (wasRunning && !session.running) {
        if (session.sessionId != _openSessionId) {
          armedByPull.add(session.sessionId);
        }
      }
      _prevRunningBySession[session.sessionId] = session.running;
    }
    // A list refresh rebuilds from the wire summaries, which carry no
    // completion fact — preserve the folded bit for sessions that still
    // hold it (web SessionManager keeps completedNotifications across
    // list pulls), extend it with the edges this pull armed, and clear it
    // wherever the wire reports the session running again (web
    // `else if (s.running)` — the same rule the frame handler applies).
    final completedById = <String, bool>{
      for (final item in _sessions.value)
        if (item.completed) item.id: true,
    };
    final result = listing.map((wire) {
      final session = _toDomainSession(wire);
      final armed =
          (completedById[session.id] ?? false) ||
          armedByPull.contains(session.id);
      return armed && !session.running
          ? _copySession(session, completed: true)
          : session;
    }).toList();
    return result;
  }

  /// Rebuilds the per-session projection the list rows read. Web
  /// SessionManager `buildListSnapshot` (sessions/manager.ts:1033-1039)
  /// takes the first non-approval status, falling back to the first:
  /// the composer answers questions ahead of approvals, so the sidebar
  /// dot names the interaction the user can act on.
  Map<String, SessionPendingInteraction> _projectPending() {
    final next = <String, SessionPendingInteraction>{};
    for (final entry in _pendingBySession.entries) {
      final statuses = entry.value.values;
      if (statuses.isEmpty) continue;
      next[entry.key] = statuses.firstWhere(
        (status) => status != SessionPendingInteraction.approval,
        orElse: () => statuses.first,
      );
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
    parentSessionId: wire.parentSessionId,
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
    final throughSeq = beforeSeq ?? _sessionCursors[sessionId] ?? 999999999;
    final value = await _call(
      DshRpcEndpoints.sessionPage,
      DshRpcEndpoints.sessionPage,
      {
        'request': <String, Object?>{
          'address': <String, Object?>{
            'kind': 'session',
            'sessionId': sessionId,
          },
          'throughSeq': throughSeq,
          if (beforeSeq != null) 'beforeSeq': beforeSeq,
          'maxMessages': _historyPageMessages,
        },
      },
    ).valueOrThrow();
    final history = SessionHistoryValueWire.fromJson(value);
    if (beforeSeq == null) {
      if (history.asOfSeq >= 0) {
        _sessionCursors[sessionId] = history.asOfSeq;
      } else if (history.events.isNotEmpty) {
        final lastSeq = wireLong(history.events.last, 'seq');
        _sessionCursors[sessionId] = lastSeq;
      } else {
        _sessionCursors[sessionId] = -1;
      }
    }
    final pv = history.projectionValues;
    if (pv != null) {
      if (pv.containsKey('goal')) {
        final goalValue = pv['goal'];
        _goalProjectionStateFor(sessionId)
            .value = (goalValue != null && goalValue != 'null')
            ? _parseGoalProjection(goalValue)
            : null;
      }
      if (pv.containsKey('plan')) {
        final planValue = pv['plan'];
        _planProjectionStateFor(sessionId)
            .value = (planValue != null && planValue != 'null')
            ? _parsePlanProjection(planValue)
            : null;
      }
      if (pv.containsKey('todos')) {
        final todosValue = pv['todos'];
        _todoProjectionStateFor(sessionId)
            .value = (todosValue != null && todosValue != 'null')
            ? _parseTodosProjection(todosValue)
            : const <TodoItem>[];
      }
      final presetValue = wireString(pv, 'agentPreset');
      if (presetValue != null && presetValue != 'null') {
        _sessions.value = _sessions.value
            .map(
              (item) => item.id == sessionId
                  ? _copySession(item, agentPreset: presetValue)
                  : item,
            )
            .toList();
      }
    }
    final pressureValue = history.projectionValues?['contextPressure'];
    if (pressureValue != null) {
      final pressure = _parseContextPressureProjection(pressureValue);
      _sessionStateFor(sessionId)
          .updateContextPressure(pressure, history.asOfSeq);
    }
    final breakdownValue = history.projectionValues?['contextBreakdown'];
    if (breakdownValue != null) {
      final breakdown = _parseContextBreakdownProjection(breakdownValue);
      _sessionStateFor(sessionId)
          .updateContextBreakdown(breakdown, history.asOfSeq);
    }
    return _HistoryPage(events: history.events, hasMore: history.hasMore);
  }

  ContextPressure? _parseContextPressureProjection(Object? value) {
    if (value == null || value == 'null') return null;
    return _tryDecode(() => decodeContextPressureProjection(value));
  }

  ContextBreakdown? _parseContextBreakdownProjection(Object? value) {
    if (value == null || value == 'null') return null;
    return _tryDecode(() => decodeContextBreakdownProjection(value));
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

  String? _frameSessionId(ServerRequest frame) {
    if (frame.rpcId.startsWith('session-follow-')) {
      return frame.rpcId.substring('session-follow-'.length);
    }
    return wireString(frame.payload, 'sessionId') ??
        wireString(
          asJsonObject(frame.payload['value']) ?? const {},
          'sessionId',
        );
  }

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
    parentSessionId: session.parentSessionId,
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
        final buffer = _pendingBuffers.putIfAbsent(
          sessionId,
          () => <ServerRequest>[],
        );
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

  T? _tryDecode<T>(T Function() decode, [String? context]) {
    try {
      return decode();
    } on FormatException catch (e, st) {
      _onDiagnostic?.call(
        AdapterDiagnostic(
          message: 'FormatException in ${context ?? T}: $e',
          level: AdapterDiagnosticLevel.error,
          context: context,
          error: e,
          stackTrace: st,
        ),
      );
      return null;
    } on TypeError catch (e, st) {
      _onDiagnostic?.call(
        AdapterDiagnostic(
          message: 'TypeError in ${context ?? T}: $e',
          level: AdapterDiagnosticLevel.error,
          context: context,
          error: e,
          stackTrace: st,
        ),
      );
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
  int _contextPressureSeq = -1;
  int _contextBreakdownSeq = -1;
  final StateStream<SessionWindowStats> sessionStats =
      StateStream<SessionWindowStats>(const SessionWindowStats());
  final SessionStatsFold _statsFold = SessionStatsFold();
  final Mutex _mutex = Mutex();
  late final TimelineReducer _reducer = TimelineReducer(sessionId);
  bool _ready = false;
  bool _loading = false;
  bool _hasMoreOlder = false;
  bool _loadingOlder = false;
  List<JsonMap> _history = <JsonMap>[];
  List<ServerRequest> _pending = <ServerRequest>[];
  List<ServerRequest> _framesAfterOpen = <ServerRequest>[];

  void updateContextPressure(ContextPressure? value, int seq) {
    if (seq < _contextPressureSeq) return;
    _contextPressureSeq = seq;
    contextPressure.value = value;
  }

  void updateContextBreakdown(ContextBreakdown? value, int seq) {
    if (seq < _contextBreakdownSeq) return;
    _contextBreakdownSeq = seq;
    contextBreakdown.value = value;
  }

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
        _history = stableSortedBy(
          page.events,
          (event) => wireLong(event, 'seq'),
        );
        _hasMoreOlder = page.hasMore;
        // Reuse the reducer across the rebuild: its queue mirror is a live
        // baseline the host only pushes once per generation, so a fresh
        // instance would silently empty the dock (see TimelineReducer.reset).
        _reducer.reset(_history);
        _statsFold.reset(_history);
        _framesAfterOpen = List.of(_pending);
        for (final frame in _pending) {
          _reducer.ingestFrame(frame);
          if (wireType(frame.payload) == 'session/event') {
            _statsFold.ingestEvent(frame.payload['event']);
          }
        }
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
    _contextPressureSeq = -1;
    _contextBreakdownSeq = -1;
    // `_framesAfterOpen` keeps its stale entries on purpose: after this prep
    // every arriving frame parks in `_pending` until `ensureLoaded` replaces
    // the list with the replayed generation's frames, so no out-of-band
    // truncation is needed — and a queue baseline that rode the list no
    // longer lives there at all (it survives the rebuild inside the
    // reducer's mirror).
  }

  Future<void> handleFrame(ServerRequest frame) {
    return _mutex.synchronized<void>(() async {
      if (!_ready) {
        _pending.add(frame);
        return;
      }
      _reducer.ingestFrame(frame);
      final frameType = wireType(frame.payload);
      if (frameType == 'session/event' || frameType == 'event') {
        _statsFold.ingestEvent(frame.payload['event']);
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
    final type = wireType(frame.payload);
    if (type != 'session/event' && type != 'event') return false;
    final event = asJsonObject(frame.payload['event']);
    if (event == null || wireType(event) != 'assistant/chunk') return false;
    final chunk = asJsonObject(
      (asJsonObject(event['data']) ?? const <String, Object?>{})['chunk'],
    );
    final chunkType = chunk == null ? null : wireType(chunk);
    return chunkType != null && chunkType != 'finish' && chunkType != 'usage';
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
    _reducer.reset(_history);
    _statsFold.reset(_history);
    for (final frame in _framesAfterOpen) {
      _reducer.ingestFrame(frame);
      if (wireType(frame.payload) == 'session/event') {
        _statsFold.ingestEvent(frame.payload['event']);
      }
    }
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
