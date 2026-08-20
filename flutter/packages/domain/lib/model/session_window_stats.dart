/// Session window statistics — the web StatsLine fallback fold
/// ("what is on screen"): turn/step counts, LLM and tool wall time,
/// TTFT average, decode throughput, and summed provider usage.
library;

final class SessionWindowStats {
  const SessionWindowStats({
    this.turns = 0,
    this.steps = 0,
    this.llmMs = 0,
    this.toolMs = 0,
    this.ttftMs = 0,
    this.ttftSteps = 0,
    this.decodeMs = 0,
    this.decodeTokens = 0,
    this.billedInputTokens = 0,
    this.outputTokens = 0,
    this.cacheReadTokens = 0,
  });

  final int turns;
  final int steps;
  final int llmMs;
  final int toolMs;
  final int ttftMs;
  final int ttftSteps;
  final int decodeMs;
  final int decodeTokens;

  /// Durable usage sums for the billing group.
  final int billedInputTokens;
  final int outputTokens;
  final int cacheReadTokens;

  /// Cache-hit share of billed input; null when nothing was billed.
  int? get cacheHitPercent => billedInputTokens == 0
      ? null
      : (cacheReadTokens * 100 / billedInputTokens).round();

  @override
  bool operator ==(Object other) =>
      other is SessionWindowStats &&
      other.turns == turns &&
      other.steps == steps &&
      other.llmMs == llmMs &&
      other.toolMs == toolMs &&
      other.ttftMs == ttftMs &&
      other.ttftSteps == ttftSteps &&
      other.decodeMs == decodeMs &&
      other.decodeTokens == decodeTokens &&
      other.billedInputTokens == billedInputTokens &&
      other.outputTokens == outputTokens &&
      other.cacheReadTokens == cacheReadTokens;

  @override
  int get hashCode => Object.hash(
    turns,
    steps,
    llmMs,
    toolMs,
    ttftMs,
    ttftSteps,
    decodeMs,
    decodeTokens,
    billedInputTokens,
    outputTokens,
    cacheReadTokens,
  );
}
