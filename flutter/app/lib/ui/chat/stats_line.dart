/// Composer stats line — port of the web StatsLine: a 12/20 tertiary,
/// centered, ellipsized row of pipe-separated groups above the composer.
library;

import 'dart:async';

import 'package:app/l10n/app_localizations.dart';
import 'package:domain/model/session_window_stats.dart';
import 'package:flutter/material.dart';

import '../shared/menu_sheet.dart';
import '../theme/theme.dart' show kShapeChip;

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

/// Longest "·"-joined prefix of [groups] that paints inside [maxWidth].
///
/// The strip drops whole facts rather than clipping a word: a number cut
/// mid-digit costs a line and tells the reader nothing. The first group
/// always survives — a one-fact strip that overflows still ellipsizes.
String fitStatsGroups(
  List<String> groups,
  TextStyle? style,
  double maxWidth,
  TextScaler textScaler,
) {
  if (groups.isEmpty) return '';
  var fitted = groups.first;
  for (var count = 2; count <= groups.length; count++) {
    final candidate = groups.take(count).join(' · ');
    final painter = TextPainter(
      text: TextSpan(text: candidate, style: style),
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
      maxLines: 1,
    )..layout();
    if (painter.width > maxWidth) break;
    fitted = candidate;
  }
  return fitted;
}

class StatsLine extends StatelessWidget {
  const StatsLine({required this.stats, super.key});

  final SessionWindowStats stats;

  /// Facts in the order a phone should spend width on: how far the session
  /// has run, what it cost, then the timings a phone reader rarely acts on.
  List<String> _groups(AppLocalizations l10n) {
    final groups = <String>[];
    final durationGroups = <String>[];
    if (stats.steps > 0) {
      groups.add(l10n.statsTurnsSteps(stats.steps, stats.turns));
      final durations = <String>[];
      if (stats.llmMs > 0) {
        durations.add(l10n.statsLlmDuration(formatDuration(stats.llmMs)));
      }
      if (stats.toolMs > 0) {
        durations.add(l10n.statsToolDuration(formatDuration(stats.toolMs)));
      }
      if (durations.isNotEmpty) durationGroups.add(durations.join(' · '));
      final speeds = <String>[];
      if (stats.ttftSteps > 0) {
        speeds.add(
          l10n.statsTtftAvg(formatDuration(stats.ttftMs ~/ stats.ttftSteps)),
        );
      }
      if (stats.decodeMs > 0) {
        speeds.add(
          l10n.statsTokensPerSecond(
            formatTokensPerSecond(stats.decodeTokens / (stats.decodeMs / 1000)),
          ),
        );
      }
      if (speeds.isNotEmpty) durationGroups.add(speeds.join(' · '));
    }
    if (stats.billedInputTokens > 0 || stats.outputTokens > 0) {
      groups.add(
        '${l10n.statsInputTokens(formatTokens(stats.billedInputTokens))} · '
        '${l10n.statsOutputTokens(formatTokens(stats.outputTokens))}',
      );
      final cacheHit = stats.cacheHitPercent;
      if (cacheHit != null) groups.add(l10n.statsCacheHit(cacheHit));
    }
    return groups..addAll(durationGroups);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final groups = _groups(l10n);
    if (groups.isEmpty) return const SizedBox.shrink();
    final style = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Padding(
      // Caption spacing: the line belongs to the transcript above it, not
      // to the dock it sits on top of.
      padding: const EdgeInsets.only(top: 2, bottom: 8, left: 8, right: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(kShapeChip),
          onTap: () => _openStatsSheet(context, stats, l10n),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SizedBox(
                  width: double.infinity,
                  child: Text(
                    fitStatsGroups(
                      groups,
                      style,
                      constraints.maxWidth,
                      MediaQuery.textScalerOf(context),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: style,
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  void _openStatsSheet(
    BuildContext context,
    SessionWindowStats stats,
    AppLocalizations l10n,
  ) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    unawaited(
      showMenuSheet<void>(
        context,
        maxHeight: 380,
        builder: (sheetContext) => SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.analytics_outlined,
                    size: 18,
                    color: scheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n.statsTurnsSteps(stats.steps, stats.turns),
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Divider(height: 1, color: scheme.outlineVariant),
              const SizedBox(height: 12),
              if (stats.billedInputTokens > 0 || stats.outputTokens > 0) ...[
                _statRow(
                  theme,
                  Icons.data_usage_outlined,
                  l10n.statsInputTokens(formatTokens(stats.billedInputTokens)),
                  trailing: l10n.statsOutputTokens(
                    formatTokens(stats.outputTokens),
                  ),
                ),
                if (stats.cacheHitPercent case final hit?)
                  _statRow(
                    theme,
                    Icons.cached_outlined,
                    l10n.statsCacheHit(hit),
                  ),
                const SizedBox(height: 8),
              ],
              if (stats.llmMs > 0 || stats.toolMs > 0) ...[
                if (stats.llmMs > 0)
                  _statRow(
                    theme,
                    Icons.smart_toy_outlined,
                    l10n.statsLlmDuration(formatDuration(stats.llmMs)),
                  ),
                if (stats.toolMs > 0)
                  _statRow(
                    theme,
                    Icons.build_outlined,
                    l10n.statsToolDuration(formatDuration(stats.toolMs)),
                  ),
                const SizedBox(height: 8),
              ],
              if (stats.ttftSteps > 0 || stats.decodeMs > 0) ...[
                if (stats.ttftSteps > 0)
                  _statRow(
                    theme,
                    Icons.speed_outlined,
                    l10n.statsTtftAvg(
                      formatDuration(stats.ttftMs ~/ stats.ttftSteps),
                    ),
                  ),
                if (stats.decodeMs > 0)
                  _statRow(
                    theme,
                    Icons.electric_bolt_outlined,
                    l10n.statsTokensPerSecond(
                      formatTokensPerSecond(
                        stats.decodeTokens / (stats.decodeMs / 1000),
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _statRow(
    ThemeData theme,
    IconData icon,
    String text, {
    String? trailing,
  }) {
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: scheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurface,
              ),
            ),
          ),
          if (trailing != null)
            Text(
              trailing,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}
