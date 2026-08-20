/// Context-pressure fold — port of the web `contextPressure` projection
/// (reference/deepseek-harness/packages/llm/token-meter/src/
/// usage-projection.ts): last-wins pressure from usage chunks / finalized
/// assistant messages, last-wins capacity from `request/context`
/// envelopes, and a running heuristic surface total (surface-projection.ts
/// + estimate.ts) that carries the newest sample forward as
/// `projectedTokens`.
library;

import 'dart:convert' show jsonEncode;
import 'dart:math' show max;

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

  /// Running heuristic total over the model-visible surface (web
  /// surface-projection.ts): each user/assistant/tool-result message adds
  /// its estimate, each compaction subtracts its shadow price.
  int _surfaceTokens = 0;

  /// [_surfaceTokens] at the newest usage sample; null until one lands.
  int? _sampledSurfaceTokens;

  void _publish() {
    if (_pressureTokens == null && _contextWindow == null) {
      _value = null;
    } else {
      final pressure = _pressureTokens;
      final sampled = _sampledSurfaceTokens;
      _value = ContextPressure(
        pressureTokens: pressure,
        // Web usage-projection.ts view rule: publish the sample carried
        // forward over the surface's signed movement since it was taken,
        // clamped at zero, only while a sample exists.
        projectedTokens: pressure == null || sampled == null
            ? null
            : max(0, pressure + _surfaceTokens - sampled),
        contextWindow: _contextWindow,
      );
    }
  }

  /// Replay a chronologically ordered session-log event list.
  void reset(List<JsonMap> events) {
    _pressureTokens = null;
    _contextWindow = null;
    _surfaceTokens = 0;
    _sampledSurfaceTokens = null;
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
        // Web usage-projection.ts stamps the sample BEFORE the same event
        // joins the surface, so the sample anchors against the surface its
        // own request saw.
        _applyUsage(asJsonObject(data['usage']));
        final message = asJsonObject(data['message']);
        final content = message?['content'];
        // Web surface.ts deriveEventMessage: an empty-content assistant
        // message exists only to host usage and prices at zero on the
        // surface.
        final blocks = asJsonArray(content);
        _applySurfaceDelta(
          blocks == null || blocks.isEmpty
              ? 0
              : estimateContent(blocks) + _roleOverhead,
        );
        _messageTokens += estimateContent(content) + _roleOverhead;
        _publishBreakdown();
      case 'user/message':
        // Web surface.ts deriveEventMessage: the event data IS the message.
        final tokens = _estimateMessage(data['content']);
        _applySurfaceDelta(tokens);
        _messageTokens += tokens;
        _publishBreakdown();
      case 'tool/result':
        // Web surface.ts: tool results are model-visible surface — the
        // result message prices like any append.
        _applySurfaceDelta(
          _estimateMessage(asJsonObject(data['message'])?['content']),
        );
      case 'compaction/summary':
      case 'compaction/prune':
        _applyCompaction(data);
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

  /// Web estimate.ts `estimateMessage`: content estimate plus role framing.
  int _estimateMessage(Object? rawContent) =>
      estimateContent(rawContent) + _roleOverhead;

  /// Apply a signed change to the running surface total and republish —
  /// once a sample exists, `projectedTokens` moves with the surface.
  void _applySurfaceDelta(int delta) {
    if (delta == 0) return;
    _surfaceTokens += delta;
    _publish();
  }

  /// Compaction metering event — `compaction/summary` or
  /// `compaction/prune` (wire shapes:
  /// reference/deepseek-harness/packages/compaction/compaction/src/types.ts):
  /// subtract the shadowed range's heuristic price.
  ///
  /// The web prices a replacement through a claim/replace protocol
  /// (surface-projection.ts): the metering event arms the shadowed range's
  /// price, and the immediately following replacement message folds
  /// `estimateMessage - claim`. This port does not track the web's
  /// `surfaceOp` marker and applies the arithmetic equivalent directly:
  /// subtract `shadowedTokenCount` here — producers derive it from the
  /// same fixed estimator this fold prices appends with, so the
  /// subtraction is exact — and let the adjacent replacement (the
  /// summary-bearing `user/message` after `compaction/summary`, the pruned
  /// `tool/result` after `compaction/prune`) join the surface through the
  /// ordinary append estimate. The compaction therefore nets to
  /// `surfaceTokens - shadowedTokenCount + estimate(summary text)`, equal
  /// to the web's total at every event boundary.
  void _applyCompaction(JsonMap data) {
    final shadowed = wireLongOrNull(data, 'shadowedTokenCount');
    if (shadowed == null || shadowed < 0) return;
    _applySurfaceDelta(-shadowed);
  }

  void _applyUsage(Object? rawUsage) {
    final usage = asJsonObject(rawUsage);
    if (usage == null) return;
    final input = wireLongOrNull(usage, 'inputTokens');
    if (input == null) return;
    final cacheRead = wireLongOrNull(usage, 'cacheReadTokens') ?? 0;
    final cacheWrite = wireLongOrNull(usage, 'cacheWriteTokens') ?? 0;
    _pressureTokens = input + cacheRead + cacheWrite;
    // Web usage-projection.ts: the sample stamps the surface total as of
    // the request it priced.
    _sampledSurfaceTokens = _surfaceTokens;
    _publish();
  }
}
