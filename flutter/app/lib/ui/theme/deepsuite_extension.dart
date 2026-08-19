/// deepsuite semantic surface tokens beyond Material's color roles.
///
/// Carries the `--dsw-alias-*` values screens need but a [ColorScheme]
/// cannot express (background layers, sidebar fills, link/accent ink).
/// Attached to every [DshTheme] via `ThemeExtension`.
library;

import 'package:flutter/material.dart';

import 'deepsuite_tokens.dart';

@immutable
class DeepSuiteColors extends ThemeExtension<DeepSuiteColors> {
  const DeepSuiteColors({
    required this.bgLayer1,
    required this.bgLayer2,
    required this.bgLayer3,
    required this.sidebarFill,
    required this.sidebarNavItemActive,
    required this.sidebarNavItemActiveAccent,
    required this.sidebarNavItemHover,
    required this.brandText,
    required this.accent,
    required this.divider,
    required this.labelSecondary,
  });

  /// Elevated surfaces: cards, code blocks, candidate panels.
  final Color bgLayer1;
  final Color bgLayer2;
  final Color bgLayer3;

  /// `--dsw-specific-sidebar-*` navigation chrome.
  final Color sidebarFill;
  final Color sidebarNavItemActive;
  final Color sidebarNavItemActiveAccent;
  final Color sidebarNavItemHover;

  /// DeepSeek-blue accent (links, active marks, focus).
  final Color brandText;

  /// The "new color" accent token (DeepSeek blue per theme).
  final Color accent;

  final Color divider;
  final Color labelSecondary;

  static DeepSuiteColors light() => const DeepSuiteColors(
        bgLayer1: DeepSuiteLight.aliasBgLayer1,
        bgLayer2: DeepSuiteLight.aliasBgLayer2,
        bgLayer3: DeepSuiteLight.aliasBgLayer3,
        sidebarFill: DeepSuiteLight.specificSidebarFill,
        sidebarNavItemActive: DeepSuiteLight.specificSidebarNavItemActive,
        sidebarNavItemActiveAccent:
            DeepSuiteLight.specificSidebarNavItemActiveAccent,
        sidebarNavItemHover: DeepSuiteLight.specificSidebarNavItemHover,
        brandText: DeepSuiteLight.aliasBrandText,
        accent:
            DeepSuiteLight.aliasBrandPrimaryNewColorprimaryNewColor,
        divider: DeepSuiteLight.aliasBorderL1,
        labelSecondary: DeepSuiteLight.aliasLabelSecondary,
      );

  static DeepSuiteColors dark() => const DeepSuiteColors(
        bgLayer1: DeepSuiteDark.aliasBgLayer1,
        bgLayer2: DeepSuiteDark.aliasBgLayer2,
        bgLayer3: DeepSuiteDark.aliasBgLayer3,
        sidebarFill: DeepSuiteDark.specificSidebarFill,
        sidebarNavItemActive: DeepSuiteDark.specificSidebarNavItemActive,
        sidebarNavItemActiveAccent:
            DeepSuiteDark.specificSidebarNavItemActiveAccent,
        sidebarNavItemHover: DeepSuiteDark.specificSidebarNavItemHover,
        brandText: DeepSuiteDark.aliasBrandText,
        accent: DeepSuiteDark.aliasBrandPrimaryNewColorprimaryNewColor,
        divider: DeepSuiteDark.aliasBorderL1,
        labelSecondary: DeepSuiteDark.aliasLabelSecondary,
      );

  @override
  DeepSuiteColors copyWith({
    Color? bgLayer1,
    Color? bgLayer2,
    Color? bgLayer3,
    Color? sidebarFill,
    Color? sidebarNavItemActive,
    Color? sidebarNavItemActiveAccent,
    Color? sidebarNavItemHover,
    Color? brandText,
    Color? accent,
    Color? divider,
    Color? labelSecondary,
  }) {
    return DeepSuiteColors(
      bgLayer1: bgLayer1 ?? this.bgLayer1,
      bgLayer2: bgLayer2 ?? this.bgLayer2,
      bgLayer3: bgLayer3 ?? this.bgLayer3,
      sidebarFill: sidebarFill ?? this.sidebarFill,
      sidebarNavItemActive: sidebarNavItemActive ?? this.sidebarNavItemActive,
      sidebarNavItemActiveAccent:
          sidebarNavItemActiveAccent ?? this.sidebarNavItemActiveAccent,
      sidebarNavItemHover: sidebarNavItemHover ?? this.sidebarNavItemHover,
      brandText: brandText ?? this.brandText,
      accent: accent ?? this.accent,
      divider: divider ?? this.divider,
      labelSecondary: labelSecondary ?? this.labelSecondary,
    );
  }

  @override
  DeepSuiteColors lerp(DeepSuiteColors? other, double t) {
    if (other == null) return this;
    return DeepSuiteColors(
      bgLayer1: Color.lerp(bgLayer1, other.bgLayer1, t)!,
      bgLayer2: Color.lerp(bgLayer2, other.bgLayer2, t)!,
      bgLayer3: Color.lerp(bgLayer3, other.bgLayer3, t)!,
      sidebarFill: Color.lerp(sidebarFill, other.sidebarFill, t)!,
      sidebarNavItemActive:
          Color.lerp(sidebarNavItemActive, other.sidebarNavItemActive, t)!,
      sidebarNavItemActiveAccent: Color.lerp(
          sidebarNavItemActiveAccent, other.sidebarNavItemActiveAccent, t)!,
      sidebarNavItemHover:
          Color.lerp(sidebarNavItemHover, other.sidebarNavItemHover, t)!,
      brandText: Color.lerp(brandText, other.brandText, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
      labelSecondary: Color.lerp(labelSecondary, other.labelSecondary, t)!,
    );
  }
}

/// Resolves the deepsuite extension from any context; falls back to the
/// light tokens when the host MaterialApp skipped `DshTheme` (tests).
DeepSuiteColors dsOf(BuildContext context) =>
    Theme.of(context).extension<DeepSuiteColors>() ?? DeepSuiteColors.light();
