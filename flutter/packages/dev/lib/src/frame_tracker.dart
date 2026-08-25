/// Frame-rate telemetry: per-frame histogram + jank counter via
/// `WidgetsBinding.addTimingsCallback`, per-second fps gauge.
///
/// Uses the framework's built-in [FrameTiming] stream — no third-party
/// instrumentation — and emits through the [DebugTelemetry] facade:
/// - `app.frame.total_ms` histogram: one record per frame (total span);
/// - `app.frame.jank_total` counter: +1 per frame over the jank threshold;
/// - `app.frame.fps` gauge: frames per second, refreshed each second.
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/widgets.dart';
import 'package:flutter/scheduler.dart' show FrameTiming;

import 'build_info.dart' show kDebugTelemetryEnabled;
import 'frame_stats.dart';
import 'telemetry.dart';

class FrameTracker {
  FrameTracker({
    required this.telemetry,
    FrameStatsAccumulator? accumulator,
    this.jankThresholdMs = 16.7,
  }) : _accumulator = accumulator ?? FrameStatsAccumulator();

  final DebugTelemetry telemetry;
  final FrameStatsAccumulator _accumulator;
  final double jankThresholdMs;

  Timer? _timer;
  bool _started = false;

  /// Whether the timings callback is registered (exposed for tests).
  bool get isStarted => _started;

  /// Register the timings callback and start the per-second fps gauge
  /// timer. No-op in release mode when telemetry is compiled out (stable
  /// releases); debug and prerelease release builds still track.
  void start() {
    if (_started || (kReleaseMode && !kDebugTelemetryEnabled)) return;
    _started = true;
    WidgetsBinding.instance.addTimingsCallback(_onTimings);
    _timer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _emitFps(_accumulator.flush(interval: const Duration(seconds: 1))),
    );
  }

  void stop() {
    if (!_started) return;
    WidgetsBinding.instance.removeTimingsCallback(_onTimings);
    _timer?.cancel();
    _timer = null;
    _started = false;
  }

  void _onTimings(List<FrameTiming> timings) {
    for (final timing in timings) {
      final totalMs = timing.totalSpan.inMicroseconds / 1000.0;
      telemetry.record('app.frame.total_ms', totalMs);
      if (totalMs > jankThresholdMs) {
        telemetry.count('app.frame.jank_total');
      }
      _accumulator.ingest(totalMs);
    }
  }

  void _emitFps(FrameIntervalStats stats) {
    telemetry.setGauge('app.frame.fps', stats.fps);
  }
}
