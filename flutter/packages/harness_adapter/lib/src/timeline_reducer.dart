/// Incremental, seq-ordered reducer: raw dsh session events -> immutable
/// [TimelineItem] snapshot.
///
/// History replay and live frames meet at the same `lastSeq` boundary, so
/// an event already folded by a history page is never applied twice.
library;

import 'dart:convert';

import 'package:domain/model/attachment.dart';
import 'package:domain/model/chat_message.dart';
import 'package:domain/model/jobs.dart';
import 'package:domain/model/sandbox.dart';
import 'package:domain/model/schedule.dart';
import 'package:domain/model/session.dart';
import 'package:domain/model/timeline_item.dart';
import 'package:domain/model/token_usage.dart';
import 'package:network/rpc_envelope.dart';

import 'adapter_diagnostics.dart';
import 'dsh_wire_types.dart';
import 'rpc_map.dart';
import 'session_event_payloads.dart';
import 'wire_json.dart';

class TimelineReducer {
  TimelineReducer(this.sessionId, {this.onDiagnostic});

  final String sessionId;

  /// Reports a wire event type this fold does not know. The fold stays a
  /// permissive project-onto-the-timeline pass — an unknown type contributes
  /// no item rather than throwing — but it is never silent: the gap must be
  /// visible so wire coverage can be measured. Mirrors the `mux.projection`
  /// diagnostic's level, context and metadata posture.
  final AdapterDiagnosticListener? onDiagnostic;

  final List<TimelineItem> _items = <TimelineItem>[];
  int _lastSeq = -1;
  String? _partialKey;
  int _partialIndex = -1;
  final Set<int> _seenTurns = <int>{};
  bool _hasSeenInitialSystemPrompt = false;

  /// Latest entered step per turn, from `step/start`. Tool events carry their
  /// own `step` on the wire; this map serves the code-dispatch sub-calls,
  /// whose `tool/ptc-dispatch-start` payload carries the pairing ids and name
  /// but no step.
  final Map<int, int> _stepByTurn = <int, int>{};

  /// Logged time of each `step/start`, keyed `turn:step`: the reference's
  /// `stepStartTime` (`ui-chat` assistant node
  /// `stepStartTime: context.start?.event.time`), the minuend of its TTFT
  /// reading. Absent for a step whose start fell outside the folded window.
  final Map<String, int> _stepStartedAtMs = <String, int>{};

  /// Session-level facts folded alongside the timeline: the effective
  /// sandbox mode (`sandbox/mode`), the active schedule reminders
  /// (`schedule/change`), and the durable workflow runs (`tool-workflow/*`).
  /// A fact change bumps [factsRevision] so the repository publishes only
  /// when something moved.
  SandboxModeFact? _sandboxMode;
  final List<ScheduleReminder> _schedules = <ScheduleReminder>[];
  final Map<String, _WorkflowState> _workflows = <String, _WorkflowState>{};
  final Map<String, List<_WorkflowUpdate>> _pendingWorkflowUpdates =
      <String, List<_WorkflowUpdate>>{};

  /// Seq of the latest `turn/end`; a workflow run whose start precedes it and
  /// which never logged a terminal event presents as interrupted.
  int _lastTurnEndSeq = -1;
  int _factsRevision = 0;

  /// Monotonic revision of the sandbox/schedule facts; the repository
  /// compares it to decide whether to republish.
  int get factsRevision => _factsRevision;

  /// The session's latest `sandbox/mode` override, or null when the session
  /// logged none (the deployment default applies).
  SandboxModeFact? get sandboxMode => _sandboxMode;

  /// The session's active durable reminders, in original create order.
  List<ScheduleReminder> get schedules =>
      List<ScheduleReminder>.unmodifiable(_schedules);

  /// The streaming partial accumulates into buffers: one delta is one
  /// O(delta) append, and the [ChatMessage] string is materialized only
  /// when a snapshot reads it. Concatenating an immutable string per
  /// delta is quadratic in the final message length — a huge streamed
  /// reply re-copied the whole text on every chunk.
  StringBuffer? _partialText;
  StringBuffer? _partialReasoning;
  int? _partialReasoningStartMs;
  Duration? _partialReasoningDuration;

  /// Timestamp of the open partial's first streamed token delta.
  int? _partialFirstTokenMs;
  bool _partialDirty = false;

  void reset(List<JsonMap> history) {
    // The queue projection is not durable history: `session/queue` snapshots
    // never land in the session log, and the host pushes a session's baseline
    // exactly once per mux generation, right after its `session/subscribed`
    // frame. A rebuild that drops the mirror leaves the dock empty until the
    // next reconnect (web `Session.resync` keeps its queueMirror for the same
    // reason — reference session.ts:419-426). The mirror is re-baselined
    // in-band by the next `session/subscribed` frame, never here.
    TimelineQueue? queueMirror;
    // A pending request is live state too, not history: `approval/requested`
    // and `question/requested` never land in the session log, and the host
    // re-sends a still-pending request only on a new mux generation. A
    // rebuild that drops one takes the reader's only way to answer off the
    // screen until the next reconnect — the runtime keeps its `PendingWait`
    // carrier alive across the same rebuild for the same reason
    // (manager.ts `pendingInteractions`). A frame replayed after the reset
    // upserts by the same key, so nothing is duplicated.
    final liveWaits = <TimelineItem>[];
    for (final item in _items) {
      if (item is TimelineQueue) {
        queueMirror ??= item;
      } else if (item is TimelineApprovalRequest ||
          item is TimelineQuestionRequest) {
        liveWaits.add(item);
      }
    }
    _items.clear();
    _lastSeq = -1;
    _clearPartial();
    _seenTurns.clear();
    _stepByTurn.clear();
    _stepStartedAtMs.clear();
    _hasSeenInitialSystemPrompt = false;
    _sandboxMode = null;
    _schedules.clear();
    _workflows.clear();
    _pendingWorkflowUpdates.clear();
    _lastTurnEndSeq = -1;
    _factsRevision++;
    final sorted = List<JsonMap>.of(history)
      ..sort((a, b) => wireLong(a, 'seq').compareTo(wireLong(b, 'seq')));
    for (final event in sorted) {
      _ingestEvent(event);
    }
    if (queueMirror != null) _items.add(queueMirror);
    _items.addAll(liveWaits);
  }

  List<TimelineItem> snapshot() {
    if (_partialDirty) {
      _materializePartial();
    }
    return List<TimelineItem>.unmodifiable(_items);
  }

