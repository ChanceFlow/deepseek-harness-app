/// The shared text-activity primitive: one stepped highlight crossing a row's
/// text while the row's work runs.
///
/// Ports the reference's `TextShimmer` (`client/ui-primitives/src/
/// TextShimmer.tsx` and its `.module.css`). The band travels the full width of
/// the content across the first two thirds of [kSweepCycle] and holds at the far
/// edge for the last third, quantised by the reference's `steps(48, end)` —
/// [kSweepSteps] positions, each held for 1/72 of the cycle — after the one-shot
/// [kSweepDelay]. [SweepHighlight] paints it over the row's own text with
/// [BlendMode.srcATop], the composition the reference reaches with an inert
/// decorative copy; the row therefore stays one text node, announced once and
/// still selectable, and no nested widget is built twice.
///
/// Nesting: an instance inside another instance's subtree renders its content
/// only and takes the enclosing instance's activity — the reference's
/// `DecorativeCopy` context, which every nested `TextShimmer` reads instead of
/// its own `active` prop. One wrapper therefore sweeps a whole row once, and
/// text fragments inside it are never swept twice.
///
/// Stillness: a null [SweepHighlight.controller], or
/// `MediaQuery.disableAnimationsOf`, renders the content unchanged with no
/// highlight.
library;

import 'package:flutter/material.dart';

/// One full sweep: the reference's `animation-duration` on both the sweep and
/// the highlight layer (`TextShimmer.module.css`).
const Duration kSweepCycle = Duration(milliseconds: 1500);

/// The one-shot wait before the first sweep: the reference's `animation-delay`.
const Duration kSweepDelay = Duration(milliseconds: 300);

/// The reference's `steps(48, end)` resolution.
const int kSweepSteps = 48;

/// The highlight band's position after [elapsed] on the row's clock.
///
/// Returns the reference's `translateX` for the sweep layer as a fraction of the
/// content width: `-1` while [kSweepDelay] runs, then the `steps(48, end)`
/// quantisation of the keyframes `0% → -100%` and `66.6667%, 100% → +100%` — one
/// of [kSweepSteps] discrete positions across the first two thirds of
/// [kSweepCycle], held whole, then a hold at the far edge. Both ends of the
/// travel are off the content box, so a clock that is not running sweeps
/// nothing.
double sweepTravel(Duration elapsed) {
  final elapsedMs =
      elapsed.inMicroseconds / Duration.microsecondsPerMillisecond;
  final cycleMs = elapsedMs - kSweepDelay.inMilliseconds;
  if (cycleMs <= 0) return -1;
  final travelMs = kSweepCycle.inMilliseconds * 2 / 3;
  final step = (cycleMs % kSweepCycle.inMilliseconds) * kSweepSteps / travelMs;
  return -1 + 2 * step.floor().clamp(0, kSweepSteps) / kSweepSteps;
}

/// The highlight colour a row wears when it names none.
///
/// The reference's platform alias `--dsw-alias-label-shimmer` is a translucent
/// neutral wash — 30% of the palette's `neutral-1000` in light, 45% of
/// `neutral-00` in dark (`design-platform.css:224` / `:342`) — read onto the
/// scheme's [ColorScheme.onSurface]. The chat transcript overrides that alias to
/// its deep-diving shimmer (`ChatView.module.css:121`), which a caller passes as
/// [SweepHighlight.color].
Color sweepGlint(ColorScheme scheme) => scheme.onSurface.withValues(
  alpha: scheme.brightness == Brightness.light ? 0.30 : 0.45,
);

/// The moving mask: the reference's `mask-image` trapezoid — transparent at the
/// sweep layer's leading edge, opaque from 40% to 60%, transparent at its
/// trailing edge — placed at [travel] times the content width.
///
/// [travel] is [sweepTravel]'s output, so the axis runs from one content width
/// to the left of the box at `-1` to one width to the right at `+1`, and
/// [TileMode.clamp] keeps the ends transparent.
LinearGradient sweepBand(double travel, Color glint) => LinearGradient(
  begin: Alignment(2 * travel - 1, 0),
  end: Alignment(2 * travel + 1, 0),
  colors: <Color>[
    glint.withValues(alpha: 0),
    glint,
    glint,
    glint.withValues(alpha: 0),
  ],
  stops: const <double>[0, 0.4, 0.6, 1],
);

/// Sweeps [child] while the row it belongs to is active.
///
/// [controller] is the row's clock: a null one — and reduced motion — leaves the
/// child still. The sweep runs the reference's [kSweepCycle] off that clock's
/// elapsed time rather than off its own period, so every row sweeps at the
/// pinned rate whatever period its controller was built with.
class SweepHighlight extends StatelessWidget {
  const SweepHighlight({
    required this.controller,
    required this.child,
    this.color,
    super.key,
  });

  /// The row's activity clock; null means the row is not running.
  final AnimationController? controller;

  /// The row's content: the real, selectable, announced text.
  final Widget child;

  /// The highlight colour; null takes [sweepGlint].
  final Color? color;

  @override
  Widget build(BuildContext context) {
    // A nested instance renders content only: the enclosing instance owns the
    // highlight, exactly as a nested `TextShimmer` reads `DecorativeCopy`.
    if (_SweepHighlightScope.maybeOf(context) != null) return child;
    final controller = this.controller;
    if (controller == null || MediaQuery.disableAnimationsOf(context)) {
      return _SweepHighlightScope(child: child);
    }
    final glint = color ?? sweepGlint(Theme.of(context).colorScheme);
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) => ShaderMask(
        // The band tints the row's own glyphs: `srcATop` keeps the text's alpha
        // and replaces the covered pixels, which is the reference's decorative
        // copy composited over the real text.
        blendMode: BlendMode.srcATop,
        shaderCallback: (bounds) => sweepBand(
          sweepTravel(controller.lastElapsedDuration ?? Duration.zero),
          glint,
        ).createShader(bounds),
        child: child,
      ),
      child: _SweepHighlightScope(child: child),
    );
  }
}

/// Marks a subtree as owned by an enclosing [SweepHighlight].
///
/// The reference's `DecorativeCopy` context. A nested [SweepHighlight] reads it
/// and renders its content only, so one wrapper sweeps a whole row exactly once.
class _SweepHighlightScope extends InheritedWidget {
  const _SweepHighlightScope({required super.child});

  static _SweepHighlightScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_SweepHighlightScope>();

  @override
  bool updateShouldNotify(_SweepHighlightScope oldWidget) => false;
}
