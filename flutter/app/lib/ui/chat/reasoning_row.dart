/// Assistant reasoning disclosure — port of the web ReasoningRow.
///
/// Collapsed: icon + "Think" title + first/latest-line summary; expanded:
/// the full reasoning body. The streaming tail shows a sweeping highlight.
library;

import 'package:flutter/material.dart';

import '../theme/deepsuite_extension.dart';

class ReasoningRow extends StatefulWidget {
  const ReasoningRow({super.key, required this.text, required this.running});

  /// Complete or streaming reasoning text.
  final String text;

  /// Whether this block is the streaming tail.
  final bool running;

  @override
  State<ReasoningRow> createState() => _ReasoningRowState();
}

class _ReasoningRowState extends State<ReasoningRow>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;
  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  );

  @override
  void initState() {
    super.initState();
    if (widget.running) _sweep.repeat();
  }

  @override
  void didUpdateWidget(covariant ReasoningRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.running && !oldWidget.running) _sweep.repeat();
    if (!widget.running && oldWidget.running) _sweep.stop(canceled: true);
  }

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  String get _summary =>
      widget.running ? _latestLine(widget.text) : _firstLine(widget.text);

  static String _firstLine(String text) {
    final newline = text.indexOf('\n');
    return newline == -1 ? text : text.substring(0, newline);
  }

  static String _latestLine(String text) {
    final visible = text.trimRight();
    final newline = visible.lastIndexOf('\n');
    return newline == -1 ? visible : visible.substring(newline + 1);
  }

  @override
  Widget build(BuildContext context) {
    final ds = dsOf(context);
    final reduced = MediaQuery.disableAnimationsOf(context);
    final theme = Theme.of(context);
    return Semantics(
      label: widget.running ? 'Running' : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(4),
            onTap: () => setState(() => _expanded = !_expanded),
            child: ClipRect(
              child: _SweepHighlight(
                controller: widget.running && !reduced ? _sweep : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 4,
                    horizontal: 2,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.psychology_outlined,
                        size: 14,
                        color: ds.labelSecondary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Think',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: ds.labelSecondary,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(
                        _expanded
                            ? Icons.keyboard_arrow_up
                            : Icons.keyboard_arrow_down,
                        size: 14,
                        color: ds.labelSecondary,
                      ),
                      if (!_expanded) ...[
                        Container(
                          width: 2,
                          height: 2,
                          margin: const EdgeInsets.symmetric(horizontal: 8),
                          decoration: BoxDecoration(
                            color: ds.labelCaption,
                            shape: BoxShape.circle,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            _summary,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: ds.labelTertiary,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 4, left: 22),
              child: Text(
                widget.text,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: ds.labelTertiary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The web `dsh-reasoning-row-sweep`: a soft highlight sweeping across the
/// row while reasoning streams (disabled under reduced motion).
class _SweepHighlight extends StatelessWidget {
  const _SweepHighlight({required this.controller, required this.child});

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
