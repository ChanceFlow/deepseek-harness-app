/// The transcript's two process disclosures.
///
/// Ports of the reference's `chat/TurnProcessNodeView.tsx` and
/// `chat/ChatGroupSeat.tsx` header: one Turn-level control that owns a Turn's
/// process rows, and one category-icon header per process group. Chrome stays
/// stock Material — the reference's `--dsw-*` aliases map onto the app's
/// [ColorScheme] roles, and its 100ms cross-fades onto [DshMotion].
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:app/l10n/app_localizations.dart';
import 'package:app/ui/chat/process_activity.dart';
import 'package:app/ui/chat/turn_process.dart';
import 'package:app/ui/theme/theme.dart';
import 'package:flutter/material.dart';

/// The reference's per-category activity icon
/// (`chat/ChatGroupSeat.tsx` `PROCESS_ICONS`), read onto Material symbols.
///
/// The mapping follows the glyph the reference draws, not the label it sits
/// next to: its own table reuses the one document glyph for `read`,
/// `readImage` and `webFetch`, so those three share Material's document here
/// too.
IconData processActivityIcon(ProcessActivity activity) => switch (activity) {
  ProcessActivity.thinking => Icons.psychology_outlined,
  ProcessActivity.read => Icons.description_outlined,
  ProcessActivity.readImage => Icons.description_outlined,
  ProcessActivity.search => Icons.search,
  ProcessActivity.write => Icons.edit_outlined,
  ProcessActivity.edit => Icons.edit_outlined,
  ProcessActivity.commands => Icons.terminal,
  ProcessActivity.code => Icons.code,
  ProcessActivity.webSearch => Icons.public,
  ProcessActivity.webFetch => Icons.description_outlined,
  ProcessActivity.subagents => Icons.account_tree_outlined,
  ProcessActivity.plan => Icons.checklist,
  ProcessActivity.questions => Icons.help_outline,
  ProcessActivity.tools => Icons.auto_awesome,
};

/// The reference's per-category icon size: 14 for the glyphs its table draws
/// small, 16 — the leading box's own size — for the rest.
double processActivityIconSize(ProcessActivity activity) => switch (activity) {
  ProcessActivity.thinking ||
  ProcessActivity.commands ||
  ProcessActivity.webSearch ||
  ProcessActivity.plan ||
  ProcessActivity.questions => 16,
  _ => 14,
};

/// One Turn's process control, wrapping the rows it owns.
///
/// The reference's `TurnProcessNodeView` is a full-width row under a hairline
/// rule whose label reports the run — `Deep diving for 8s` while it runs,
/// `Took 2m 03s` / `Stopped` / `Process failed` once it ends — and whose body
/// holds the Turn's work. A Turn that is still running, was stopped or failed,
/// or had a human speak inside it keeps its body: the reference's
/// `turnProcessAlwaysOpen` plus its interleaved-input rule.
class TurnProcessRow extends StatefulWidget {
  const TurnProcessRow({
    required this.section,
    required this.buildRow,
    super.key,
  });

  final TurnProcessSection section;

  /// Renders one of the section's own rows through the transcript's row path.
  final Widget Function(Object row) buildRow;

  @override
  State<TurnProcessRow> createState() => _TurnProcessRowState();
}

class _TurnProcessRowState extends State<TurnProcessRow> {
  late bool _open = widget.section.defaultOpen;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _syncTicker();
  }

  @override
  void didUpdateWidget(covariant TurnProcessRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.section.facts.alwaysOpen &&
        widget.section.facts.alwaysOpen) {
      // A Turn that starts running again — or was stopped — cannot stay
      // folded: the reader has to see what is happening.
      _open = true;
    }
    _syncTicker();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  /// The label counts elapsed seconds, so an open Turn re-reads the clock once
  /// a second — the reference's `LIVE_RUN_CLOCK_INTERVAL_MS`.
  void _syncTicker() {
    final ticking =
        widget.section.facts.alwaysOpen && !widget.section.facts.closed;
    if (!ticking && _ticker == null) return;
    if (!ticking) {
      _ticker?.cancel();
      _ticker = null;
      return;
    }
    _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final facts = widget.section.facts;
    // The reference's `canCollapse`: a Turn that is still running, stopped or
    // failed never folds, and neither does one with nothing to reveal.
    final canCollapse = !facts.alwaysOpen && widget.section.hasContent;
    final open = !canCollapse || _open;
    final label = turnProcessLabel(
      facts,
      l10n,
      nowMs: DateTime.now().millisecondsSinceEpoch,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          button: canCollapse,
          expanded: canCollapse ? open : null,
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: canCollapse ? () => setState(() => _open = !_open) : null,
              child: Container(
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: scheme.outlineVariant,
                      width: 0.5,
                    ),
                  ),
                ),
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.outline,
                          height: 24 / 12,
                        ),
                      ),
                    ),
                    if (canCollapse) ...[
                      const SizedBox(width: 4),
                      AnimatedRotation(
                        turns: open ? 0.5 : 0,
                        duration: DshMotion.durationMicro,
                        curve: DshMotion.curveStandard,
                        child: Icon(
                          Icons.keyboard_arrow_down,
                          size: 14,
                          color: scheme.outline,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
        if (open) const SizedBox(height: 8),
        // Transcript order, with the folded rows dropped rather than moved: a
        // collapsed Turn hides what the agent did, and never relocates the
        // reader's own message or the answer that followed the work.
        for (final member in widget.section.members)
          if (open || !member.folds)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: widget.buildRow(member.row),
            ),
      ],
    );
  }
}

