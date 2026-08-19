/// Composer stats line — port of the web StatsLine: a 12/20 tertiary,
/// centered, ellipsized row of pipe-separated groups above the composer.
library;

import 'package:domain/model/session_window_stats.dart';
import 'package:flutter/material.dart';

import '../theme/deepsuite_extension.dart';

/// Compact token count: 517 / 12.2K / 1.2M (one decimal under 100).
String formatTokens(int n) {
  String scaled(double v) => v >= 100
      ? v.round().toString()
      : (v * 10).round() / 10 % 1 == 0
      ? v.round().toString()
      : ((v * 10).round() / 10).toString();
  if (n < 1000) return n.toString();
  if (n < 1000000) return '${scaled(n / 1000)}K';
  return '${scaled(n / 1000000)}M';
}

/// Compact duration: 45.2s under a minute, 2m42s from there on.
String formatDuration(int ms) {
  final s = ms / 1000;
  if (s < 60) {
    final tenths = (s * 10).round();
    return tenths % 10 == 0 ? '${tenths ~/ 10}s' : '${tenths / 10}s';
  }
  final whole = s.round();
  return '${whole ~/ 60}m${whole % 60}s';
}

/// Decode-throughput figure: whole from ten up, one decimal below.
String formatTokensPerSecond(double tps) {
  final clamped = tps < 0 ? 0.0 : tps;
  if (clamped >= 10) return clamped.round().toString();
  final tenths = (clamped * 10).round();
  return tenths % 10 == 0
      ? (tenths ~/ 10).toString()
      : (tenths / 10).toString();
}

class StatsLine extends StatelessWidget {
  const StatsLine({super.key, required this.stats});

  final SessionWindowStats stats;

  @override
  Widget build(BuildContext context) {
    final groups = <String>[];
    if (stats.steps > 0) {
      groups.add('${stats.turns} turns · ${stats.steps} steps');
      final durations = <String>[];
      if (stats.llmMs > 0) durations.add('LLM ${formatDuration(stats.llmMs)}');
      if (stats.toolMs > 0) {
        durations.add('Tool call ${formatDuration(stats.toolMs)}');
      }
      if (durations.isNotEmpty) groups.add(durations.join(' · '));
      final speeds = <String>[];
      if (stats.ttftSteps > 0) {
        speeds.add(
          'TTFT avg ${formatDuration(stats.ttftMs ~/ stats.ttftSteps)}',
        );
      }
      if (stats.decodeMs > 0) {
        speeds.add(
          '${formatTokensPerSecond(stats.decodeTokens / (stats.decodeMs / 1000))} tok/s',
        );
      }
      if (speeds.isNotEmpty) groups.add(speeds.join(' · '));
    }
    if (stats.billedInputTokens > 0 || stats.outputTokens > 0) {
      final cacheHit = stats.cacheHitPercent;
      if (cacheHit != null) groups.add('Cache hit $cacheHit%');
      groups.add(
        'Input ${formatTokens(stats.billedInputTokens)} tok · '
        'Output ${formatTokens(stats.outputTokens)} tok',
      );
    }
    if (groups.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      width: double.infinity,
      child: Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 2),
        child: Text(
          groups.join(' | '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.labelSmall
              ?.copyWith(color: dsOf(context).labelTertiary),
        ),
      ),
    );
  }
}
