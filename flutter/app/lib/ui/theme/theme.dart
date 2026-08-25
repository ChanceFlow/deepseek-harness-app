/// App theme — native Material 3, seeded from the DeepSeek brand violet.
///
/// Components ride stock M3 roles ([ColorScheme] from [ColorScheme.fromSeed]);
/// no dsh-web design-platform tokens are ported. What this file adds beyond
/// the scheme is the part M3 leaves to the product: a reading-first type
/// scale, one shape language, and the component defaults that keep chrome
/// from competing with the transcript.
library;

import 'package:flutter/material.dart';

/// Colors Material 3 ships no role for. This extension is their one home: a
/// call site reads `scheme.success` rather than naming a green, and a new
/// entry is added here or argued down to an existing role.
extension DshSchemeColors on ColorScheme {
  /// Success green. M3 carries `error` but no success counterpart; the light
  /// value is Material green 600, the dark one green 300 for legibility on
  /// dark surfaces.
  Color get success => brightness == Brightness.light
      ? const Color(0xFF43A047)
      : const Color(0xFF81C784);
}

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

/// DeepSeek's brand violet — the one seed every role derives from.
const Color kDshBrandSeed = Color(0xFF4D6BFE);

/// Corner radii, largest to smallest: sheets and dialogs, the composer
/// dock, cards and menus, chips and rows. Four steps, no ad-hoc radius.
const double kShapeSheet = 28;
const double kShapeDock = 20;
const double kShapeCard = 14;
const double kShapeChip = 8;

class DshTheme {
  const DshTheme._();

  /// Light scheme seeded from the brand violet.
  static ThemeData light() => _build(Brightness.light);

  /// Dark scheme seeded from the brand violet.
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: kDshBrandSeed,
      brightness: brightness,
    );
    final base = ThemeData(colorScheme: scheme);
    return base.copyWith(
      scaffoldBackgroundColor: scheme.surface,
      // Android ripple feel (no-op on iOS).
      splashFactory: InkSparkle.splashFactory,
      textTheme: _typography(base.textTheme),
      // Chrome and content sit on different tones: the transcript keeps
      // `surface`, while every frame around it — bar, dock, drawer —
      // shares `surfaceContainer`. The reader never needs a rule to see
      // where the page stops.
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surfaceContainer,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        centerTitle: false,
        titleSpacing: 4,
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),
      popupMenuTheme: PopupMenuThemeData(
        elevation: 3,
        // The framework's stock shadow is opaque black at full strength,
        // which reads as a hard outline around a small menu; the panel
        // lifts on the same soft shadow the dock uses.
        shadowColor: scheme.shadow.withValues(alpha: 0.28),
        color: scheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(kShapeCard),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        showDragHandle: true,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(kShapeSheet),
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(kShapeChip),
        ),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      // The composer's small send/stop FAB keeps a compact footprint and
      // stays flat: the dock is already a raised surface, and a shadow
      // inside it reads as debris.
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        smallSizeConstraints: BoxConstraints.tightFor(width: 40, height: 40),
        elevation: 0,
        highlightElevation: 1,
        hoverElevation: 1,
        focusElevation: 1,
      ),
    );
  }

  /// Reading-first scale: a taller body measure for transcript prose,
  /// quieter labels for chrome, and titles that carry weight rather than
  /// size — a phone bar has no room to grow a headline.
  static TextTheme _typography(TextTheme base) => base.copyWith(
    titleLarge: base.titleLarge?.copyWith(
      fontWeight: FontWeight.w600,
      letterSpacing: -0.2,
    ),
    titleMedium: base.titleMedium?.copyWith(
      fontWeight: FontWeight.w600,
      letterSpacing: -0.1,
      height: 1.25,
    ),
    bodyLarge: base.bodyLarge?.copyWith(height: 1.5),
    bodyMedium: base.bodyMedium?.copyWith(fontSize: 15, height: 1.55),
    bodySmall: base.bodySmall?.copyWith(fontSize: 12.5, height: 1.45),
    labelLarge: base.labelLarge?.copyWith(fontWeight: FontWeight.w600),
    labelSmall: base.labelSmall?.copyWith(letterSpacing: 0.4),
  );
}
