/// Context-pressure fold — port of the web `contextPressure` projection
/// (dsh-token-meter usage-projection.ts): last-wins pressure from usage
/// chunks / finalized assistant messages, last-wins capacity from
/// `request/context` envelopes.
library;

import 'package:domain/model/context_pressure.dart';

import 'rpc_map.dart';
import 'wire_json.dart';

class ContextPressureFold {
  ContextPressure? _value;

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
    for (final event in events) {
      ingestEvent(event);
    }
  }

  /// One raw session-log event (`type` keyed at the top level).
  void ingestEvent(Object? raw) {
    final event = asJsonObject(raw);
    if (event == null) return;
    switch (wireType(event)) {
      case 'assistant/chunk':
        final chunk = asJsonObject(event['chunk']);
        if (chunk == null || wireType(chunk) != 'usage') return;
        _applyUsage(asJsonObject(chunk['usage']));
      case 'assistant/message':
        _applyUsage(asJsonObject(event['usage']));
      case 'request/context':
        final window = wireLongOrNull(event, 'contextWindow');
        if (window != null && window > 0) {
          _contextWindow = window;
          _publish();
        }
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
