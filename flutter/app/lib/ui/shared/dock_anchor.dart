/// Composer-sheet anchor: lets the thumb sheets opened from the input
/// dock (model seat, permission seat, preset seat, the ➕ command roster,
/// the prompt-mode shim) float directly above the dock instead of hugging
/// the screen's bottom edge, where they crowded the thumb and covered
/// nothing the reader cares about. The chat panel binds a GlobalKey to
/// [_InputDock] and publishes it here; a sheet's opener measures the
/// dock's on-screen rect and takes the returned geometry.
library;

import 'package:flutter/widgets.dart';

class DockAnchor extends InheritedWidget {
  const DockAnchor({required this.dockKey, required super.child, super.key});

  final GlobalKey dockKey;

  /// Gap kept between the dock's top edge and the sheet card, and between
  /// the card and the screen bottom when no dock is in the tree.
  static const double gap = 8;

  /// (lift, maxHeight) for a sheet card: `lift` is the bottom inset that
  /// seats the card above the dock; `maxHeight` caps the card to the
  /// space actually left above it. Screens without a composer dock (the
  /// subagent page, settings) resolve to the legacy bottom-seat values
  /// through the fallback, so the same opener works everywhere.
  static (double lift, double maxHeight) sheetGeometry(
    BuildContext context, {
    double legacyMaxHeight = 440,
  }) {
    final anchor = context.dependOnInheritedWidgetOfExactType<DockAnchor>();
    final screen = MediaQuery.sizeOf(context).height;
    final box = anchor?.dockKey.currentContext?.findRenderObject();
    if (anchor == null || box is! RenderBox || !box.hasSize) {
      return (gap, legacyMaxHeight);
    }
    final dockTop = box.localToGlobal(Offset.zero).dy;
    final topSafe = MediaQuery.paddingOf(context).top;
    final maxHeight = (dockTop - gap * 2 - topSafe).clamp(160.0, 520.0);
    return (screen - dockTop + gap, maxHeight);
  }

  @override
  bool updateShouldNotify(covariant DockAnchor oldWidget) =>
      oldWidget.dockKey != dockKey;
}
