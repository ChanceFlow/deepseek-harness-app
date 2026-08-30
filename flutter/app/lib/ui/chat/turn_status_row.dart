/// Turn-level activity line — port of the web ChatView turnStatus node:
/// one status label at the timeline tail while the session's turn runs,
/// hopping letter by letter (a rectified sine travelling left to right)
/// under the shared sweep glare (the web line's own text shimmer), and
/// only while the tail carries no louder signal (the streaming caret
/// speaks once text flows). The elapsed clock joins once the wait is
/// clearly long (the web threshold: 15s), anchored at mount — the web
/// line's own fallback when the turn boundary sits outside the loaded
/// window.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

import 'job_list_action.dart' show formatJobDuration;
import 'sweep_highlight.dart';

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

  /// The glare band's pass: the web status line's shimmer period.
  static const Duration _glarePeriod = Duration(milliseconds: 1800);

  /// Short turns keep the plain label; the clock only appears once the
  /// wait is clearly long (web showClock threshold).
  static const int _clockAfterMs = 15000;

  final int _startedAt = DateTime.now().millisecondsSinceEpoch;
  late final AnimationController _hop = AnimationController(
    vsync: this,
    duration: _hopPeriod,
  );
  late final AnimationController _glare = AnimationController(
    vsync: this,
    duration: _glarePeriod,
  );
  Timer? _tick;
  int _elapsedMs = 0;

  @override
  void initState() {
    super.initState();
    _hop.repeat();
    _glare.repeat();
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
    _glare.dispose();
    super.dispose();
  }

  /// The label set letter by letter so each one hops on its own phase,
  /// with the shared sweep glare band gliding across the whole word. The
  /// top padding keeps the lifted letters inside the mask's bounds.
  /// Under reduced motion the text renders whole and rests.
  Widget _label(BuildContext context, TextStyle? style, bool reduced) {
    final label = AppLocalizations.of(context)!.turnStatusWorking;
    if (reduced) return Text(label, style: style);
    return ClipRect(
      child: SweepHighlight(
        controller: _glare,
        child: Padding(
          padding: const EdgeInsets.only(top: _hopLift),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < label.length; i++)
                AnimatedBuilder(
                  animation: _hop,
                  child: Text(label[i], style: style),
                  builder: (context, child) {
                    final wave = math.sin(
                      _hop.value * 2 * math.pi - i * _phaseStep,
                    );
                    return Transform.translate(
                      offset: Offset(0, -_hopLift * math.max(0.0, wave)),
                      child: child,
                    );
                  },
                ),
            ],
          ),
        ),
      ),
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
            _label(context, style, reduced),
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
