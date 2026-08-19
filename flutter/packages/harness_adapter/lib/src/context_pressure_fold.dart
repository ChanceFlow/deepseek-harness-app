/// Context-pressure fold — port of the web `contextPressure` projection
/// (dsh-token-meter usage-projection.ts): last-wins pressure from usage
/// chunks / finalized assistant messages, last-wins capacity from
/// `request/context` envelopes.
library;

import 'dart:convert' show jsonEncode;

import 'package:domain/model/context_pressure.dart';

import 'rpc_map.dart';
import 'wire_json.dart';

/// Fixed text-density heuristic — port of dsh-token-meter estimate.ts.
const int _charsPerToken = 4;
const int _blockOverhead = 4;
const int _roleOverhead = 4;

int _ceilDiv4(int length) => (length + _charsPerToken - 1) ~/ _charsPerToken;

/// Price content blocks under the fixed density heuristic.
int estimateContent(Object? rawBlocks) {
  final blocks = asJsonArray(rawBlocks);
  if (blocks == null) return 0;
  var tokens = 0;
  for (final rawBlock in blocks) {
    final block = asJsonObject(rawBlock);
    if (block == null) continue;
    switch (wireType(block)) {
      case 'text':
      case 'reasoning':
        tokens +=
            _ceilDiv4((wireString(block, 'text') ?? '').length) +
            _blockOverhead;
      case 'tool-call':
        final arguments = block['arguments'];
        final argumentsLength = arguments is String
            ? arguments.length
            : arguments == null
            ? 0
            : jsonEncode(arguments).length;
        tokens +=
            _ceilDiv4((wireString(block, 'name') ?? '').length) +
            _ceilDiv4(argumentsLength) +
            _blockOverhead;
      case 'tool-result':
        tokens += estimateContent(block['content']) + _blockOverhead;
      default:
        tokens += _blockOverhead + _ceilDiv4(jsonEncode(block).length);
    }
  }
  return tokens;
}

int _estimateSystem(Object? system) {
  if (system is! String || system.isEmpty) return 0;
  return _ceilDiv4(system.length) + _roleOverhead;
}

int _estimateTools(Object? tools) {
  if (tools is! List || tools.isEmpty) return 0;
  return _ceilDiv4(jsonEncode(tools).length) + _blockOverhead;
}

class ContextPressureFold {
  ContextPressure? _value;
  ContextBreakdown? _breakdown;

  /// Heuristic composition; null until any component is priced.
  ContextBreakdown? get breakdown => _breakdown;

  int? _systemTokens;
  int? _toolsTokens;
  int _messageTokens = 0;

  /// Current projection; null until any record exists.
  ContextPressure? get value => _value;

  int? _pressureTokens;
  int? _contextWindow;

  void _publish() {
    if (_pressureTokens == null && _contextWindow == null) {
      _value = null;
    } else {
      _value = ContextPressure(
        pressureTokens: _pressureTokens,
        contextWindow: _contextWindow,
      );
    }
  }

  /// Replay a chronologically ordered session-log event list.
  void reset(List<JsonMap> events) {
    _pressureTokens = null;
    _contextWindow = null;
    _value = null;
    _systemTokens = null;
    _toolsTokens = null;
    _messageTokens = 0;
    _breakdown = null;
    for (final event in events) {
      ingestEvent(event);
    }
  }

  /// One raw session-log event — the wire envelope `{type, seq, time,
  /// data: {...}}` (payloads live under `data`, matching the timeline
  /// reducer's `_eventData` reads).
  void ingestEvent(Object? raw) {
    final event = asJsonObject(raw);
    if (event == null) return;
    final data = asJsonObject(event['data']) ?? const <String, Object?>{};
    switch (wireType(event)) {
      case 'assistant/chunk':
        final chunk = asJsonObject(data['chunk']);
        if (chunk == null || wireType(chunk) != 'usage') return;
        _applyUsage(asJsonObject(chunk['usage']));
      case 'assistant/message':
        _applyUsage(asJsonObject(data['usage']));
        final message = asJsonObject(data['message']);
        _messageTokens += estimateContent(message?['content']) +
            _roleOverhead;
        _publishBreakdown();
      case 'user/message':
        _messageTokens += estimateContent(data['content']) + _roleOverhead;
        _publishBreakdown();
      case 'request/context':
        final window = wireLongOrNull(data, 'contextWindow');
        if (window != null && window > 0) {
          _contextWindow = window;
          _publish();
        }
      case 'request/header':
        final header = asJsonObject(data['header']);
        _systemTokens = _estimateSystem(header?['system']);
        _toolsTokens = _estimateTools(header?['tools']);
        _publishBreakdown();
    }
  }

  void _publishBreakdown() {
    if (_systemTokens == null && _toolsTokens == null && _messageTokens == 0) {
      _breakdown = null;
    } else {
      _breakdown = ContextBreakdown(
        systemTokens: _systemTokens ?? 0,
        toolsTokens: _toolsTokens ?? 0,
        messageTokens: _messageTokens,
      );
    }
  }

  void _applyUsage(Object? rawUsage) {
    final usage = asJsonObject(rawUsage);
    if (usage == null) return;
    final input = wireLongOrNull(usage, 'inputTokens');
    if (input == null) return;
    final cacheRead = wireLongOrNull(usage, 'cacheReadTokens') ?? 0;
    final cacheWrite = wireLongOrNull(usage, 'cacheWriteTokens') ?? 0;
    _pressureTokens = input + cacheRead + cacheWrite;
    _publish();
  }
}
