/// The running Turn's brand mark: the web client's whale tail, drawn from the
/// reference's own SVG geometry and swayed natively while work runs.
///
/// The web `RunningWhaleTail.tsx` mounts a 21KB APNG behind an alpha mask so
/// the tail takes `currentColor`, and keeps a static stroked path
/// (`REST_PATH`, a 16×16 viewBox) for hosts that cannot animate a mask or
/// prefer reduced motion. Flutter has no animated-mask equivalent, so this
/// port draws that same path — [RunningWhaleTailPainter] owns the geometry —
/// and approximates the mask's motion with a continuous sway about the tail's
/// base. Reduced motion draws the still path and runs no controller.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'fish_logo.dart' show parseSvgPath;

/// The reference's static fallback path — `REST_PATH` in the pinned
/// `RunningWhaleTail.tsx`, verbatim: one absolute `M` and fifteen absolute
/// `C` segments, no fill, stroked at [runningWhaleStrokeWidth].
const String runningWhaleRestPath =
    'M8.844 13.742C8.967 12.328 8.45 10.4 8.45 9.65C8.45 8.94 8.88 8.43 9.6 '
    '8.43C11.285 8.43 12.106 8.281 12.685 8.104C13.71 7.791 14.585 6.768 15.055 '
    '5.945C15.137 5.803 14.99 5.641 14.829 5.671C13.829 5.86 12.828 5.376 11.827 '
    '4.978C10.659 4.514 9.491 4.707 8.935 4.876C8.805 4.915 8.658 4.819 8.636 '
    '4.686C8.468 3.643 7.405 2.615 5.498 2.238C4.54 2.048 3.748 1.574 3.347 '
    '1.202C3.252 1.113 3.088 1.125 3.03 1.242C2.628 2.059 2.168 3.82 5.248 '
    '6.115C5.82 6.494 6.31 6.785 6.574 7.637C6.72 8.104 6.157 9.168 6.061 '
    '9.368C5.157 11.27 5.089 12.19 4.926 13.742';

/// The reference viewBox [runningWhaleRestPath] coordinates live in; the
/// widget's `size` maps onto this square.
const double runningWhaleViewBox = 16;

/// The reference stroke width, in viewBox units (the SVG's `strokeWidth={1}`):
/// the stroke scales with the box rather than holding an optical 1px, so the
/// default 14px seat renders the reference's own 0.875px weight.
const double runningWhaleStrokeWidth = 1;

/// The parsed [runningWhaleRestPath]; one parse for every paint.
final ui.Path _restPath = parseSvgPath(runningWhaleRestPath);

/// The running Turn's brand mark: a 14px whale tail that animates while work runs.
class RunningWhaleTail extends StatefulWidget {
  const RunningWhaleTail({super.key, this.size = 14, this.color});

  /// The square box the mark is drawn in, in logical px — the reference's
  /// `calc(14px + var(--dsh-content-font-delta, 0px))` icon seat at its
  /// default delta.
  final double size;

  /// The ink, or null to follow the ambient text colour (`currentColor`).
  final Color? color;

  @override
  State<RunningWhaleTail> createState() => _RunningWhaleTailState();
}

class _RunningWhaleTailState extends State<RunningWhaleTail>
    with SingleTickerProviderStateMixin {
  /// One tail beat. The reference APNG is 60 frames of 50ms; the ink centroid
  /// of its composited frames swings on a ~20-frame (1s) period, which is the
  /// beat the sway reproduces rather than the loop's held opening frames.
  static const Duration _beatPeriod = Duration(milliseconds: 1000);

  /// Peak sway, radians (≈2.9°). The reference mask deforms rather than
  /// translates: its ink centroid travels 0.86px in the 28px frame, 0.43px at
  /// this 14px seat, and a sway of this size carries this glyph's centroid the
  /// same 0.43px. At its peak the stroked glyph's outer edge sits 0.08 viewBox
  /// units (0.07px at 14px) past the box — the clip the reference's own
  /// `overflow: hidden` applies.
  static const double _swayAmplitude = 0.05;

  late final AnimationController _sway;

  @override
  void initState() {
    super.initState();
    _sway = AnimationController(vsync: this, duration: _beatPeriod);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncMotion();
  }

  /// Run the sway only where the host allows motion: the moment animations are
  /// disabled the controller stops, so no frame is scheduled and no ticker
  /// survives the accessibility setting.
  void _syncMotion() {
    if (MediaQuery.disableAnimationsOf(context)) {
      if (_sway.isAnimating) _sway.stop();
    } else if (!_sway.isAnimating) {
      _sway.repeat();
    }
  }

  @override
  void dispose() {
    _sway.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // `currentColor`: the caller's colour, else the ambient text colour, else
    // the scheme's own text role — never a literal. `IconTheme` is not the
    // last resort: Flutter's `ThemeData` default icon colour is
    // `Colors.black87`, a palette literal that is also wrong on a dark
    // surface, so the scheme role is the only safe fallback.
    final ink =
        widget.color ??
        DefaultTextStyle.of(context).style.color ??
        Theme.of(context).colorScheme.onSurface;
    final still = CustomPaint(
      size: Size.square(widget.size),
      painter: RunningWhaleTailPainter(ink),
    );
    return ExcludeSemantics(
      // The reference marks the icon `aria-hidden`; the tail is decoration.
      child: SizedBox.square(
        dimension: widget.size,
        // The reference's `overflow: hidden`: the fixed footprint contains the
        // sway at every size.
        child: ClipRect(
          child: MediaQuery.disableAnimationsOf(context)
              ? still
              : AnimatedBuilder(
                  animation: _sway,
                  builder: (context, child) => Transform.rotate(
                    angle: math.sin(_sway.value * 2 * math.pi) * _swayAmplitude,
                    // The tail hinges where it meets the body — the reference
                    // path's own baseline at the bottom of the viewBox.
                    alignment: Alignment.bottomCenter,
                    child: child,
                  ),
                  child: still,
                ),
        ),
      ),
    );
  }
}

/// Paints [runningWhaleRestPath] the way the reference strokes it: no fill, a
/// [runningWhaleStrokeWidth] stroke, scaled from the 16-unit viewBox onto the
/// square box. Public so a caller or test can read back the ink the widget
/// resolved.
class RunningWhaleTailPainter extends CustomPainter {
  const RunningWhaleTailPainter(this.color);

  /// The ink the tail is stroked with.
  final Color color;

  /// The device-space stroke width for a box of [size] logical px.
  static double strokeWidthFor(double size) =>
      runningWhaleStrokeWidth * size / runningWhaleViewBox;

  @override
  void paint(Canvas canvas, Size size) {
    final side = size.shortestSide;
    if (side <= 0) return;
    final scale = side / runningWhaleViewBox;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidthFor(side);
    canvas.drawPath(
      _restPath.transform(Matrix4.diagonal3Values(scale, scale, 1).storage),
      stroke,
    );
  }

  @override
  bool shouldRepaint(RunningWhaleTailPainter oldDelegate) =>
      oldDelegate.color != color;
}
