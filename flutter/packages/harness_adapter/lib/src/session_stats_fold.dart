/// Session-stats fold — port of the web StatsLine `deriveStats` fallback
/// plus the billing usage sums: window-scoped wall times and token counts
/// folded from the on-screen event log.
library;

import 'package:domain/model/session_window_stats.dart';

import 'rpc_map.dart';
import 'wire_json.dart';

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

  /// Step anchor: the newest boundary-ish event time (turn/start,
  /// user/message, tool/result) — the fallback for `timing.stepStartTime`.
  int? _stepStartMs;

  /// First-chunk time of the streaming step in flight.
  int? _firstChunkMs;

  /// Outstanding tool calls awaiting their result, by call id.
  final Map<String, int> _callStartMs = <String, int>{};

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
    _stepStartMs = null;
    _firstChunkMs = null;
    _callStartMs.clear();
    for (final event in events) {
      ingestEvent(event);
    }
    _publish();
  }

  void ingestEvent(Object? raw) {
    final event = asJsonObject(raw);
    if (event == null) return;
    final time = wireLongOrNull(event, 'time');
    switch (wireType(event)) {
      case 'turn/start':
        final turn = wireLongOrNull(event, 'turn');
        if (turn != null) _turns.add(turn);
        _stepStartMs = time;
      case 'user/message':
        _stepStartMs = time;
      case 'tool/call':
        final callId = wireString(event, 'id');
        if (callId != null && time != null) _callStartMs[callId] = time;
      case 'tool/result':
        if (time != null) _stepStartMs = time;
        final callId = wireString(event, 'callId');
        final start = callId == null ? null : _callStartMs.remove(callId);
        if (start != null && time != null && time > start) {
          _toolMs += time - start;
        }
      case 'assistant/chunk':
        if (_firstChunkMs == null && time != null) {
          _firstChunkMs = time;
          final stepStart = _stepStartMs;
          if (stepStart != null && time >= stepStart) {
            _ttftMs += time - stepStart;
            _ttftSteps++;
          }
        }
      case 'assistant/message':
        _steps++;
        var decodeTimed = false;
        if (time != null) {
          final stepStart = _stepStartMs;
          if (stepStart != null && time >= stepStart) {
            _llmMs += time - stepStart;
          }
          final firstChunk = _firstChunkMs;
          if (firstChunk != null && time >= firstChunk) {
            _decodeMs += time - firstChunk;
            decodeTimed = true;
          }
        }
        _firstChunkMs = null;
        final usage = asJsonObject(event['usage']);
        if (usage != null) {
          final input = wireLongOrNull(usage, 'inputTokens') ?? 0;
          _billedInput +=
              input +
              (wireLongOrNull(usage, 'cacheReadTokens') ?? 0) +
              (wireLongOrNull(usage, 'cacheWriteTokens') ?? 0);
          final output = wireLongOrNull(usage, 'outputTokens') ?? 0;
          _outputTokens += output;
          // Decode throughput only prices decode-timed steps (web rule).
          if (decodeTimed) _decodeTokens += output;
          _cacheRead += wireLongOrNull(usage, 'cacheReadTokens') ?? 0;
        }
    }
    _publish();
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
