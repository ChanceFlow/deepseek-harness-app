/// Composer context-occupancy ring — port of the web ContextMeter
/// (14px ring, 2px stroke). The ring is a permanent composer seat: while
/// no usage sample or route capacity exists it sits as a bare
/// `outlineVariant` circle, so the dock row never reflows around an
/// appearing/disappearing control. The web removes the
/// whole meter in that state (`ContextMeter.tsx` returns null on missing
/// occupancy); always-drawing the empty track is a mobile deviation
/// recorded in
/// [the ring visibility and popup note](../../../../../.agents/notes/implemented/bug-fix/2026-08-30-context-ring-always-on-and-anchored-popup.md).
/// Occupancy prefers the projected sample (web ui-conversation
/// StatsLine.tsx `contextOccupancy`: `projectedTokens ?? pressureTokens`),
/// so the ring moves while a turn streams instead of holding still at the
/// last usage sample. Tap opens the composition panel (system / tools /
/// conversation legend) as an anchored popup from the ring's own position
/// — the web meter's popover (`ContextMeter.module.css` `.panel`: menu
/// surface, r12, inverted hairline, lv3 shadow), delivered by the native
/// [MenuAnchor].
library;

import 'package:app/l10n/app_localizations.dart';
import 'package:domain/model/context_pressure.dart';
import 'package:flutter/material.dart';

import '../theme/theme.dart' show kShapeMenuSheet;
import 'stats_line.dart' show formatTokens;

class ContextRing extends StatefulWidget {
  const ContextRing({required this.pressure, super.key, this.breakdown});

  final ContextPressure? pressure;

  /// Heuristic composition shown in the tap-open panel; may be null.
  final ContextBreakdown? breakdown;

  @override
  State<ContextRing> createState() => _ContextRingState();
}

class _ContextRingState extends State<ContextRing> {
  final MenuController _menu = MenuController();

  /// Whether the widget carries both the occupancy numerator and the
  /// route capacity; without them the ring is an empty, inert track.
  bool get _occupied {
    final pressure = widget.pressure;
    final used = pressure?.projectedTokens ?? pressure?.pressureTokens;
    final window = pressure?.contextWindow;
    return used != null && window != null && window > 0;
  }

  @override
  void didUpdateWidget(ContextRing oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A model switch or session change can remove capacity while the
    // panel is open; close the stale panel instead of preserving it
    // (the web meter's availability effect).
    if (_menu.isOpen && !_occupied) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _menu.isOpen) _menu.close();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final pressure = widget.pressure;
    final used = pressure?.projectedTokens ?? pressure?.pressureTokens;
    final window = pressure?.contextWindow;
    final available = used != null && window != null && window > 0;
    final occupancy = available
        ? (used / window).clamp(0.0, 1.0).toDouble()
        : 0.0;
    final percent = (occupancy * 100).round();
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    return MenuAnchor(
      // With no sample, menuChildren is empty, so the anchor itself is
      // inert and the ring below loses its tap handler.
      controller: _menu,
      // A dismiss tap closes the popup and never reaches the ring, so
      // the anchor tap below can only open (the web trigger's toggle
      // needs no double-fire guard).
      consumeOutsideTap: true,
      // House menu surface, the same card family as the picker sheets:
      // menu-tone background, the outline-variant hairline, and the
      // menu-sheet radius (elevation 3 rides the framework's shadow).
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll<Color>(scheme.surfaceContainer),
        elevation: const WidgetStatePropertyAll<double>(3),
        shape: WidgetStatePropertyAll<OutlinedBorder>(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(kShapeMenuSheet),
            side: BorderSide(color: scheme.outlineVariant),
          ),
        ),
      ),
      menuChildren: available
          ? [_panel(context, percent: percent, used: used, window: window)]
          : const <Widget>[],
      builder: (context, controller, child) => Semantics(
        label: available ? l10n.contextUsedPercent(percent) : l10n.contextLabel,
        button: available,
        child: InkWell(
          borderRadius: BorderRadius.circular(7),
          // The web trigger toggles the panel on tap; outside taps and
          // Escape close through MenuAnchor natively.
          onTap: available
              ? () {
                  if (controller.isOpen) {
                    controller.close();
                  } else {
                    controller.open();
                  }
                }
              : null,
          child: SizedBox(
            width: 14,
            height: 14,
            // Two states, one footprint. The reading is the native
            // determinate M3 indicator; the empty seat is a bare
            // outline-variant circle — the indicator's own track,
            // drawn as a static placeholder so the always-present ring
            // never reads as a spinner (activity spinners elsewhere
            // assert their absence through this same type finder, and
            // a 0-value indicator animates its track-in).
            child: available
                ? CircularProgressIndicator(
                    value: occupancy,
                    strokeWidth: 2,
                    color: scheme.secondary,
                    backgroundColor: scheme.outlineVariant,
                  )
                : DecoratedBox(
                    key: const ValueKey('context-ring-track'),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: scheme.outlineVariant,
                        width: 2,
                      ),
                    ),
                    child: const SizedBox.expand(),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _panel(
    BuildContext context, {
    required int percent,
    required int used,
    required int window,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final rows = <(String, int, Color)>[
      (
        l10n.systemPromptLabel,
        widget.breakdown?.systemTokens ?? 0,
        scheme.outline,
      ),
      (l10n.toolsLabel, widget.breakdown?.toolsTokens ?? 0, scheme.tertiary),
      (
        l10n.conversationLabel,
        widget.breakdown?.messageTokens ?? 0,
        scheme.primary,
      ),
    ];
    return SizedBox(
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
              l10n.contextTokens(formatTokens(used), formatTokens(window)),
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
    );
  }
}