  void ingestFrame(ServerRequest envelope) {
    final frame = envelope.payload;
    switch (wireType(frame)) {
      case 'session/subscribed':
        // New mux-generation baseline: the host pushes this session's queue
        // snapshot after this frame on the same stream (api-proxy.ts mux
        // burst), so the stale mirror clears here — race-free against the
        // connected publish (web session.ts:482-490 parity: the mirror
        // re-baselines on the session/subscribed frame).
        _removeByKey('queue');
      case 'event':
      case 'session/event':
        final event = asJsonObject(frame['event']);
        if (event != null) _ingestEvent(event);
      case 'approval/requested':
        final approvalId = wireString(frame, 'approvalId') ?? envelope.rpcId;
        _upsertByKey(
          key: 'approval:$approvalId',
          item: TimelineApprovalRequest(
            requestId: envelope.rpcId,
            sessionId: wireString(frame, 'sessionId') ?? sessionId,
            approvalId: approvalId,
            toolName: wireString(frame, 'toolName') ?? 'unknown',
            callId: wireString(frame, 'callId'),
            reason: wireString(frame, 'reason'),
          ),
        );
      case 'approval/resolved':
        _removeByKey('approval:${wireString(frame, 'approvalId')}');
      case 'question/requested':
        final questionArray = asJsonArray(frame['questions']);
        final questions =
            questionArray
                ?.map((entry) => asJsonObject(entry))
                .whereType<JsonMap>()
                .map(_toQuestionItem)
                .whereType<QuestionItem>()
                .toList() ??
            <QuestionItem>[];
        _upsertByKey(
          key: 'question:${envelope.rpcId}',
          item: TimelineQuestionRequest(
            requestId: envelope.rpcId,
            questions: questions,
          ),
        );
      case 'question/resolved':
        _removeByKey('question:${wireString(frame, 'questionRpcId')}');
      case 'queue':
      case 'session/queue':
        // The whole-snapshot items array is required by the wire contract
        // (muxFrameSchema: `items` is a non-optional array; an emptied queue
        // still sends `[]`), so its absence is host breakage, not an empty
        // queue.
        final queueArray = asJsonArray(frame['items']);
        if (queueArray == null) {
          throw const FormatException(
            'session/queue frame missing required field "items"',
          );
        }
        final queueItems = <SessionQueueItem>[];
        for (final entry in queueArray) {
          final obj = asJsonObject(entry);
          if (obj == null) {
            throw const FormatException(
              'session/queue frame "items" entry is not an object',
            );
          }
          queueItems.add(_toQueueItem(obj));
        }
        _upsertByKey(
          key: 'queue',
          item: TimelineQueue(items: queueItems),
        );
      case 'jobs':
      case 'session/jobs':
        final jobsArray = asJsonArray(frame['jobs']);
        final jobs =
            jobsArray
                ?.map((entry) => asJsonObject(entry))
                .whereType<JsonMap>()
                .map(_toJobView)
                .whereType<JobView>()
                .toList() ??
            <JobView>[];
        _upsertByKey(
          key: 'jobs',
          item: TimelineJobs(jobs: jobs),
        );
    }
  }

  void _ingestEvent(JsonMap event) {
    final seq = wireLong(event, 'seq');
    if (seq <= _lastSeq) return;
    _lastSeq = seq;

    final type = wireType(event);
    switch (type) {
      case 'turn/start':
        _appendTurnStart(event);
      case 'step/start':
        _recordStepStart(event);
      case 'compaction/summary':
        _appendCompaction(event);
      case 'command/run':
        _appendCommandRun(event);
      case 'command/done':
        _resolveCommandDone(event);
      case 'system/message':
        _appendSystemMessage(event);
      case 'user/message':
        _appendUserMessage(event);
      case 'assistant/message':
        _appendAssistantFinal(event);
      case 'assistant/chunk':
        _appendAssistantDelta(event);
      case 'tool/call':
        _appendToolCall(event);
      case 'tool/result':
        _appendToolResult(event);
      case 'tool/ptc-dispatch-start':
        _appendPtcDispatchStart(event);
      case 'tool/ptc-dispatch':
        _resolvePtcDispatch(event);
      case 'hook/invoked':
        _appendHookInvoked(event);
      case 'hook/result':
        _resolveHookResult(event);
      case 'tool-workflow/run-start':
        _startWorkflowRun(event);
      case 'tool-workflow/agent-start':
      case 'tool-workflow/agent-end':
      case 'tool-workflow/run-end':
        _updateWorkflowRun(event);
      case 'sandbox/mode':
        _sandboxMode = decodeSandboxModeEvent(_eventData(event));
        _factsRevision++;
      case 'schedule/change':
        _applyScheduleChange(decodeScheduleChange(_eventData(event)));
        _factsRevision++;
      case 'turn/end':
        _appendTurnEnd(event);
      default:
        // The dsh `SessionEventMap` is merge-extensible (the reference
        // switches closed unions with `assertNever` and merge-extensible
        // unions through a documented default), so an unrecognised wire type
        // is expected input, not a client bug: the fold publishes no item for
        // it. Reporting it is what keeps a parity gap measurable — a silent
        // drop here is invisible. Only the type and `seq` travel; the payload
        // can carry user text and stays out.
        onDiagnostic?.call(
          AdapterDiagnostic(
            message:
                'Unrecognised session event type "$type" at seq $seq — no '
                'timeline fold; wire coverage gap',
            level: AdapterDiagnosticLevel.debug,
            context: 'timeline.event',
            metadata: <String, Object?>{
              'type': type,
              'seq': seq,
              'sessionId': sessionId,
            },
          ),
        );
    }
  }

  void _appendTurnStart(JsonMap event) {
    final turn = wireLong(_eventData(event), 'turn');
    if (turn <= 0 || !_seenTurns.add(turn)) return;
    _finalizePartial();
    _items.add(TimelineTurnBoundary(turn, startedAtEpochMs: _eventTime(event)));
  }

  /// Records the turn's latest entered step (`step/start`) so later events
  /// that omit a step — code-dispatch sub-calls — can be placed in the
  /// ledger's step structure, and records the step's logged time so an
  /// assistant row can carry the reference's `stepStartTime`. The marker
  /// itself publishes no row: steps are a fact of the rows inside them, and
  /// a row-less marker would add ledger noise without a reader action.
  void _recordStepStart(JsonMap event) {
    final data = _eventData(event);
    final turn = wireLong(data, 'turn');
    final step = wireLong(data, 'step');
    if (turn <= 0 || step <= 0) return;
    _stepByTurn[turn] = step;
    final time = _eventTime(event);
    if (time != null) _stepStartedAtMs[_turnStepKey(turn, step)] = time;
  }

  /// A summary shadows its range; the marker captures counts and optional summary.
  void _appendCompaction(JsonMap event) {
    final data = _eventData(event);
    final int? shadowedCount;
    if (data.containsKey('shadowedSeqs')) {
      final raw = data['shadowedSeqs'];
      if (raw is! List) {
        throw const FormatException(
          'compaction/summary "shadowedSeqs" must be an array',
        );
      }
      for (final item in raw) {
        if (item is! int || item < 0) {
          throw const FormatException(
            'compaction/summary "shadowedSeqs" entries must be non-negative integers',
          );
        }
      }
      shadowedCount = raw.length;
    } else {
      shadowedCount = null;
    }

    final int? shadowedTokens;
    if (data.containsKey('shadowedTokenCount')) {
      final raw = data['shadowedTokenCount'];
      if (raw is! num ||
          raw < 0 ||
          (raw is double && raw != raw.truncateToDouble())) {
        throw const FormatException(
          'compaction/summary "shadowedTokenCount" must be a non-negative integer',
        );
      }
      shadowedTokens = raw.toInt();
    } else {
      shadowedTokens = null;
    }

    final String? summaryText;
    if (data.containsKey('summary')) {
      final raw = data['summary'];
      if (raw is! List) {
        throw const FormatException(
          'compaction/summary "summary" must be an array',
        );
      }
      final buffer = StringBuffer();
      for (final block in raw) {
        final blockObj = asJsonObject(block);
        if (blockObj != null && wireType(blockObj) == 'text') {
          final text = wireString(blockObj, 'text');
          if (text != null) buffer.write(text);
        }
      }
      final str = buffer.toString();
      summaryText = str.trim().isEmpty ? null : str;
    } else {
      summaryText = null;
    }

    _items.add(
      TimelineCompaction(
        id: 'compaction:$_lastSeq',
        shadowedCount: shadowedCount,
        shadowedTokens: shadowedTokens,
        summary: summaryText,
      ),
    );
  }

