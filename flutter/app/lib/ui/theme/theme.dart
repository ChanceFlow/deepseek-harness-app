/// App theme — deepsuite port: the dsh web design platform mapped onto
/// Material 3 roles plus a [DeepSuiteColors] extension.
///
/// Provenance: `reference/.../ui-theme/src/styles/design-platform.css`
/// (regenerate constants via `scripts/gen_deepsuite_tokens.py`).
library;

import 'package:flutter/material.dart';

import 'deepsuite_extension.dart';
import 'deepsuite_tokens.dart';

class DshTheme {
  const DshTheme._();

  /// Light scheme per the `body { --dsw-alias-* }` block.
  static ThemeData light() => _build(Brightness.light);

  /// Dark scheme per `body[data-ds-dark-theme]`.
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final brand = isDark
        ? DeepSuiteDark.aliasBrandPrimary
        : DeepSuiteLight.aliasBrandPrimary;
    // The web ink brand flips polarity per theme; Material needs explicit
    // on-color contrast (the CSS `*-invert` alias is not a contrast pair).
    final onBrand = isDark
        ? DeepSuiteStatic.neutralBluish1000
        : DeepSuiteStatic.neutralBluish00;
    final accent = isDark
        ? DeepSuiteDark.aliasBrandPrimaryNewColorprimaryNewColor
        : DeepSuiteLight.aliasBrandPrimaryNewColorprimaryNewColor;

    final scheme = ColorScheme(
      brightness: brightness,
      primary: brand,
      onPrimary: onBrand,
      secondary: accent,
      onSecondary: onBrand,
      surface: isDark ? DeepSuiteDark.aliasBgBase : DeepSuiteLight.aliasBgBase,
      onSurface: isDark
          ? DeepSuiteDark.aliasLabelPrimary
          : DeepSuiteLight.aliasLabelPrimary,
      surfaceContainerHighest: isDark
          ? DeepSuiteDark.aliasBgLayer2
          : DeepSuiteLight.aliasBgLayer2,
      onSurfaceVariant: isDark
          ? DeepSuiteDark.aliasLabelSecondary
          : DeepSuiteLight.aliasLabelSecondary,
      outline: isDark
          ? DeepSuiteDark.aliasBorderL1
          : DeepSuiteLight.aliasBorderL1,
      error: isDark
          ? DeepSuiteDark.aliasStateErrorPrimary
          : DeepSuiteLight.aliasStateErrorPrimary,
      onError: DeepSuiteStatic.neutralBluish00,
    );

    // Figma weight 510 renders as 500 in the web UI; apply the same
    // emphasis to the three title roles.
    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      splashFactory: InkSparkle.splashFactory,
      // Native component defaults ride the brand: the composer's small
      // send/stop FAB takes the brand fill unless the seat overrides it
      // (idle keeps the neutral selector fill).
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        smallSizeConstraints: const BoxConstraints.tightFor(
          width: 40,
          height: 40,
        ),
        backgroundColor: brand,
        foregroundColor: onBrand,
        elevation: 2,
        highlightElevation: 3,
        hoverElevation: 3,
        focusElevation: 3,
      ),
      extensions: <ThemeExtension<dynamic>>[
        isDark ? DeepSuiteColors.dark() : DeepSuiteColors.light(),
      ],
    );
    final titles = base.textTheme;
    final ds = isDark ? DeepSuiteColors.dark() : DeepSuiteColors.light();
    return base.copyWith(
      textTheme: titles.copyWith(
        titleLarge: titles.titleLarge?.copyWith(fontWeight: FontWeight.w500),
        titleMedium: titles.titleMedium?.copyWith(fontWeight: FontWeight.w500),
        titleSmall: titles.titleSmall?.copyWith(fontWeight: FontWeight.w500),
      ),
      // Timeline row chrome rides native components while keeping the
      // deepsuite flat visual: transparent tiles, no M3 card chrome, a
      // compact trailing arrow in the label-toned ink. Rows override only
      // per-row geometry (tilePadding / minTileHeight / childrenPadding).
      expansionTileTheme: ExpansionTileThemeData(
        backgroundColor: Colors.transparent,
        collapsedBackgroundColor: Colors.transparent,
        shape: const RoundedRectangleBorder(),
        collapsedShape: const RoundedRectangleBorder(),
        iconColor: ds.labelSecondary,
        collapsedIconColor: ds.labelSecondary,
        textColor: ds.labelSecondary,
        collapsedTextColor: ds.labelPrimaryDimmed,
        childrenPadding: const EdgeInsets.only(left: 20),
      ),
      // Question-card option rows (RadioListTile / CheckboxListTile): the
      // selected row keeps the web option fill, the tile text rides the
      // card's 14px body rhythm, and native indicators use the deepsuite
      // accent (radio) and the on-surface fill + foreground check
      // (checkbox) of the hand-drawn seats they replace.
      listTileTheme: ListTileThemeData(
        dense: true,
        visualDensity: VisualDensity.compact,
        contentPadding: const EdgeInsets.only(left: 8),
        minVerticalPadding: 4,
        selectedTileColor: ds.interactiveBgHover,
        selectedColor: scheme.onSurface,
        titleTextStyle: titles.bodyMedium?.copyWith(
          fontSize: 14,
          height: 24 / 14,
          fontWeight: FontWeight.w500,
        ),
        subtitleTextStyle: titles.bodyMedium?.copyWith(
          fontSize: 14,
          height: 24 / 14,
          color: ds.labelTertiary,
        ),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? ds.accent
              : Colors.transparent,
        ),
        overlayColor: WidgetStatePropertyAll(
          ds.interactiveBgHover.withValues(alpha: 0.25),
        ),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? scheme.onSurface
              : Colors.transparent,
        ),
        checkColor: WidgetStatePropertyAll(ds.labelPrimaryForeground),
        side: BorderSide(color: ds.borderL4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}