/// One process group's header: the category icon, a chevron that fades in over
/// it on hover or while open, the live or settled label, and — while the group
/// runs and no detail-free policy is in force — the running one-liner.
class ProcessGroupHeader extends StatefulWidget {
  const ProcessGroupHeader({
    required this.summary,
    required this.closed,
    required this.open,
    required this.onTap,
    super.key,
  });

  final ProcessActivitySummary summary;

  /// Whether the group's Turn has ended; a live group shimmers and names what
  /// it is doing.
  final bool closed;
  final bool open;
  final VoidCallback onTap;

  @override
  State<ProcessGroupHeader> createState() => _ProcessGroupHeaderState();
}

class _ProcessGroupHeaderState extends State<ProcessGroupHeader> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final summary = widget.summary;
    final activity = widget.closed
        ? (summary.counts.isEmpty
              ? ProcessActivity.thinking
              : summary.counts.first.kind)
        : (summary.running ?? ProcessActivity.thinking);
    final label = widget.closed
        ? processTitle(summary, l10n)
        : liveActivityLabel(activity, l10n, preparing: summary.preparing);
    final detail = !widget.closed ? summary.runningDetail : '';
    final title = detail.isEmpty
        ? label
        : '$label${l10n.turnProcessSeparator}$detail';
    final showChevron = _hovered || widget.open;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Semantics(
        button: true,
        expanded: widget.open,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: widget.onTap,
            child: Padding(
              padding: EdgeInsets.only(bottom: widget.open ? 16 : 0),
              child: Row(
                children: [
                  // The reference stacks the icon and the chevron in one 16px
                  // box and cross-fades them; an open or hovered header shows
                  // the chevron.
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        AnimatedOpacity(
                          opacity: showChevron ? 0 : 1,
                          duration: DshMotion.durationMicro,
                          curve: DshMotion.curveStandard,
                          child: Icon(
                            processActivityIcon(activity),
                            size: processActivityIconSize(activity),
                            color: scheme.outline,
                          ),
                        ),
                        AnimatedOpacity(
                          opacity: showChevron ? 1 : 0,
                          duration: DshMotion.durationMicro,
                          curve: DshMotion.curveStandard,
                          child: AnimatedRotation(
                            turns: widget.open ? 0.5 : 0,
                            duration: DshMotion.durationMicro,
                            curve: DshMotion.curveStandard,
                            child: Icon(
                              Icons.keyboard_arrow_down,
                              size: 14,
                              color: scheme.outline,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      // The reference's group title is 14px, one step above its
                      // 13px Turn-control label; Material has both roles.
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: _hovered
                            ? scheme.onSurface
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One process group's body: the reference caps a collapsed body at
/// `min(400px, 50vh)` with its own scroll and fades the overflow edges, and
/// lets an expanded body grow without either.
///
/// The mask is the reference's `fadeTop`/`fadeBottom`: a 24px transparent ramp
/// on whichever edge still has content behind it.
class ProcessGroupBody extends StatefulWidget {
  const ProcessGroupBody({
    required this.child,
    this.startAtBottom = false,
    super.key,
  });

  final Widget child;

  /// Whether the body opens on its newest row. The reference stages a live
  /// group's scroll at the bottom (`ChatGroupSeat` `toggle` →
  /// `initialize('bottom')`), so the call that is running is the one in view.
  final bool startAtBottom;

  @override
  State<ProcessGroupBody> createState() => _ProcessGroupBodyState();
}

class _ProcessGroupBodyState extends State<ProcessGroupBody> {
  final ScrollController _controller = ScrollController();
  bool _canScrollUp = false;
  bool _canScrollDown = false;
  bool _staged = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_readEdges);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _readEdges() {
    if (!_controller.hasClients) return;
    final position = _controller.position;
    final up = position.pixels > 0;
    final down = position.pixels < position.maxScrollExtent;
    if (up == _canScrollUp && down == _canScrollDown) return;
    setState(() {
      _canScrollUp = up;
      _canScrollDown = down;
    });
  }

  /// Land a live body on its last row, once there is content to land on: a
  /// group opens on the frame its first members were laid out, and the running
  /// call arrives after that.
  void _stageScroll() {
    if (_staged || !widget.startAtBottom || !_controller.hasClients) return;
    final position = _controller.position;
    if (position.maxScrollExtent <= 0) return;
    _staged = true;
    _controller.jumpTo(position.maxScrollExtent);
  }

  @override
  Widget build(BuildContext context) {
    // Measure after layout: the edges are a fact of the laid-out content.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _stageScroll();
      _readEdges();
    });
    final maxHeight = math.min(400.0, MediaQuery.sizeOf(context).height * 0.5);
    // Under `dstIn` only the shader's alpha ramp reads through, so the surface
    // role is the ramp's opaque end — the `EdgeFade` convention, which keeps a
    // mask value out of the palette and the gate's way.
    final surface = Theme.of(context).colorScheme.surface;
    Widget body = SingleChildScrollView(
      controller: _controller,
      child: widget.child,
    );
    if (_canScrollUp || _canScrollDown) {
      body = ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (rect) => LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            surface.withValues(alpha: _canScrollUp ? 0 : 1),
            surface.withValues(alpha: 1),
            surface.withValues(alpha: 1),
            surface.withValues(alpha: _canScrollDown ? 0 : 1),
          ],
          stops: const <double>[0, 0.06, 0.94, 1],
        ).createShader(rect),
        child: body,
      );
    }
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: body,
    );
  }
}