  /// Opens the command card (wire `command/run`: `{commandId, name, args?,
  /// source}` — a direct log-only append, no turn wraps it).
  void _appendCommandRun(JsonMap event) {
    final data = _eventData(event);
    final commandId = wireString(data, 'commandId');
    if (commandId == null) return;
    _upsertCommand(
      TimelineCommand(
        commandId: commandId,
        name: wireString(data, 'name') ?? 'unknown',
        args: wireString(data, 'args'),
        status: CommandRunStatus.running,
      ),
    );
  }

  /// Resolves the card in place by `commandId` (wire `command/done`:
  /// `{commandId, kind: 'success'|'error', text?}`). A done whose run fell
  /// outside the folded window (e.g. the command started before replay)
  /// appends the settled card rather than losing the outcome.
  void _resolveCommandDone(JsonMap event) {
    final data = _eventData(event);
    final commandId = wireString(data, 'commandId');
    if (commandId == null) return;
    final kind = wireString(data, 'kind');
    final existing = _commandAt(commandId);
    _upsertCommand(
      TimelineCommand(
        commandId: commandId,
        name: existing?.name ?? 'unknown',
        args: existing?.args,
        status: kind == 'success'
            ? CommandRunStatus.success
            : CommandRunStatus.failed,
        text: wireString(data, 'text'),
      ),
    );
  }

  void _upsertCommand(TimelineCommand item) {
    for (var i = 0; i < _items.length; i++) {
      final current = _items[i];
      if (current is TimelineCommand && current.commandId == item.commandId) {
        _items[i] = item;
        return;
      }
    }
    _items.add(item);
  }

  TimelineCommand? _commandAt(String commandId) {
    for (final item in _items) {
      if (item is TimelineCommand && item.commandId == commandId) return item;
    }
    return null;
  }

  void _appendSystemMessage(JsonMap event) {
    _finalizePartial();
    final seq = wireLong(event, 'seq');
    final data = _eventData(event);
    final message = asJsonObject(data['message']);
    final promptText = message != null ? _extractText(message) : '';

    // Node 0 is the initial system prompt in Session V3; it is model configuration,
    // not user-visible conversation transcript.
    if (seq == 0 || (!_hasSeenInitialSystemPrompt && _items.isEmpty)) {
      _hasSeenInitialSystemPrompt = true;
      return;
    }
    _hasSeenInitialSystemPrompt = true;

    // An in-history system prompt update (appended mid-conversation) is presented
    // as an inspectable context injection notice.
    _items.add(
      TimelineContextInjection(
        id: 'system-prompt:$seq',
        text: promptText,
        producerLabel: 'system-prompt',
        summary: 'System prompt updated',
      ),
    );
  }

  void _appendUserMessage(JsonMap event) {
    _finalizePartial();
    final data = _eventData(event);
    final messageId = wireString(data, 'id') ?? 'user:$_lastSeq';
    // Web message.ts classifier: a `user/message` whose durable source
    // kind is not `user` is injected context (goal snapshots, skill
    // invocations, workspace instructions, plugin catalogs, recalls),
    // never a user bubble.
    final source = asJsonObject(data['source']);
    final kind = wireString(source ?? const <String, Object?>{}, 'kind');
    if (kind == 'plugin' &&
        wireString(source ?? const <String, Object?>{}, 'plugin') ==
            'compact' &&
        wireString(source ?? const <String, Object?>{}, 'compactionId') !=
            null) {
      // Compaction replacement checkpoint user/message: written for model
      // history, not rendered as context injection (compaction/summary
      // already rendered the marker).
      return;
    }
    if (kind != 'user') {
      _items.add(_contextInjection(messageId, data, source, kind));
      return;
    }
    _items.add(
      TimelineMessage(
        ChatMessage(
          id: messageId,
          sessionId: sessionId,
          role: MessageRole.user,
          text: _extractText(data),
          createdAtEpochMs: wireLong(event, 'time'),
          images: _extractImages(data),
          seq: _lastSeq,
        ),
      ),
    );
  }

  /// Web context-provenance projection: the transcript role and the
  /// producer name read from the durable source alone.
  TimelineContextInjection _contextInjection(
    String id,
    JsonMap data,
    JsonMap? source,
    String? kind,
  ) {
    final label = switch (kind) {
      // Cross-session snapshots name the sessions they were read from.
      'session-reference' =>
        _joinedNames(source, 'references', 'label') ?? kind,
      // Workspace instructions name the files they were reconciled from.
      'agent-instructions' => _joinedNames(source, 'changes', 'path') ?? kind,
      'plugin' =>
        (source == null ? null : wireString(source, 'plugin')) ?? kind,
      // A user-explicit skill invocation names the skill it injected.
      'skill-invocation' =>
        (source == null ? null : wireString(source, 'name')) ?? kind,
      // Documented default: an unknown producer identifies itself by its
      // own durable kind; a source with no readable kind has no label.
      final readable? => readable,
      null => null,
    };
    // A notice-form context carries a one-line account shown without
    // expanding the row.
    final summary = source != null && wireString(source, 'form') == 'notice'
        ? wireString(source, 'summary')
        : null;
    return TimelineContextInjection(
      id: id,
      text: _extractText(data),
      producerLabel: label,
      isRecall: kind == 'session-reference',
      summary: summary,
    );
  }

  /// Distinct non-empty `field` values of an array-valued source member,
  /// joined as one label; null when the list is empty (web `collect`).
  String? _joinedNames(JsonMap? source, String member, String field) {
    if (source == null) return null;
    final list = asJsonArray(source[member]);
    if (list == null) return null;
    final names = <String>[];
    for (final entry in list) {
      final record = asJsonObject(entry);
      final value = record == null ? null : wireString(record, field);
      if (value != null && !names.contains(value)) names.add(value);
    }
    return names.isEmpty ? null : names.join(', ');
  }

  void _appendAssistantFinal(JsonMap event) {
    final data = _eventData(event);
    final turn = wireLong(data, 'turn');
    final step = wireLong(data, 'step');
    final message = asJsonObject(data['message']);
    if (message == null) return;
    final reasoning = _extractReasoning(message);
    final matchingPartial = _partialKey == _turnStepKey(turn, step);
    final Duration? reasoningDuration;
    if (reasoning != null || matchingPartial) {
      if (matchingPartial) {
        reasoningDuration = _partialReasoningDuration;
      } else if (_partialReasoningDuration != null) {
        reasoningDuration = _partialReasoningDuration;
      } else {
        reasoningDuration = null;
      }
    } else {
      reasoningDuration = null;
    }

    // The step's token accounting travels with its assistant message
    // (`assistant/message.usage`); the recorded stream carries the only
    // latency boundary the log preserves.
    final usage = decodeTokenUsage(data['usage']);
    final firstTokenAtEpochMs =
        _partialFirstTokenMs ?? assistantStreamFirstTokenTime(data['stream']);
    final finalItem = TimelineMessage(
      ChatMessage(
        id: wireString(message, 'id') ?? 'assistant:$_lastSeq',
        sessionId: sessionId,
        role: MessageRole.assistant,
        text: _extractText(message),
        reasoning: reasoning,
        reasoningDuration: reasoningDuration,
        createdAtEpochMs: wireLong(event, 'time'),
        images: _extractImages(message),
        seq: _lastSeq,
      ),
      step: step,
      usage: usage,
      firstTokenAtEpochMs: firstTokenAtEpochMs,
      stepStartedAtEpochMs: _stepStartedAtMs[_turnStepKey(turn, step)],
    );

    if (matchingPartial) {
      _items[_partialIndex] = finalItem;
      _clearPartial();
    } else {
      _finalizePartial();
      _items.add(finalItem);
    }
  }

