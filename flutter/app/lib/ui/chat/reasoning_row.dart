/// Assistant reasoning disclosure — port of the web ReasoningRow.
///
/// Collapsed: icon + "Think" title + first/latest-line summary; expanded:
/// the full reasoning body. The streaming tail shows a sweeping highlight.
library;

import 'package:flutter/material.dart';

import '../theme/deepsuite_extension.dart';
import 'sweep_highlight.dart';

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
              child: SweepHighlight(
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
