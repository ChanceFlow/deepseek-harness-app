/// Three-finger swipe detection for the shell.
///
/// The page belongs to the host, so the shell claims exactly one gesture: a
/// three-finger vertical swipe. A raw [Listener] sees every pointer without
/// joining the gesture arena, which is what lets the WebView keep its own
/// pan/zoom while the shell watches the finger count.
library;

import 'package:flutter/widgets.dart';

/// How far the three fingers must travel before the swipe fires.
const double kThreeFingerDistance = 36;

/// Calls [onSwipeDown] / [onSwipeUp] for a three-finger vertical swipe.
///
/// The gesture arms only when exactly three pointers are down and no fourth
/// joins; a one- or two-finger drag is never a shell gesture.
class ThreeFingerSwipeDetector extends StatefulWidget {
  const ThreeFingerSwipeDetector({
    required this.child,
    required this.onSwipeDown,
    required this.onSwipeUp,
    this.enabled = true,
    super.key,
  });

  final Widget child;
  final VoidCallback onSwipeDown;
  final VoidCallback onSwipeUp;
  final bool enabled;

  @override
  State<ThreeFingerSwipeDetector> createState() =>
      _ThreeFingerSwipeDetectorState();
}

class _ThreeFingerSwipeDetectorState extends State<ThreeFingerSwipeDetector> {
  final Map<int, Offset> _origins = <int, Offset>{};
  Offset _latest = Offset.zero;
  bool _exceeded = false;
  bool _fired = false;

  void _reset() {
    _origins.clear();
    _latest = Offset.zero;
    _exceeded = false;
    _fired = false;
  }

  void _onDown(PointerDownEvent event) {
    if (!widget.enabled) return;
    if (_origins.length >= 3) {
      _exceeded = true;
    }
    _origins[event.pointer] = event.position;
    _latest = event.position;
  }

  void _onMove(PointerMoveEvent event) {
    if (!widget.enabled || !_origins.containsKey(event.pointer)) return;
    _latest = event.position;
    if (_fired || _exceeded || _origins.length != 3) return;
    var dx = 0.0;
    var dy = 0.0;
    for (final origin in _origins.values) {
      dx += _latest.dx - origin.dx;
      dy += _latest.dy - origin.dy;
    }
    dx /= 3;
    dy /= 3;
    if (dy.abs() <= dx.abs()) return;
    if (dy > kThreeFingerDistance) {
      _fired = true;
      widget.onSwipeDown();
    } else if (dy < -kThreeFingerDistance) {
      _fired = true;
      widget.onSwipeUp();
    }
  }

  void _onUp(PointerEvent event) {
    _origins.remove(event.pointer);
    if (_origins.isEmpty) _reset();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      // Opaque so the detector still sees pointers when its child is an
      // IgnorePointer'd page (the drawer is open); children keep their own
      // gestures.
      behavior: HitTestBehavior.opaque,
      onPointerDown: _onDown,
      onPointerMove: _onMove,
      onPointerUp: _onUp,
      onPointerCancel: _onUp,
      child: widget.child,
    );
  }
}
