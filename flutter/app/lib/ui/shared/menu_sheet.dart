/// The one opener for the house menu-surface sheet (the MenuDropdown family):
/// the pin's menu material — a translucent `menuSurfaceFill` over the
/// `blur(40px) saturate(150%)` backdrop (`MenuSurface.module.css` `.material`,
/// :25-31), the `--dsw-radius-lg` menu corner (`:3-5`), and
/// `--dsw-elevation-prominent` with the menu's own `--dsw-alias-border-l1`
/// stroke (`Menu.module.css:16-18`) — floating on a transparent modal bottom
/// sheet.
///
/// The card is drawn by [MenuMaterial], the same construction the chat's own
/// floating panels use, so a menu opened from the chat and one opened from
/// settings cannot drift apart. It carries the material because the fill's
/// 58% / 45% alpha assumes a blurred page behind it: Material's own
/// `PopupMenuRoute` has no backdrop hook, and what it can carry instead is
/// recorded on `popupMenuTheme` in `theme.dart`.
///
/// Placement: where the chat panel publishes its composer dock through
/// [DockAnchor], the card seats directly above the dock — a thumb sheet
/// should not cover the field the reader just left, and should not hug
/// the screen edge where the home indicator lives. Screens without a
/// dock (settings, subagents) fall back to the legacy 8px bottom seam,
/// pixel-identical to the old hand-assembled sites.
library;

import 'package:flutter/material.dart';

import 'menu_material.dart';
import '../theme/theme.dart';
import 'dock_anchor.dart';

Future<T?> showMenuSheet<T>(
  BuildContext context, {
  required Widget Function(BuildContext sheetContext) builder,
  double maxHeight = kMenuSheetMaxHeight,
}) {
  final (double lift, double cap) = DockAnchor.sheetGeometry(
    context,
    legacyMaxHeight: maxHeight,
  );
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    // The sheet is transparent and the card is the surface: Material's drag
    // handle (the app's `bottomSheetTheme` turns it on for real sheets) would
    // otherwise float on the page above the card, and the pin's menu has no
    // handle at all.
    showDragHandle: false,
    sheetAnimationStyle: const AnimationStyle(
      duration: DshMotion.durationMedium,
      curve: DshMotion.curveEmphasized,
      reverseCurve: DshMotion.curveExit,
    ),
    backgroundColor: Colors.transparent,
    // A transparent background hides Material's sheet surface but not its
    // elevation: the modal route still paints `modalElevation`'s shadow (level 1
    // in M3) under the whole sheet, so the card's `DshElevation` ring would sit
    // on a second, heavier shadow. `elevation: 0` is the whole fix on this
    // Flutter version — `showModalBottomSheet` takes no `shadowColor`, and a
    // zero elevation paints none.
    elevation: 0,
    builder: (sheetContext) {
      final scheme = Theme.of(sheetContext).colorScheme;
      return Padding(
        padding: EdgeInsets.fromLTRB(8, 0, 8, lift),
        child: MenuMaterial(
          // The test anchor for the float-above-dock and in-sheet-shape
          // assertions.
          key: const ValueKey('menu-sheet-card'),
          // `--dsw-radius-lg`: the menu surface's own corner
          // (`MenuSurface.module.css:3-5`); only a caller-opted compact menu
          // takes the smaller `md` step.
          borderRadius: BorderRadius.circular(kRadiusLg),
          padding: const EdgeInsets.all(4),
          // `--dsw-elevation-prominent` with the menu's `border-l1` stroke
          // rebound (`Menu.module.css:16-18`): drawn outside the clip, where
          // the material's `BackdropFilter` cannot eat it. The ring is the
          // elevation's own stroke, which is how the pin's card draws it —
          // `border: 0` on the list.
          shadows: DshElevation.prominent(scheme, stroke: scheme.borderL1),
          border: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: cap),
            child: builder(sheetContext),
          ),
        ),
      );
    },
  );
}
