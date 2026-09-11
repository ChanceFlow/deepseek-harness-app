/// Provider-reported token accounting for one model call.
///
/// Neutral counterpart of the harness `TokenUsage` record: counts are
/// DISJOINT, so billed input is `input + cacheRead + cacheWrite` and
/// `output` includes `reasoning`. The optional fields are absent when the
/// adapter reported no cache or reasoning split — never zero-filled here,
/// because the ledger must not invent a figure the host never sent.
library;

final class TokenUsage {
  const TokenUsage({
    required this.inputTokens,
    required this.outputTokens,
    this.totalTokens,
    this.cacheReadTokens,
    this.cacheWriteTokens,
    this.reasoningTokens,
  });

  /// Uncached input tokens only.
  final int inputTokens;

  /// Completion tokens, reasoning included.
  final int outputTokens;

  /// Full-call total including aggregate prompt and output tokens; null when
  /// the adapter did not preserve or derive one.
  final int? totalTokens;

  /// Input tokens served from a provider cache.
  final int? cacheReadTokens;

  /// Input tokens written into a provider cache.
  final int? cacheWriteTokens;

  /// Reasoning tokens carved out of [outputTokens].
  final int? reasoningTokens;

  /// Billed input total, or null when no bucket was reported.
  ///
  /// [inputTokens] and [outputTokens] are required on the wire, so a present
  /// usage object always yields a number here.
  int get billedInputTokens =>
      inputTokens + (cacheReadTokens ?? 0) + (cacheWriteTokens ?? 0);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TokenUsage &&
          other.inputTokens == inputTokens &&
          other.outputTokens == outputTokens &&
          other.totalTokens == totalTokens &&
          other.cacheReadTokens == cacheReadTokens &&
          other.cacheWriteTokens == cacheWriteTokens &&
          other.reasoningTokens == reasoningTokens);

  @override
  int get hashCode => Object.hash(
    inputTokens,
    outputTokens,
    totalTokens,
    cacheReadTokens,
    cacheWriteTokens,
    reasoningTokens,
  );
}
