/// Every value in the pin's alias table, checked through the theme that is
/// assembled from it.
///
/// The expected colours are the pin's own resolution at
/// `reference/deepseek-harness/packages/client/ui-theme/src/styles/design-platform.css`:
/// `body` carries the light binding (:176-298) and `body[data-ds-dark-theme]`
/// the dark one (:300-420), over the static palette at :5-87. The aliases are
/// read back from `DshTheme.light()` / `DshTheme.dark()` rather than from the
/// bare constant, so this file fails if a theme stops carrying the table the
/// widgets are painted from.
library;

import 'package:app/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// The pin's static palette steps the alpha and mixed rows are derived from.
const Color _deepseek400 = Color(0xFF7AAAFF); // :26
const Color _deepseek450 = Color(0xFF5686FE); // :27
const Color _deepseek500 = Color(0xFF4176E6); // :28
const Color _blue300 = Color(0xFF93C5FD); // :11
const Color _blue950 = Color(0xFF172554); // :21
const Color _bluish400 = Color(0xFFADB2B8); // :63
const Color _bluish750 = Color(0xFF43454A); // :70
const Color _bluish850 = Color(0xFF2C2C2E); // :73
const Color _white = Color(0xFFFFFFFF); // :56

/// One aliased colour: the getter to read, the pin line that defines it, and
/// the `Color` the pin's `var()`/`color-mix()`/`rgba()` chain resolves to.
typedef _Alias = ({
  String name,
  String pin,
  Color Function(DshAliases aliases) read,
  Color light,
  Color dark,
});

