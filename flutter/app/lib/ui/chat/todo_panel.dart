/// Plan strip above the composer — port of the web `TodoPanel`
/// (`ui-conversation/src/client/skeleton/TodoPanel.tsx`): renders the
/// standing `todo/write` whole-list snapshot (cleared on the next
/// `turn/start`) with per-status counts in the header and the checklist
/// behind a whole-row disclosure.
library;

import 'dart:math' as math;

import 'package:domain/model/todo.dart';
import 'package:flutter/material.dart';

import '../theme/deepsuite_extension.dart';

/// Web `progressLabel`: "·"-joined per-status counts; zero-count segments
/// drop out as noise (a non-empty list keeps at least one).
String todoProgressLabel(List<TodoItem> todos) {
  final done = todos
      .where((item) => item.status == TodoStatus.completed)
      .length;
  final active = todos
      .where((item) => item.status == TodoStatus.inProgress)
      .length;
  final pending = todos.length - done - active;
  return [
    if (done > 0) '$done completed',
    if (active > 0) '$active active',
    if (pending > 0) '$pending pending',
  ].join(' · ');
}

/// One status glyph on the figma 14×14 artboard: a filled check ring for
/// completed, a business-blue ring for in-progress, a dashed ring for
/// pending.
class _StatusGlyph extends StatelessWidget {
  const _StatusGlyph({required this.status});

  final TodoStatus status;

  @override
  Widget build(BuildContext context) {
    final ds = dsOf(context);
    final color = switch (status) {
      TodoStatus.completed => ds.accent,
      TodoStatus.inProgress => Theme.of(context).colorScheme.onSurface,
      TodoStatus.pending => ds.labelCaption,
    };
    final Widget ring = CustomPaint(
      size: const Size(14, 14),
      painter: _RingPainter(color: color, status: status),
    );
    return SizedBox(width: 16, height: 16, child: Center(child: ring));
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({required this.color, required this.status});

  final Color color;
  final TodoStatus status;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = color;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width * 6.4 / 14;
    if (status == TodoStatus.pending) {
      // figma dash 2.4 2.4: eight short arc segments.
      paint.strokeCap = StrokeCap.butt;
      const segments = 8;
      const sweep = math.pi * 2 / segments;
      const gap = sweep * 0.35;
      final rect = Rect.fromCircle(center: center, radius: radius);
      for (var i = 0; i < segments; i++) {
        canvas.drawArc(rect, i * sweep, sweep - gap, false, paint);
      }
      return;
    }
    canvas.drawCircle(center, radius, paint);
    if (status == TodoStatus.completed) {
      final check = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..strokeCap = StrokeCap.round
        ..color = color;
      final c = center;
      canvas.drawLine(
        Offset(c.dx - radius * 0.5, c.dy),
        Offset(c.dx - radius * 0.1, c.dy + radius * 0.4),
        check,
      );
      canvas.drawLine(
        Offset(c.dx - radius * 0.1, c.dy + radius * 0.4),
        Offset(c.dx + radius * 0.55, c.dy - radius * 0.45),
        check,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.status != status;
}

class TodoPanel extends StatefulWidget {
  const TodoPanel({super.key, required this.todos});

  /// The session's standing plan; an empty list renders nothing (web
  /// rule — no data of its own, hidden while empty).
  final List<TodoItem> todos;

  @override
  State<TodoPanel> createState() => _TodoPanelState();
}

class _TodoPanelState extends State<TodoPanel> {
  bool _collapsed = true;

  @override
  Widget build(BuildContext context) {
    if (widget.todos.isEmpty) return const SizedBox.shrink();
    final ds = dsOf(context);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: ds.tip,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
          border: Border(
            top: BorderSide(color: ds.divider),
            left: BorderSide(color: ds.divider),
            right: BorderSide(color: ds.divider),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: () => setState(() => _collapsed = !_collapsed),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Icon(Icons.checklist, size: 14, color: ds.labelSecondary),
                      const SizedBox(width: 6),
                      Text('To-dos', style: theme.textTheme.bodySmall),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          todoProgressLabel(widget.todos),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: ds.labelTertiary,
                          ),
                        ),
                      ),
                      Icon(
                        _collapsed
                            ? Icons.keyboard_arrow_up
                            : Icons.keyboard_arrow_down,
                        size: 14,
                        color: ds.labelSecondary,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (!_collapsed)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final item in widget.todos)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(width: 2),
                            _StatusGlyph(status: item.status),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                item.content,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: item.status == TodoStatus.completed
                                      ? ds.labelTertiary
                                      : null,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
