/// The reasoning/tool-row sweep pattern: a soft glare band gliding across
/// a row while work streams. Shared by ReasoningRow and ToolCallRow; pass a
/// null controller to disable (also disabled under reduced motion by the
/// callers).
library;

import 'package:flutter/material.dart';

class SweepHighlight extends StatelessWidget {
  const SweepHighlight({
    super.key,
    required this.controller,
    required this.child,
  });

  final AnimationController? controller;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final controller = this.controller;
    if (controller == null) return child;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) {
            final t = controller.value;
            final center = bounds.width * (t * 1.3 - 0.15);
            return const LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [Color(0x00000000), Color(0x33888888), Color(0x00000000)],
              stops: [0.0, 0.55, 1.0],
            ).createShader(
              Rect.fromCenter(
                center: Offset(center, bounds.height / 2),
                width: bounds.width * 0.6,
                height: bounds.height,
              ),
            );
          },
          child: child,
        );
      },
      child: child,
    );
  }
}
