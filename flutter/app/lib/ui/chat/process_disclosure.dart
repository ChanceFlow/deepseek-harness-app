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
import 'package:app/ui/chat/chat_local_state.dart';
import 'package:app/ui/chat/process_activity.dart';
import 'package:app/ui/chat/sweep_highlight.dart';
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

/// Runs a disclosure row with Material's ink overlays switched off.
///
/// The reference's disclosure rows carry no fill in any state — its
/// `DisclosureRow` row and the `ChatGroupSeat` title are `background: none`
/// (`DisclosureRow.module.css:46`, `ChatGroupSeat.module.css:12`) and a press
/// changes only the label's tone. Material's `InkWell` would paint a highlight
/// tile across the row on press, so every overlay colour is off and the row
/// keeps the reference's flat surface.
Widget flatInkOverlay(BuildContext context, Widget child) => Theme(
  data: Theme.of(context).copyWith(
    splashColor: Colors.transparent,
    highlightColor: Colors.transparent,
    hoverColor: Colors.transparent,
    focusColor: Colors.transparent,
  ),
  child: child,
);

/// One Turn's process control, wrapping the rows it owns.
///
/// The reference's `TurnProcessNodeView` is a full-width row under a hairline
/// rule whose label reports only a settled Turn — `Completed in 2m 3s` /
/// `Stopped` / `Failed` — and whose body holds the Turn's work; while the Turn
/// runs there is no control label, because the running row carries the live
/// state. A Turn that is still running, was stopped or failed, or had a human
/// speak inside it keeps its body: the reference's `turnProcessAlwaysOpen` plus
/// its interleaved-input rule.
///
/// The reference lays the control out as one flow item and its rows as the
/// siblings after it, so the column's own flow gap spaces them: the row that
/// follows a `turn-process` item takes the item's clearance, and the rows
/// under it step apart (`ChatView.module.css:70-94`,
/// `ChatGroupSeat.module.css:87`). This port nests those rows in the section
/// to keep one fold over them, so [gapAfter] — the transcript's own rule — is
/// applied between them here instead.
class TurnProcessRow extends StatefulWidget {
  const TurnProcessRow({
    required this.section,
    required this.buildRow,
    required this.gapAfter,
    super.key,
    this.expansion,
  });

  final TurnProcessSection section;

  /// Renders one of the section's own rows through the transcript's row path.
  final Widget Function(Object row) buildRow;

  /// The transcript's flow gap between two of its rows. The section's control
  /// is handed in as the row above its first member, so the hairline keeps the
  /// clearance the reference gives the sibling after a `turn-process` item.
  final double Function(Object above, Object? below) gapAfter;

  /// The reader's fold, keyed by the block's identity rather than held in the
  /// element: a remount (an older page arriving, or a Turn boundary entering
  /// the window and re-parenting the phase) restores what the reader opened
  /// instead of dropping it. Null keeps the fold in memory for this mount.
  final ToolExpansionPersistence? expansion;

  @override
  State<TurnProcessRow> createState() => _TurnProcessRowState();
}

class _TurnProcessRowState extends State<TurnProcessRow> {
  /// The reader's own choice for this Turn, or null while the transcript view
  /// still decides. Keeping it null is what lets a mode change re-fold the
  /// Turns the reader never touched while every override stands.
  bool? _override;
  bool _hovered = false;

  /// The state the body renders in: a Turn that must stay visible never folds,
  /// the reader's override outranks the mode, and the mode decides the rest.
  bool get _open =>
      widget.section.facts.alwaysOpen ||
      (_override ?? widget.section.defaultOpen);

  /// Set once the reader toggles, so a restore that lands late cannot undo the
  /// tap that came after it.
  bool _toggled = false;

  String get _expansionKey => 'turn-process:${widget.section.windowOrdinal}';

  @override
  void initState() {
    super.initState();
    _restoreExpansion();
  }

  /// Reads the stored fold once per mount; no entry leaves the mode's default.
  void _restoreExpansion() {
    final expansion = widget.expansion;
    if (expansion == null) return;
    unawaited(
      expansion.expanded(_expansionKey).then((restored) {
        if (!mounted || _toggled || restored == _open) return;
        setState(() => _override = restored);
      }),
    );
  }

  void _toggle() {
    _toggled = true;
    setState(() => _override = !_open);
    unawaited(widget.expansion?.setExpanded(_expansionKey, _open));
  }

