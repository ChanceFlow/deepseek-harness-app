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
    required this.labelTertiary,
    required this.labelCaption,
    required this.inputMajor,
    required this.borderThin,
    required this.bubble,
    required this.bubbleHighlight,
    required this.tip,
    required this.buttonElevatedFill,
    required this.borderL2,
    required this.warnPrimary,
    required this.warnSecondary,
    required this.warnTertiary,
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
  final Color labelTertiary;
  final Color labelCaption;

  /// Composer card surface + its one-notch-weaker stroke.
  final Color inputMajor;
  final Color borderThin;

  /// User-message bubble fill and its highlight variant.
  final Color bubble;
  final Color bubbleHighlight;

  /// `--dsw-specific-tip` — the queue dock panel fill.
  final Color tip;

  /// `--dsw-alias-button-elevated-fill` + `--dsw-alias-border-l2` — the
  /// sidebar New Session button pair.
  final Color buttonElevatedFill;
  final Color borderL2;

  /// `--dsw-alias-state-warn-*` — the approval-takeover card accents.
  final Color warnPrimary;
  final Color warnSecondary;
  final Color warnTertiary;

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
        labelTertiary: DeepSuiteLight.aliasLabelTertiary,
        labelCaption: DeepSuiteLight.aliasLabelCaption,
        inputMajor: DeepSuiteLight.specificInputMajor,
        borderThin: DeepSuiteLight.aliasBorderL2DarkmodeThin,
        bubble: DeepSuiteLight.specificBubble,
        bubbleHighlight: DeepSuiteLight.specificBubbleHighlight,
        tip: DeepSuiteLight.specificTip,
        buttonElevatedFill: DeepSuiteLight.aliasButtonElevatedFill,
        borderL2: DeepSuiteLight.aliasBorderL2,
        warnPrimary: DeepSuiteLight.aliasStateWarnPrimary,
        warnSecondary: DeepSuiteLight.aliasStateWarnSecondary,
        warnTertiary: DeepSuiteLight.aliasStateWarnTertiary,
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
        labelTertiary: DeepSuiteDark.aliasLabelTertiary,
        labelCaption: DeepSuiteDark.aliasLabelCaption,
        inputMajor: DeepSuiteDark.specificInputMajor,
        borderThin: DeepSuiteDark.aliasBorderL2DarkmodeThin,
        bubble: DeepSuiteDark.specificBubble,
        bubbleHighlight: DeepSuiteDark.specificBubbleHighlight,
        tip: DeepSuiteDark.specificTip,
        buttonElevatedFill: DeepSuiteDark.aliasButtonElevatedFill,
        borderL2: DeepSuiteDark.aliasBorderL2,
        warnPrimary: DeepSuiteDark.aliasStateWarnPrimary,
        warnSecondary: DeepSuiteDark.aliasStateWarnSecondary,
        warnTertiary: DeepSuiteDark.aliasStateWarnTertiary,
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
    Color? labelTertiary,
    Color? labelCaption,
    Color? inputMajor,
    Color? borderThin,
    Color? bubble,
    Color? bubbleHighlight,
    Color? tip,
    Color? buttonElevatedFill,
    Color? borderL2,
    Color? warnPrimary,
    Color? warnSecondary,
    Color? warnTertiary,
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
      labelTertiary: labelTertiary ?? this.labelTertiary,
      labelCaption: labelCaption ?? this.labelCaption,
      inputMajor: inputMajor ?? this.inputMajor,
      borderThin: borderThin ?? this.borderThin,
      bubble: bubble ?? this.bubble,
      bubbleHighlight: bubbleHighlight ?? this.bubbleHighlight,
      tip: tip ?? this.tip,
      buttonElevatedFill: buttonElevatedFill ?? this.buttonElevatedFill,
      borderL2: borderL2 ?? this.borderL2,
      warnPrimary: warnPrimary ?? this.warnPrimary,
      warnSecondary: warnSecondary ?? this.warnSecondary,
      warnTertiary: warnTertiary ?? this.warnTertiary,
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
      labelTertiary: Color.lerp(labelTertiary, other.labelTertiary, t)!,
      labelCaption: Color.lerp(labelCaption, other.labelCaption, t)!,
      inputMajor: Color.lerp(inputMajor, other.inputMajor, t)!,
      borderThin: Color.lerp(borderThin, other.borderThin, t)!,
      bubble: Color.lerp(bubble, other.bubble, t)!,
      bubbleHighlight: Color.lerp(bubbleHighlight, other.bubbleHighlight, t)!,
      tip: Color.lerp(tip, other.tip, t)!,
      buttonElevatedFill:
          Color.lerp(buttonElevatedFill, other.buttonElevatedFill, t)!,
      borderL2: Color.lerp(borderL2, other.borderL2, t)!,
      warnPrimary: Color.lerp(warnPrimary, other.warnPrimary, t)!,
      warnSecondary: Color.lerp(warnSecondary, other.warnSecondary, t)!,
      warnTertiary: Color.lerp(warnTertiary, other.warnTertiary, t)!,
    );
  }
}

/// `--dsw-shadow-lv2` (gradient-shadow-text.css): two soft layers.
const List<BoxShadow> kDsShadowLv2 = [
  BoxShadow(offset: Offset(0, 4), blurRadius: 12, color: Color(0x05000000)),
  BoxShadow(offset: Offset(0, 2), blurRadius: 8, color: Color(0x0A000000)),
];

/// Resolves the deepsuite extension from any context; falls back to the
/// light tokens when the host MaterialApp skipped `DshTheme` (tests).
DeepSuiteColors dsOf(BuildContext context) =>
    Theme.of(context).extension<DeepSuiteColors>() ?? DeepSuiteColors.light();