final List<_Alias> _aliases = <_Alias>[
  (
    name: 'bgBase',
    pin: 'design-platform.css:177 / :301',
    read: (aliases) => aliases.bgBase,
    light: const Color(0xFFFFFFFF),
    dark: const Color(0xFF151517),
  ),
  (
    name: 'bgLayer1',
    pin: 'design-platform.css:181 / :305',
    read: (aliases) => aliases.bgLayer1,
    light: const Color(0xFFFFFFFF),
    dark: const Color(0xFF232324),
  ),
  (
    name: 'bgLayer2',
    pin: 'design-platform.css:182 / :306',
    read: (aliases) => aliases.bgLayer2,
    light: const Color(0xFFFFFFFF),
    dark: const Color(0xFF2C2C2E),
  ),
  (
    name: 'bgLayer3',
    pin: 'design-platform.css:183 / :307',
    read: (aliases) => aliases.bgLayer3,
    light: const Color(0xFFFFFFFF),
    dark: const Color(0xFF353638),
  ),
  (
    name: 'bgOverlay',
    pin: 'design-platform.css:191 / :315',
    read: (aliases) => aliases.bgOverlay,
    light: const Color(0xFFE9ECF2),
    dark: const Color(0xFF61666B),
  ),
  (
    name: 'bgMask1',
    pin: 'design-platform.css:184 / :308',
    read: (aliases) => aliases.bgMask1,
    light: const Color.fromRGBO(0, 0, 0, 0.24),
    dark: const Color.fromRGBO(0, 0, 0, 0.50),
  ),
  (
    name: 'bgMask2',
    pin: 'design-platform.css:185 / :309',
    read: (aliases) => aliases.bgMask2,
    light: const Color.fromRGBO(0, 0, 0, 0.12),
    dark: const Color.fromRGBO(0, 0, 0, 0.20),
  ),
  (
    name: 'labelPrimary',
    pin: 'design-platform.css:238 / :362',
    read: (aliases) => aliases.labelPrimary,
    light: const Color(0xFF0F1115),
    dark: const Color(0xFFF9FAFB),
  ),
  (
    name: 'labelSecondary',
    pin: 'design-platform.css:239 / :363',
    read: (aliases) => aliases.labelSecondary,
    light: const Color(0xFF61666B),
    dark: const Color(0xFFCFD3D6),
  ),
  (
    name: 'labelTertiary',
    pin: 'design-platform.css:241 / :365',
    read: (aliases) => aliases.labelTertiary,
    light: const Color(0xFF81858C),
    dark: const Color(0xFFADB2B8),
  ),
  (
    name: 'labelCaption',
    pin: 'design-platform.css:230 / :354',
    read: (aliases) => aliases.labelCaption,
    light: const Color(0xFFADB2B8),
    dark: const Color(0xFF81858C),
  ),
  (
    name: 'labelDimmed',
    pin: 'design-platform.css:233 / :357',
    read: (aliases) => aliases.labelDimmed,
    light: const Color(0xFFE1E5EE),
    dark: const Color(0xFF43454A),
  ),
  (
    name: 'labelPrimaryDimmed',
    pin: 'design-platform.css:235 / :359',
    read: (aliases) => aliases.labelPrimaryDimmed,
    light: const Color(0xFF151517),
    dark: const Color(0xFFEBEEF2),
  ),
  (
    name: 'labelShimmer',
    pin: 'design-platform.css:240 / :364',
    read: (aliases) => aliases.labelShimmer,
    light: const Color.fromRGBO(0, 0, 0, 0.30),
    dark: const Color.fromRGBO(255, 255, 255, 0.45),
  ),
  (
    name: 'link',
    pin: 'design-platform.css:243 / :367',
    read: (aliases) => aliases.link,
    light: const Color(0xFF4176E6),
    dark: const Color(0xFF7AAAFF),
  ),
  (
    name: 'menuIcon',
    pin: 'design-platform.css:242 / :366',
    read: (aliases) => aliases.menuIcon,
    light: const Color(0xFF353638),
    dark: const Color(0xFFEBEEF2),
  ),
  (
    name: 'brandText',
    pin: 'design-platform.css:203 / :327',
    read: (aliases) => aliases.brandText,
    light: const Color(0xFF0F1115),
    dark: const Color(0xFFF9FAFB),
  ),
  (
    name: 'borderL1',
    pin: 'design-platform.css:195 / :319',
    read: (aliases) => aliases.borderL1,
    light: const Color.fromRGBO(0, 0, 0, 0.04),
    dark: const Color.fromRGBO(255, 255, 255, 0.06),
  ),
  (
    name: 'borderL2',
    pin: 'design-platform.css:197 / :321',
    read: (aliases) => aliases.borderL2,
    light: const Color.fromRGBO(0, 0, 0, 0.10),
    dark: const Color.fromRGBO(255, 255, 255, 0.12),
  ),
  (
    name: 'borderL3',
    pin: 'design-platform.css:198 / :322',
    read: (aliases) => aliases.borderL3,
    light: const Color.fromRGBO(0, 0, 0, 0.12),
    dark: const Color.fromRGBO(255, 255, 255, 0.16),
  ),
  (
    name: 'borderL4',
    pin: 'design-platform.css:199 / :323',
    read: (aliases) => aliases.borderL4,
    light: const Color.fromRGBO(0, 0, 0, 0.16),
    dark: const Color.fromRGBO(255, 255, 255, 0.20),
  ),
  (
    name: 'borderInverted2',
    pin: 'design-platform.css:193 / :317',
    read: (aliases) => aliases.borderInverted2,
    light: const Color.fromRGBO(0, 0, 0, 0),
    dark: const Color.fromRGBO(255, 255, 255, 0.08),
  ),
  (
    name: 'brandPrimary',
    pin: 'design-platform.css:202 / :326',
    read: (aliases) => aliases.brandPrimary,
    light: const Color(0xFF0F1115),
    dark: const Color(0xFFF9FAFB),
  ),
  (
    name: 'buttonPrimaryFill',
    pin: 'design-platform.css:214 / :338',
    read: (aliases) => aliases.buttonPrimaryFill,
    light: const Color(0xFF0F1115),
    dark: const Color(0xFFF9FAFB),
  ),
  (
    name: 'buttonInfoFill',
    pin: 'design-platform.css:211 / :335',
    read: (aliases) => aliases.buttonInfoFill,
    light: const Color(0xFF4176E6),
    dark: const Color(0xFF7AAAFF),
  ),
  (
    name: 'buttonInfoHover',
    pin: 'design-platform.css:212 / :336',
    read: (aliases) => aliases.buttonInfoHover,
    light: const Color(0xFF7AAAFF),
    dark: const Color(0xFF4176E6),
  ),
  (
    name: 'buttonElevatedFill',
    pin: 'design-platform.css:205 / :329',
    read: (aliases) => aliases.buttonElevatedFill,
    light: const Color(0xFFFFFFFF),
    dark: const Color(0xFF43454A),
  ),
  (
    name: 'buttonFloatingFill',
    pin: 'design-platform.css:206 / :330',
    read: (aliases) => aliases.buttonFloatingFill,
    light: const Color(0xFFFFFFFF),
    dark: const Color(0xFF2C2C2E),
  ),
  (
    name: 'buttonFloatingHover',
    pin: 'design-platform.css:207 / :331',
    read: (aliases) => aliases.buttonFloatingHover,
    light: const Color(0xFFF1F3F5),
    dark: const Color(0xFF353638),
  ),
  (
    name: 'buttonContrastFill',
    pin: 'design-platform.css:204 / :328',
    read: (aliases) => aliases.buttonContrastFill,
    light: const Color(0xFF61666B),
    dark: const Color(0xFFF9FAFB),
  ),
  (
    name: 'buttonGhostActiveFill',
    pin: 'design-platform.css:209 / :333',
    read: (aliases) => aliases.buttonGhostActiveFill,
    light: const Color(0xFFEBEEF2),
    dark: const Color(0xFF43454A),
  ),
  (
    name: 'stateBusinessPrimary',
    pin: 'design-platform.css:256 / :380',
    read: (aliases) => aliases.stateBusinessPrimary,
    light: const Color(0xFF4176E6),
    dark: const Color(0xFF7AAAFF),
  ),
  (
    name: 'stateBusinessTertiary',
    pin: 'design-platform.css:257 / :381',
    read: (aliases) => aliases.stateBusinessTertiary,
    light: const Color(0xFFE4EDFD),
    dark: const Color(0xFF34415B),
  ),
  (
    name: 'stateSuccessPrimary',
    pin: 'design-platform.css:270 / :394',
    read: (aliases) => aliases.stateSuccessPrimary,
    light: const Color(0xFF22C55E),
    dark: const Color(0xFF22C55E),
  ),
  (
    name: 'stateSuccessSecondary',
    pin: 'design-platform.css:271 / :395',
    read: (aliases) => aliases.stateSuccessSecondary,
    light: const Color(0xFF4ED17E),
    dark: const Color(0xFF4ED17E),
  ),
  (
    name: 'stateSuccessTertiary',
    pin: 'design-platform.css:272 / :396',
    read: (aliases) => aliases.stateSuccessTertiary,
    light: const Color(0xFFE6FAED),
    dark: const Color(0xFF233C2C),
  ),
  (
    name: 'stateWarnPrimary',
    pin: 'design-platform.css:274 / :398',
    read: (aliases) => aliases.stateWarnPrimary,
    light: const Color(0xFFF59E0B),
    dark: const Color(0xFFF59E0B),
  ),
  (
    name: 'stateWarnSecondary',
    pin: 'design-platform.css:275 / :399',
    read: (aliases) => aliases.stateWarnSecondary,
    light: const Color(0xFFF7AD31),
    dark: const Color(0xFFF7AD31),
  ),
  (
    name: 'stateWarnTertiary',
    pin: 'design-platform.css:276 / :400',
    read: (aliases) => aliases.stateWarnTertiary,
    light: const Color(0xFFFEF5E7),
    dark: const Color(0xFF27241F),
  ),
  (
    name: 'stateWarnLabel',
    pin: 'design-platform.css:273 / :397',
    read: (aliases) => aliases.stateWarnLabel,
    light: const Color(0xFFDD8629),
    dark: const Color(0xFFDD8629),
  ),
  (
    name: 'stateErrorPrimary',
    pin: 'design-platform.css:267 / :391',
    read: (aliases) => aliases.stateErrorPrimary,
    light: const Color(0xFFEC1313),
    dark: const Color(0xFFF25A5A),
  ),
  (
    name: 'stateErrorSecondary',
    pin: 'design-platform.css:268 / :392',
    read: (aliases) => aliases.stateErrorSecondary,
    light: const Color(0xFFF25A5A),
    dark: const Color(0xFFF25A5A),
  ),
  (
    name: 'stateDonePrimary',
    pin: 'design-platform.css:266 / :390',
    read: (aliases) => aliases.stateDonePrimary,
    light: const Color(0xFF7C3AED),
    dark: const Color(0xFFA78BFA),
  ),
  (
    name: 'stateIdlePrimary',
    pin: 'design-platform.css:269 / :393',
    read: (aliases) => aliases.stateIdlePrimary,
    light: const Color(0xFFD4D4D4),
    dark: const Color(0xFF545557),
  ),
  (
    name: 'interactiveBgHover',
    pin: 'design-platform.css:229 / :353',
    read: (aliases) => aliases.interactiveBgHover,
    light: const Color.fromRGBO(38, 49, 72, 0.06),
    dark: const Color.fromRGBO(255, 255, 255, 0.08),
  ),
  (
    name: 'interactiveBgActive',
    pin: 'design-platform.css:225 / :349',
    read: (aliases) => aliases.interactiveBgActive,
    light: const Color.fromRGBO(38, 49, 72, 0.10),
    dark: const Color.fromRGBO(255, 255, 255, 0.14),
  ),
  (
    name: 'interactiveBgHoverAccent',
    pin: 'design-platform.css:226 / :350',
    read: (aliases) => aliases.interactiveBgHoverAccent,
    light: const Color.fromRGBO(38, 49, 72, 0.14),
    dark: const Color.fromRGBO(255, 255, 255, 0.24),
  ),
  (
    name: 'interactiveBgHoverDanger',
    pin: 'design-platform.css:227 / :351',
    read: (aliases) => aliases.interactiveBgHoverDanger,
    light: const Color.fromRGBO(236, 19, 19, 0.05),
    dark: const Color.fromRGBO(242, 90, 90, 0.15),
  ),
  (
    name: 'interactiveBgHoverSolid',
    pin: 'design-platform.css:228 / :352',
    read: (aliases) => aliases.interactiveBgHoverSolid,
    light: const Color(0xFFF1F3F5),
    dark: const Color(0xFF353638),
  ),
  (
    name: 'specificBubble',
    pin: 'design-platform.css:285 / :409',
    read: (aliases) => aliases.specificBubble,
    light: const Color(0xFFEDF3FE),
    dark: const Color(0xFF2C2C2E),
  ),
  (
    name: 'specificBubbleHighlight',
    pin: 'design-platform.css:284 / :408',
    read: (aliases) => aliases.specificBubbleHighlight,
    light: const Color(0xFFD3E2FF),
    dark: const Color(0xFF43454A),
  ),
  (
    name: 'specificInputMajor',
    pin: 'design-platform.css:286 / :410',
    read: (aliases) => aliases.specificInputMajor,
    light: const Color(0xFFFFFFFF),
    dark: const Color(0xFF2C2C2E),
  ),
  (
    name: 'specificLoginInput',
    pin: 'design-platform.css:287 / :411',
    read: (aliases) => aliases.specificLoginInput,
    light: const Color(0xFFF9FAFB),
    dark: const Color(0xFF1B1B1C),
  ),
  (
    name: 'specificSelector',
    pin: 'design-platform.css:291 / :415',
    read: (aliases) => aliases.specificSelector,
    light: const Color(0xFFF5F6F7),
    dark: const Color(0xFF353638),
  ),
  (
    name: 'specificSidebarFill',
    pin: 'design-platform.css:292 / :416',
    read: (aliases) => aliases.specificSidebarFill,
    light: const Color(0xFFF9FAFB),
    dark: const Color(0xFF1B1B1C),
  ),
  (
    name: 'specificSidebarNavItemActive',
    pin: 'design-platform.css:294 / :418',
    read: (aliases) => aliases.specificSidebarNavItemActive,
    light: const Color(0xFFEBEEF2),
    dark: const Color(0xFF43454A),
  ),
  (
    name: 'menuSurfaceFill',
    pin: 'design-platform.css:288 / :412',
    read: (aliases) => aliases.menuSurfaceFill,
    light: const Color.fromRGBO(252, 253, 254, 0.70),
    dark: const Color.fromRGBO(48, 49, 54, 0.64),
  ),
  (
    name: 'markdownCodeBlock',
    pin: 'design-platform.css:246 / :370',
    read: (aliases) => aliases.markdownCodeBlock,
    light: const Color(0xFFF9FAFB),
    dark: const Color(0xFF1B1B1C),
  ),
  (
    name: 'markdownCodeBlockBanner',
    pin: 'design-platform.css:245 / :369',
    read: (aliases) => aliases.markdownCodeBlockBanner,
    light: const Color(0xFFF9FAFB),
    dark: const Color(0xFF2C2C2E),
  ),
  (
    name: 'markdownInlineCode',
    pin: 'design-platform.css:249 / :373',
    read: (aliases) => aliases.markdownInlineCode,
    light: const Color(0xFFFAFAFA),
    dark: const Color(0xFF292929),
  ),
  (
    name: 'markdownCitation',
    pin: 'design-platform.css:244 / :368',
    read: (aliases) => aliases.markdownCitation,
    light: const Color(0xFFEBEEF2),
    dark: const Color(0xFF353638),
  ),
  (
    name: 'markdownPlaceholder',
    pin: 'design-platform.css:250 / :374',
    read: (aliases) => aliases.markdownPlaceholder,
    light: const Color(0xFFF5F6F7),
    dark: const Color(0xFF2C2C2E),
  ),
  (
    name: 'markdownTag',
    pin: 'design-platform.css:251 / :375',
    read: (aliases) => aliases.markdownTag,
    light: const Color(0xFFF1F3F5),
    dark: const Color(0xFF2C2C2E),
  ),
  (
    name: 'fileDiffAddedBg',
    pin: 'design-platform.css:260 / :384',
    read: (aliases) => aliases.fileDiffAddedBg,
    light: const Color(0xFFE6F4E7),
    dark: const Color(0xFF1F3124),
  ),
  (
    name: 'fileDiffAddedGutter',
    pin: 'design-platform.css:261 / :385',
    read: (aliases) => aliases.fileDiffAddedGutter,
    light: const Color(0xFFEDF7ED),
    dark: const Color(0xFF132016),
  ),
  (
    name: 'fileDiffAddedMarker',
    pin: 'design-platform.css:262 / :386',
    read: (aliases) => aliases.fileDiffAddedMarker,
    light: const Color(0xFF01A241),
    dark: const Color(0xFF41C977),
  ),
  (
    name: 'fileDiffDeletedBg',
    pin: 'design-platform.css:263 / :387',
    read: (aliases) => aliases.fileDiffDeletedBg,
    light: const Color(0xFFFCE6E2),
    dark: const Color(0xFF3C1F1B),
  ),
  (
    name: 'fileDiffDeletedGutter',
    pin: 'design-platform.css:264 / :388',
    read: (aliases) => aliases.fileDiffDeletedGutter,
    light: const Color(0xFFFDECE9),
    dark: const Color(0xFF28130E),
  ),
  (
    name: 'fileDiffDeletedMarker',
    pin: 'design-platform.css:265 / :389',
    read: (aliases) => aliases.fileDiffDeletedMarker,
    light: const Color(0xFFBA2723),
    dark: const Color(0xFFFA423E),
  ),
  (
    name: 'toastBg',
    pin: 'design-platform.css:278 / :402',
    read: (aliases) => aliases.toastBg,
    light: const Color(0xFF353638),
    dark: const Color(0xFF43454A),
  ),
  (
    name: 'toastLabel',
    pin: 'design-platform.css:279 / :403',
    read: (aliases) => aliases.toastLabel,
    light: const Color(0xFFFFFFFF),
    dark: const Color(0xFFFFFFFF),
  ),
  (
    name: 'tooltipBg',
    pin: 'design-platform.css:280 / :406',
    read: (aliases) => aliases.tooltipBg,
    light: const Color(0xFF2C2C2E),
    dark: const Color(0xFF43454A),
  ),
  (
    name: 'switchThumb',
    pin: 'design-platform.css:277 / :401',
    read: (aliases) => aliases.switchThumb,
    light: const Color(0xFFFFFFFF),
    dark: const Color(0xFFADB2B8),
  ),
  (
    name: 'scrollbarBgL1',
    pin: 'design-platform.css:252 / :376',
    read: (aliases) => aliases.scrollbarBgL1,
    light: const Color(0xFFE5E5E5),
    dark: const Color(0xFF3C3C3D),
  ),
  (
    name: 'scrollbarBgL2',
    pin: 'design-platform.css:253 / :377',
    read: (aliases) => aliases.scrollbarBgL2,
    light: const Color(0xFFE5E5E5),
    dark: const Color(0xFF545557),
  ),
  (
    name: 'tooltipKeyBg',
    pin: 'design-platform.css:281 / :407',
    read: (aliases) => aliases.tooltipKeyBg,
    light: Color.lerp(_bluish850, _white, 0.18)!,
    dark: Color.lerp(_bluish750, _white, 0.18)!,
  ),
  (
    name: 'labelDeepDiving',
    pin: 'design-platform.css:231 / :355',
    read: (aliases) => aliases.labelDeepDiving,
    light: Color.lerp(_blue950, _deepseek500, 0.70)!,
    dark: Color.lerp(_bluish400, _deepseek450, 0.55)!,
  ),
  (
    name: 'labelDeepDivingShimmer',
    pin: 'design-platform.css:232 / :356',
    read: (aliases) => aliases.labelDeepDivingShimmer,
    light: Color.lerp(_blue950, _deepseek500, 0.30)!,
    dark: Color.lerp(_deepseek400, _blue300, 0.65)!,
  ),
];
void main() {
  // The tables the two schemes actually carry, not a second transcription.
  final DshAliases light = DshTheme.light().colorScheme.aliases;
  final DshAliases dark = DshTheme.dark().colorScheme.aliases;

  for (final alias in _aliases) {
    test('${alias.name} is ${alias.pin}', () {
      expect(alias.read(light), alias.light, reason: 'light ${alias.name}');
      expect(alias.read(dark), alias.dark, reason: 'dark ${alias.name}');
    });
  }

  test('the table names the binding it came from', () {
    expect(light.isDark, isFalse);
    expect(dark.isDark, isTrue);
    expect(DshAliases.light, same(light));
    expect(DshAliases.dark, same(dark));
  });

  test('the OLED appearance reuses the dark table', () {
    expect(DshTheme.oled().colorScheme.aliases, same(DshAliases.dark));
  });
}
