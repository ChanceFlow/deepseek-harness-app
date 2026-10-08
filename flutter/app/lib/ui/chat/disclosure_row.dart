/// The reference's disclosure-row chrome, ported for the transcript's rows.
///
/// A disclosure row in the pin is a fixed **24px** flex box at the root's left
/// edge, not a Material tile: `DisclosureRow.module.css` `.row`
/// (`height: calc(24px + delta)`, :19-22) holds a 16px leading box with a 6px
/// gap (:47-69), the title on the row's own 13/24 step (:85-90), and the
/// chevron appears only while the row is expandable (:41-58). The row paints no
/// fill in any state (`background: none`, :46) and steps its tone from
/// `label-tertiary` to `label-secondary` on hover (:20-28).
///
/// The 24px box is the point: the group body is a flat list of these rows six
/// pixels apart (`ChatGroupSeat.module.css:87`), so two stacked members pitch
/// 30px. A Material [ExpansionTile] carries the same content at 40px, which is
/// what made the expanded group read loose against the pin.
library;

import 'package:flutter/material.dart';

import '../theme/theme.dart';
import 'process_disclosure.dart' show flatInkOverlay;

class DisclosureRow extends StatefulWidget {
  /// The header's own content, built with the tone the row currently wears.
  final Widget Function(BuildContext context, Color tone) header;

  /// The expanded body. Rendered under the row only while [open].
  final Widget body;

  final bool open;

  /// Whether the row can open at all. A row without a body drops its chevron
  /// and takes no tap, the way the pin's `expandable` controls both.
  final bool expandable;

  final VoidCallback? onToggle;

  /// The label assistive technology hears for the toggle.
  final String? semanticLabel;

  /// The row's hidden accessible state, announced beside [semanticLabel].
  final String? stateLabel;

  const DisclosureRow({
    required this.header,
    required this.body,
    required this.open,
    super.key,
    this.expandable = true,
    this.onToggle,
    this.semanticLabel,
    this.stateLabel,
  });

  @override
  State<DisclosureRow> createState() => _DisclosureRowState();
}

class _DisclosureRowState extends State<DisclosureRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // The row's tone at rest and on hover (`DisclosureRow.module.css:20-28`).
    final Color tone = _hovered ? scheme.labelSecondary : scheme.labelTertiary;
    final bool open = widget.open && widget.expandable;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: Semantics(
            button: widget.expandable,
            expanded: widget.expandable ? open : null,
            label: widget.semanticLabel,
            child: flatInkOverlay(
              context,
              Material(
                type: MaterialType.transparency,
                child: InkWell(
                  onTap: widget.expandable ? widget.onToggle : null,
                  onHover: (bool hovering) =>
                      setState(() => _hovered = hovering),
                  child: SizedBox(
                    height: 24,
                    child: Row(
                      children: [
                        Expanded(child: widget.header(context, tone)),
                        if (widget.expandable) ...[
                          const SizedBox(width: 4),
                          AnimatedRotation(
                            turns: open ? 0.5 : 0,
                            duration: DshMotion.transitionFast,
                            curve: DshMotion.easeInOut,
                            child: Icon(
                              Icons.keyboard_arrow_down,
                              size: 14,
                              color: tone,
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
        if (open) widget.body,
      ],
    );
  }
}
