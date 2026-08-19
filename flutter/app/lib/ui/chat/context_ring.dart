/// Composer context-occupancy ring — port of the web ContextMeter
/// (14px ring, 2px stroke): renders nothing until a provider reported
/// both pressure and route capacity; tap target carries the localized
/// occupancy sentence as its semantic label.
library;

import 'dart:math' as math;

import 'package:domain/model/context_pressure.dart';
import 'package:flutter/material.dart';

class ContextRing extends StatelessWidget {
  const ContextRing({super.key, required this.pressure});

  final ContextPressure? pressure;

  @override
  Widget build(BuildContext context) {
    final occupancy = pressure?.occupancy;
    if (occupancy == null) return const SizedBox.shrink();
    final percent = (occupancy * 100).round();
    return Semantics(
      label: '$percent% of context used',
      child: CustomPaint(
        size: const Size(14, 14),
        painter: _RingPainter(
          occupancy: occupancy,
          color: Theme.of(context).colorScheme.secondary,
          track: Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.occupancy,
    required this.color,
    required this.track,
  });

  final double occupancy;
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 2.0;
    final rect = Offset.zero & size;
    final inset = rect.deflate(stroke / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    canvas.drawArc(inset, 0, math.pi * 2, false, paint..color = track);
    canvas.drawArc(
      inset,
      -math.pi / 2,
      math.pi * 2 * occupancy,
      false,
      paint..color = color,
    );
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) =>
      oldDelegate.occupancy != occupancy ||
      oldDelegate.color != color ||
      oldDelegate.track != track;
}