  void _appendAssistantDelta(JsonMap event) {
    final data = _eventData(event);
    final turn = wireLong(data, 'turn');
    final step = wireLong(data, 'step');
    final chunk = asJsonObject(data['chunk']);
    if (chunk == null) return;
    _ensurePartial(turn, step, event);

    final chunkType = wireType(chunk);
    final text = _partialText ??= StringBuffer();
    var reasoning = _partialReasoning;

    switch (chunkType) {
      case 'text-delta':
        final delta = wireString(chunk, 'text') ?? '';
        if (delta != '' && _partialFirstTokenMs == null) {
          _partialFirstTokenMs = _streamTime(event);
        }
        text.write(delta);
        _partialDirty = true;
      case 'reasoning-delta':
        if (_partialReasoningStartMs == null) {
          final time = wireLong(event, 'time');
          _partialReasoningStartMs = time > 0
              ? time
              : DateTime.now().millisecondsSinceEpoch;
        }
        final delta = wireString(chunk, 'text') ?? '';
        if (delta != '' && _partialFirstTokenMs == null) {
          _partialFirstTokenMs = _streamTime(event);
        }
        reasoning = (reasoning ??= StringBuffer())..write(delta);
        _partialDirty = true;
      case 'block-start':
        final blockType = wireString(chunk, 'blockType');
        if (blockType == 'reasoning' && _partialReasoningStartMs == null) {
          final time = wireLong(event, 'time');
          _partialReasoningStartMs = time > 0
              ? time
              : DateTime.now().millisecondsSinceEpoch;
        }
      case 'block-end':
        final block = asJsonObject(chunk['block']);
        if (block != null) {
          final blockType = wireType(block);
          if (blockType == 'text') {
            final str = wireString(block, 'text');
            if (str != null) {
              text
                ..clear()
                ..write(str);
            }
          } else if (blockType == 'reasoning') {
            if (_partialReasoningStartMs != null) {
              final time = wireLong(event, 'time');
              final nowMs = time > 0
                  ? time
                  : DateTime.now().millisecondsSinceEpoch;
              final diff = nowMs - _partialReasoningStartMs!;
              if (diff > 0) {
                _partialReasoningDuration = Duration(milliseconds: diff);
              }
            }
            final str = wireString(block, 'text');
            if (str != null) {
              reasoning = (reasoning ??= StringBuffer())
                ..clear()
                ..write(str);
            }
          }
          _partialDirty = true;
        }
      case 'finish':
      case 'usage':
        break;
    }
    _partialText = text;
    _partialReasoning = reasoning;
  }

  void _ensurePartial(int turn, int step, JsonMap event) {
    final key = _turnStepKey(turn, step);
    if (_partialKey == key) return;
    _finalizePartial();
    _partialKey = key;
    _partialIndex = _items.length;
    _partialReasoningStartMs = null;
    _partialReasoningDuration = null;
    _partialFirstTokenMs = null;
    _items.add(
      TimelineMessage(
        ChatMessage(
          id: 'partial-$sessionId-$turn-$step',
          sessionId: sessionId,
          role: MessageRole.assistant,
          text: '',
          streaming: true,
          createdAtEpochMs: wireLong(event, 'time'),
          seq: _lastSeq,
        ),
        step: step,
        stepStartedAtEpochMs: _stepStartedAtMs[_turnStepKey(turn, step)],
      ),
    );
  }

  void _finalizePartial() {
    if (_partialIndex >= 0 && _partialIndex < _items.length) {
      final current = _items[_partialIndex];
      if (current is TimelineMessage && current.value.streaming) {
        _items[_partialIndex] = _partialMessage(streaming: false);
      }
    }
    _clearPartial();
  }

  /// Build the partial's current [ChatMessage] from the buffers; the
  /// item's own fields stand in for parts no chunk has touched yet.
  TimelineMessage _partialMessage({required bool streaming}) {
    final current = _items[_partialIndex] as TimelineMessage;
    final value = current.value;
    return TimelineMessage(
      ChatMessage(
        id: value.id,
        sessionId: value.sessionId,
        role: value.role,
        text: _partialText?.toString() ?? value.text,
        reasoning: _partialReasoning?.toString() ?? value.reasoning,
        reasoningDuration: _partialReasoningDuration ?? value.reasoningDuration,
        streaming: streaming,
        createdAtEpochMs: value.createdAtEpochMs,
        images: value.images,
        seq: value.seq,
      ),
      step: current.step,
      firstTokenAtEpochMs: _partialFirstTokenMs ?? current.firstTokenAtEpochMs,
      stepStartedAtEpochMs: current.stepStartedAtEpochMs,
    );
  }

  /// Fold the buffers into the streaming item (snapshot read path).
  void _materializePartial() {
    if (_partialIndex >= 0 &&
        _partialIndex < _items.length &&
        _items[_partialIndex] is TimelineMessage &&
        (_items[_partialIndex] as TimelineMessage).value.streaming) {
      _items[_partialIndex] = _partialMessage(streaming: true);
    }
    _partialDirty = false;
  }

  void _clearPartial() {
    _partialKey = null;
    _partialIndex = -1;
    _partialText = null;
    _partialReasoning = null;
    _partialReasoningStartMs = null;
    _partialReasoningDuration = null;
    _partialFirstTokenMs = null;
    _partialDirty = false;
  }

  /// Stream timestamp for a latency boundary: the event's logged time, or
  /// the wall clock when the host sent none (a live delta always has one;
  /// the fallback keeps a replayed zero from collapsing a real interval).
  int _streamTime(JsonMap event) {
    final time = wireLong(event, 'time');
    return time > 0 ? time : DateTime.now().millisecondsSinceEpoch;
  }

  void _appendToolCall(JsonMap event) {
    final data = _eventData(event);
    final callId = wireString(data, 'callId') ?? 'tool:$_lastSeq';
    _items.add(
      TimelineToolCall(
        id: callId,
        name: wireString(data, 'name') ?? 'unknown',
        arguments: wireString(data, 'arguments'),
        status: ToolRunStatus.running,
        step: wireLong(data, 'step'),
        startedAtEpochMs: _eventTime(event),
      ),
    );
  }

