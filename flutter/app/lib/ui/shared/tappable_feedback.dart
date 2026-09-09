/// Tactile press feedback wrapper: applies an organic scale-down on pointer down
/// and springs back on release/cancel, paired with subtle haptic feedback.
///
/// Automatically respects system-level reduced motion by disabling scaling
/// when [MediaQuery.disableAnimationsOf] is true.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/theme.dart';

/// Wraps [child] with an interactive tactile press scale-down and spring-back animation.
class DshTappable extends StatefulWidget {
  const DshTappable({
    required this.child,
    this.onTap,
    this.onLongPress,
    this.pressedScale = 0.96,
    this.enableHaptic = false,
    this.behavior = HitTestBehavior.opaque,
    super.key,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double pressedScale;
  final bool enableHaptic;
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
