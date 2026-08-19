/// Composer context-occupancy ring — port of the web ContextMeter
/// (14px ring, 2px stroke): renders nothing until a provider reported
/// both pressure and route capacity. Tap opens the composition panel
/// (system / tools / conversation legend, web panel chrome).
library;

import 'dart:math' as math;

import 'package:domain/model/context_pressure.dart';
import 'package:flutter/material.dart';

import '../theme/deepsuite_extension.dart';
import '../theme/deepsuite_tokens.dart';

class ContextRing extends StatelessWidget {
  const ContextRing({super.key, required this.pressure, this.breakdown});

  final ContextPressure? pressure;

  /// Heuristic composition shown in the tap-open panel; may be null.
  final ContextBreakdown? breakdown;

  @override
  Widget build(BuildContext context) {
    final occupancy = pressure?.occupancy;
    if (occupancy == null) return const SizedBox.shrink();
    final percent = (occupancy * 100).round();
    return Semantics(
      label: '$percent% of context used',
      button: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(7),
        onTap: () => _openPanel(context, percent),
        child: CustomPaint(
          size: const Size(14, 14),
          painter: _RingPainter(
            occupancy: occupancy,
            color: Theme.of(context).colorScheme.secondary,
            track: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
      ),
    );
  }

  void _openPanel(BuildContext context, int percent) {
    // Web anchors a popover above the ring; mobile v2 uses a right-aligned
    // bottom sheet-like dialog with the same panel chrome (deviation §8.1).
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final ds = dsOf(dialogContext);
        final theme = Theme.of(dialogContext);
        final rows = <(String, int, Color)>[
          (
            'System prompt',
            breakdown?.systemTokens ?? 0,
            DeepSuiteStatic.neutralBluish400,
          ),
          (
            'Tools',
            breakdown?.toolsTokens ?? 0,
            const Color(0xffA78BFA),
          ), // violet-400 literal, as the web
          (
            'Conversation',
            breakdown?.messageTokens ?? 0,
            DeepSuiteStatic.blue450,
          ),
        ];
        return Dialog(
          alignment: Alignment.bottomCenter,
          backgroundColor: ds.menu,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: ds.divider),
          ),
          child: SizedBox(
            width: 264,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$percent% of context used',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 6),
                  for (final (label, tokens, color) in rows)
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(child: Text(label)),
                        Text('$tokens'),
                      ],
                    ),
                ],
              ),
            ),
          ),
        );
      },
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
