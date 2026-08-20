/// Session-stats fold — port of the host `sessionStats` projection
/// (dsh-session-stats `projection.ts`) plus the billing usage sums the web
/// reads from `tokenUsage`: counts and wall times folded from step
/// boundaries, stream chunks, tool pairs, and assembled assistant messages.
///
/// `step/end` — not `assistant/message` — is the counted step event: the
/// agent loop appends exactly one per entered step, so completed, failed,
/// cancelled, and max-tokens steps all land one. A turn counts once at
/// least one of its steps has closed. Model time spans `step/start` → the
/// step's assembled `assistant/message`; the first token is the first
/// non-empty delta chunk of the open step and survives an in-step
/// `llm/retry`; decode spans first token → assembled message on steps that
/// also report valid output tokens; tool time pairs `tool/call` →
/// `tool/result` by callId. A cancelled step assembles no message, so its
/// partial stream time stays uncounted.
library;

import 'package:domain/model/session_window_stats.dart';

import 'rpc_map.dart';
import 'wire_json.dart';

/// The open step's boundary facts.
final class _OpenStep {
  _OpenStep(this.turn, this.step, this.startTime);

  /// `data.turn` / `data.step` of the opening `step/start`.
  final int turn;
  final int step;

  /// Envelope `time` of the `step/start`; null on a malformed envelope,
  /// which leaves the step's wall times uncounted.
  final int? startTime;

  /// Envelope `time` of the first token delta; null until one lands.
  int? firstTokenTime;
}

class SessionStatsFold {
  SessionWindowStats _value = const SessionWindowStats();
  SessionWindowStats get value => _value;

  final Set<int> _turns = <int>{};
  int _steps = 0;
  int _llmMs = 0;
  int _toolMs = 0;
  int _ttftMs = 0;
  int _ttftSteps = 0;
  int _decodeMs = 0;
  int _decodeTokens = 0;
  int _billedInput = 0;
  int _outputTokens = 0;
  int _cacheRead = 0;

  /// The step opened by the newest `step/start`; null outside a step or
  /// after its message assembled.
  _OpenStep? _openStep;

  /// Dispatch times of tool calls whose result has not landed, by callId.
  final Map<String, int> _callStartMs = <String, int>{};

  /// Replay a chronologically ordered session-log event list.
  void reset(List<JsonMap> events) {
    _turns.clear();
    _steps = 0;
    _llmMs = 0;
    _toolMs = 0;
    _ttftMs = 0;
    _ttftSteps = 0;
    _decodeMs = 0;
    _decodeTokens = 0;
    _billedInput = 0;
    _outputTokens = 0;
    _cacheRead = 0;
    _openStep = null;
    _callStartMs.clear();
    for (final event in events) {
      ingestEvent(event);
    }
    _publish();
  }

  /// One raw session-log event envelope (`type`, `seq`, `time`, `data`).
  void ingestEvent(Object? raw) {
    final event = asJsonObject(raw);
    if (event == null) return;
    final time = wireLongOrNull(event, 'time');
    final data = asJsonObject(event['data']) ?? <String, Object?>{};
    switch (wireType(event)) {
      case 'step/start':
        _openStep = _OpenStep(
          wireLong(data, 'turn'),
          wireLong(data, 'step'),
          time,
        );
      case 'assistant/chunk':
        final open = _openStep;
        if (open == null ||
            open.turn != wireLong(data, 'turn') ||
            open.step != wireLong(data, 'step')) {
          return;
        }
        if (open.firstTokenTime != null ||
            !_isTokenDelta(asJsonObject(data['chunk']))) {
          return;
        }
        open.firstTokenTime = time;
      case 'assistant/message':
        final usage = asJsonObject(data['usage']);
        _applyUsage(usage);
        _closeOpenStep(data, usage, time);
      case 'tool/call':
        final callId = wireString(data, 'callId');
        if (callId != null && time != null) _callStartMs[callId] = time;
      case 'tool/result':
        final callId = _resultCallId(data);
        if (callId == null || time == null) return;
        final start = _callStartMs.remove(callId);
        if (start == null || time < start) return;
        _toolMs += time - start;
      case 'step/end':
        // The step lifecycle authority: the loop appends exactly one per
        // entered step, in a `finally`, so completed, failed, cancelled,
        // and max-tokens steps all land one.
        _turns.add(wireLong(data, 'turn'));
        _steps++;
        _openStep = null;
      case 'turn/end':
        // A call whose result never landed belongs to a cancelled or
        // failed turn; results always land within their turn, so drop the
        // leftovers instead of growing state forever.
        _callStartMs.clear();
    }
    _publish();
  }

