/// Parity between the reference's alias layer and the tokens in `theme.dart`.
///
/// Every value below is the reference's own computation at
/// `reference/deepseek-harness/packages/client/ui-theme/src/styles/`, quoted by
/// file and line: `design-platform.css` publishes the aliases on `body` (light,
/// :167-282) and rebinds them on `body[data-ds-dark-theme]` (:285-398), over the
/// static palette at :5-82. The test exists so a token cannot drift from the pin
/// silently: it asserts each alias in *both* brightnesses against the literal
/// colour the pin's `var()`/`color-mix()` chain resolves to.
library;

import 'package:app/ui/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// The pin's static palette steps, by their `--dsw-static-*` names.

const Color _deepseek50 = Color(0xFFEDF3FE); // :29
const Color _deepseek200 = Color(0xFFD3E2FF); // :23
const Color _deepseek400 = Color(0xFF7AAAFF); // :26
const Color _deepseek450 = Color(0xFF5686FE); // :27
const Color _deepseek500 = Color(0xFF4176E6); // :28
const Color _blue300 = Color(0xFF93C5FD); // :11
const Color _blue950 = Color(0xFF172554); // :21
const Color _bluish00 = Color(0xFFFFFFFF); // :56
const Color _bluish50 = Color(0xFFF9FAFB); // :64
const Color _bluish60 = Color(0xFFF5F6F7); // :66
const Color _bluish75 = Color(0xFFF1F3F5); // :69
const Color _bluish100 = Color(0xFFEBEEF2); // :58
const Color _bluish200 = Color(0xFFE1E5EE); // :60
const Color _bluish300 = Color(0xFFCFD3D6); // :61
const Color _bluish400 = Color(0xFFADB2B8); // :62
const Color _bluish600 = Color(0xFF81858C); // :65
const Color _bluish700 = Color(0xFF61666B); // :67
const Color _bluish750 = Color(0xFF43454A); // :68
const Color _bluish800 = Color(0xFF353638); // :70
const Color _bluish850 = Color(0xFF2C2C2E); // :71
const Color _bluish875 = Color(0xFF232324); // :72
const Color _bluish900 = Color(0xFF1B1B1C); // :73
const Color _bluish950 = Color(0xFF151517); // :74
const Color _bluish1000 = Color(0xFF0F1115); // :57
const Color _neutral50 = Color(0xFFFAFAFA); // :49
const Color _neutral300 = Color(0xFFD4D4D4); // :46
const Color _neutral600 = Color(0xFF545557); // :51
const Color _neutral800 = Color(0xFF292929); // :53
const Color _green500 = Color(0xFF22C55E); // :36
const Color _amber500 = Color(0xFFF59E0B); // :7
const Color _amber600 = Color(0xFFDD8629); // :8
const Color _red400 = Color(0xFFF25A5A); // :76
const Color _red600 = Color(0xFFEC1313); // :80

/// `rgba(r, g, b, a)` as the pin writes it.
Color _rgba(int r, int g, int b, double a) =>
    Color.from(alpha: a, red: r / 255, green: g / 255, blue: b / 255);

/// One aliased colour: how to read it, the pin line that defines it, and the
/// value its `var()`/`color-mix()` chain resolves to in each brightness.
typedef _Alias = ({
  String name,
  String pin,
  Color Function(ColorScheme scheme) read,
  Color light,
  Color dark,
});

final ColorScheme _light = DshTheme.light().colorScheme;
final ColorScheme _dark = DshTheme.dark().colorScheme;

