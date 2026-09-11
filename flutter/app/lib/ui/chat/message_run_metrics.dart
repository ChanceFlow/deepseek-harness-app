/// Per-message run metrics — the caption a finalized assistant message's
/// action row carries.
///
/// The reference renders `· Ran for 15s · TTFT 1.2s · 34 tok/s` from a
/// turn's step timings (`ui-chat/src/client/chat/TurnUsagePanel.tsx:132-181`,
/// `contract/turn-metrics.ts:42-51`). The recorded session log this client
/// decodes carries only two of those boundaries on an assistant message: the
/// first output delta (`firstTokenAtEpochMs`) and the `assistant/message`
/// event time (`createdAtEpochMs`, the reference's `completedTime`), plus the
/// provider's token accounting (`usage`).
///
/// So this row states what those boundaries measure — decode throughput over
/// the first-token..message window, and the message's reported token total.
/// Turn wall time and TTFT need a `turn/start`/`turn/end` timestamp and the
/// owning `step/start` time, neither of which the client exposes; they are
/// omitted rather than approximated.
library;

import 'package:app/l10n/app_localizations.dart';
import 'package:domain/model/token_usage.dart';

import 'stats_line.dart';

/// The ` · `-joined metrics caption for one finalized assistant message, or
/// null when the host reported no usable figure.
String? messageRunMetricsText({
  required TokenUsage? usage,
  required int? firstTokenAtEpochMs,
  required int messageAtEpochMs,
  required AppLocalizations l10n,
}) {
  final parts = <String>[];
  final outputTokens = usage?.outputTokens;
  // Throughput needs both boundaries and a positive window: a zero or
  // clamped interval would print a figure the host never measured.
  if (outputTokens != null &&
      outputTokens > 0 &&
      firstTokenAtEpochMs != null &&
      messageAtEpochMs > firstTokenAtEpochMs) {
    final seconds = (messageAtEpochMs - firstTokenAtEpochMs) / 1000;
    parts.add(
      l10n.messageTokensPerSecond(
        formatTokensPerSecond(outputTokens / seconds),
      ),
    );
  }
  if (usage case final TokenUsage reported) {
    // The provider total when it sent one; otherwise the sum of the buckets
    // it did send. Never zero-filled: an absent total stays absent.
    final total =
        reported.totalTokens ??
        (reported.billedInputTokens + reported.outputTokens);
    if (total > 0) parts.add(l10n.messageTokenUsage(formatTokens(total)));
  }
  return parts.isEmpty ? null : parts.join(' · ');
}
