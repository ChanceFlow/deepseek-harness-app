/// Context-occupancy vocabulary for the composer status ring.
///
/// Mirrors the web `ContextPressureProjection`: two independent last-wins
/// records — the provider-reported prompt pressure of the newest request
/// and the newest advertised route capacity. Not an atomic observation;
/// a user-facing reference only.
library;

final class ContextPressure {
  const ContextPressure({this.pressureTokens, this.contextWindow});

  /// Prompt size of the most recent request: uncached input plus cache
  /// reads and writes. Null until a provider reports usage.
  final int? pressureTokens;

  /// Newest recorded route capacity; null when no adapter advertised one.
  final int? contextWindow;

  /// Ring occupancy ratio in 0..1; null until both records exist.
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
      other.contextWindow == contextWindow;

  @override
  int get hashCode => Object.hash(pressureTokens, contextWindow);
}
