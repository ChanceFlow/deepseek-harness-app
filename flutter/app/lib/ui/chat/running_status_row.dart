/// The running Turn's status line: one line at the transcript tail while the
/// Session runs.
///
/// The chrome follows the reference's `chat/RunningStatus.tsx` and the
/// `ChatView.module.css` `.running*` rules — the brand tail, the optional
/// hairline above it, the 12px/22px line, and the reduced-motion behaviour.
/// The words are this app's own: the label is the static
/// [AppLocalizations.turnProcessDeepDiving] (`Deep diving…` / `正在深入研究…`),
/// with the Turn's elapsed clock beside it as a second, dimmer element — not
/// the reference's single `Deep diving for {duration} ···` sentence.
///
/// Like the reference, the ticking text is isolated from the rest of the
/// transcript and only the static state is announced, in one live region, so
/// assistive technology is not interrupted once a second.
///
/// The label wears the palette's own deep-diving alias ([DshSchemeColors.labelDeepDiving])
/// and its sweep the deep-diving shimmer alias, through the shared
/// [SweepHighlight] at the reference's `TextShimmer` timing; reduced motion
/// stops both the sweep and the tail's sway.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

import '../theme/theme.dart';
import 'run_duration.dart';
import 'running_whale_tail.dart';
import 'sweep_highlight.dart';

class RunningStatusRow extends StatefulWidget {
  const RunningStatusRow({
    this.startedAtEpochMs,
    this.showDivider = false,
    super.key,
  });

  /// The running Turn's start, or null when its boundary sits outside the
  /// loaded window; the label then carries the state without a clock.
  final int? startedAtEpochMs;

  /// Whether the row above carries output. The reference draws the hairline
  /// only when the transcript above ends in something other than an input, so
  /// a status line never rules off the reader's own message.
  final bool showDivider;

  @override
  State<RunningStatusRow> createState() => _RunningStatusRowState();
}

class _RunningStatusRowState extends State<RunningStatusRow>
    with SingleTickerProviderStateMixin {
  /// The row's activity clock. Its period is the primitive's own
  /// [kSweepCycle]; a controller that repeats is all [SweepHighlight] needs.
  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: kSweepCycle,
  );
  Timer? _tick;
  late int _nowMs = DateTime.now().millisecondsSinceEpoch;

  @override
  void initState() {
    super.initState();
    _syncTick();
  }

  @override
  void didUpdateWidget(covariant RunningStatusRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.startedAtEpochMs == oldWidget.startedAtEpochMs) return;
    // A start that arrives or leaves re-arms the clock: the Turn boundary can
    // appear or fall outside the loaded window while this State stays mounted.
    // The baseline refreshes with it, so a late start reads its own age on the
    // first frame instead of the previous start's.
    if (widget.startedAtEpochMs != null) {
      _nowMs = DateTime.now().millisecondsSinceEpoch;
    }
    _syncTick();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncSweep();
  }

  /// Keeps the 1 Hz clock alive exactly while a start can be named: without it
  /// the label freezes at its first value, and with a stale one the row
  /// rebuilds once a second against a label that cannot change.
  void _syncTick() {
    if (widget.startedAtEpochMs != null) {
      _tick ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() => _nowMs = DateTime.now().millisecondsSinceEpoch);
      });
      return;
    }
    _tick?.cancel();
    _tick = null;
  }

  /// Runs the row's clock unless the host asked for reduced motion, where the
  /// line stays still and keeps its tail. [SweepHighlight] reads the same
  /// setting and draws no band under it either.
  void _syncSweep() {
    if (DshMotion.isReducedMotion(context)) {
      if (_sweep.isAnimating) _sweep.stop();
    } else if (!_sweep.isAnimating) {
      _sweep.repeat();
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    _sweep.dispose();
    super.dispose();
  }

  /// The elapsed clock, or null while the Turn's start is unknown.
  ///
  /// Floored at one second — the reference's `Math.max(1000, now - startTime)`
  /// — so a fresh Turn reads `1s`, never `0s`.
  String? _clock(AppLocalizations l10n) {
    final start = widget.startedAtEpochMs;
    if (start == null) return null;
    final elapsed = math.max(1000, _nowMs - start);
    return runDurationParts(elapsed, l10n).map((part) => part.text).join();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;
    // One label line shared by the sweep and the clock: 12px on a 22px line.
    final line = theme.textTheme.bodySmall?.copyWith(
      fontSize: 12,
      height: 22 / 12,
      fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
    );
    final label = Text(
      l10n.turnProcessDeepDiving,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: line?.copyWith(color: scheme.labelDeepDiving),
    );
    final clock = _clock(l10n);
    return Semantics(
      container: true,
      liveRegion: true,
      // The static state is announced once, never the ticking clock, so no
      // visible text enters the semantics tree.
      label: l10n.turnProcessDeepDiving,
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.showDivider)
              Container(
                height: 0.5,
                margin: const EdgeInsets.only(top: 8, bottom: 10),
                color: scheme.outlineVariant,
              ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                RunningWhaleTail(size: 14, color: scheme.labelDeepDiving),
                const SizedBox(width: 6),
                Flexible(
                  child: SweepHighlight(
                    controller: _sweep,
                    color: scheme.labelDeepDivingShimmer,
                    child: label,
                  ),
                ),
                // The clock is its own element, dimmer than the label and
                // outside its sweep; the reference folds it into the sentence
                // instead, which this app does not do.
                if (clock != null) ...[
                  const SizedBox(width: 8),
                  Text(
                    clock,
                    maxLines: 1,
                    style: line?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
