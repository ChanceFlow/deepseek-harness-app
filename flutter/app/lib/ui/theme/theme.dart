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
    final onBrand =
        isDark ? DeepSuiteStatic.neutralBluish1000 : DeepSuiteStatic.neutralBluish00;
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
      surfaceContainerHighest:
          isDark ? DeepSuiteDark.aliasBgLayer2 : DeepSuiteLight.aliasBgLayer2,
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

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      splashFactory: InkSparkle.splashFactory,
      extensions: <ThemeExtension<dynamic>>[
        isDark ? DeepSuiteColors.dark() : DeepSuiteColors.light(),
      ],
    );
  }
}
