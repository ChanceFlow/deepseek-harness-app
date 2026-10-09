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
    this.clock,
    super.key,
  });

  /// The row's time source, in epoch milliseconds.
  ///
  /// Null reads the wall clock, which is what the app does. A test injects a
  /// fixed source instead: the label is whole seconds, so a wall-clock read
  /// that lands a second later than the fixture computed its start turns a
  /// loaded machine into a failing assertion rather than a slower test.
  final int Function()? clock;

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
  late int _nowMs = _readClock();

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
      _nowMs = _readClock();
    }
    _syncTick();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncSweep();
  }

  /// One reading of the row's time source: the wall clock unless a caller
  /// injected a fixed one.
  int _readClock() =>
      widget.clock?.call() ?? DateTime.now().millisecondsSinceEpoch;

  /// Keeps the 1 Hz clock alive exactly while a start can be named: without it
  /// the label freezes at its first value, and with a stale one the row
  /// rebuilds once a second against a label that cannot change.
  void _syncTick() {
    if (widget.startedAtEpochMs != null) {
      _tick ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() => _nowMs = _readClock());
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

  /// The reference's own running sentence: the state with the elapsed clock,
  /// floored at one second (`Math.max(1000, now - startTime)`), or the bare
  /// state while the Turn's start is unknown.
  String _label(AppLocalizations l10n) {
    final start = widget.startedAtEpochMs;
    if (start == null) return l10n.turnProcessDeepDiving;
    final elapsed = math.max(1000, _nowMs - start);
    final duration = runDurationParts(
      elapsed,
      l10n,
    ).map((part) => part.text).join();
    return l10n.turnProcessDeepDivingFor(duration);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;
    // The reference's own line: 12px on a 22px line, the sentence under the
    // stepped sweep.
    final label = Text(
      _label(l10n),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      // The reference's running line: two steps under the content size on its
      // own 22px line (`ChatView.module.css:122-123`), tabular so the clock
      // does not move the row.
      style: DshType.chatRunningLabel
          .style(color: scheme.labelDeepDiving)
          .copyWith(
            fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
          ),
    );
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
                // The reference's hairline is its own derived alias —
                // `color-mix(border-l1 75%, border-l2)`
                // (`ChatView.module.css:141`).
                color: scheme.runningDivider,
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
              ],
            ),
          ],
        ),
      ),
    );
  }
}