  /// Opens one nested code-dispatch call (`tool/ptc-dispatch-start`).
  /// The payload carries the pairing ids and the dispatch name; the step
  /// comes from the enclosing turn's latest `step/start`, the only place
  /// it was logged.
  void _appendPtcDispatchStart(JsonMap event) {
    final data = _eventData(event);
    final subCallId = wireString(data, 'subCallId');
    if (subCallId == null) return;
    final parentCallId = wireString(data, 'parentCallId');
    final turn = wireLong(data, 'turn');
    final step = turn > 0
        ? (_stepByTurn[turn] ?? 0)
        : (_stepByTurn.values.isEmpty ? 0 : _stepByTurn.values.last);
    final call = TimelineToolCall(
      id: subCallId,
      name: wireString(data, 'name') ?? 'unknown',
      arguments: _stringifyArguments(data['arguments']),
      status: ToolRunStatus.running,
      step: step,
      parentCallId: parentCallId,
      startedAtEpochMs: _eventTime(event),
    );
    _attachChildCall(call);
  }

  /// Settles one nested call (`tool/ptc-dispatch`): the same
  /// `content` + `isError` vocabulary as `tool/result`, paired by
  /// `subCallId`.
  void _resolvePtcDispatch(JsonMap event) {
    final data = _eventData(event);
    final subCallId = wireString(data, 'subCallId');
    if (subCallId == null) return;
    final isError = wireBool(data, 'isError') || data['error'] != null;
    final name = wireString(data, 'name');
    final result = _extractContentText(data['content']);

    for (var i = 0; i < _items.length; i++) {
      final item = _items[i];
      if (item is! TimelineToolCall) continue;
      if (_findCall(item, subCallId) == null) continue;
      _items[i] = _updateCall(item, subCallId, (call) {
        return _withChildren(
          call,
          call.children,
          name: name,
          result: result,
          isError: isError,
          settle: true,
        );
      });
      return;
    }
    // A dispatch whose start fell outside the folded window (an older page
    // cut between the pair) still settles as its own row: the outcome is a
    // real logged fact and dropping it would hide a finished call.
    _items.add(
      TimelineToolCall(
        id: subCallId,
        name: name ?? 'unknown',
        arguments: _stringifyArguments(data['arguments']),
        result: result,
        isError: isError,
        status: isError ? ToolRunStatus.failed : ToolRunStatus.completed,
        parentCallId: wireString(data, 'parentCallId'),
        startedAtEpochMs: _eventTime(event),
      ),
    );
  }

  /// Inserts [call] under its parent when that parent is loaded, else as a
  /// root row. The host logs a sub-dispatch inside the parent's execution,
  /// so the parent is normally already folded; a window cut that left the
  /// parent out keeps the call visible at the top level.
  void _attachChildCall(TimelineToolCall call) {
    final parentCallId = call.parentCallId;
    if (parentCallId == null) {
      _items.add(call);
      return;
    }
    for (var i = 0; i < _items.length; i++) {
      final item = _items[i];
      if (item is! TimelineToolCall) continue;
      if (_findCall(item, parentCallId) == null) continue;
      _items[i] = _updateCall(
        item,
        parentCallId,
        (node) => _withChildren(node, [...node.children, call]),
      );
      return;
    }
    _items.add(call);
  }

  /// The call with [callId] anywhere in [root]'s subtree, or null.
  TimelineToolCall? _findCall(TimelineToolCall root, String callId) {
    if (root.id == callId) return root;
    for (final child in root.children) {
      final found = _findCall(child, callId);
      if (found != null) return found;
    }
    return null;
  }

  /// Rebuilds [root]'s subtree with [update] applied to the [callId] node.
  /// The caller has already proved the node exists.
  TimelineToolCall _updateCall(
    TimelineToolCall root,
    String callId,
    TimelineToolCall Function(TimelineToolCall) update,
  ) {
    if (root.id == callId) return update(root);
    return _withChildren(root, [
      for (final child in root.children) _updateCall(child, callId, update),
    ]);
  }

  TimelineToolCall _withChildren(
    TimelineToolCall call,
    List<TimelineToolCall> children, {
    String? name,
    String? result,
    bool isError = false,
    bool settle = false,
  }) => TimelineToolCall(
    id: call.id,
    name: name ?? call.name,
    arguments: call.arguments,
    result: settle ? result : call.result,
    isError: settle ? isError : call.isError,
    status: settle
        ? (isError ? ToolRunStatus.failed : ToolRunStatus.completed)
        : call.status,
    step: call.step,
    parentCallId: call.parentCallId,
    children: children,
    startedAtEpochMs: call.startedAtEpochMs,
    presentation: call.presentation,
  );

  /// The logged event time, or null when the host sent none — a start
  /// timestamp is a fact, and 0 would render as 1970 rather than "unknown".
  int? _eventTime(JsonMap event) {
    final time = wireLong(event, 'time');
    return time > 0 ? time : null;
  }

  String? _stringifyArguments(Object? value) {
    if (value == null) return null;
    if (value is String) return value;
    return jsonEncode(value);
  }

  /// Text of a `tool/ptc-dispatch` `content` block list, the same
  /// projection `_collectText` applies to message content.
  String _extractContentText(Object? content) {
    final blocks = asJsonArray(content);
    if (blocks == null) return '';
    final buffer = StringBuffer();
    for (final block in blocks) {
      final obj = asJsonObject(block);
      if (obj == null) continue;
      switch (wireType(obj)) {
        case 'text':
          final text = wireString(obj, 'text');
          if (text != null) buffer.write(text);
        case 'tool-result':
          buffer.write(_collectText(obj));
      }
    }
    return buffer.toString();
  }

  void _appendToolResult(JsonMap event) {
    final data = _eventData(event);
    final toolMessage = asJsonObject(data['message']);
    if (toolMessage == null) return;
    final resultBlock = asJsonObject(
      asJsonArray(toolMessage['content'])?.firstOrNull,
    );
    final callId =
        (resultBlock != null ? wireString(resultBlock, 'toolCallId') : null) ??
        wireString(data, 'callId') ??
        'tool-result:$_lastSeq';
    final resultText = _extractText(toolMessage);

    var index = -1;
    TimelineToolCall? previous;
    for (var i = 0; i < _items.length; i++) {
      final item = _items[i];
      if (item is TimelineToolCall && item.id == callId) {
        index = i;
        previous = item;
        break;
      }
    }

    // dsh writes tool failures in either the `tool/result` event's optional
    // `error` field or the ToolResultBlock's `isError` flag.
    // Non-zero bash/pwsh exit codes are reported as [exit code: N] or [killed by signal: ...].
    final isExitCodeError =
        (previous?.name == 'bash' || previous?.name == 'pwsh') &&
        (resultText.contains(RegExp(r'\[exit code: [1-9]\d*\]')) ||
            resultText.contains('[killed by signal:') ||
            resultText.contains('[sandbox: file access denied'));
    final isError =
        wireBool(toolMessage, 'isError') ||
        (resultBlock != null && wireBool(resultBlock, 'isError')) ||
        data['error'] != null ||
        isExitCodeError;
    final newItem = TimelineToolCall(
      id: callId,
      name: previous?.name ?? 'unknown',
      arguments: previous?.arguments,
      result: resultText,
      isError: isError,
      status: isError ? ToolRunStatus.failed : ToolRunStatus.completed,
      step: previous?.step ?? wireLong(data, 'step'),
      parentCallId: previous?.parentCallId,
      children: previous?.children ?? const <TimelineToolCall>[],
      startedAtEpochMs: previous?.startedAtEpochMs ?? _eventTime(event),
      // The tool's persisted render intent (`output.presentationMeta`); the
      // host's `presentCall`/`presentResult` functions themselves never
      // cross the wire, so this `meta` member is the only structured card
      // data on the result event. A payload with no known card yields null
      // (the reference's generic fallback).
      presentation: decodeToolResultPresentation(data['meta']),
    );
    if (index >= 0) {
      _items[index] = newItem;
    } else {
      _items.add(newItem);
    }
  }