final List<_Alias> _aliases = <_Alias>[
  (
    name: 'bgBase',
    pin: 'design-platform.css:167 / :285',
    read: (scheme) => scheme.bgBase,
    light: _bluish00,
    dark: _bluish950,
  ),
  (
    name: 'bgLayer1',
    pin: 'design-platform.css:171 / :289',
    read: (scheme) => scheme.bgLayer1,
    light: _bluish00,
    dark: _bluish875,
  ),
  (
    name: 'bgLayer2',
    pin: 'design-platform.css:172 / :290',
    read: (scheme) => scheme.bgLayer2,
    light: _bluish00,
    dark: _bluish850,
  ),
  (
    name: 'bgLayer3',
    pin: 'design-platform.css:173 / :291',
    read: (scheme) => scheme.bgLayer3,
    light: _bluish00,
    dark: _bluish800,
  ),
  (
    name: 'borderL1',
    pin: 'design-platform.css:185 / :303',
    read: (scheme) => scheme.borderL1,
    light: _rgba(0, 0, 0, 0.04),
    dark: _rgba(255, 255, 255, 0.06),
  ),
  (
    name: 'borderL2',
    pin: 'design-platform.css:187 / :305',
    read: (scheme) => scheme.borderL2,
    light: _rgba(0, 0, 0, 0.10),
    dark: _rgba(255, 255, 255, 0.12),
  ),
  (
    name: 'borderL3',
    pin: 'design-platform.css:188 / :306',
    read: (scheme) => scheme.borderL3,
    light: _rgba(0, 0, 0, 0.12),
    dark: _rgba(255, 255, 255, 0.16),
  ),
  (
    name: 'borderL4',
    pin: 'design-platform.css:189 / :307',
    read: (scheme) => scheme.borderL4,
    light: _rgba(0, 0, 0, 0.16),
    dark: _rgba(255, 255, 255, 0.20),
  ),
  (
    name: 'labelPrimary',
    pin: 'design-platform.css:222 / :340',
    read: (scheme) => scheme.labelPrimary,
    light: _bluish1000,
    dark: _bluish50,
  ),
  (
    name: 'labelSecondary',
    pin: 'design-platform.css:223 / :341',
    read: (scheme) => scheme.labelSecondary,
    light: _bluish700,
    dark: _bluish300,
  ),
  (
    name: 'labelTertiary',
    pin: 'design-platform.css:225 / :343',
    read: (scheme) => scheme.labelTertiary,
    light: _bluish600,
    dark: _bluish400,
  ),
  (
    name: 'labelCaption',
    pin: 'design-platform.css:214 / :332',
    read: (scheme) => scheme.labelCaption,
    light: _bluish400,
    dark: _bluish600,
  ),
  (
    name: 'labelDimmed',
    pin: 'design-platform.css:217 / :335',
    read: (scheme) => scheme.labelDimmed,
    light: _bluish200,
    dark: _bluish750,
  ),
  (
    name: 'labelPrimaryDimmed',
    pin: 'design-platform.css:219 / :337',
    read: (scheme) => scheme.labelPrimaryDimmed,
    light: _bluish950,
    dark: _bluish100,
  ),
  (
    name: 'labelShimmer',
    pin: 'design-platform.css:224 / :342',
    read: (scheme) => scheme.labelShimmer,
    light: _rgba(0, 0, 0, 0.30),
    dark: _rgba(255, 255, 255, 0.45),
  ),
  (
    name: 'labelDeepDiving',
    pin: 'design-platform.css:215 / :334',
    read: (scheme) => scheme.labelDeepDiving,
    light: Color.lerp(_blue950, _deepseek500, 0.70)!,
    dark: Color.lerp(_bluish400, _deepseek450, 0.55)!,
  ),
  (
    name: 'labelDeepDivingShimmer',
    pin: 'design-platform.css:216 / :335',
    read: (scheme) => scheme.labelDeepDivingShimmer,
    light: Color.lerp(_blue950, _deepseek500, 0.30)!,
    dark: Color.lerp(_deepseek400, _blue300, 0.65)!,
  ),
  (
    name: 'interactiveBgHover',
    pin: 'design-platform.css:213 / :331',
    read: (scheme) => scheme.interactiveBgHover,
    light: _rgba(38, 49, 72, 0.06),
    dark: _rgba(255, 255, 255, 0.08),
  ),
  (
    name: 'interactiveBgActive',
    pin: 'design-platform.css:209 / :327',
    read: (scheme) => scheme.interactiveBgActive,
    light: _rgba(38, 49, 72, 0.10),
    dark: _rgba(255, 255, 255, 0.14),
  ),
  (
    name: 'interactiveBgHoverSolid',
    pin: 'design-platform.css:212 / :330',
    read: (scheme) => scheme.interactiveBgHoverSolid,
    light: _bluish75,
    dark: _bluish800,
  ),
  (
    name: 'markdownCodeBlock',
    pin: 'design-platform.css:230 / :348',
    read: (scheme) => scheme.markdownCodeBlock,
    light: _bluish50,
    dark: _bluish900,
  ),
  (
    name: 'markdownCodeBlockBanner',
    pin: 'design-platform.css:229 / :347',
    read: (scheme) => scheme.markdownCodeBlockBanner,
    light: _bluish50,
    dark: _bluish850,
  ),
  (
    name: 'markdownInlineCode',
    pin: 'design-platform.css:233 / :351',
    read: (scheme) => scheme.markdownInlineCode,
    light: _neutral50,
    dark: _neutral800,
  ),
  (
    name: 'markdownPlaceholder',
    pin: 'design-platform.css:234 / :352',
    read: (scheme) => scheme.markdownPlaceholder,
    light: _bluish60,
    dark: _bluish850,
  ),
  (
    name: 'markdownTag',
    pin: 'design-platform.css:235 / :353',
    read: (scheme) => scheme.markdownTag,
    light: _bluish75,
    dark: _bluish850,
  ),
  (
    name: 'stateBusinessPrimary',
    pin: 'design-platform.css:240 / :358',
    read: (scheme) => scheme.stateBusinessPrimary,
    light: _deepseek500,
    dark: _deepseek400,
  ),
  (
    name: 'stateErrorPrimary',
    pin: 'design-platform.css:250 / :368',
    read: (scheme) => scheme.stateErrorPrimary,
    light: _red600,
    dark: _red400,
  ),
  (
    name: 'stateSuccessPrimary',
    pin: 'design-platform.css:253 / :371',
    read: (scheme) => scheme.stateSuccessPrimary,
    light: _green500,
    dark: _green500,
  ),
  (
    name: 'stateIdlePrimary',
    pin: 'design-platform.css:252 / :370',
    read: (scheme) => scheme.stateIdlePrimary,
    light: _neutral300,
    dark: _neutral600,
  ),
  (
    name: 'stateWarnPrimary',
    pin: 'design-platform.css:257 / :375',
    read: (scheme) => scheme.stateWarnPrimary,
    light: _amber500,
    dark: _amber500,
  ),
  (
    name: 'stateWarnLabel',
    pin: 'design-platform.css:256 / :374',
    read: (scheme) => scheme.stateWarnLabel,
    light: _amber600,
    dark: _amber600,
  ),
  (
    name: 'turnTriggerBg',
    pin: 'design-platform.css:265 / :381',
    read: (scheme) => scheme.turnTriggerBg,
    light: _bluish50,
    dark: _rgba(255, 255, 255, 0.08),
  ),
  (
    name: 'turnTriggerBgHover',
    pin: 'design-platform.css:266 / :382',
    read: (scheme) => scheme.turnTriggerBgHover,
    light: _rgba(38, 49, 72, 0.06),
    dark: _rgba(255, 255, 255, 0.14),
  ),
  (
    name: 'bubble',
    pin: 'design-platform.css:268 / :386',
    read: (scheme) => scheme.bubble,
    light: _deepseek50,
    dark: _bluish850,
  ),
  (
    name: 'bubbleHighlight',
    pin: 'design-platform.css:267 / :385',
    read: (scheme) => scheme.bubbleHighlight,
    light: _deepseek200,
    dark: _bluish750,
  ),
  (
    name: 'inputSurface',
    pin: 'design-platform.css:269 / :387',
    read: (scheme) => scheme.inputSurface,
    light: _bluish00,
    dark: _bluish850,
  ),
  (
    name: 'menuSurfaceFill',
    pin: 'design-platform.css:271 / :389',
    read: (scheme) => scheme.menuSurfaceFill,
    light: _rgba(248, 249, 250, 0.58),
    dark: _rgba(67, 69, 74, 0.45),
  ),
  (
    name: 'buttonFloatingFill',
    pin: 'design-platform.css:196 / :314',
    read: (scheme) => scheme.buttonFloatingFill,
    light: _bluish00,
    dark: _bluish850,
  ),
  (
    name: 'buttonFloatingHover',
    pin: 'design-platform.css:197 / :315',
    read: (scheme) => scheme.buttonFloatingHover,
    light: _bluish75,
    dark: _bluish800,
  ),
];

