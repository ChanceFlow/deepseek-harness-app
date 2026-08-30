/// The one opener for the house menu-surface sheet (MenuDropdown family):
/// a `surfaceContainer` card with an `outlineVariant` hairline, the
/// elevation-3 shadow, `kShapeMenuSheet` radius, and 4px inner padding,
/// floating on a transparent modal bottom sheet.
///
/// Placement: where the chat panel publishes its composer dock through
/// [DockAnchor], the card seats directly above the dock — a thumb sheet
/// should not cover the field the reader just left, and should not hug
/// the screen edge where the home indicator lives. Screens without a
/// dock (settings, subagents) fall back to the legacy 8px bottom seam,
/// pixel-identical to the old hand-assembled sites.
library;

import 'package:flutter/material.dart';

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
    backgroundColor: Colors.transparent,
    builder: (sheetContext) {
      final scheme = Theme.of(sheetContext).colorScheme;
      return Padding(
        padding: EdgeInsets.fromLTRB(8, 0, 8, lift),
        child: Container(
          // The test anchor for the float-above-dock and in-sheet-shape
          // assertions.
          key: const ValueKey('menu-sheet-card'),
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: scheme.surfaceContainer,
            borderRadius: BorderRadius.circular(kShapeMenuSheet),
            border: Border.all(color: scheme.outlineVariant),
            boxShadow: kM3ShadowElevation3,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: cap),
            child: builder(sheetContext),
          ),
        ),
      );
    },
  );
}