  /// Fold the step's assembled message: model, first-token, and decode
  /// wall time. One assembled message per step: closing the boundary means
  /// a defensive duplicate cannot accrue twice.
  void _closeOpenStep(JsonMap data, JsonMap? usage, int? time) {
    final open = _openStep;
    if (open == null ||
        open.turn != wireLong(data, 'turn') ||
        open.step != wireLong(data, 'step')) {
      return;
    }
    _openStep = null;
    final start = open.startTime;
    if (start != null && time != null && time > start) {
      _llmMs += time - start;
    }
    final firstToken = open.firstTokenTime;
    if (firstToken == null) return;
    if (start != null) {
      if (firstToken > start) _ttftMs += firstToken - start;
      _ttftSteps++;
    }
    final output = _usageOutputTokens(usage);
    if (output == null) return;
    if (time != null && time > firstToken) _decodeMs += time - firstToken;
    _decodeTokens += output;
  }

  /// Billing usage sums (the web reads these from the `tokenUsage`
  /// projection): the three prompt-side buckets plus provider output
  /// tokens. Only the assembled message is folded — the usage chunk that
  /// may precede it carries the same figures for its step.
  void _applyUsage(JsonMap? usage) {
    if (usage == null) return;
    final cacheRead = wireLongOrNull(usage, 'cacheReadTokens') ?? 0;
    _billedInput +=
        (wireLongOrNull(usage, 'inputTokens') ?? 0) +
        cacheRead +
        (wireLongOrNull(usage, 'cacheWriteTokens') ?? 0);
    _cacheRead += cacheRead;
    final output = _usageOutputTokens(usage);
    if (output != null) _outputTokens += output;
  }

  /// Provider-reported output tokens, guarded the way the projection
  /// guards them: null when unreported, invalid, or negative.
  int? _usageOutputTokens(JsonMap? usage) {
    if (usage == null) return null;
    final value = wireLongOrNull(usage, 'outputTokens');
    return value != null && value >= 0 ? value : null;
  }

  /// The callId of a `tool/result` lives inside its result message
  /// (`data.message.source.callId`); Dart maps carry no inherited keys, so
  /// the projection's own-key check holds structurally.
  String? _resultCallId(JsonMap data) {
    final message = asJsonObject(data['message']);
    final source = message == null ? null : asJsonObject(message['source']);
    return source == null ? null : wireString(source, 'callId');
  }

  /// Port of `isTokenDelta` (dsh-llm `message.ts`): whether a stream chunk
  /// carries visible model output — the first-token boundary. Empty deltas
  /// (heartbeats, empty tool-call frames) do not count as a first token.
  bool _isTokenDelta(JsonMap? chunk) {
    if (chunk == null) return false;
    switch (wireType(chunk)) {
      case 'text-delta':
      case 'reasoning-delta':
        final text = wireString(chunk, 'text');
        return text != null && text.isNotEmpty;
      case 'tool-call-delta':
        final delta = wireString(chunk, 'argumentsDelta');
        if (delta != null && delta.isNotEmpty) return true;
        return chunk.containsKey('name');
      default:
        return false;
    }
  }

  void _publish() {
    _value = SessionWindowStats(
      turns: _turns.length,
      steps: _steps,
      llmMs: _llmMs,
      toolMs: _toolMs,
      ttftMs: _ttftMs,
      ttftSteps: _ttftSteps,
      decodeMs: _decodeMs,
      decodeTokens: _decodeTokens,
      billedInputTokens: _billedInput,
      outputTokens: _outputTokens,
      cacheReadTokens: _cacheRead,
    );
  }
}
