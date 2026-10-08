/// The reference's menu material: the surface every floating menu-family panel
/// is drawn on.
///
/// A menu panel in the pin is not a Material card. It is a translucent fill
/// (`--dsw-specific-menu`, [DshSchemeColors.menuSurfaceFill]) sitting on a
/// blurred, saturated page (`--dsw-menu-backdrop-filter`: `blur(40px)
/// saturate(150%)`, `gradient-shadow-text.css:20`) and edged by a half-pixel
/// `border-l1` hairline drawn inside the panel, not by a Material border
/// (`ChatGroupSeat`'s family, `QueueDock.module.css:37-58`, `GoalBar.module.css`
/// `::before`/`::after` :41-49). The fill's 58%/45% alpha assumes that blur: on
/// its own it reads as a flat translucent panel.
///
/// [shadows] carries the caller's elevation step ([DshElevation.panel] or
/// [DshElevation.prominent]) on an outer box, because a `BackdropFilter` sits
/// inside a `ClipRRect` and a shadow drawn there would be clipped away.
library;

import 'package:flutter/material.dart';

import '../theme/theme.dart';

class MenuMaterial extends StatelessWidget {
  const MenuMaterial({
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(kRadiusLg)),
    this.padding,
    this.shadows = const <BoxShadow>[],
    this.border = true,
    this.borderBottom = true,
    super.key,
  });

  final Widget child;

  /// The panel's own radius. The queue dock attaches under the input card, so
  /// it rounds its top corners only (`QueueDock.module.css` `.panel`, :34-35).
  final BorderRadius borderRadius;

  final EdgeInsetsGeometry? padding;

  /// The caller's elevation step, drawn outside the clip.
  final List<BoxShadow> shadows;

  /// Whether the panel draws the pin's half-pixel `border-l1` hairline.
  final bool border;

  /// The queue dock's hairline stops at the bottom edge, where the input card's
  /// own top border closes the shape (`QueueDock.module.css` `.panel::after`,
  /// :51-57).
  final bool borderBottom;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final Widget panel = ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: menuBackdropFilter(),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.menuSurfaceFill,
            borderRadius: borderRadius,
            border: border
                ? Border(
                    top: BorderSide(color: scheme.borderL1, width: 0.5),
                    left: BorderSide(color: scheme.borderL1, width: 0.5),
                    right: BorderSide(color: scheme.borderL1, width: 0.5),
                    bottom: borderBottom
                        ? BorderSide(color: scheme.borderL1, width: 0.5)
                        : BorderSide.none,
                  )
                : null,
          ),
          child: Material(
            // A `ListTile` row paints its background and ink splashes on the
            // nearest `Material` ancestor. The panel's own fill is a
            // `DecoratedBox`, which would hide them, and the framework asserts on
            // that combination; a transparent Material between the fill and the
            // rows keeps the panel's colour and gives the rows their ink
            // surface.
            type: MaterialType.transparency,
            child: padding == null
                ? child
                : Padding(padding: padding!, child: child),
          ),
        ),
      ),
    );
    if (shadows.isEmpty) return panel;
    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: borderRadius, boxShadow: shadows),
      child: panel,
    );
  }
}
