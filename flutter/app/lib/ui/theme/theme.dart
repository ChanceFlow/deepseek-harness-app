/// App theme — native Material 3, seeded from the Material blue palette.
///
/// Components ride stock M3 roles ([ColorScheme] from [ColorScheme.fromSeed]);
/// no dsh-web design-platform tokens are ported.
library;

import 'package:flutter/material.dart';

/// Material 3 floating-surface shadow at elevation 1 (cards, chips).
const List<BoxShadow> kM3ShadowElevation1 = [
  BoxShadow(offset: Offset(0, 1), blurRadius: 2, color: Color(0x33000000)),
  BoxShadow(offset: Offset(0, 2), blurRadius: 6, color: Color(0x1F000000)),
];

/// Material 3 floating-surface shadow at elevation 3 (menus, popovers).
const List<BoxShadow> kM3ShadowElevation3 = [
  BoxShadow(offset: Offset(0, 1), blurRadius: 3, color: Color(0x3D000000)),
  BoxShadow(offset: Offset(0, 8), blurRadius: 24, color: Color(0x29000000)),
];

class DshTheme {
  const DshTheme._();

  /// Light scheme seeded from the Material blue palette.
  static ThemeData light() => _build(Brightness.light);

  /// Dark scheme seeded from the Material blue palette.
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: Colors.blue,
      brightness: brightness,
    );
    return ThemeData(
      colorScheme: scheme,
      // Android ripple feel (no-op on iOS).
      splashFactory: InkSparkle.splashFactory,
      // The composer's small send/stop FAB keeps a compact footprint;
      // fill/ink ride the stock M3 roles.
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        smallSizeConstraints: BoxConstraints.tightFor(
          width: 40,
          height: 40,
        ),
        elevation: 2,
        highlightElevation: 3,
        hoverElevation: 3,
        focusElevation: 3,
      ),
    );
  }
}