void main() {
  for (final alias in _aliases) {
    test('${alias.name} matches ${alias.pin}', () {
      expect(alias.read(_light), alias.light, reason: 'light ${alias.name}');
      expect(alias.read(_dark), alias.dark, reason: 'dark ${alias.name}');
    });
  }

  test('the running divider is the pin\'s border mix', () {
    // `ChatView.module.css` `.runningDivider`, :141:
    // color-mix(in srgb, border-l1 75%, border-l2).
    expect(
      _light.runningDivider,
      Color.lerp(_rgba(0, 0, 0, 0.10), _rgba(0, 0, 0, 0.04), 0.75),
    );
    expect(
      _dark.runningDivider,
      Color.lerp(_rgba(255, 255, 255, 0.12), _rgba(255, 255, 255, 0.06), 0.75),
    );
  });

  test('the OLED appearance keeps the dark alias family', () {
    // The appearance moves the surface family only; every alias above is a
    // brightness branch and must therefore be the dark one.
    final oled = DshTheme.oled().colorScheme;
    expect(oled.labelPrimary, _dark.labelPrimary);
    expect(oled.labelTertiary, _dark.labelTertiary);
    expect(oled.borderL1, _dark.borderL1);
    expect(oled.markdownCodeBlock, _dark.markdownCodeBlock);
    expect(oled.bubble, _dark.bubble);
  });

  test('the radius scale is the pin\'s base.css steps', () {
    // base.css:16-21.
    expect(kRadiusXs, 4);
    expect(kRadiusSm, 8);
    expect(kRadiusMd, 12);
    expect(kRadiusLg, 16);
    expect(kRadiusXl, 20);
    expect(kRadiusPanel, 28);
    // The app's older names stand for the same steps, so they cannot drift.
    expect(kShapeChip, kRadiusSm);
    expect(kShapeMenuSheet, kRadiusMd);
    expect(kShapeDock, kRadiusXl);
    expect(kShapeBubble, kRadiusXl);
    expect(kShapeSheet, kRadiusPanel);
  });

  test('the type steps carry the pin\'s size, weight and line height', () {
    // gradient-shadow-text.css:181-271.
    expect(DshType.xl24.size, 24);
    expect(DshType.xl24.weight, FontWeight.w600);
    expect(DshType.xl24.lineHeight, 32);
    expect(DshType.l20.size, 20);
    expect(DshType.l20.weight, FontWeight.w500);
    expect(DshType.l20.lineHeight, 28);
    expect(DshType.m18.size, 16);
    expect(DshType.m18.weight, FontWeight.w500);
    expect(DshType.m18.lineHeight, 28);
    expect(DshType.base16.size, 16);
    expect(DshType.base16.weight, FontWeight.w400);
    expect(DshType.base16.lineHeight, 24);
    expect(DshType.baseStrong16.weight, FontWeight.w500);
    expect(DshType.s14.size, 14);
    expect(DshType.s14.lineHeight, 22);
    expect(DshType.sStrong14.weight, FontWeight.w500);
    expect(DshType.xs13.size, 13);
    expect(DshType.xs13.weight, FontWeight.w400);
    expect(DshType.xs13.lineHeight, 20);
    expect(DshType.xsStrong13.weight, FontWeight.w500);
    expect(DshType.xxs12.size, 12);
    expect(DshType.xxs12.lineHeight, 18);
    expect(DshType.xxsStrong12.weight, FontWeight.w500);
    expect(DshType.xxxs11.size, 11);
    expect(DshType.xxxs11.lineHeight, 14);
    expect(DshType.xxxsStrong11.weight, FontWeight.w500);

    expect(DshType.markdownH1.size, 21);
    expect(DshType.markdownH1.weight, FontWeight.w700);
    expect(DshType.markdownH1.lineHeight, 30);
    expect(DshType.markdownH2.size, 19);
    expect(DshType.markdownH2.lineHeight, 28);
    expect(DshType.markdownH3.size, 18);
    expect(DshType.markdownH3.lineHeight, 26);
    expect(DshType.markdownH4.size, 14);
    expect(DshType.markdownH4.weight, FontWeight.w600);
    expect(DshType.markdownBase.size, 14);
    expect(DshType.markdownBase.lineHeight, 24);
    expect(DshType.markdownBaseStrong.weight, FontWeight.w600);
    expect(DshType.markdownTable.size, 13);
    expect(DshType.markdownTable.lineHeight, 22);
    expect(DshType.markdownTableHead.weight, FontWeight.w500);
    expect(DshType.markdownSmall.size, 12);
    expect(DshType.markdownSmall.lineHeight, 20);
    expect(DshType.markdownSmallStrong.weight, FontWeight.w600);
    expect(DshType.markdownCode.size, 12);
    expect(DshType.markdownCode.lineHeight, 19);
    expect(DshType.markdownCodeBlock.size, 11);
    expect(DshType.markdownCodeBlock.lineHeight, 19);
    expect(DshType.markdownCodeBlockSmall.lineHeight, 16);

    // The chat's composition of the content axis at the default 14px.
    expect(DshType.chatRowTitle.size, kContentFontSizeSecondary);
    expect(DshType.chatRowTitle.lineHeight, 24);
    expect(DshType.chatRowSummary, same(DshType.xs13));
    expect(DshType.chatRunningLabel.size, kContentFontSize - 2);
    expect(DshType.chatRunningLabel.lineHeight, 22);
  });

  test('a step resolves to its absolute line box', () {
    final style = DshType.chatRowTitle.style(color: _light.labelTertiary);
    expect(style.fontSize, 13);
    expect(style.fontWeight, FontWeight.w400);
    expect(style.height, 24 / 13);
    expect(style.color, _light.labelTertiary);
  });

  test('the content axis and flow gaps are the pin\'s values', () {
    // gradient-shadow-text.css:57-59.
    expect(kContentFontSize, 14);
    expect(kContentFontSizeSecondary, 13);
    // ChatView.module.css:70 / :76 / :94.
    expect(kChatFlowGapStep, 6);
    expect(kChatFlowGap, 12);
    expect(kChatFlowGapAfterTurnHeader, 16);
  });

  test('motion names the pin\'s durations and curve', () {
    // base.css:12-15.
    expect(DshMotion.transitionFast, const Duration(milliseconds: 100));
    expect(DshMotion.transitionBase, const Duration(milliseconds: 200));
    expect(DshMotion.transitionSlow, const Duration(milliseconds: 300));
    expect(DshMotion.durationMicro, DshMotion.transitionFast);
    expect(DshMotion.durationShort, DshMotion.transitionBase);
    expect(DshMotion.durationMedium, DshMotion.transitionSlow);
    // `--ds-ease-in-out` is cubic-bezier(0.4, 0, 0.2, 1).
    const reference = Cubic(0.4, 0, 0.2, 1);
    for (final t in <double>[0, 0.25, 0.5, 0.75, 1]) {
      expect(DshMotion.easeInOut.transform(t), reference.transform(t));
    }
  });
}
