/// Turn-level activity line — port of the web ChatView turnStatus node:
/// one status label at the timeline tail while the session's turn runs,
/// hopping letter by letter (a rectified sine travelling left to right)
/// with a bright text shimmer glint travelling across the words (the web
/// line's own background-clip:text shimmer), and only while the tail carries
/// no louder signal (the streaming caret speaks once text flows). The elapsed
/// clock joins once the wait is clearly long (the web threshold: 15s),
/// anchored at mount — the web line's own fallback when the turn boundary sits
/// outside the loaded window.
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

import '../theme/theme.dart';
import 'job_list_action.dart' show formatJobDuration;

class TurnStatusRow extends StatefulWidget {
  const TurnStatusRow({super.key});

  @override
  State<TurnStatusRow> createState() => _TurnStatusRowState();
}

class _TurnStatusRowState extends State<TurnStatusRow>
    with TickerProviderStateMixin {
  /// One full wave across the label per hop period.
  static const Duration _hopPeriod = Duration(milliseconds: 1200);

  /// The letters ride the rising half of the sine and rest at the base
  /// line on the falling half: a hop, not a tremor.
  static const double _hopLift = 3.0;

  /// Per-letter phase lag (radians), shallow enough that the wave reads
  /// as travelling through the words.
  static const double _phaseStep = 0.6;

  /// The text shimmer period: matching the web status line's 1.8s shimmer.
  static const Duration _shimmerPeriod = Duration(milliseconds: 1800);

  /// Short turns keep the plain label; the clock only appears once the
  /// wait is clearly long (web showClock threshold).
  static const int _clockAfterMs = 15000;

  final int _startedAt = DateTime.now().millisecondsSinceEpoch;
  late final AnimationController _hop = AnimationController(
    vsync: this,
    duration: _hopPeriod,
  );
  late final AnimationController _shimmer = AnimationController(
    vsync: this,
    duration: _shimmerPeriod,
  );
  Timer? _tick;
  int _elapsedMs = 0;

  @override
  void initState() {
    super.initState();
    _hop.repeat();
    _shimmer.repeat();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _elapsedMs = DateTime.now().millisecondsSinceEpoch - _startedAt;
      });
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _hop.dispose();
    _shimmer.dispose();
    super.dispose();
  }

  /// The label set letter by letter so each one hops on its own phase,
  /// with a bright text shimmer glint gliding across the letters.
  /// Under reduced motion the text renders whole, rests, and has no shimmer.
  Widget _label(
    BuildContext context,
    TextStyle? style,
    Color glint,
    bool reduced,
  ) {
    final label = AppLocalizations.of(context)!.turnStatusWorking;
    if (reduced) return Text(label, style: style);
    return AnimatedBuilder(
      animation: Listenable.merge([_hop, _shimmer]),
      builder: (context, child) {
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) {
            final w = bounds.width;
            final progress = _shimmer.value;
            final bandWidth = w * 0.4;
            final glintCenter = -bandWidth + progress * (w + 2 * bandWidth);
            return ui.Gradient.linear(
              Offset(glintCenter - bandWidth, 0),
              Offset(glintCenter + bandWidth, 0),
              [glint.withValues(alpha: 0), glint, glint.withValues(alpha: 0)],
              const [0.0, 0.5, 1.0],
            );
          },
          child: Padding(
            padding: const EdgeInsets.only(top: _hopLift),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < label.length; i++)
                  Transform.translate(
                    offset: Offset(
                      0,
                      -_hopLift *
                          math.max(
                            0.0,
                            math.sin(_hop.value * 2 * math.pi - i * _phaseStep),
                          ),
                    ),
                    child: Text(label[i], style: style),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final reduced = MediaQuery.disableAnimationsOf(context);
    final style = theme.textTheme.labelLarge?.copyWith(
      fontWeight: FontWeight.w600,
      color: scheme.primary,
    );
    final glint = scheme.statusGlint;
    return Semantics(
      label: l10n.semanticsRunning,
      // The label renders as letters for the hop; assistive technology
      // hears only the run state (the web line marks the decoration
      // aria-hidden and announces the state).
      excludeSemantics: true,
      child: SizedBox(
        height: 26,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // The web line is brand-blue text; the role map's accent
            // seat is primary.
            _label(context, style, glint, reduced),
            if (_elapsedMs >= _clockAfterMs) ...[
              const SizedBox(width: 8),
              Text(
                formatJobDuration(_elapsedMs, l10n),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
