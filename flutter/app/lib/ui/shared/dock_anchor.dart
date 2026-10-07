/// Composer dock geometry, shared with everything that sizes itself against
/// the dock.
///
/// [DockAnchor] lets the thumb sheets opened from the input dock (model seat,
/// permission seat, preset seat, the ➕ command roster, the prompt-mode shim)
/// float directly above the dock instead of hugging the screen's bottom edge,
/// where they crowded the thumb and covered nothing the reader cares about.
/// The chat panel binds a GlobalKey to its dock and publishes it here; a
/// sheet's opener measures the dock's on-screen rect and takes the returned
/// geometry.
///
/// [DockBudget] publishes how tall the dock may be. A decision seat (a
/// question, a plan review) caps its scrollable body against it, so its own
/// action row stays on screen — the row is the only way to answer, and the
/// dock sits directly above the root navigation bar.
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

/// The height the input dock's content may occupy, published by the dock to
/// its own children.
///
/// A decision card reads it to decide between a fixed cap (no dock: a bare
/// pump) and a flexing body whose action row is guaranteed to stay inside the
/// dock. Null outside a sized dock.
class DockBudget extends InheritedWidget {
  const DockBudget({required this.maxHeight, required super.child, super.key});

  final double maxHeight;

  /// The dock's budget for the calling context, or null when no sized dock
  /// encloses it.
  static double? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DockBudget>()?.maxHeight;

  @override
  bool updateShouldNotify(covariant DockBudget oldWidget) =>
      oldWidget.maxHeight != maxHeight;
}