  void _appendTurnEnd(JsonMap event) {
    _finalizePartial();
    // A closed turn is the reference's `locationClosed` signal: a durable
    // workflow run still lacking its terminal event presents as interrupted
    // from here on, without touching the workflow tool's own result row.
    _lastTurnEndSeq = _lastSeq;
    _refreshOpenWorkflows();
    final turn = wireLong(_eventData(event), 'turn');
    final reason = asJsonObject(_eventData(event)['reason']);
    final kind = reason != null ? wireString(reason, 'kind') : null;
    // The item publishes the wire kind plus host-authored detail only —
    // never composed UI copy: the chat surface localizes the known kinds
    // by `code` and falls back to `message` for host error text.
    final String? message;
    switch (kind) {
      case 'error':
        final failure = asJsonObject(reason!['error']);
        message = failure == null ? null : wireString(failure, 'message') ?? '';
      case 'aborted':
      case 'interrupted':
      case 'max-tokens':
      case 'blocked':
        message = null;
      default:
        message = null;
    }
    if (message != null || (kind != null && kind != 'completed')) {
      _items.add(
        TimelineError(
          id: 'turn-end:$_lastSeq',
          message: message ?? '',
          code: kind,
        ),
      );
    }
    _foldTurnUsage(turn, _eventTime(event));
  }

  // -------------------------------------------------------------------------
  // Hook audit (`hook/invoked` + `hook/result` — log-only)
  // -------------------------------------------------------------------------

  /// Opens one hook audit row. The pair is correlated by `handlerId`, the
  /// same pairing the reference's `appendHookResult` uses.
  void _appendHookInvoked(JsonMap event) {
    _items.add(TimelineHookAudit(decodeHookInvoked(_eventData(event))));
  }

  /// Settles the audit row opened by `hook/invoked`. A result whose invoked
  /// half fell outside the folded window is dropped: the pair's dialect is
  /// only on `hook/invoked`, and the reference renders complete pairs.
  void _resolveHookResult(JsonMap event) {
    final data = _eventData(event);
    final handlerId = wireString(data, 'handlerId');
    if (handlerId == null) return;
    for (var i = 0; i < _items.length; i++) {
      final current = _items[i];
      if (current is! TimelineHookAudit) continue;
      if (current.audit.handlerId != handlerId) continue;
      _items[i] = TimelineHookAudit(applyHookResult(current.audit, data));
      return;
    }
  }

  // -------------------------------------------------------------------------
  // Durable workflow runs (`tool-workflow/*` — log-only)
  // -------------------------------------------------------------------------

  /// Opens one durable workflow run record. Updates that arrived before the
  /// start (a history tail cut between the pair) are buffered and applied
  /// here, so the run's members/terminal state survive the tail.
  void _startWorkflowRun(JsonMap event) {
    final start = decodeWorkflowRunStart(_eventData(event));
    if (_workflows.containsKey(start.runId)) {
      throw FormatException(
        'tool-workflow/run-start repeats run "${start.runId}"',
      );
    }
    final state = _WorkflowState(
      runId: start.runId,
      name: start.name,
      startSeq: _lastSeq,
    );
    final buffered = _pendingWorkflowUpdates.remove(start.runId);
    if (buffered != null) {
      for (final update in buffered) {
        update.apply(state);
      }
    }
    _workflows[start.runId] = state;
    _items.add(_workflowItem(state));
  }

  /// Folds one member or terminal update. An update whose run start has not
  /// been folded stays pending until the unique `run-start` arrives.
  void _updateWorkflowRun(JsonMap event) {
    final data = _eventData(event);
    final runId = wireString(data, 'runId');
    if (runId == null) {
      throw const FormatException(
        'tool-workflow event missing required field "runId"',
      );
    }
    final update = switch (wireType(event)) {
      'tool-workflow/agent-start' => _WorkflowUpdate((state) {
        final member = decodeWorkflowAgentStart(data);
        state.members.add(
          _WorkflowMemberState(
            seq: member.seq,
            label: member.label,
            phase: member.phase,
            childId: member.childId,
          ),
        );
      }),
      'tool-workflow/agent-end' => _WorkflowUpdate((state) {
        final end = decodeWorkflowAgentEnd(data);
        // The reference's `updateAgentEnd` maps over the run's members and
        // leaves the state unchanged when no seq matches: an end whose start
        // fell outside the folded window is not an error.
        for (var i = 0; i < state.members.length; i++) {
          if (state.members[i].seq == end.seq) {
            state.members[i] = state.members[i].withOutcome(end.outcome);
            return;
          }
        }
      }),
      'tool-workflow/run-end' => _WorkflowUpdate((state) {
        state.stopReason = decodeWorkflowRunEnd(data).stopReason;
      }),
      final other => throw FormatException(
        'unknown tool-workflow event "$other"',
      ),
    };
    final state = _workflows[runId];
    if (state == null) {
      (_pendingWorkflowUpdates[runId] ??= <_WorkflowUpdate>[]).add(update);
      return;
    }
    update.apply(state);
    _publishWorkflowItem(runId, state);
  }

  /// Rebuilds every run item still lacking a terminal event after a turn
  /// closed, so their interrupted status projects.
  void _refreshOpenWorkflows() {
    for (final entry in _workflows.entries) {
      if (entry.value.stopReason != null) continue;
      if (entry.value.startSeq >= _lastTurnEndSeq) continue;
      _publishWorkflowItem(entry.key, entry.value);
    }
  }

  void _publishWorkflowItem(String runId, _WorkflowState state) {
    for (var i = 0; i < _items.length; i++) {
      final current = _items[i];
      if (current is! TimelineWorkflowRun) continue;
      if (current.runId != runId) continue;
      _items[i] = _workflowItem(state);
      return;
    }
  }

  /// Projects one run's folded state into its render item (the reference's
  /// `projectWorkflow`): members group by phase in first-seen order, an
  /// unsettled member is `running`, or `interrupted` when the run's turn
  /// closed.
  TimelineWorkflowRun _workflowItem(_WorkflowState state) {
    final interrupted =
        state.stopReason == null && state.startSeq < _lastTurnEndSeq;
    final phases = <WorkflowPhase>[];
    final phaseIndex = <String, int>{};
    for (final member in state.members) {
      final key = workflowPhaseKey(member.phase);
      final status = member.outcome == null
          ? (interrupted
                ? WorkflowRunStatus.interrupted
                : WorkflowRunStatus.running)
          : _statusFromOutcome(member.outcome!);
      final projected = WorkflowMember(
        seq: member.seq,
        label: member.label,
        childId: member.childId,
        status: status,
      );
      final existing = phaseIndex[key];
      if (existing == null) {
        phaseIndex[key] = phases.length;
        phases.add(
          WorkflowPhase(
            key: key,
            phase: member.phase,
            members: <WorkflowMember>[projected],
          ),
        );
      } else {
        phases[existing].members.add(projected);
      }
    }
    return TimelineWorkflowRun(
      runId: state.runId,
      name: state.name,
      status: state.stopReason == null
          ? (interrupted
                ? WorkflowRunStatus.interrupted
                : WorkflowRunStatus.running)
          : _statusFromStopReason(state.stopReason!),
      stopReason: state.stopReason?.name,
      phases: phases,
    );
  }

