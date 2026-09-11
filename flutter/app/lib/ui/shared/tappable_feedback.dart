/// Tactile press feedback: a scale-down while a pointer is held on a seat and a
/// spring back when it lifts or leaves, paired with at most one haptic.
///
/// The wrapper owns press *feedback*, not the gesture. A wrapped Material
/// control keeps its `onPressed`/`onTap`, enabled state, tooltip, semantics,
/// and hit box; the wrapper observes the pointer to drive the scale. A seat
/// with no gesture of its own passes [DshTappable.onTap] to let the wrapper
/// own it.
///
/// A seat that already animates suppresses its own ink before adopting the
/// wrapper (`NoSplash.splashFactory`, a transparent pressed overlay,
/// `enableFeedback: false`) so one press costs one animation. A seat that
/// carries its own gesture haptics (the voice mic's phase impacts) leaves
/// [DshTappable.enableHaptic] false so one press clicks once.
///
/// [DshTappable.enabled] false passes the child through untouched: a disabled
/// seat neither scales nor clicks. System reduced motion
/// ([DshMotion.isReducedMotion]) drops the scale transition, and a muted
/// [TickerMode] mutes the wrapper's ticker so the scale stays at rest; both
/// leave the seat fully usable.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/theme.dart';

/// One control's tactile press skin: scales [child] down while a pointer is
/// held on it and springs it back on release, firing at most one haptic.
class DshTappable extends StatefulWidget {
  const DshTappable({
    required this.child,
    this.onTap,
    this.onLongPress,
    this.pressedScale = 0.96,
    this.enableHaptic = false,
    this.enabled = true,
    this.behavior = HitTestBehavior.opaque,
    super.key,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double pressedScale;

  /// Fires one [HapticFeedback.selectionClick] on pointer down. A seat that
  /// already answers a press with its own haptic leaves this false.
  final bool enableHaptic;

  /// Whether the seat answers a press. False returns [child] unwrapped, so a
  /// disabled seat keeps its own disabled rendering and does not scale, click,
  /// or run [onTap].
  final bool enabled;

  final HitTestBehavior behavior;

  @override
  State<DshTappable> createState() => _DshTappableState();
}

class _DshTappableState extends State<DshTappable>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: DshMotion.durationMicro,
    reverseDuration: DshMotion.durationShort,
  );

  late final Animation<double> _scaleAnimation =
      Tween<double>(begin: 1.0, end: widget.pressedScale).animate(
        CurvedAnimation(
          parent: _controller,
          curve: DshMotion.curveStandard,
          reverseCurve: DshMotion.curveSpring,
        ),
      );

  bool get _hasExplicitCallbacks =>
      widget.onTap != null || widget.onLongPress != null;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;

    final reduced = DshMotion.isReducedMotion(context);

    Widget interactive = widget.child;
    if (_hasExplicitCallbacks) {
      interactive = MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: widget.behavior,
          onTap: widget.onTap,
          onLongPress: widget.onLongPress,
          child: widget.child,
        ),
      );
    }

    final result = Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (_) {
        if (widget.enableHaptic) {
          unawaited(HapticFeedback.selectionClick());
        }
        _controller.forward();
      },
      onPointerUp: (_) => _controller.reverse(),
      onPointerCancel: (_) => _controller.reverse(),
      child: interactive,
    );

    if (reduced) return result;

    return ScaleTransition(scale: _scaleAnimation, child: result);
  }
}
