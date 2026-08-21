import 'package:dev/src/frame_stats.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('empty interval yields zero stats', () {
    final acc = FrameStatsAccumulator();
    final stats = acc.flush();
    expect(stats.frameCount, 0);
    expect(stats.avgMs, 0);
    expect(stats.p95Ms, 0);
    expect(stats.maxMs, 0);
    expect(stats.jankCount, 0);
    expect(stats.fps, 0);
  });

  test('ingests frames and computes avg/p95/max/jank/fps', () {
    final acc = FrameStatsAccumulator(jankThresholdMs: 16.7);
    // 10 frames of 10ms + 5 frames of 40ms (jank) + 5 frames of 20ms (jank).
    for (var i = 0; i < 10; i++) {
      acc.ingest(10);
    }
    for (var i = 0; i < 5; i++) {
      acc.ingest(40);
    }
    for (var i = 0; i < 5; i++) {
      acc.ingest(20);
    }
    final stats = acc.flush(interval: const Duration(seconds: 1));
    expect(stats.frameCount, 20);
    expect(stats.avgMs, closeTo(20, 0.001));
    expect(stats.p95Ms, closeTo(40, 0.001));
    expect(stats.maxMs, 40);
    expect(stats.jankCount, 10);
    expect(stats.fps, 20);
  });

  test('flush resets the accumulator', () {
    final acc = FrameStatsAccumulator();
    acc.ingest(5);
    acc.ingest(7);
    expect(acc.flush().frameCount, 2);
    expect(acc.flush().frameCount, 0);
  });
}