  static WorkflowRunStatus _statusFromOutcome(WorkflowMemberOutcome outcome) =>
      switch (outcome) {
        WorkflowMemberOutcome.completed => WorkflowRunStatus.completed,
        WorkflowMemberOutcome.failed => WorkflowRunStatus.failed,
        WorkflowMemberOutcome.cancelled => WorkflowRunStatus.cancelled,
      };

  static WorkflowRunStatus _statusFromStopReason(WorkflowStopReason reason) =>
      switch (reason) {
        WorkflowStopReason.completed => WorkflowRunStatus.completed,
        WorkflowStopReason.cancelled => WorkflowRunStatus.cancelled,
        WorkflowStopReason.error => WorkflowRunStatus.failed,
      };

  // -------------------------------------------------------------------------
  // Schedule fold (`schedule/change` — the durable reminder stream)
  // -------------------------------------------------------------------------

  /// Applies one decoded `schedule/change` to the active set. The transition
  /// rules mirror the reference's (`packages/schedule/schedule/src/
  /// domain.ts` `applyScheduleChanges`), but the fold is window-tolerant:
  /// this reducer replays a history page, not the complete log, so a delete
  /// or dispatch naming an id created before the window neither throws nor
  /// invents a record, and a create upserts. The rules that are independent
  /// of the window — `version` 1, a one-shot dispatch carrying no
  /// `acceptedAt`, a fixed-rate dispatch carrying one — still fail loud.
  void _applyScheduleChange(ScheduleChange change) {
    switch (change) {
      case ScheduleCreate(:final reminder):
        final existing = _schedules.indexWhere(
          (item) => item.id == reminder.id,
        );
        if (existing >= 0) {
          _schedules[existing] = reminder;
        } else {
          _schedules.add(reminder);
        }
      case ScheduleDelete(:final id):
        _schedules.removeWhere((item) => item.id == id);
      case ScheduleDispatch(:final id, :final acceptedAt):
        final index = _schedules.indexWhere((item) => item.id == id);
        if (index < 0) return;
        final record = _schedules[index];
        if (record.kind != ScheduleReminderKind.every) {
          if (acceptedAt != null) {
            throw const FormatException(
              'one-shot schedule dispatch must not carry "acceptedAt"',
            );
          }
          _schedules.removeAt(index);
          return;
        }
        if (acceptedAt == null) {
          throw const FormatException(
            'fixed-rate schedule dispatch requires "acceptedAt"',
          );
        }
        final next = _nextEveryTarget(record, acceptedAt);
        if (next == null) {
          _schedules.removeAt(index);
        } else {
          _schedules[index] = ScheduleReminder(
            id: record.id,
            kind: record.kind,
            prompt: record.prompt,
            scheduledAt: next,
            everySeconds: record.everySeconds,
          );
        }
    }
  }

  /// The next anchor-aligned target after [acceptedAt], or null when the
  /// occurrence would leave the four-digit-year window
  /// (`resolveEveryOccurrence`).
  String? _nextEveryTarget(ScheduleReminder record, String acceptedAt) {
    final target = DateTime.tryParse(record.scheduledAt);
    final accepted = DateTime.tryParse(acceptedAt);
    final intervalSeconds = record.everySeconds;
    if (target == null || accepted == null || intervalSeconds == null) {
      throw FormatException(
        'schedule/change fixed-rate dispatch has an unparsable instant for '
        '"${record.id}"',
      );
    }
    final intervalMs = intervalSeconds * 1000;
    if (intervalMs <= 0) {
      throw FormatException(
        'schedule/change fixed-rate interval must be positive for '
        '"${record.id}"',
      );
    }
    final targetMs = target.toUtc().millisecondsSinceEpoch;
    final acceptedMs = accepted.toUtc().millisecondsSinceEpoch;
    if (acceptedMs < targetMs) {
      throw FormatException(
        'schedule/change dispatch precedes the active scheduledAt for '
        '"${record.id}"',
      );
    }
    final steps = (acceptedMs - targetMs) ~/ intervalMs;
    final next = targetMs + (steps + 1) * intervalMs;
    // Date.parse('9999-12-31T23:59:59.999Z') — the reference's
    // MAX_FOUR_DIGIT_YEAR_MS.
    if (next > 253402300799999) return null;
    return DateTime.fromMillisecondsSinceEpoch(
      next,
      isUtc: true,
    ).toIso8601String();
  }

  /// Sums the completed turn's per-step token accounting onto its
  /// `turn/start` boundary and stamps the `turn/end` event's own logged time,
  /// so a surface can show the turn's wall time. The total is a convenience
  /// over figures the host already sent with each `assistant/message`; a turn
  /// whose steps reported nothing keeps a null usage rather than a fabricated
  /// zero, and a missing `time` stays null.
  void _foldTurnUsage(int turn, int? endedAtEpochMs) {
    var boundaryIndex = -1;
    for (var i = 0; i < _items.length; i++) {
      final item = _items[i];
      if (item is TimelineTurnBoundary && item.turn == turn) {
        boundaryIndex = i;
        break;
      }
    }
    if (boundaryIndex < 0) return;
    final boundary = _items[boundaryIndex] as TimelineTurnBoundary;
    final usages = <TokenUsage>[];
    for (var i = boundaryIndex + 1; i < _items.length; i++) {
      final item = _items[i];
      if (item is TimelineTurnBoundary) break;
      if (item is TimelineMessage && item.usage != null) {
        usages.add(item.usage!);
      }
    }
    _items[boundaryIndex] = TimelineTurnBoundary(
      turn,
      usage: usages.isEmpty ? boundary.usage : _sumUsage(usages),
      startedAtEpochMs: boundary.startedAtEpochMs,
      endedAtEpochMs: endedAtEpochMs,
    );
  }

  TokenUsage _sumUsage(List<TokenUsage> usages) {
    var input = 0;
    var output = 0;
    var total = 0;
    var totalKnown = false;
    var cacheRead = 0;
    var cacheReadKnown = false;
    var cacheWrite = 0;
    var cacheWriteKnown = false;
    var reasoning = 0;
    var reasoningKnown = false;
    for (final usage in usages) {
      input += usage.inputTokens;
      output += usage.outputTokens;
      if (usage.totalTokens case final value?) {
        total += value;
        totalKnown = true;
      }
      if (usage.cacheReadTokens case final value?) {
        cacheRead += value;
        cacheReadKnown = true;
      }
      if (usage.cacheWriteTokens case final value?) {
        cacheWrite += value;
        cacheWriteKnown = true;
      }
      if (usage.reasoningTokens case final value?) {
        reasoning += value;
        reasoningKnown = true;
      }
    }
    return TokenUsage(
      inputTokens: input,
      outputTokens: output,
      totalTokens: totalKnown ? total : null,
      cacheReadTokens: cacheReadKnown ? cacheRead : null,
      cacheWriteTokens: cacheWriteKnown ? cacheWrite : null,
      reasoningTokens: reasoningKnown ? reasoning : null,
    );
  }