  @override
  void didUpdateWidget(covariant TurnProcessRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.section.facts.alwaysOpen &&
        widget.section.facts.alwaysOpen) {
      // A Turn that starts running again — or was stopped — cannot stay
      // folded: the reader has to see what is happening. The opening is the
      // reader's state from here, the way a manual open would be.
      _override = true;
    }
  }

  /// The reference's `.durationNumber`: the code family with tabular figures,
  /// so the clock does not shift the label's width as its digits change.
  static const TextStyle _durationNumber = TextStyle(
    fontFamily: kCodeFontFamily,
    fontFamilyFallback: kCodeFontFamilyFallback,
    fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
  );

  static TextSpan _labelSpan(TurnProcessLabel label) => TextSpan(
    children: <InlineSpan>[
      TextSpan(text: label.prefix),
      for (final part in label.duration)
        TextSpan(text: part.text, style: part.numeric ? _durationNumber : null),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final facts = widget.section.facts;
    // The reference's `canCollapse`: a Turn that is still running, stopped or
    // failed never folds, and neither does one with nothing to reveal.
    final canCollapse = !facts.alwaysOpen && widget.section.hasContent;
    final open = !canCollapse || _open;
    // Null while the Turn is open: the reference renders no control label
    // before `turn/end` folds, because the running row carries the live state.
    final label = turnProcessLabel(facts, l10n);
    // The reference's `.root:hover` steps the tertiary label tone to the
    // secondary one; the chevron inherits whichever the label wears.
    final color = _hovered ? scheme.labelSecondary : scheme.labelTertiary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: Semantics(
            button: canCollapse,
            expanded: canCollapse ? open : null,
            child: flatInkOverlay(
              context,
              Material(
                type: MaterialType.transparency,
                child: InkWell(
                  onTap: canCollapse ? _toggle : null,
                  child: Container(
                    decoration: BoxDecoration(
                      // The reference rules the control off from what follows
                      // with `border-l2` at half a pixel
                      // (`TurnProcessNodeView.module.css:13`).
                      border: Border(
                        bottom: BorderSide(color: scheme.borderL2, width: 0.5),
                      ),
                    ),
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        if (label != null)
                          Flexible(
                            child: Text.rich(
                              _labelSpan(label),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              // The control reads the content size on its own
                              // 24px line (`TurnProcessNodeView.module.css:12`
                              // and :44).
                              style: DshType.s14
                                  .style(color: color)
                                  .copyWith(height: 24 / 14),
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
                              color: color,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        // Transcript order, with the folded rows dropped rather than moved: a
        // collapsed Turn hides what the agent did, and never relocates the
        // reader's own message or the answer that followed the work.
        ..._members(open),
      ],
    );
  }

  /// The section's rows under the transcript's own flow gap.
  ///
  /// The reference spaces a `turn-process` item's following rows with the
  /// column gap, not with the item's own padding (`ChatView.module.css:70-94`):
  /// the row right after the control takes its clearance, and the rows under it
  /// step apart. The control stands in as the first member's row above, so the
  /// hairline keeps the clearance the reference gives the sibling after a
  /// `turn-process` item instead of the flush edge a bare padding produced.
  List<Widget> _members(bool open) {
    final rows = <Widget>[];
    Object above = widget.section;
    for (final member in widget.section.members) {
      if (!open && member.folds) continue;
      rows.add(
        Padding(
          padding: EdgeInsets.only(top: widget.gapAfter(above, member.row)),
          child: widget.buildRow(member.row),
        ),
      );
      above = member.row;
    }
    return rows;
  }
}

/// One process group's header: the category icon, a chevron that fades in over
/// it on hover or while open, the live or settled label, and — while the group
/// runs and no detail-free policy is in force — the running one-liner.
///
/// The row wears the reference's disclosure chrome: the tertiary label tone at
/// rest, the secondary one on hover, and a leading box whose glyph and chevron
/// inherit whichever tone the row wears. The label alone carries the group's
/// sweep, so the icon stays outside the highlight the way the reference's
/// `ChatGroupSeat` header keeps its leading box out of the `TextShimmer`.
class ProcessGroupHeader extends StatefulWidget {
  const ProcessGroupHeader({
    required this.summary,
    required this.closed,
    required this.open,
    required this.onTap,
    this.sweep,
    super.key,
  });

  final ProcessActivitySummary summary;

  /// Whether the group's Turn has ended; a live group shimmers and names what
  /// it is doing.
  final bool closed;
  final bool open;
  final VoidCallback onTap;

  /// The group's activity clock, or null while the group is settled or motion
  /// is off. The label is the only thing it sweeps.
  final AnimationController? sweep;

  @override
  State<ProcessGroupHeader> createState() => _ProcessGroupHeaderState();
}

class _ProcessGroupHeaderState extends State<ProcessGroupHeader> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
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
    // The reference's `.title:hover` steps the tertiary tone to the secondary
    // one; the leading box inherits it rather than naming a role of its own.
    final color = _hovered ? scheme.labelSecondary : scheme.labelTertiary;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Semantics(
        button: true,
        expanded: widget.open,
        child: flatInkOverlay(
          context,
          Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: widget.onTap,
              child: Padding(
                padding: EdgeInsets.only(bottom: widget.open ? 8 : 0),
                child: Row(
                  children: [
                    // The reference stacks the icon and the chevron in one
                    // 16px box and cross-fades them; an open or hovered header
                    // shows the chevron.
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
                              color: color,
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
                                color: color,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: SweepHighlight(
                        controller: widget.sweep,
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          // The reference's group title is 14px, one step above
                          // its 13px Turn-control label; Material has both
                          // roles.
                          // The group title is the content size on the
                          // disclosure row's 24px box
                          // (`ChatGroupSeat.module.css:14`, `.row` :22).
                          style: DshType.s14
                              .style(color: color)
                              .copyWith(height: 24 / 14),
                        ),
                      ),
                    ),
                  ],
                ),
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
    // mask value out of the palette and the gate's way. The mask is always in
    // the tree, even with both edges opaque: inserting it when an edge opens
    // would change the scroller's position in the tree and rebuild it, dropping
    // the scroll the group is holding.
    final surface = Theme.of(context).colorScheme.surface;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (Rect rect) {
          // A fixed ramp, not a share of the box: the reference's mask is
          // `transparent 0, #000 24px` (`ChatGroupSeat.module.css:102-110`), so
          // the fade stays 24px whatever height the body resolves to.
          final double ramp = (kEdgeFade / rect.height).clamp(0.0, 0.5);
          return LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[
              surface.withValues(alpha: _canScrollUp ? 0 : 1),
              surface.withValues(alpha: 1),
              surface.withValues(alpha: 1),
              surface.withValues(alpha: _canScrollDown ? 0 : 1),
            ],
            stops: <double>[0, ramp, 1 - ramp, 1],
          ).createShader(rect);
        },
        child: SingleChildScrollView(
          controller: _controller,
          child: widget.child,
        ),
      ),
    );
  }
}
