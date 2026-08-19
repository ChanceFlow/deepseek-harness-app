/// Context-occupancy vocabulary for the composer status ring.
///
/// Mirrors the web `ContextPressureProjection`
/// (reference/deepseek-harness/packages/llm/token-meter/src/
/// usage-projection.ts): two independent last-wins records — the
/// provider-reported prompt pressure of the newest request and the newest
/// advertised route capacity — plus the sample carried forward over the
/// surface's signed movement since it was taken. Not an atomic
/// observation; a user-facing reference only.
library;

final class ContextPressure {
  const ContextPressure({
    this.pressureTokens,
    this.projectedTokens,
    this.contextWindow,
  });

  /// Prompt size of the most recent request: uncached input plus cache
  /// reads and writes. Null until a provider reports usage.
  final int? pressureTokens;

  /// The pressure sample carried forward over the surface's signed
  /// movement since it was taken:
  /// `max(0, pressureTokens + surfaceTokens - sampledSurfaceTokens)`
  /// (the `usage-projection.ts` view rule). Occupancy prefers this over
  /// [pressureTokens] so it answers for the next request rather than the
  /// last one; null until a usage sample exists.
  final int? projectedTokens;

  /// Newest recorded route capacity; null when no adapter advertised one.
  final int? contextWindow;

  /// Occupancy ratio of the bare pressure sample in 0..1; null until both
  /// records exist. Display occupancy prefers [projectedTokens] (web
  /// ui-conversation StatsLine.tsx `contextOccupancy`:
  /// `projectedTokens ?? pressureTokens`).
  double? get occupancy {
    final pressure = pressureTokens;
    final window = contextWindow;
    if (pressure == null || window == null || window <= 0) return null;
    return (pressure / window).clamp(0.0, 1.0).toDouble();
  }

  @override
  bool operator ==(Object other) =>
      other is ContextPressure &&
      other.pressureTokens == pressureTokens &&
      other.projectedTokens == projectedTokens &&
      other.contextWindow == contextWindow;

  @override
  int get hashCode =>
      Object.hash(pressureTokens, projectedTokens, contextWindow);
}

/// Heuristic context composition (web `contextBreakdown` projection):
/// system prompt + tool schemas from the newest request envelope,
/// conversation priced with the shared fixed-density estimator.
final class ContextBreakdown {
  const ContextBreakdown({
    this.systemTokens = 0,
    this.toolsTokens = 0,
    this.messageTokens = 0,
  });

  final int systemTokens;
  final int toolsTokens;
  final int messageTokens;

  int get total => systemTokens + toolsTokens + messageTokens;

  @override
  bool operator ==(Object other) =>
      other is ContextBreakdown &&
      other.systemTokens == systemTokens &&
      other.toolsTokens == toolsTokens &&
      other.messageTokens == messageTokens;

  @override
  int get hashCode => Object.hash(systemTokens, toolsTokens, messageTokens);
}