  void _upsertByKey({required String key, required TimelineItem item}) {
    for (var i = 0; i < _items.length; i++) {
      if (_itemKey(_items[i]) == key) {
        _items[i] = item;
        return;
      }
    }
    _items.add(item);
  }

  void _removeByKey(String? key) {
    if (key == null) return;
    _items.removeWhere((item) => _itemKey(item) == key);
  }

  String _itemKey(TimelineItem item) {
    if (item is TimelineApprovalRequest) return 'approval:${item.approvalId}';
    if (item is TimelineQuestionRequest) return 'question:${item.requestId}';
    if (item is TimelineQueue) return 'queue';
    if (item is TimelineJobs) return 'jobs';
    return '';
  }

  /// Decodes one `session/queue` snapshot entry. `id`, `message` and
  /// `placement` are required by the wire contract
  /// (reference `events.schema.ts` `muxFrameSchema`), so each absence or
  /// type mismatch throws with the field name; `placement` is a closed
  /// union (`queued | steering | context`) — no silent fallback.
  SessionQueueItem _toQueueItem(JsonMap obj) {
    final itemId = wireString(obj, 'id');
    if (itemId == null) {
      throw const FormatException(
        'session/queue item missing required field "id"',
      );
    }
    final message = asJsonObject(obj['message']);
    if (message == null) {
      throw const FormatException(
        'session/queue item missing required field "message"',
      );
    }
    final placementValue = wireString(obj, 'placement');
    final placement = switch (placementValue) {
      'queued' => QueuePlacement.queued,
      'steering' => QueuePlacement.steering,
      'context' => QueuePlacement.context,
      final unknown => throw FormatException(
        'session/queue item "placement" is not a known value: '
        '${unknown == null ? "(missing)" : '"$unknown"'}',
      ),
    };
    return SessionQueueItem(
      itemId: itemId,
      placement: placement,
      text: _extractText(message),
    );
  }

  JobView? _toJobView(JsonMap obj) {
    final id = wireString(obj, 'id');
    if (id == null) return null;
    return JobView(
      id: id,
      kind: wireString(obj, 'kind') ?? 'unknown',
      label: wireString(obj, 'label') ?? '',
      status: switch (wireString(obj, 'status')) {
        'stopping' => JobStatus.stopping,
        'completed' => JobStatus.completed,
        'killed' => JobStatus.killed,
        'failed' => JobStatus.failed,
        _ => JobStatus.running,
      },
      detail: wireString(obj, 'detail'),
      startedAt: wireLong(obj, 'startedAt'),
      finishedAt: wireLongOrNull(obj, 'finishedAt'),
    );
  }

  QuestionItem? _toQuestionItem(JsonMap obj) {
    final id = wireString(obj, 'id');
    if (id == null) return null;
    final optionArray = asJsonArray(obj['options']);
    final options =
        optionArray
            ?.map((option) => asJsonObject(option))
            .whereType<JsonMap>()
            .map((optionObj) => wireString(optionObj, 'label'))
            .whereType<String>()
            .toList() ??
        <String>[];
    final optionDescriptions = <String, String>{};
    if (optionArray != null) {
      for (final option in optionArray) {
        final optionObj = asJsonObject(option);
        if (optionObj == null) continue;
        final label = wireString(optionObj, 'label');
        final description = wireString(optionObj, 'description');
        if (label != null && description != null) {
          optionDescriptions[label] = description;
        }
      }
    }
    return QuestionItem(
      id: id,
      question: wireString(obj, 'question') ?? '',
      detail: wireString(obj, 'detail'),
      options: options,
      multiSelect: wireBool(obj, 'multiSelect'),
      header: wireString(obj, 'header'),
      optionDescriptions: optionDescriptions,
      intent: () {
        final intent = asJsonObject(obj['intent']);
        if (intent == null) return null;
        final kind = wireString(intent, 'kind');
        if (kind == null) return null;
        return QuestionIntent(
          kind: kind,
          approve: wireString(intent, 'approve'),
        );
      }(),
    );
  }

  JsonMap _eventData(JsonMap event) =>
      asJsonObject(event['data']) ?? <String, Object?>{};

  String _extractText(JsonMap container) => _collectText(container);

  String _collectText(JsonMap container) {
    final content = asJsonArray(container['content']);
    if (content == null) return '';
    final buffer = StringBuffer();
    for (final block in content) {
      final obj = asJsonObject(block);
      if (obj == null) continue;
      switch (wireType(obj)) {
        case 'text':
          final text = wireString(obj, 'text');
          if (text != null) buffer.write(text);
        case 'tool-result':
          buffer.write(_collectText(obj));
      }
    }
    return buffer.toString();
  }

  String? _extractReasoning(JsonMap obj) {
    final content = asJsonArray(obj['content']);
    if (content == null) return null;
    final buffer = StringBuffer();
    for (final block in content) {
      final blockObj = asJsonObject(block);
      if (blockObj == null) continue;
      if (wireType(blockObj) == 'reasoning') {
        final text = wireString(blockObj, 'text');
        if (text != null) buffer.write(text);
      }
    }
    final value = buffer.toString();
    return value.isEmpty ? null : value;
  }

  /// Image blocks carry a durable `attachment` reference, never inline data.
  List<AttachmentRef> _extractImages(JsonMap obj) {
    final content = asJsonArray(obj['content']);
    if (content == null) return const <AttachmentRef>[];
    final refs = <AttachmentRef>[];
    for (final block in content) {
      final blockObj = asJsonObject(block);
      if (blockObj == null || wireType(blockObj) != 'image') continue;
      final attachment = asJsonObject(blockObj['attachment']);
      if (attachment == null) continue;
      final id = wireString(attachment, 'attachmentId');
      if (id == null) continue;
      refs.add(
        AttachmentRef(
          attachmentId: id,
          mediaType: wireString(attachment, 'mediaType') ?? '',
          bytes: wireLong(attachment, 'bytes'),
          width: wireLong(attachment, 'width'),
          height: wireLong(attachment, 'height'),
          name: wireString(attachment, 'name'),
        ),
      );
    }
    return refs;
  }

  String _turnStepKey(int turn, int step) => '$turn:$step';
}

/// One workflow run's folded durable state (the reference's `WorkflowState`
/// plus the anchor seq a history tail can be checked against).
final class _WorkflowState {
  _WorkflowState({
    required this.runId,
    required this.name,
    required this.startSeq,
  });

  final String runId;
  final String name;

  /// Seq of the run's `tool-workflow/run-start`.
  final int startSeq;

  final List<_WorkflowMemberState> members = <_WorkflowMemberState>[];
  WorkflowStopReason? stopReason;
}

/// One member's folded state before projection.
final class _WorkflowMemberState {
  _WorkflowMemberState({
    required this.seq,
    required this.label,
    required this.childId,
    this.phase,
  });

  final int seq;
  final String label;
  final String childId;
  final String? phase;
  WorkflowMemberOutcome? outcome;

  _WorkflowMemberState withOutcome(WorkflowMemberOutcome next) =>
      _WorkflowMemberState(
        seq: seq,
        label: label,
        childId: childId,
        phase: phase,
      )..outcome = next;
}

/// One deferred workflow update (arrived before its `run-start`).
final class _WorkflowUpdate {
  const _WorkflowUpdate(this.apply);

  final void Function(_WorkflowState state) apply;
}
