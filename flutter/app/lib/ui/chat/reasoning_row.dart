/// Assistant reasoning disclosure — port of the web ReasoningRow.
///
/// Collapsed: icon + "Think" title + first/latest-line summary; expanded:
/// the full reasoning body. The streaming tail shows a sweeping highlight.
/// Expansion rides the native [ExpansionTile] (M3 animation, ripple, and
/// expand/collapse semantics); the title row keeps the disclosure chrome
/// and the sweep.
library;

import 'dart:async';

import 'package:app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

import 'sweep_highlight.dart';

class ReasoningRow extends StatefulWidget {
  const ReasoningRow({
    required this.text,
    required this.running,
    this.elapsedDuration,
    super.key,
  });

  /// Complete or streaming reasoning text.
  final String text;

  /// Whether this block is the streaming tail.
  final bool running;

  /// Optional pre-computed elapsed duration for settled thoughts.
  final Duration? elapsedDuration;

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
  DateTime? _startedAt;
  Duration? _elapsed;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    if (widget.running) {
      _sweep.repeat();
      _startedAt = DateTime.now();
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted && widget.running) setState(() {});
      });
    }
  }

  @override
  void didUpdateWidget(covariant ReasoningRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.running && !oldWidget.running) {
      _sweep.repeat();
      _startedAt = DateTime.now();
      _ticker?.cancel();
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted && widget.running) setState(() {});
      });
    }
    if (!widget.running && oldWidget.running) {
      _sweep.stop(canceled: true);
      _ticker?.cancel();
      _ticker = null;
      if (_startedAt != null) {
        _elapsed = DateTime.now().difference(_startedAt!);
      }
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _sweep.dispose();
    super.dispose();
  }

  Duration? get _effectiveElapsed => _elapsed ?? widget.elapsedDuration;

  String _thinkTitle(AppLocalizations l10n) {
    if (widget.running && _startedAt != null) {
      final seconds = DateTime.now().difference(_startedAt!).inSeconds;
      return l10n.thinkingDuration('${seconds}s');
    }
    if (_effectiveElapsed case final elapsed?) {
      final seconds = elapsed.inSeconds;
      if (seconds > 0) {
        return l10n.thoughtDuration('${seconds}s');
      }
    }
    return l10n.thinkLabel;
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
      // One line of text, one line of row — the stock 24px chevron would
      // otherwise set the height (see the tool row).
      child: IconTheme.merge(
        data: const IconThemeData(size: 18),
        child: ExpansionTile(
          // Native expansion mirrors into _expanded so the collapsed
          // summary hides once the body opens (web disclosure contract).
          onExpansionChanged: (expanded) =>
              setState(() => _expanded = expanded),
          dense: true,
          visualDensity: VisualDensity.compact,
          minTileHeight: 30,
          shape: const Border(),
          collapsedShape: const Border(),
          tilePadding: const EdgeInsets.symmetric(horizontal: 2),
          childrenPadding: const EdgeInsets.only(left: 22),
          title: ClipRect(
            child: SweepHighlight(
              controller: widget.running && !reduced ? _sweep : null,
              child: Padding(
                padding: EdgeInsets.zero,
                child: Row(
                  children: [
                    Icon(
                      Icons.psychology_outlined,
                      size: 14,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    // Same grid as a tool row — glyph, weighted label, then
                    // the payload — so a step reads as a step whether the
                    // agent was thinking or calling.
                    Text(
                      _thinkTitle(l10n),
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurface,
                      ),
                    ),
                    if (!_expanded && _summary.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _summary,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
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
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(left: 6, top: 4, bottom: 6),
              padding: const EdgeInsets.only(left: 12),
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(color: scheme.outlineVariant, width: 1.5),
                ),
              ),
              child: Text(
                widget.text,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  height: 1.45,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
