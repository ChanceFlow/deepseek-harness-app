/// Composer context-occupancy ring — port of the web ContextMeter
/// (14px ring, 2px stroke): renders nothing until a used value and the
/// route capacity both exist. Occupancy prefers the projected sample
/// (web ui-conversation StatsLine.tsx `contextOccupancy`:
/// `projectedTokens ?? pressureTokens`), so the ring moves while a turn
/// streams instead of holding still at the last usage sample. Tap opens
/// the composition panel (system / tools / conversation legend, web panel
/// chrome).
library;

import 'package:app/l10n/app_localizations.dart';
import 'package:domain/model/context_pressure.dart';
import 'package:flutter/material.dart';

import '../theme/deepsuite_extension.dart';
import '../theme/deepsuite_tokens.dart';
import 'stats_line.dart' show formatTokens;

class ContextRing extends StatelessWidget {
  const ContextRing({super.key, required this.pressure, this.breakdown});

  final ContextPressure? pressure;

  /// Heuristic composition shown in the tap-open panel; may be null.
  final ContextBreakdown? breakdown;

  @override
  Widget build(BuildContext context) {
    final used = pressure?.projectedTokens ?? pressure?.pressureTokens;
    final window = pressure?.contextWindow;
    if (used == null || window == null || window <= 0) {
      return const SizedBox.shrink();
    }
    final occupancy = (used / window).clamp(0.0, 1.0).toDouble();
    final percent = (occupancy * 100).round();
    final l10n = AppLocalizations.of(context)!;
    return Semantics(
      label: l10n.contextUsedPercent(percent),
      button: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(7),
        onTap: () => _openPanel(context, percent, used, window),
        // Native occupancy ring: a determinate M3 progress indicator at
        // the web meter's 14px footprint — same secondary arc on the
        // outline-variant track, with the component's progress semantics
        // in place of the hand-drawn painter.
        child: SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(
            value: occupancy,
            strokeWidth: 2,
            color: Theme.of(context).colorScheme.secondary,
            backgroundColor: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
      ),
    );
  }

  void _openPanel(BuildContext context, int percent, int used, int window) {
    // Web anchors a popover above the ring; mobile v2 uses a right-aligned
    // bottom sheet-like dialog with the same panel chrome (deviation §8.1).
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final ds = dsOf(dialogContext);
        final theme = Theme.of(dialogContext);
        final l10n = AppLocalizations.of(dialogContext)!;
        final rows = <(String, int, Color)>[
          (
            l10n.systemPromptLabel,
            breakdown?.systemTokens ?? 0,
            DeepSuiteStatic.neutralBluish400,
          ),
          (
            l10n.toolsLabel,
            breakdown?.toolsTokens ?? 0,
            const Color(0xffA78BFA),
          ), // violet-400 literal, as the web
          (
            l10n.conversationLabel,
            breakdown?.messageTokens ?? 0,
            DeepSuiteStatic.blue450,
          ),
        ];
        return Dialog(
          alignment: Alignment.bottomCenter,
          backgroundColor: ds.menu,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: ds.divider),
          ),
          child: SizedBox(
            width: 264,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.contextUsedPercent(percent),
                    style: theme.textTheme.bodyMedium,
                  ),
                  // Web panel header `.figures`: the reading's numerator
                  // and capacity in compact token form.
                  Text(
                    l10n.contextTokens(
                      formatTokens(used),
                      formatTokens(window),
                    ),
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 6),
                  for (final (label, tokens, color) in rows)
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(child: Text(label)),
                        Text('$tokens'),
                      ],
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
