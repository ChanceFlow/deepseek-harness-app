/// Continuation hint for a scrolling region — the web
/// WorkspaceBrowser `.fade` made mobile-correct: the content dissolves
/// into its own surface at the edge through a `dstIn` mask, instead of
/// sliding under an overlay band. An overlay band reads as a stuck-on
/// banner: a saturated row (the selected-session fill) passing beneath a
/// half-transparent strip shows through it faded, like a blur from
/// behind. A dissolve belongs to the list itself — nothing overlays,
/// nothing bleeds through, and the hint survives both brightnesses
/// because the caller passes the surface role it sits on.
///
/// Hand-built chrome: this SDK ships no edge-fade component (the
/// sidebar edge-fade note records the reason).
library;

import 'package:flutter/material.dart';

class EdgeFade extends StatelessWidget {
  const EdgeFade({
    required this.surface,
    required this.child,
    super.key,
    this.extent = 24,
  });

  /// The surface the list dissolves into. Under `dstIn` only the
  /// shader's alpha ramp reads through, so any ColorScheme role that
  /// matches the backdrop is a correct value.
  final Color surface;

  final Widget child;

  /// Height of the dissolve zone at the bottom edge.
  final double extent;

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (bounds) {
        final start = ((bounds.height - extent) / bounds.height).clamp(
          0.0,
          1.0,
        );
        return LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            surface.withValues(alpha: 1),
            surface.withValues(alpha: 1),
            surface.withValues(alpha: 0),
          ],
          stops: [0.0, start, 1.0],
        ).createShader(Offset.zero & bounds.size);
      },
      child: child,
    );
  }
}
