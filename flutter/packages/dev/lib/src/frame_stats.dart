/// Per-second aggregate of the frame timings observed in one interval.
class FrameIntervalStats {
  const FrameIntervalStats({
    required this.frameCount,
    required this.avgMs,
    required this.p95Ms,
    required this.maxMs,
    required this.jankCount,
    required this.interval,
  });

  final int frameCount;
  final double avgMs;
  final double p95Ms;
  final double maxMs;

  /// Frames whose total span exceeded the jank threshold.
  final int jankCount;
  final Duration interval;

  double get fps => interval.inMilliseconds == 0
      ? 0
      : frameCount / (interval.inMilliseconds / 1000.0);
}

/// Pure accumulator: ingests one frame duration per frame and produces a
/// per-interval aggregate on [flush]. Kept free of Flutter/OTel so the
/// arithmetic is unit-testable with real values.
class FrameStatsAccumulator {
  FrameStatsAccumulator({this.jankThresholdMs = 16.7});

  /// Total-span threshold above which a frame counts as jank (a 60 fps
  /// frame budget is 16.7 ms).
  final double jankThresholdMs;

  final List<double> _samples = [];
  int _jankCount = 0;

  /// Record one frame's total duration in milliseconds.
  void ingest(double totalMs) {
    _samples.add(totalMs);
    if (totalMs > jankThresholdMs) _jankCount++;
  }

  /// Compute the aggregate over the collected samples and reset. An empty
  /// interval yields all-zero stats.
  FrameIntervalStats flush({Duration interval = const Duration(seconds: 1)}) {
    if (_samples.isEmpty) {
      return FrameIntervalStats(
        frameCount: 0,
        avgMs: 0,
        p95Ms: 0,
        maxMs: 0,
        jankCount: 0,
        interval: interval,
      );
    }
    _samples.sort();
    var sum = 0.0;
    for (final s in _samples) {
      sum += s;
    }
    final stats = FrameIntervalStats(
      frameCount: _samples.length,
      avgMs: sum / _samples.length,
      p95Ms: _samples[(_samples.length * 0.95 - 1).round().clamp(0, _samples.length - 1)],
      maxMs: _samples.last,
      jankCount: _jankCount,
      interval: interval,
    );
    _samples.clear();
    _jankCount = 0;
    return stats;
  }
}