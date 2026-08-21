/// Assistant reasoning disclosure — port of the web ReasoningRow.
///
/// Collapsed: icon + "Think" title + first/latest-line summary; expanded:
/// the full reasoning body. The streaming tail shows a sweeping highlight.
/// Expansion rides the native [ExpansionTile] (M3 animation, ripple, and
/// expand/collapse semantics); the title row keeps the disclosure chrome
/// and the sweep.
library;

import 'package:app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final reduced = MediaQuery.disableAnimationsOf(context);
    final l10n = AppLocalizations.of(context)!;
    return Semantics(
      label: widget.running ? l10n.semanticsRunning : null,
      child: ExpansionTile(
        // Native expansion mirrors into _expanded so the collapsed
        // summary hides once the body opens (web disclosure contract).
        onExpansionChanged: (expanded) =>
            setState(() => _expanded = expanded),
        dense: true,
        visualDensity: VisualDensity.compact,
        minTileHeight: 24,
        tilePadding: const EdgeInsets.symmetric(horizontal: 2),
        childrenPadding: const EdgeInsets.only(left: 22),
        title: ClipRect(
          child: SweepHighlight(
            controller: widget.running && !reduced ? _sweep : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Icon(
                    Icons.psychology_outlined,
                    size: 14,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    l10n.thinkLabel,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  if (!_expanded) ...[
                    Container(
                      width: 2,
                      height: 2,
                      margin: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        color: scheme.outline,
                        shape: BoxShape.circle,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        _summary,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              widget.text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}