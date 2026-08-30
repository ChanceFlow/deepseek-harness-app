/// Incremental, seq-ordered reducer: raw dsh session events -> immutable
/// [TimelineItem] snapshot.
///
/// History replay and live frames meet at the same `lastSeq` boundary, so
/// an event already folded by a history page is never applied twice.
library;

import 'package:domain/model/attachment.dart';
import 'package:domain/model/chat_message.dart';
import 'package:domain/model/jobs.dart';
import 'package:domain/model/session.dart';
import 'package:domain/model/timeline_item.dart';
import 'package:network/rpc_envelope.dart';

import 'rpc_map.dart';
import 'wire_json.dart';

class TimelineReducer {
  TimelineReducer(this.sessionId);

  final String sessionId;

  final List<TimelineItem> _items = <TimelineItem>[];
  int _lastSeq = -1;
  String? _partialKey;
  int _partialIndex = -1;
  final Set<int> _seenTurns = <int>{};

  /// The streaming partial accumulates into buffers: one delta is one
  /// O(delta) append, and the [ChatMessage] string is materialized only
  /// when a snapshot reads it. Concatenating an immutable string per
  /// delta is quadratic in the final message length — a huge streamed
  /// reply re-copied the whole text on every chunk.
  StringBuffer? _partialText;
  StringBuffer? _partialReasoning;
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
    for (final item in _items) {
      if (item is TimelineQueue) {
        queueMirror = item;
        break;
      }
    }
    _items.clear();
    _lastSeq = -1;
    _clearPartial();
    _seenTurns.clear();
    final sorted = List<JsonMap>.of(history)
      ..sort((a, b) => wireLong(a, 'seq').compareTo(wireLong(b, 'seq')));
    for (final event in sorted) {
      _ingestEvent(event);
    }
    if (queueMirror != null) _items.add(queueMirror);
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

    switch (wireType(event)) {
      case 'turn/start':
        _appendTurnStart(event);
      case 'compaction/summary':
        _appendCompaction(event);
      case 'command/run':
        _appendCommandRun(event);
      case 'command/done':
        _resolveCommandDone(event);
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
      case 'turn/end':
        _appendTurnEnd(event);
    }
  }

  void _appendTurnStart(JsonMap event) {
    final turn = wireLong(_eventData(event), 'turn');
    if (turn <= 0 || !_seenTurns.add(turn)) return;
    _finalizePartial();
    _items.add(TimelineTurnBoundary(turn));
  }

  /// A summary shadows its range; the marker keeps only the count.
  void _appendCompaction(JsonMap event) {
    final shadowed =
        asJsonArray(_eventData(event)['shadowedSeqs'])?.length ?? 0;
    _items.add(
      TimelineCompaction(id: 'compaction:$_lastSeq', shadowedCount: shadowed),
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
    final finalItem = TimelineMessage(
      ChatMessage(
        id: wireString(message, 'id') ?? 'assistant:$_lastSeq',
        sessionId: sessionId,
        role: MessageRole.assistant,
        text: _extractText(message),
        reasoning: _extractReasoning(message),
        createdAtEpochMs: wireLong(event, 'time'),
        images: _extractImages(message),
        seq: _lastSeq,
      ),
    );

    if (_partialKey == _turnStepKey(turn, step)) {
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
        text.write(wireString(chunk, 'text') ?? '');
        _partialDirty = true;
      case 'reasoning-delta':
        reasoning = (reasoning ??= StringBuffer())
          ..write(wireString(chunk, 'text') ?? '');
        _partialDirty = true;
      case 'block-end':
        final block = asJsonObject(chunk['block']);
        if (block != null) {
          if (wireType(block) == 'text') {
            text
              ..clear()
              ..write(_extractText(block));
          }
          final blockReasoning = _extractReasoning(block);
          if (blockReasoning != null) {
            reasoning = (reasoning ??= StringBuffer())
              ..clear()
              ..write(blockReasoning);
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
    final value = (_items[_partialIndex] as TimelineMessage).value;
    return TimelineMessage(
      ChatMessage(
        id: value.id,
        sessionId: value.sessionId,
        role: value.role,
        text: _partialText?.toString() ?? value.text,
        reasoning: _partialReasoning?.toString() ?? value.reasoning,
        streaming: streaming,
        createdAtEpochMs: value.createdAtEpochMs,
        images: value.images,
        seq: value.seq,
      ),
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
    _partialDirty = false;
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
      ),
    );
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
    // dsh writes tool failures in either the `tool/result` event's optional
    // `error` field or the ToolResultBlock's `isError` flag.
    final isError =
        wireBool(toolMessage, 'isError') ||
        (resultBlock != null && wireBool(resultBlock, 'isError')) ||
        data['error'] != null;

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
    final newItem = TimelineToolCall(
      id: callId,
      name: previous?.name ?? 'unknown',
      arguments: previous?.arguments,
      result: resultText,
      isError: isError,
      status: isError ? ToolRunStatus.failed : ToolRunStatus.completed,
    );
    if (index >= 0) {
      _items[index] = newItem;
    } else {
      _items.add(newItem);
    }
  }

  void _appendTurnEnd(JsonMap event) {
    _finalizePartial();
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
    if (message != null || kind != null) {
      _items.add(
        TimelineError(
          id: 'turn-end:$_lastSeq',
          message: message ?? '',
          code: kind,
        ),
      );
    }
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
