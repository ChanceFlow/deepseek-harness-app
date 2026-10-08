/// Assistant reasoning disclosure — port of the web ReasoningRow.
///
/// Collapsed: icon + "Think" title + first/latest-line summary; expanded:
/// the full reasoning body. The streaming tail shows a sweeping highlight.
/// Expansion rides the native [ExpansionTile] (M3 animation, ripple, and
/// expand/collapse semantics); the title row keeps the disclosure chrome
/// and the sweep.
///
/// [ReasoningRow.inline] renders the label and the body without that
/// disclosure, for the activity card that owns the fold for a whole phase
/// (see [TimelineActivityGroup]).
library;

import 'dart:async';

import 'package:app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

import '../theme/theme.dart';
import 'process_disclosure.dart';
import 'sweep_highlight.dart';

/// The label a thought row carries: a live "Thinking 4s" while it streams, a
/// settled "Thought 12s" once its duration is known, and the bare label when
/// neither is. Shared by the reasoning row and the activity card that folds
/// it, so a phase's header and its member say the same thing.
String reasoningLabel(
  AppLocalizations l10n, {
  required bool running,
  Duration? elapsed,
}) {
  if (elapsed != null) {
    final seconds = elapsed.inSeconds;
    if (running) return l10n.thinkingDuration('${seconds}s');
    if (seconds > 0) return l10n.thoughtDuration('${seconds}s');
  }
  return l10n.thinkLabel;
}

class ReasoningRow extends StatefulWidget {
  const ReasoningRow({
    required this.text,
    required this.running,
    this.elapsedDuration,
    this.inline = false,
    super.key,
  });

  /// Complete or streaming reasoning text.
  final String text;

  /// Whether this block is the streaming tail.
  final bool running;

  /// Optional pre-computed elapsed duration for settled thoughts.
  final Duration? elapsedDuration;

  /// Render the label and the body without a disclosure of this row's own:
  /// the activity card already opened for this phase.
  final bool inline;

  @override
  State<ReasoningRow> createState() => _ReasoningRowState();
}

class _ReasoningRowState extends State<ReasoningRow>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;
  bool _hovered = false;

  /// The row's activity clock. [SweepHighlight] reads the pinned
  /// [kSweepCycle] off this clock's elapsed time, so the controller only has
  /// to repeat.
  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: kSweepCycle,
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
    final live = widget.running && _startedAt != null
        ? DateTime.now().difference(_startedAt!)
        : _effectiveElapsed;
    return reasoningLabel(l10n, running: widget.running, elapsed: live);
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

  /// The thought's label line: glyph, label, and — only in the standalone
  /// disclosure — a one-line preview of the text.
  ///
  /// The sweep wraps the row's text only: the reference keeps its leading
  /// glyph outside the `TextShimmer` (its `DisclosureRow` shimmers the title
  /// and collapsed content, never the icon), and one controller drives both
  /// the label and the preview. Both texts take [color] rather than a role of
  /// their own — the reference's `.summaryText` inherits the disclosure row's
  /// tone. The title carries no weight of its own: the reference's disclosure
  /// title is regular (`.title { font-weight: 400 }`, ReasoningRow.module.css
  /// :28-30).
  Widget _labelRow(
    BuildContext context, {
    required bool showPreview,
    required Color color,
  }) {
    final theme = Theme.of(context);
    final reduced = DshMotion.isReducedMotion(context);
    final l10n = AppLocalizations.of(context)!;
    return Row(
      children: [
        Icon(Icons.psychology_outlined, size: 14, color: color),
        const SizedBox(width: 8),
        Flexible(
          child: ClipRect(
            child: SweepHighlight(
              controller: widget.running && !reduced ? _sweep : null,
              child: Row(
                children: [
                  // Same grid as a tool row — glyph, label, then the payload —
                  // so a step reads as a step whether the agent was thinking or
                  // calling.
                  Text(
                    _thinkTitle(l10n),
                    style: theme.textTheme.bodySmall?.copyWith(color: color),
                  ),
                  if (showPreview &&
                      !_expanded &&
                      _effectiveElapsed == null) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: widget.running
                          ? _streamingFade(_preview(context, color))
                          : _preview(context, color),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// The collapsed preview's one line: the newest words while the thought
  /// streams, its first line once it settles. A streaming preview is hard-cut
  /// at the box edge and left to [_streamingFade]; a settled one ends in an
  /// ellipsis, the way the reference's `.summaryText` does outside streaming.
  Widget _preview(BuildContext context, Color color) => Text(
    _summary,
    maxLines: 1,
    overflow: widget.running ? TextOverflow.clip : TextOverflow.ellipsis,
    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color),
  );

  /// The streaming preview's right-edge mask: the reference fades the summary's
  /// last [kReasoningSummaryFade] px while it streams
  /// (`ReasoningRow.module.css:60`), so the newest words dissolve rather than
  /// ending in an ellipsis mid-thought. Under `dstIn` only the shader's alpha
  /// reads through, so the opaque end is the surface role.
  Widget _streamingFade(Widget child) {
    final surface = Theme.of(context).colorScheme.surface;
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (Rect rect) {
        final double fade = (kReasoningSummaryFade / rect.width).clamp(
          0.0,
          0.5,
        );
        return LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: <Color>[
            surface.withValues(alpha: 1),
            surface.withValues(alpha: 1),
            surface.withValues(alpha: 0),
          ],
          stops: <double>[0, 1 - fade, 1],
        ).createShader(rect);
      },
      child: child,
    );
  }

  /// The reasoning text: the reference's `.thinkBody` — an indent to the row's
  /// own content edge and nothing else (`ReasoningRow.module.css:74-78`:
  /// `padding: 4px 0 4px calc(22px + delta)`, no rule, no fill). The same shape
  /// serves the row's own disclosure and the activity card that opened for the
  /// phase.
  Widget _body(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 4, 0, 4),
      child: Text(
        widget.text,
        style: theme.textTheme.bodySmall?.copyWith(
          color: scheme.onSurfaceVariant,
          height: 1.45,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    // The reference's disclosure row wears the tertiary label tone at rest and
    // steps to the secondary one on hover; its leading glyph, title, summary
    // and chevron all inherit whichever tone the row wears.
    final color = _hovered ? scheme.onSurface : scheme.onSurfaceVariant;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Semantics(
        label: widget.running ? l10n.semanticsRunning : null,
        // One line of text, one line of row — the stock 24px chevron would
        // otherwise set the height (see the tool row). The icon theme carries
        // the row's tone to that chevron, which sits outside the label line.
        child: IconTheme.merge(
          data: IconThemeData(size: 18, color: color),
          child: widget.inline
              // The activity card already opened for this phase: the thought
              // shows its label and text with no disclosure of its own.
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _labelRow(context, showPreview: false, color: color),
                    _body(context),
                  ],
                )
              : flatInkOverlay(
                  context,
                  ExpansionTile(
                    // Native expansion mirrors into _expanded so the collapsed
                    // summary hides once the body opens (web disclosure
                    // contract).
                    onExpansionChanged: (expanded) =>
                        setState(() => _expanded = expanded),
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    minTileHeight: 30,
                    shape: const Border(),
                    collapsedShape: const Border(),
                    tilePadding: const EdgeInsets.symmetric(horizontal: 2),
                    // No `childrenPadding`: the body carries the reference's
                    // own 22px indent, so the standalone disclosure and the
                    // inline card lay the text out the same way.
                    title: _labelRow(context, showPreview: true, color: color),
                    children: [_body(context)],
                  ),
                ),
        ),
      ),
    );
  }
}
