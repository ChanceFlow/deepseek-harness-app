/// App theme — the reference's design language, carried by Material 3's
/// [ColorScheme] and the tokens M3 leaves to the product.
///
/// Material 3 still supplies the component defaults, but the chat window is
/// painted by the reference's own alias layer: the `--dsw-alias-*`,
/// `--dsw-specific-*` and `--dsw-radius-*` names from
/// `reference/deepseek-harness/packages/client/ui-theme/src/styles/{design-platform,base,gradient-shadow-text}.css`
/// are ported here by name, cited to their home, and never re-derived from the
/// M3 seed. This file is their only home: `verify_theme_native` rejects a raw
/// colour or radius at every other call site.
///
/// What lives where:
/// - colours: the [DshAliases] table (the pin's `--dsw-alias-*`,
///   `--dsw-specific-*` and `--dsw-menu-*` values) and the [DshSchemeColors]
///   extension on [ColorScheme], so a row reads `scheme.labelTertiary` rather
///   than `scheme.onSurfaceVariant`;
/// - radii: the `kRadius*` scale, with the app's older `kShape*` names kept as
///   aliases to the same steps;
/// - type: [DshType]'s `--dsw-font-*` steps with their weights and absolute
///   line heights, over the content-size axis [kContentFontSize];
/// - rhythm: the `kChatFlowGap*` scale, the edge fades and the code face;
/// - motion: [DshMotion]'s durations and curves, aliased to the reference's
///   `--ds-transition-*` / `--ds-ease-in-out`.
library;

import 'dart:ui' show ImageFilter;

import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

/// Colors Material 3 ships no role for. This extension is their one home: a
/// call site reads `scheme.labelTertiary` rather than naming a grey, and a new
/// entry is added here or argued down to an existing role.
extension DshSchemeColors on ColorScheme {
  /// The pin's alias table this scheme was assembled from: [DshAliases.light]
  /// on a light scheme, [DshAliases.dark] on both dark appearances. Every
  /// getter below that names an alias reads it through here, so the scheme and
  /// the table cannot drift.
  DshAliases get aliases =>
      brightness == Brightness.light ? DshAliases.light : DshAliases.dark;

  /// Success green. M3 carries `error` but no success counterpart. This is the
  /// **text** ink, not the state dot: the light value is a deep green for
  /// contrast >= 4.5:1 on light surfaces (6.44:1 on `bgBase`), the dark one
  /// green 300 for legibility on dark surfaces (9.06:1 on `bgBase`). The dots
  /// and fills wear the pin's exact `stateSuccess*` aliases below.
  Color get success => brightness == Brightness.light
      ? const Color(0xFF1B6D24)
      : const Color(0xFF81C784);

  /// The terminal screen's background and foreground. M3 has no "text console"
  /// pair: the surface is a fixed dark panel in both brightnesses, the way a
  /// terminal emulator is, so the host's plain text keeps its contrast
  /// regardless of the app theme. `surface`/`onSurface` would make a light
  /// theme render a dark-on-light console, which is not what the user picked
  /// when they opened a shell.
  Color get terminalBackground => const Color(0xFF101418);
  Color get terminalForeground => const Color(0xFFE6E6E6);

  /// Warning amber — the "waiting on the user" state, kept apart from
  /// `error`'s red. M3 ships no warn role; the reference web palette does:
  /// `--dsw-alias-state-warn-primary` is amber-500 in both brightnesses
  /// (design-platform.css:274 / :398). This getter is the **text** ink, not
  /// that dot: light takes deep amber-brown (#8D4F00) for contrast >= 4.5:1 on
  /// a light surface (6.46:1 on `bgBase`); dark takes amber-400
  /// (design-platform.css:6) for legibility on dark surfaces (9.53:1). The
  /// dots and fills wear the exact `stateWarn*` aliases below.
  Color get warning => brightness == Brightness.light
      ? const Color(0xFF8D4F00)
      : const Color(0xFFF7AD31);

  /// The running row's label tone — the reference's dedicated
  /// `--dsw-alias-label-deep-diving` alias (design-platform.css:231 light,
  /// :355 dark), which a running Turn's status text wears instead of any
  /// accent role.
  ///
  /// Each value is that alias's own `color-mix`: light is 70% of the palette's
  /// `--dsw-static-deepseek-500` (rgb(65, 118, 230), :28) over
  /// `--dsw-static-blue-950` (rgb(23, 37, 84), :21); dark is 55% of
  /// `--dsw-static-deepseek-450` (rgb(86, 134, 254), :27) over
  /// `--dsw-static-neutral-bluish-400` (rgb(173, 178, 184), :62). Both stops
  /// are opaque sRGB, so `color-mix(in srgb, A p%, B)` is the componentwise
  /// `p·A + (1 - p)·B` that [Color.lerp] computes as `lerp(B, A, p)`.
  Color get labelDeepDiving => aliases.labelDeepDiving;

  /// The running row's sweep highlight — the reference's
  /// `--dsw-alias-label-deep-diving-shimmer` (design-platform.css:232 light,
  /// :356 dark), mixed the same way: light is 30% `--dsw-static-deepseek-500`
  /// over `--dsw-static-blue-950`; dark is 65% `--dsw-static-blue-300`
  /// (rgb(147, 197, 253), :11) over `--dsw-static-deepseek-400`
  /// (rgb(122, 170, 255), :26).
  Color get labelDeepDivingShimmer => aliases.labelDeepDivingShimmer;

  /// Code-token colours for fenced blocks ([code_highlight.dart] classifies
  /// them, the markdown renderer paints them). Material 3 carries no syntax
  /// roles, and these three have to stay apart from each other *and* from
  /// `onSurface`, which the rest of the code body keeps wearing.
  ///
  /// Every value holds >= 4.5:1 against the surface a code block actually
  /// sits on — `surfaceContainerHigh`, #F1F3F5 light / #2C2C2E dark /
  /// #232329 in the OLED appearance — not against the page. Measured
  /// keyword / string / number: 8.44 / 5.79 / 5.72 in light, 5.83 / 6.93 /
  /// 8.05 in dark, 6.54 / 7.77 / 9.03 on the OLED code surface.
  Color get syntaxKeyword => brightness == Brightness.light
      ? const Color(0xFF6A1B9A)
      : const Color(0xFFCE93D8);

  /// String-literal token: green in both brightnesses, the reading a code
  /// fence carries everywhere else, and deliberately not `success` so a state
  /// colour never doubles as a token colour.
  Color get syntaxString => brightness == Brightness.light
      ? const Color(0xFF1B6D24)
      : const Color(0xFF81C784);

  /// Numeric-literal token.
  Color get syntaxNumber => brightness == Brightness.light
      ? const Color(0xFFA0430A)
      : const Color(0xFFFFB74D);

  /// The reader's own message container — `--dsw-specific-bubble`
  /// (design-platform.css:285 light, :409 dark), deepseek-50 light and
  /// neutral-bluish-850 dark, both opaque. The dark value is the same on the
  /// OLED appearance, which moves only the surface family.
  Color get bubble => aliases.specificBubble;

  // The reference's alias layer, by name.
  //
  // `design-platform.css` publishes these on `body` (light, :176-298) and
  // rebinds them on `body[data-ds-dark-theme]` (:300-420). [DshAliases] is
  // the single transcription of that table: each getter below is its alias
  // value for the scheme's brightness, never a value derived from the retired
  // M3 seed.

  /// `--dsw-alias-bg-base` (:177 / :301): the page behind the transcript.
  Color get bgBase => aliases.bgBase;

  /// `--dsw-alias-bg-layer-1/2/3` (:181-183 / :305-307): the raised surfaces
  /// above the page.
  Color get bgLayer1 => aliases.bgLayer1;
  Color get bgLayer2 => aliases.bgLayer2;
  Color get bgLayer3 => aliases.bgLayer3;

  /// `--dsw-alias-border-l1` (:195 / :319): the lightest hairline, worn by the
  /// transcript's rules and the running row's divider.
  Color get borderL1 => aliases.borderL1;

  /// `--dsw-alias-border-l2` (:197 / :321): the standard container stroke.
  Color get borderL2 => aliases.borderL2;

  /// `--dsw-alias-border-l3` (:198 / :322): the floating-button stroke.
  Color get borderL3 => aliases.borderL3;

  /// `--dsw-alias-border-l4` (:199 / :323): the heaviest hairline.
  Color get borderL4 => aliases.borderL4;

  /// The reference's `color-mix(in srgb, var(--dsw-alias-border-l1) 75%,
  /// var(--dsw-alias-border-l2))` — the running row's hairline
  /// (`ChatView.module.css` `.runningDivider`, :141).
  Color get runningDivider => Color.lerp(borderL2, borderL1, 0.75)!;

  /// `--dsw-alias-label-primary` (:238 / :362): the reading tone.
  Color get labelPrimary => aliases.labelPrimary;

  /// `--dsw-alias-label-secondary` (:239 / :363): the hovered row tone.
  Color get labelSecondary => aliases.labelSecondary;

  /// `--dsw-alias-label-tertiary` (:241 / :365): the row tone at rest.
  Color get labelTertiary => aliases.labelTertiary;

  /// `--dsw-alias-label-caption` (:230 / :354): the smallest furniture tone,
  /// worn by a separator dot.
  Color get labelCaption => aliases.labelCaption;

  /// `--dsw-alias-label-dimmed` (:233 / :357): the disabled tone.
  Color get labelDimmed => aliases.labelDimmed;

  /// `--dsw-alias-label-primary-dimmed` (:235 / :359): the compaction notice's
  /// old tone, one step off primary.
  Color get labelPrimaryDimmed => aliases.labelPrimaryDimmed;

  /// `--dsw-alias-label-shimmer` (:240 / :364): the platform's translucent
  /// neutral sweep.
  Color get labelShimmer => aliases.labelShimmer;

  /// `--dsw-alias-interactive-bg-hover` (:229 / :353): the row wash under the
  /// pointer.
  Color get interactiveBgHover => aliases.interactiveBgHover;

  /// `--dsw-alias-interactive-bg-active` (:225 / :349): the pressed wash.
  Color get interactiveBgActive => aliases.interactiveBgActive;

  /// `--dsw-alias-interactive-bg-hover-solid` (:228 / :352): the opaque
  /// companion of [interactiveBgHover], for a surface that cannot show a wash.
  Color get interactiveBgHoverSolid => aliases.interactiveBgHoverSolid;

  /// `--dsw-alias-markdown-code-block` (:246 / :370): the code surface — the
  /// fence, the tool body, the command body.
  Color get markdownCodeBlock => aliases.markdownCodeBlock;

  /// `--dsw-alias-markdown-code-block-banner` (:245 / :369): the fence's
  /// header strip.
  Color get markdownCodeBlockBanner => aliases.markdownCodeBlockBanner;

  /// `--dsw-alias-markdown-inline-code` (:249 / :373): the inline-code chip.
  Color get markdownInlineCode => aliases.markdownInlineCode;

  /// `--dsw-alias-markdown-placeholder` (:250 / :374): the skeleton tone
  /// behind a streaming block.
  Color get markdownPlaceholder => aliases.markdownPlaceholder;

  /// `--dsw-alias-markdown-tag` (:251 / :375): the citation/tag chip.
  Color get markdownTag => aliases.markdownTag;

  /// `--dsw-alias-state-business-primary` (:256 / :380): the brand state mark.
  Color get stateBusinessPrimary => aliases.stateBusinessPrimary;

  /// `--dsw-alias-state-business-tertiary` (:257 / :381): the brand container.
  Color get stateBusinessTertiary => aliases.stateBusinessTertiary;

  /// `--dsw-alias-state-error-primary` (:267 / :391): the failure mark.
  Color get stateErrorPrimary => aliases.stateErrorPrimary;

  /// `--dsw-alias-state-error-secondary` (:268 / :392): its lighter mark.
  Color get stateErrorSecondary => aliases.stateErrorSecondary;

  /// `--dsw-alias-state-success-primary` (:270 / :394): the settled mark.
  Color get stateSuccessPrimary => aliases.stateSuccessPrimary;

  /// `--dsw-alias-state-success-secondary` (:271 / :395): its lighter mark.
  Color get stateSuccessSecondary => aliases.stateSuccessSecondary;

  /// `--dsw-alias-state-success-tertiary` (:272 / :396): its container fill.
  Color get stateSuccessTertiary => aliases.stateSuccessTertiary;

  /// `--dsw-alias-state-idle-primary` (:269 / :393): the queued mark.
  Color get stateIdlePrimary => aliases.stateIdlePrimary;

  /// `--dsw-alias-state-warn-primary` (:274 / :398): the "waiting on you"
  /// mark, amber-500 in both brightnesses.
  Color get stateWarnPrimary => aliases.stateWarnPrimary;

  /// `--dsw-alias-state-warn-secondary` (:275 / :399): its lighter mark.
  Color get stateWarnSecondary => aliases.stateWarnSecondary;

  /// `--dsw-alias-state-warn-tertiary` (:276 / :400): its container fill.
  Color get stateWarnTertiary => aliases.stateWarnTertiary;

  /// `--dsw-alias-state-warn-label` (:273 / :397): the warn tone a *label*
  /// wears, amber-600 in both brightnesses.
  Color get stateWarnLabel => aliases.stateWarnLabel;

  /// `--dsw-alias-state-done-primary` (:266 / :390): the done mark —
  /// violet-600 light, violet-400 dark.
  Color get stateDonePrimary => aliases.stateDonePrimary;

  /// `--dsw-alias-turn-trigger-bg` (:282 / :404): the trigger notice's fill —
  /// the code surface in light, the pointer wash in dark.
  Color get turnTriggerBg => brightness == Brightness.light
      ? aliases.markdownCodeBlock
      : aliases.interactiveBgHover;

  /// `--dsw-alias-turn-trigger-bg-hover` (:283 / :405): its hovered fill — the
  /// pointer wash in light, the pressed wash in dark.
  Color get turnTriggerBgHover => brightness == Brightness.light
      ? aliases.interactiveBgHover
      : aliases.interactiveBgActive;

  /// `--dsw-specific-bubble-highlight` (:284 / :408): the bubble's own accent,
  /// the selection/highlight inside the reader's message.
  Color get bubbleHighlight => aliases.specificBubbleHighlight;

  /// `--dsw-specific-input-major` (:286 / :410): the composer's field fill.
  Color get inputSurface => aliases.specificInputMajor;

  /// `--dsw-menu-surface-fill` (:288 / :412): the translucent menu sheet —
  /// rgb(252, 253, 254) at 70% / rgb(48, 49, 54) at 64%.
  Color get menuSurfaceFill => aliases.menuSurfaceFill;

  /// [menuSurfaceFill] over the page it would have blurred: the fill
  /// alpha-composited onto [bgBase].
  ///
  /// The pin only ever paints the fill over `--dsw-menu-backdrop-filter`
  /// (`MenuSurface.module.css:27`), so its 70% / 64% alpha assumes a blur behind
  /// it. A surface that cannot blur — Material's `PopupMenuRoute` takes no
  /// backdrop hook — wears this composite instead of a see-through panel.
  Color get menuSurfaceOpaque => Color.alphaBlend(menuSurfaceFill, bgBase);

  /// `--dsw-alias-button-floating-fill` (:206 / :330): the scroll-to-bottom
  /// pill's fill.
  Color get buttonFloatingFill => aliases.buttonFloatingFill;

  /// `--dsw-alias-button-floating-hover` (:207 / :331): its hovered fill.
  Color get buttonFloatingHover => aliases.buttonFloatingHover;
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

/// The design-platform static palette steps the alias layer reads
/// (`design-platform.css:5-87`). The names are the pin's own families: `bluish`
/// is its `neutral-bluish`, `neutral` its `neutral`, plus the brand ramps. They
/// stay private — [DshAliases] and the M3 role map in [DshTheme] are their only
/// consumers.
const Color _deepseek50 = Color(0xFFEDF3FE); // :29
const Color _deepseek100 = Color(0xFFE4EDFD); // :22
const Color _deepseek200 = Color(0xFFD3E2FF); // :23
const Color _deepseek400 = Color(0xFF7AAAFF); // :26
const Color _deepseek450 = Color(0xFF5686FE); // :27
const Color _deepseek500 = Color(0xFF4176E6); // :28
const Color _deepseek800 = Color(0xFF34415B); // :32
const Color _blue300 = Color(0xFF93C5FD); // :11
const Color _blue900 = Color(0xFF0E3074); // :20
const Color _blue950 = Color(0xFF172554); // :21
const Color _bluish00 = Color(0xFFFFFFFF); // :56
const Color _bluish50 = Color(0xFFF9FAFB); // :65
const Color _bluish60 = Color(0xFFF5F6F7); // :68
const Color _bluish75 = Color(0xFFF1F3F5); // :71
const Color _bluish100 = Color(0xFFEBEEF2); // :58
const Color _bluish150 = Color(0xFFE9ECF2); // :59
const Color _bluish200 = Color(0xFFE1E5EE); // :60
const Color _bluish300 = Color(0xFFCFD3D6); // :61
const Color _bluish400 = Color(0xFFADB2B8); // :63
const Color _bluish600 = Color(0xFF81858C); // :67
const Color _bluish700 = Color(0xFF61666B); // :69
const Color _bluish750 = Color(0xFF43454A); // :70
const Color _bluish800 = Color(0xFF353638); // :72
const Color _bluish850 = Color(0xFF2C2C2E); // :73
const Color _bluish875 = Color(0xFF232324); // :74
const Color _bluish900 = Color(0xFF1B1B1C); // :75
const Color _bluish950 = Color(0xFF151517); // :77
const Color _bluish1000 = Color(0xFF0F1115); // :57
const Color _neutral50 = Color(0xFFFAFAFA); // :49
const Color _neutral200 = Color(0xFFE5E5E5); // :44
const Color _neutral300 = Color(0xFFD4D4D4); // :46
const Color _neutral600 = Color(0xFF545557); // :51
const Color _neutral700 = Color(0xFF3C3C3D); // :52
const Color _neutral800 = Color(0xFF292929); // :53
const Color _green100 = Color(0xFFE6FAED); // :34
const Color _green400 = Color(0xFF4ED17E); // :35
const Color _green500 = Color(0xFF22C55E); // :36
const Color _green900 = Color(0xFF233C2C); // :39
const Color _amber100 = Color(0xFFFEF5E7); // :5
const Color _amber400 = Color(0xFFF7AD31); // :6
const Color _amber500 = Color(0xFFF59E0B); // :7
const Color _amber600 = Color(0xFFDD8629); // :8
const Color _amber900 = Color(0xFF27241F); // :9
const Color _red50 = Color(0xFFFEF2F2); // :82
const Color _red400 = Color(0xFFF25A5A); // :79
const Color _red600 = Color(0xFFEC1313); // :83
const Color _red900 = Color(0xFF570C0C); // :85
const Color _violet400 = Color(0xFFA78BFA); // :86
const Color _violet600 = Color(0xFF7C3AED); // :87

/// The pin's alias layer, value for value.
///
/// `design-platform.css` publishes these on `body` (light, :176-298) and
/// rebinds them on `body[data-ds-dark-theme]` (:300-420). Each field names the
/// `--dsw-alias-*` (or `--dsw-specific-*` / `--dsw-menu-*`) property it ports
/// and cites the line that defines it; [light] and [dark] carry the two
/// bindings. [DshTheme] assembles its [ColorScheme] from this table, and
/// [DshSchemeColors] reads it for the roles Material 3 has no name for.
///
/// A value that the pin writes as `var(--dsw-static-*)` is the palette step
/// itself; one it writes as `rgba(...)` keeps its alpha; one it writes as
/// `color-mix(...)` is the mix in [Color.lerp] form. The table is `const`
/// apart from the three mixed values, which are computed on read so they stay
/// exact instead of rounding to a nearby 8-bit literal.
@immutable
final class DshAliases {
  const DshAliases({
    required this.bgBase,
    required this.bgLayer1,
    required this.bgLayer2,
    required this.bgLayer3,
    required this.bgOverlay,
    required this.bgMask1,
    required this.bgMask2,
    required this.labelPrimary,
    required this.labelSecondary,
    required this.labelTertiary,
    required this.labelCaption,
    required this.labelDimmed,
    required this.labelPrimaryDimmed,
    required this.labelShimmer,
    required this.link,
    required this.menuIcon,
    required this.brandText,
    required this.borderL1,
    required this.borderL2,
    required this.borderL3,
    required this.borderL4,
    required this.borderInverted2,
    required this.brandPrimary,
    required this.buttonPrimaryFill,
    required this.buttonInfoFill,
    required this.buttonInfoHover,
    required this.buttonElevatedFill,
    required this.buttonFloatingFill,
    required this.buttonFloatingHover,
    required this.buttonContrastFill,
    required this.buttonGhostActiveFill,
    required this.stateBusinessPrimary,
    required this.stateBusinessTertiary,
    required this.stateSuccessPrimary,
    required this.stateSuccessSecondary,
    required this.stateSuccessTertiary,
    required this.stateWarnPrimary,
    required this.stateWarnSecondary,
    required this.stateWarnTertiary,
    required this.stateWarnLabel,
    required this.stateErrorPrimary,
    required this.stateErrorSecondary,
    required this.stateDonePrimary,
    required this.stateIdlePrimary,
    required this.interactiveBgHover,
    required this.interactiveBgActive,
    required this.interactiveBgHoverAccent,
    required this.interactiveBgHoverDanger,
    required this.interactiveBgHoverSolid,
    required this.specificBubble,
    required this.specificBubbleHighlight,
    required this.specificInputMajor,
    required this.specificLoginInput,
    required this.specificSelector,
    required this.specificSidebarFill,
    required this.specificSidebarNavItemActive,
    required this.menuSurfaceFill,
    required this.markdownCodeBlock,
    required this.markdownCodeBlockBanner,
    required this.markdownInlineCode,
    required this.markdownCitation,
    required this.markdownPlaceholder,
    required this.markdownTag,
    required this.fileDiffAddedBg,
    required this.fileDiffAddedGutter,
    required this.fileDiffAddedMarker,
    required this.fileDiffDeletedBg,
    required this.fileDiffDeletedGutter,
    required this.fileDiffDeletedMarker,
    required this.toastBg,
    required this.toastLabel,
    required this.tooltipBg,
    required this.switchThumb,
    required this.scrollbarBgL1,
    required this.scrollbarBgL2,
    required this.isDark,
  });

  /// Whether this is the `body[data-ds-dark-theme]` binding.
  final bool isDark;

  // Page and raised surfaces.

  /// `--dsw-alias-bg-base` (:177 / :301): the page behind the transcript.
  final Color bgBase;

  /// `--dsw-alias-bg-layer-1` (:181 / :305): the first raised tone above it.
  final Color bgLayer1;

  /// `--dsw-alias-bg-layer-2` (:182 / :306): a menu, a sheet, a dialog.
  final Color bgLayer2;

  /// `--dsw-alias-bg-layer-3` (:183 / :307): the highest raised tone.
  final Color bgLayer3;

  /// `--dsw-alias-bg-overlay` (:191 / :315): the tone behind a full overlay.
  final Color bgOverlay;

  /// `--dsw-alias-bg-mask-1` (:184 / :308): the modal scrim.
  final Color bgMask1;

  /// `--dsw-alias-bg-mask-2` (:185 / :309): the lighter mask.
  final Color bgMask2;

  // Label inks.

  /// `--dsw-alias-label-primary` (:238 / :362): the reading tone.
  final Color labelPrimary;

  /// `--dsw-alias-label-secondary` (:239 / :363): metadata and secondary ink.
  final Color labelSecondary;

  /// `--dsw-alias-label-tertiary` (:241 / :365): the row tone at rest.
  final Color labelTertiary;

  /// `--dsw-alias-label-caption` (:230 / :354): the smallest furniture tone.
  final Color labelCaption;

  /// `--dsw-alias-label-dimmed` (:233 / :357): the disabled tone.
  final Color labelDimmed;

  /// `--dsw-alias-label-primary-dimmed` (:235 / :359): one step off primary.
  final Color labelPrimaryDimmed;

  /// `--dsw-alias-label-shimmer` (:240 / :364): the translucent sweep.
  final Color labelShimmer;

  /// `--dsw-alias-link` (:243 / :367): link ink — deepseek-500 / deepseek-400.
  final Color link;

  /// `--dsw-alias-menu-icon` (:242 / :366): the menu glyph tone. In dark it
  /// resolves to `--dsw-alias-label-primary-dimmed` (:366).
  final Color menuIcon;

  /// `--dsw-alias-brand-text` (:203 / :327): the wordmark's ink.
  final Color brandText;

  // Hairlines and the inverted pair.

  /// `--dsw-alias-border-l1` (:195 / :319): the lightest hairline.
  final Color borderL1;

  /// `--dsw-alias-border-l2` (:197 / :321): the standard container stroke.
  final Color borderL2;

  /// `--dsw-alias-border-l3` (:198 / :322): the floating-button stroke.
  final Color borderL3;

  /// `--dsw-alias-border-l4` (:199 / :323): the heaviest hairline.
  final Color borderL4;

  /// `--dsw-alias-border-inverted2` (:193 / :317): the inverted ghost stroke.
  final Color borderInverted2;

  // Brand and button fills.

  /// `--dsw-alias-brand-primary` (:202 / :326): the brand mark — bluish-1000
  /// light, bluish-50 dark.
  final Color brandPrimary;

  /// `--dsw-alias-button-primary-fill` (:214 / :338): the primary button,
  /// bound to `--dsw-alias-brand-primary`.
  final Color buttonPrimaryFill;

  /// `--dsw-alias-button-info-fill` (:211 / :335): the blue action fill.
  final Color buttonInfoFill;

  /// `--dsw-alias-button-info-hover` (:212 / :336): its hovered fill.
  final Color buttonInfoHover;

  /// `--dsw-alias-button-elevated-fill` (:205 / :329): the elevated button.
  final Color buttonElevatedFill;

  /// `--dsw-alias-button-floating-fill` (:206 / :330): the floating pill.
  final Color buttonFloatingFill;

  /// `--dsw-alias-button-floating-hover` (:207 / :331): its hovered fill.
  final Color buttonFloatingHover;

  /// `--dsw-alias-button-contrast-fill` (:204 / :328): the contrast button.
  final Color buttonContrastFill;

  /// `--dsw-alias-button-ghost-active-fill` (:209 / :333): an active ghost.
  final Color buttonGhostActiveFill;

  // State marks and fills.

  /// `--dsw-alias-state-business-primary` (:256 / :380): the brand state mark.
  final Color stateBusinessPrimary;

  /// `--dsw-alias-state-business-tertiary` (:257 / :381): its container fill.
  final Color stateBusinessTertiary;

  /// `--dsw-alias-state-success-primary` (:270 / :394): the settled mark.
  final Color stateSuccessPrimary;

  /// `--dsw-alias-state-success-secondary` (:271 / :395): its lighter mark.
  final Color stateSuccessSecondary;

  /// `--dsw-alias-state-success-tertiary` (:272 / :396): its container fill.
  final Color stateSuccessTertiary;

  /// `--dsw-alias-state-warn-primary` (:274 / :398): the waiting mark.
  final Color stateWarnPrimary;

  /// `--dsw-alias-state-warn-secondary` (:275 / :399): its lighter mark.
  final Color stateWarnSecondary;

  /// `--dsw-alias-state-warn-tertiary` (:276 / :400): its container fill.
  final Color stateWarnTertiary;

  /// `--dsw-alias-state-warn-label` (:273 / :397): the warn label tone.
  final Color stateWarnLabel;

  /// `--dsw-alias-state-error-primary` (:267 / :391): the failure mark.
  final Color stateErrorPrimary;

  /// `--dsw-alias-state-error-secondary` (:268 / :392): its lighter mark.
  final Color stateErrorSecondary;

  /// `--dsw-alias-state-done-primary` (:266 / :390): the done mark.
  final Color stateDonePrimary;

  /// `--dsw-alias-state-idle-primary` (:269 / :393): the queued mark.
  final Color stateIdlePrimary;

  // Pointer and pressed washes.

  /// `--dsw-alias-interactive-bg-hover` (:229 / :353): the row wash.
  final Color interactiveBgHover;

  /// `--dsw-alias-interactive-bg-active` (:225 / :349): the pressed wash.
  final Color interactiveBgActive;

  /// `--dsw-alias-interactive-bg-hover-accent` (:226 / :350): the accent wash.
  final Color interactiveBgHoverAccent;

  /// `--dsw-alias-interactive-bg-hover-danger` (:227 / :351): the danger wash.
  final Color interactiveBgHoverDanger;

  /// `--dsw-alias-interactive-bg-hover-solid` (:228 / :352): the opaque wash.
  final Color interactiveBgHoverSolid;

  // The pin's `--dsw-specific-*` surfaces.

  /// `--dsw-specific-bubble` (:285 / :409): the reader's message fill.
  final Color specificBubble;

  /// `--dsw-specific-bubble-highlight` (:284 / :408): its selection accent.
  final Color specificBubbleHighlight;

  /// `--dsw-specific-input-major` (:286 / :410): the composer's field fill.
  final Color specificInputMajor;

  /// `--dsw-specific-login-input` (:287 / :411): the login field fill.
  final Color specificLoginInput;

  /// `--dsw-specific-selector` (:291 / :415): the picker's resting fill.
  final Color specificSelector;

  /// `--dsw-specific-sidebar-fill` (:292 / :416): the chrome tone.
  final Color specificSidebarFill;

  /// `--dsw-specific-sidebar-nav-item-active` (:294 / :418): the active row.
  final Color specificSidebarNavItemActive;

  /// `--dsw-menu-surface-fill` (:288 / :412): the translucent menu sheet.
  final Color menuSurfaceFill;

  // Markdown.

  /// `--dsw-alias-markdown-code-block` (:246 / :370): the code surface.
  final Color markdownCodeBlock;

  /// `--dsw-alias-markdown-code-block-banner` (:245 / :369): its header strip.
  final Color markdownCodeBlockBanner;

  /// `--dsw-alias-markdown-inline-code` (:249 / :373): the inline-code chip.
  final Color markdownInlineCode;

  /// `--dsw-alias-markdown-citation` (:244 / :368): the citation chip.
  final Color markdownCitation;

  /// `--dsw-alias-markdown-placeholder` (:250 / :374): the skeleton tone.
  final Color markdownPlaceholder;

  /// `--dsw-alias-markdown-tag` (:251 / :375): the tag chip.
  final Color markdownTag;

  // File diffs.

  /// `--dsw-alias-file-diff-added-bg` (:260 / :384): an added line's fill.
  final Color fileDiffAddedBg;

  /// `--dsw-alias-file-diff-added-gutter` (:261 / :385): its gutter.
  final Color fileDiffAddedGutter;

  /// `--dsw-alias-file-diff-added-marker` (:262 / :386): its marker.
  final Color fileDiffAddedMarker;

  /// `--dsw-alias-file-diff-deleted-bg` (:263 / :387): a deleted line's fill.
  final Color fileDiffDeletedBg;

  /// `--dsw-alias-file-diff-deleted-gutter` (:264 / :388): its gutter.
  final Color fileDiffDeletedGutter;

  /// `--dsw-alias-file-diff-deleted-marker` (:265 / :389): its marker.
  final Color fileDiffDeletedMarker;

  // Toasts, tooltips and scrollbars.

  /// `--dsw-alias-toast-bg` (:278 / :402): the toast panel.
  final Color toastBg;

  /// `--dsw-alias-toast-label` (:279 / :403): the toast's ink.
  final Color toastLabel;

  /// `--dsw-alias-tooltip-bg` (:280 / :406): the tooltip panel.
  final Color tooltipBg;

  /// `--dsw-alias-tooltip-key-bg` (:281 / :407):
  /// `color-mix(in srgb, tooltip-bg, white 18%)`.
  Color get tooltipKeyBg => isDark
      ? Color.lerp(_bluish750, _bluish00, 0.18)!
      : Color.lerp(_bluish850, _bluish00, 0.18)!;

  /// `--dsw-alias-switch-thumb` (:277 / :401): the switch thumb.
  final Color switchThumb;

  /// `--dsw-alias-scrollbar-bg-l1` (:252 / :376): the scrollbar's track.
  final Color scrollbarBgL1;

  /// `--dsw-alias-scrollbar-bg-l2` (:253 / :377): its lighter level.
  final Color scrollbarBgL2;

  // The two `color-mix` labels, computed so the mix stays exact.

  /// `--dsw-alias-label-deep-diving` (:231 / :355): the running row's label —
  /// 70% deepseek-500 over blue-950 light, 55% deepseek-450 over
  /// neutral-bluish-400 dark.
  Color get labelDeepDiving => isDark
      ? Color.lerp(_bluish400, _deepseek450, 0.55)!
      : Color.lerp(_blue950, _deepseek500, 0.70)!;

  /// `--dsw-alias-label-deep-diving-shimmer` (:232 / :356): its sweep — 30%
  /// deepseek-500 over blue-950 light, 65% blue-300 over deepseek-400 dark.
  Color get labelDeepDivingShimmer => isDark
      ? Color.lerp(_deepseek400, _blue300, 0.65)!
      : Color.lerp(_blue950, _deepseek500, 0.30)!;

  /// The `body` binding (light).
  static const DshAliases light = DshAliases(
    isDark: false,
    bgBase: _bluish00,
    bgLayer1: _bluish00,
    bgLayer2: _bluish00,
    bgLayer3: _bluish00,
    bgOverlay: _bluish150,
    bgMask1: Color.fromRGBO(0, 0, 0, 0.24),
    bgMask2: Color.fromRGBO(0, 0, 0, 0.12),
    labelPrimary: _bluish1000,
    labelSecondary: _bluish700,
    labelTertiary: _bluish600,
    labelCaption: _bluish400,
    labelDimmed: _bluish200,
    labelPrimaryDimmed: _bluish950,
    labelShimmer: Color.fromRGBO(0, 0, 0, 0.30),
    link: _deepseek500,
    menuIcon: _bluish800,
    brandText: _bluish1000,
    borderL1: Color.fromRGBO(0, 0, 0, 0.04),
    borderL2: Color.fromRGBO(0, 0, 0, 0.10),
    borderL3: Color.fromRGBO(0, 0, 0, 0.12),
    borderL4: Color.fromRGBO(0, 0, 0, 0.16),
    borderInverted2: Color.fromRGBO(0, 0, 0, 0),
    brandPrimary: _bluish1000,
    buttonPrimaryFill: _bluish1000,
    buttonInfoFill: _deepseek500,
    buttonInfoHover: _deepseek400,
    buttonElevatedFill: _bluish00,
    buttonFloatingFill: _bluish00,
    buttonFloatingHover: _bluish75,
    buttonContrastFill: _bluish700,
    buttonGhostActiveFill: _bluish100,
    stateBusinessPrimary: _deepseek500,
    stateBusinessTertiary: _deepseek100,
    stateSuccessPrimary: _green500,
    stateSuccessSecondary: _green400,
    stateSuccessTertiary: _green100,
    stateWarnPrimary: _amber500,
    stateWarnSecondary: _amber400,
    stateWarnTertiary: _amber100,
    stateWarnLabel: _amber600,
    stateErrorPrimary: _red600,
    stateErrorSecondary: _red400,
    stateDonePrimary: _violet600,
    stateIdlePrimary: _neutral300,
    interactiveBgHover: Color.fromRGBO(38, 49, 72, 0.06),
    interactiveBgActive: Color.fromRGBO(38, 49, 72, 0.10),
    interactiveBgHoverAccent: Color.fromRGBO(38, 49, 72, 0.14),
    interactiveBgHoverDanger: Color.fromRGBO(236, 19, 19, 0.05),
    interactiveBgHoverSolid: _bluish75,
    specificBubble: _deepseek50,
    specificBubbleHighlight: _deepseek200,
    specificInputMajor: _bluish00,
    specificLoginInput: _bluish50,
    specificSelector: _bluish60,
    specificSidebarFill: _bluish50,
    specificSidebarNavItemActive: _bluish100,
    menuSurfaceFill: Color.fromRGBO(252, 253, 254, 0.70),
    markdownCodeBlock: _bluish50,
    markdownCodeBlockBanner: _bluish50,
    markdownInlineCode: _neutral50,
    markdownCitation: _bluish100,
    markdownPlaceholder: _bluish60,
    markdownTag: _bluish75,
    fileDiffAddedBg: Color(0xFFE6F4E7),
    fileDiffAddedGutter: Color(0xFFEDF7ED),
    fileDiffAddedMarker: Color(0xFF01A241),
    fileDiffDeletedBg: Color(0xFFFCE6E2),
    fileDiffDeletedGutter: Color(0xFFFDECE9),
    fileDiffDeletedMarker: Color(0xFFBA2723),
    toastBg: _bluish800,
    toastLabel: _bluish00,
    tooltipBg: _bluish850,
    switchThumb: _bluish00,
    scrollbarBgL1: _neutral200,
    scrollbarBgL2: _neutral200,
  );

  /// The `body[data-ds-dark-theme]` binding.
  static const DshAliases dark = DshAliases(
    isDark: true,
    bgBase: _bluish950,
    bgLayer1: _bluish875,
    bgLayer2: _bluish850,
    bgLayer3: _bluish800,
    bgOverlay: _bluish700,
    bgMask1: Color.fromRGBO(0, 0, 0, 0.50),
    bgMask2: Color.fromRGBO(0, 0, 0, 0.20),
    labelPrimary: _bluish50,
    labelSecondary: _bluish300,
    labelTertiary: _bluish400,
    labelCaption: _bluish600,
    labelDimmed: _bluish750,
    labelPrimaryDimmed: _bluish100,
    labelShimmer: Color.fromRGBO(255, 255, 255, 0.45),
    link: _deepseek400,
    menuIcon: _bluish100,
    brandText: _bluish50,
    borderL1: Color.fromRGBO(255, 255, 255, 0.06),
    borderL2: Color.fromRGBO(255, 255, 255, 0.12),
    borderL3: Color.fromRGBO(255, 255, 255, 0.16),
    borderL4: Color.fromRGBO(255, 255, 255, 0.20),
    borderInverted2: Color.fromRGBO(255, 255, 255, 0.08),
    brandPrimary: _bluish50,
    buttonPrimaryFill: _bluish50,
    buttonInfoFill: _deepseek400,
    buttonInfoHover: _deepseek500,
    buttonElevatedFill: _bluish750,
    buttonFloatingFill: _bluish850,
    buttonFloatingHover: _bluish800,
    buttonContrastFill: _bluish50,
    buttonGhostActiveFill: _bluish750,
    stateBusinessPrimary: _deepseek400,
    stateBusinessTertiary: _deepseek800,
    stateSuccessPrimary: _green500,
    stateSuccessSecondary: _green400,
    stateSuccessTertiary: _green900,
    stateWarnPrimary: _amber500,
    stateWarnSecondary: _amber400,
    stateWarnTertiary: _amber900,
    stateWarnLabel: _amber600,
    stateErrorPrimary: _red400,
    stateErrorSecondary: _red400,
    stateDonePrimary: _violet400,
    stateIdlePrimary: _neutral600,
    interactiveBgHover: Color.fromRGBO(255, 255, 255, 0.08),
    interactiveBgActive: Color.fromRGBO(255, 255, 255, 0.14),
    interactiveBgHoverAccent: Color.fromRGBO(255, 255, 255, 0.24),
    interactiveBgHoverDanger: Color.fromRGBO(242, 90, 90, 0.15),
    interactiveBgHoverSolid: _bluish800,
    specificBubble: _bluish850,
    specificBubbleHighlight: _bluish750,
    specificInputMajor: _bluish850,
    specificLoginInput: _bluish900,
    specificSelector: _bluish800,
    specificSidebarFill: _bluish900,
    specificSidebarNavItemActive: _bluish750,
    menuSurfaceFill: Color.fromRGBO(48, 49, 54, 0.64),
    markdownCodeBlock: _bluish900,
    markdownCodeBlockBanner: _bluish850,
    markdownInlineCode: _neutral800,
    markdownCitation: _bluish800,
    markdownPlaceholder: _bluish850,
    markdownTag: _bluish850,
    fileDiffAddedBg: Color(0xFF1F3124),
    fileDiffAddedGutter: Color(0xFF132016),
    fileDiffAddedMarker: Color(0xFF41C977),
    fileDiffDeletedBg: Color(0xFF3C1F1B),
    fileDiffDeletedGutter: Color(0xFF28130E),
    fileDiffDeletedMarker: Color(0xFFFA423E),
    toastBg: _bluish750,
    toastLabel: _bluish00,
    tooltipBg: _bluish750,
    switchThumb: _bluish400,
    scrollbarBgL1: _neutral700,
    scrollbarBgL2: _neutral600,
  );
}

/// The reference's radius scale (`base.css:16-21`), by its own names. A chat
/// surface reads the step the pin gives it rather than a Material corner:
/// `--dsw-radius-sm` on a call row and a code fence
/// (`ChatView.module.css:104`, `:208`), `--dsw-radius-md` on the
/// context-injection card (`ContextInjectionRow.module.css:59`),
/// `--dsw-radius-lg` on the tool and command bodies
/// (`ToolRow.module.css:184-187`, `GenericCommandCard.module.css:44`),
/// `--dsw-radius-xl` on the bubble, the trigger notice and the question card
/// (`MessageItem.module.css:28`, `TurnTriggerNodeView.module.css:4`), and
/// `--dsw-radius-panel` on a full panel.
const double kRadiusXs = 4;
const double kRadiusSm = 8;
const double kRadiusMd = 12;
const double kRadiusLg = 16;
const double kRadiusXl = 20;
const double kRadiusPanel = 28;

/// The app's pre-refactor names for the same steps, kept while the rows migrate
/// onto the [kRadiusPanel]/[kRadiusXl]/[kRadiusSm]/[kRadiusMd] scale: each is
/// the reference step it was standing in for, so the two names cannot drift.
/// [kShapeBubble] keeps its own name because the pin gives the reader's bubble
/// `--dsw-radius-xl` by name (`MessageItem.module.css` `.bubble`, :28).
///
/// `verify_theme_native` rejects a numeric radius at every other call site, so
/// a new surface takes a name from this file, never a literal.
const double kShapeSheet = kRadiusPanel;
const double kShapeDock = kRadiusXl;
const double kShapeBubble = kRadiusXl;
const double kShapeChip = kRadiusSm;
const double kShapeMenuSheet = kRadiusMd;

/// The app's in-page card corner, 14. The reference's scale carries no 14 step
/// — the nearest are `md` 12 and `lg` 16 — so this is the one radius the chat
/// refactor has to place on a pin step; it stays a literal until its consumers
/// move.
const double kShapeCard = 14;

/// The stadium step: a full pill. Error and status badges read as pills,
/// not as the rounded rectangles `kShapeChip` draws, and Material 3
/// carries a pill as its own badge form. The value exceeds half the
/// tallest badge, so every height resolves to a stadium.
const double kShapePill = 999;

/// Height ceiling for the menu-surface sheet card: a long picker scrolls
/// inside the sheet instead of covering the transcript behind it.
const double kMenuSheetMaxHeight = 520;

/// Width of the session sidebar in each state, shared by the two-pane
/// chat screen and the panel's rail geometry. The rail is the web shell's
/// closed-sidebar width — `SIDEBAR_COLLAPSED` in
/// `reference/deepseek-harness/packages/client/ui-layout/src/client/columns.ts`
/// (a 24px icon column between 16px paddings, the same 56 the Material 3
/// NavigationRail spec carries) — and the wide value is this app's fixed
/// sidebar for both the two-pane pane and the compact drawer (the web
/// sidebar is drag-resizable between 264 and 420 with a 280 default; a
/// phone client fixes one width).
const double kRailWidth = 56;
const double kSidebarWidth = 320;

/// Gap between the sidebar rail's stacked icon controls: the web rail's
/// control rhythm (`margin-bottom: 12px` on the rail controls in
/// `WorkspaceBrowser.module.css`).
const double kRailControlGap = 12;

/// The transcript's vertical rhythm between rows — the reference's
/// `--dsh-chat-flow-gap` (`ChatView.module.css:70-95`). Process steps sit
/// `6px` apart (the property's `6px` fallback, :71); a message/response block
/// is separated from its neighbours by `12px`
/// (`.flowItem[data-chat-group-part="response"]`, :76); a Turn's process header
/// opens its own block with `16px` clearance (:93).
const double kChatFlowGapStep = 6;
const double kChatFlowGap = 12;
const double kChatFlowGapAfterTurnHeader = 16;

/// The transcript's end fade: a scroll region ramps its content out over this
/// many pixels on an edge that still has content behind it — the reference's
/// `fadeTop`/`fadeBottom` 24px mask (`ChatGroupSeat.module.css:102-110`, and
/// the same rule in `TurnNavigator.module.css:61-63`).
const double kEdgeFade = 24;

/// The streaming reasoning summary's right-edge fade: the reference dissolves
/// the summary's last 48px while the thought streams
/// (`ReasoningRow.module.css:60`). It is wider than [kEdgeFade] because it
/// closes a line of moving text, not a scroll region.
const double kReasoningSummaryFade = 48;

/// The reference's content-size axis (`gradient-shadow-text.css:57-59`): a chat
/// row is composed from a base content size and its delta, not from a fixed
/// table. The app ships no font-size preference, so the axis resolves at the
/// pin's own default of 14 logical pixels and a reader's larger text rides
/// `MediaQuery.textScaler` instead. Secondary text is the pin's
/// `--dsh-content-font-size-secondary`, `min(size - 1, max(13, size - 2))`,
/// which is 13 at the default.
const double kContentFontSize = 14;
const double kContentFontSizeSecondary = 13;

/// One step of the reference's `--dsw-font-*` scale
/// (`gradient-shadow-text.css:181-271`): the absolute size the pin states, the
/// weight it states with it (its Figma 510 always renders as 500), and the
/// absolute line height that belongs to it.
final class DshFontStep {
  const DshFontStep(this.size, this.weight, this.lineHeight);

  /// The pin's `*-font-size`, in logical pixels.
  final double size;

  /// The pin's `*-font-weight`.
  final FontWeight weight;

  /// The pin's `*-line-height`, in logical pixels.
  final double lineHeight;

  /// The step as a [TextStyle]. [color] null leaves the ambient tone in place;
  /// `height` is the pin's absolute line height over its size, which is how
  /// Flutter carries an absolute line box.
  TextStyle style({Color? color}) => TextStyle(
    fontSize: size,
    fontWeight: weight,
    height: lineHeight / size,
    color: color,
  );
}

/// The reference's type steps by their own names
/// (`gradient-shadow-text.css:181-271`), so a row can be read against the pin
/// line by line: `base-16` 400 16/24 (:204-206), `s-14` 400 14/22 (:218-220),
/// `xs-13` 400 13/20 (:232-234), `xxs-12` 400 12/18 (:246-248), and each strong
/// variant one weight step up. `m-18` is named for its Figma step but measures
/// 16 (:197-199), which is what the pin ships.
abstract final class DshType {
  static const DshFontStep xl24 = DshFontStep(24, FontWeight.w600, 32);
  static const DshFontStep l20 = DshFontStep(20, FontWeight.w500, 28);
  static const DshFontStep m18 = DshFontStep(16, FontWeight.w500, 28);
  static const DshFontStep base16 = DshFontStep(16, FontWeight.w400, 24);
  static const DshFontStep baseStrong16 = DshFontStep(16, FontWeight.w500, 24);
  static const DshFontStep s14 = DshFontStep(14, FontWeight.w400, 22);
  static const DshFontStep sStrong14 = DshFontStep(14, FontWeight.w500, 22);
  static const DshFontStep xs13 = DshFontStep(13, FontWeight.w400, 20);
  static const DshFontStep xsStrong13 = DshFontStep(13, FontWeight.w500, 20);
  static const DshFontStep xxs12 = DshFontStep(12, FontWeight.w400, 18);
  static const DshFontStep xxsStrong12 = DshFontStep(12, FontWeight.w500, 18);
  static const DshFontStep xxxs11 = DshFontStep(11, FontWeight.w400, 14);
  static const DshFontStep xxxsStrong11 = DshFontStep(11, FontWeight.w500, 14);

  /// The markdown tier the transcript body reads
  /// (`gradient-shadow-text.css:60-178`): base 14/24 (:91-93), strong 600 14/24
  /// (:98-100), the four headings (:63-86), the table pair 13/22 (:119-128),
  /// small 12/20 (:133-142), inline code 12/19 (:161-163), the fence 11/19
  /// (:168-170) and the compact fence 11/16 (:176-178).
  static const DshFontStep markdownH1 = DshFontStep(21, FontWeight.w700, 30);
  static const DshFontStep markdownH2 = DshFontStep(19, FontWeight.w700, 28);
  static const DshFontStep markdownH3 = DshFontStep(18, FontWeight.w700, 26);
  static const DshFontStep markdownH4 = DshFontStep(14, FontWeight.w600, 24);
  static const DshFontStep markdownBase = DshFontStep(14, FontWeight.w400, 24);
  static const DshFontStep markdownBaseStrong = DshFontStep(
    14,
    FontWeight.w600,
    24,
  );
  static const DshFontStep markdownTable = DshFontStep(13, FontWeight.w400, 22);
  static const DshFontStep markdownTableHead = DshFontStep(
    13,
    FontWeight.w500,
    22,
  );
  static const DshFontStep markdownSmall = DshFontStep(12, FontWeight.w400, 20);
  static const DshFontStep markdownSmallStrong = DshFontStep(
    12,
    FontWeight.w600,
    20,
  );
  static const DshFontStep markdownCode = DshFontStep(12, FontWeight.w400, 19);
  static const DshFontStep markdownCodeBlock = DshFontStep(
    11,
    FontWeight.w400,
    19,
  );
  static const DshFontStep markdownCodeBlockSmall = DshFontStep(
    11,
    FontWeight.w400,
    16,
  );

  /// The chat's own composition of the content axis at the default 14px: a
  /// disclosure row's title is the secondary size on the body line
  /// (`DisclosureRow.module.css:85-90`, 13/24), its summary the secondary size
  /// on the summary line (`ReasoningRow.module.css` `.summary`, :53-59 → 13/20,
  /// which is [xs13]), and the running line two steps under the body
  /// (`ChatView.module.css:122-123`, 12/22).
  static const DshFontStep chatRowTitle = DshFontStep(13, FontWeight.w400, 24);
  static const DshFontStep chatRowSummary = xs13;
  static const DshFontStep chatRunningLabel = DshFontStep(
    12,
    FontWeight.w400,
    22,
  );
}

/// The UI family stack, ported from the reference's `--dsw-font-family`
/// (`base.css:7-8`):
/// `-apple-system, BlinkMacSystemFont, 'Segoe UI', 'PingFang SC',
/// 'Hiragino Sans GB', 'Microsoft YaHei', 'Helvetica Neue', Helvetica, Arial,
/// sans-serif`.
///
/// The pin states **one** stack for both scripts: the Latin faces come first and
/// the Han faces sit inside the same list, so the engine resolves each glyph
/// against one declared chain — Latin from the first family that has it, Han
/// from the Han family behind it. Our app used to declare no family at all, so
/// both scripts came from whatever the platform defaulted to and nothing
/// recorded which pair that was; this names it.
///
/// Android ships none of the pin's Latin faces; `Roboto` is the one it ships for
/// Latin, and the Han families behind it are the Noto/Source Han family the pin
/// itself pairs with a platform sans on every platform it names. The pair is
/// metric-led, from the faces themselves: cap height 0.711 em and x-height
/// 0.528 em for Roboto Regular against 0.733 em / 0.543 em for Noto Sans SC —
/// within 3% on both axes, both low-contrast humanist/grotesque designs at
/// weight class 400, so a mixed paragraph keeps one colour and one optical size.
/// A face that is not on the device is a request the platform may refuse; that
/// trade, and the bundled-face alternative, are recorded in the decision note.
const String kUiFontFamily = 'Roboto';
const List<String> kUiFontFamilyFallback = <String>[
  // Android's Han faces, in the order the platform ships them. A device that
  // names none of them falls back to its own Han default, which is what every
  // build did before this list existed.
  'Noto Sans CJK SC',
  'Noto Sans SC',
  'Source Han Sans SC',
  // The pin's own last resort, and Android's generic sans.
  'sans-serif',
];

/// The reference's code face (`base.css:10`):
/// `'SF Mono', 'JetBrains Mono', 'Fira Code', Consolas, 'Liberation Mono',
/// Menlo, Courier, 'PingFang SC', 'Microsoft YaHei'`.
///
/// No face in that stack ships with the app and `pubspec.yaml` bundles none, so
/// the names are a request the platform resolves, not a guarantee — and an
/// unresolvable `fontFamily` is **not** walked into [kCodeFontFamilyFallback]:
/// the run falls to the platform's *proportional* default instead, which is how
/// inline code stopped reading as code. The primary is therefore `monospace`,
/// the one mono family Android resolves by name. Measured on the test engine:
/// primary `'SF Mono'` with `['Roboto Mono', 'monospace']` behind it paints one
/// solid box, while primary `'monospace'` paints real mono glyphs.
///
/// The tail is consequently a *glyph-coverage* list, not a preference list: the
/// engine consults it only for glyphs the resolved family lacks. That is what
/// the Han names are for — a path, flag or identifier can carry a Han character,
/// and Android's are the Noto names the UI chain already declares, so a code run
/// mixes scripts at the code step instead of falling through to tofu. The pin's
/// own faces stay listed as the record of its stack; the pin omits a bare
/// `monospace` tail (its comment: a bare `monospace` tail makes Windows CJK
/// fall back to SimSun), and this app pays that trade for a code face that
/// resolves on its only shipping platform.
const String kCodeFontFamily = 'monospace';
const List<String> kCodeFontFamilyFallback = <String>[
  // The pin's stack, retained as the record of it (`base.css:10`).
  'SF Mono',
  'JetBrains Mono',
  'Fira Code',
  'Consolas',
  'Liberation Mono',
  'Menlo',
  'Courier',
  // The pin's Han faces, then Android's, for glyphs the mono face lacks.
  'PingFang SC',
  'Microsoft YaHei',
  'Noto Sans CJK SC',
  'Noto Sans SC',
  'Source Han Sans SC',
];

/// Global unified motion design tokens: durations, easing curves, and
/// accessibility helpers for all animations across the app.
///
/// The reference publishes three durations and one curve for its whole UI
/// (`base.css:12-15`); the app's older `duration*` names are the same values and
/// now alias them, so a chat row can read the token the pin names.
abstract final class DshMotion {
  /// The reference's `--ds-transition-duration-fast` (`base.css:14`): the
  /// cross-fade a row's colour rides.
  static const Duration transitionFast = Duration(milliseconds: 100);

  /// The reference's `--ds-transition-duration` (`base.css:13`).
  static const Duration transitionBase = Duration(milliseconds: 200);

  /// The reference's `--ds-transition-duration-slow` (`base.css:15`).
  static const Duration transitionSlow = Duration(milliseconds: 300);

  /// 100ms: micro-interactions (icon rotation, state-dot morph, splash, fade).
  static const Duration durationMicro = transitionFast;

  /// 200ms: small components and controls (buttons, tooltips, badges, chips).
  static const Duration durationShort = transitionBase;

  /// 300ms: medium containers and disclosures (toasts, sheets, accordions, FABs).
  static const Duration durationMedium = transitionSlow;

  /// 450ms: full-page route transitions and large surface changes. The app's
  /// own step: the reference carries no 450.
  static const Duration durationLong = Duration(milliseconds: 450);

  /// The reference's `--ds-ease-in-out` (`base.css:12`),
  /// `cubic-bezier(0.4, 0, 0.2, 1)` — the curve every `transition` in its
  /// component CSS rides.
  static const Curve easeInOut = Curves.fastOutSlowIn;

  /// Material 3 emphasized easing: for expressive entry and container transforms.
  static const Curve curveEmphasized = Curves.easeInOutCubicEmphasized;

  /// Decelerate entry curve: elements entering the viewport calmly settle in place.
  static const Curve curveEnter = Curves.easeOutCubic;

  /// Accelerate exit curve: elements exiting the viewport depart crisply.
  static const Curve curveExit = Curves.easeInCubic;

  /// Standard easing: in-viewport translation, scaling, and property morphing.
  static const Curve curveStandard = Curves.easeInOutCubic;

  /// Tactile spring-like curve: for button press release and bounce feedback.
  static const Curve curveSpring = Curves.easeOutBack;

  /// Whether reduced-motion accessibility mode is active on the host device.
  static bool isReducedMotion(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context);
}

/// The reference's elevation family: a half-pixel stroke plus one or two very
/// soft black layers (`gradient-shadow-text.css:12-39`).
///
/// Material 3's [kM3ShadowElevation1]/[kM3ShadowElevation3] are opaque black
/// shadows with no stroke; a surface drawn with them reads heavier than the
/// pin's, which separates a floating surface with a hairline and lifts it with
/// almost no shadow. The pin declares the values per element, so a component may
/// rebind the stroke colour — [menuStrokeColor] is the one rebind it ships
/// (`:24`).
abstract final class DshElevation {
  /// The default stroke colour, `--dsw-elevation-stroke-color` bound to
  /// `--dsw-alias-border-l4` (`gradient-shadow-text.css:17`).
  static Color strokeColor(ColorScheme scheme) => scheme.borderL4;

  /// The menu material's stroke colour, rebound to `--dsw-alias-border-l3`
  /// (`gradient-shadow-text.css:24`).
  static Color menuStrokeColor(ColorScheme scheme) => scheme.borderL3;

  /// `--dsw-elevation-stroke` (`:33`): `0 0 0 0.5px <stroke>` — a half-pixel
  /// ring drawn inside `box-shadow`, so the surface keeps `border: 0` and the
  /// ring costs no layout.
  static List<BoxShadow> strokeRing(Color stroke) => <BoxShadow>[
    BoxShadow(color: stroke, spreadRadius: 0.5),
  ];

  /// `--dsw-elevation-panel` (`:34-35`): the stroke, `0 3px 8px rgba(0,0,0,.03)`
  /// and `0 0 16px rgba(0,0,0,.02)`. [stroke] overrides the ring colour for a
  /// surface that rebinds it, as the menu material does.
  static List<BoxShadow> panel(ColorScheme scheme, {Color? stroke}) =>
      <BoxShadow>[
        ...strokeRing(stroke ?? strokeColor(scheme)),
        BoxShadow(
          offset: const Offset(0, 3),
          blurRadius: 8,
          color: _shadowBlack(0.03),
        ),
        BoxShadow(blurRadius: 16, color: _shadowBlack(0.02)),
      ];

  /// `--dsw-elevation-prominent` (`:36-37`): the stroke,
  /// `0 3px 8px rgba(0,0,0,.04)` and `0 0 20px rgba(0,0,0,.05)`.
  static List<BoxShadow> prominent(ColorScheme scheme, {Color? stroke}) =>
      <BoxShadow>[
        ...strokeRing(stroke ?? strokeColor(scheme)),
        BoxShadow(
          offset: const Offset(0, 3),
          blurRadius: 8,
          color: _shadowBlack(0.04),
        ),
        BoxShadow(blurRadius: 20, color: _shadowBlack(0.05)),
      ];

  /// `--dsw-elevation-soft` (`:38-39`): the stroke,
  /// `0 4px 16px rgba(0,0,0,.03)` and `0 0 24px rgba(0,0,0,.03)` — the input
  /// field's wider, fainter lift.
  static List<BoxShadow> soft(ColorScheme scheme, {Color? stroke}) =>
      <BoxShadow>[
        ...strokeRing(stroke ?? strokeColor(scheme)),
        BoxShadow(
          offset: const Offset(0, 4),
          blurRadius: 16,
          color: _shadowBlack(0.03),
        ),
        BoxShadow(blurRadius: 24, color: _shadowBlack(0.03)),
      ];
}

/// `rgba(0, 0, 0, alpha)` as the pin writes its elevation layers.
Color _shadowBlack(double alpha) =>
    Color.from(alpha: alpha, red: 0, green: 0, blue: 0);

/// The reference's `--dsw-menu-backdrop-filter` (`gradient-shadow-text.css:20`):
/// `blur(40px) saturate(150%)`, worn by every floating surface it draws. It is
/// why [DshSchemeColors.menuSurfaceFill] is 70% / 64% alpha — the fill has a
/// blurred, saturated page behind it, and on its own it reads as a flat
/// translucent panel.
const double kMenuBackdropSigma = 40;

/// The saturation half of [kMenuBackdropSigma]'s filter.
const double kMenuBackdropSaturation = 1.5;

/// The luminance weights the saturation matrix is built from, the sRGB
/// constants CSS's `saturate()` uses.
const double _saturationLr = 0.213;
const double _saturationLg = 0.715;
const double _saturationLb = 0.072;
const double _saturationSr = (1 - kMenuBackdropSaturation) * _saturationLr;
const double _saturationSg = (1 - kMenuBackdropSaturation) * _saturationLg;
const double _saturationSb = (1 - kMenuBackdropSaturation) * _saturationLb;

/// The saturation half of the menu backdrop as a colour matrix: `s + (1 - s)`
/// of each luminance weight on the diagonal, `(1 - s)` of it off the diagonal,
/// so a fully desaturated pixel takes the luminance and the identity survives at
/// `s = 1`.
const List<double> kMenuBackdropSaturationMatrix = <double>[
  _saturationSr + kMenuBackdropSaturation,
  _saturationSg,
  _saturationSb,
  0,
  0, //
  _saturationSr,
  _saturationSg + kMenuBackdropSaturation,
  _saturationSb,
  0,
  0, //
  _saturationSr,
  _saturationSg,
  _saturationSb + kMenuBackdropSaturation,
  0,
  0, //
  0, 0, 0, 1, 0, //
];

/// The blur half of the menu backdrop, the Flutter form of `blur(40px)`.
ImageFilter menuBackdropBlur() =>
    ImageFilter.blur(sigmaX: kMenuBackdropSigma, sigmaY: kMenuBackdropSigma);

/// The saturation half of the menu backdrop, the Flutter form of
/// `saturate(150%)`.
ColorFilter menuBackdropSaturation() =>
    const ColorFilter.matrix(kMenuBackdropSaturationMatrix);

/// The whole menu backdrop filter: `blur(40px) saturate(150%)`, saturated after
/// the blur, which is the order the CSS filter list applies.
ImageFilter menuBackdropFilter() => ImageFilter.compose(
  outer: menuBackdropSaturation(),
  inner: menuBackdropBlur(),
);

class DshTheme {
  const DshTheme._();

  /// The light scheme, assembled from the pin's `body` alias binding.
  static ThemeData light() => _build(Brightness.light);

  /// The dark scheme, assembled from the pin's
  /// `body[data-ds-dark-theme]` alias binding.
  static ThemeData dark() => _build(Brightness.dark);

  /// The optional OLED appearance: the pin's dark aliases on a pure-black
  /// page.
  ///
  /// Only the surface family moves — `surface` (the page and the transcript)
  /// becomes true black, so an OLED panel lights no pixel behind the content
  /// the reader spends the session in, and the container family steps up
  /// from it in near-black tones:
  ///
  /// | role | OLED | standard dark |
  /// |---|---|---|
  /// | `surface` | `#000000` | `#151517` |
  /// | `surfaceContainerLow` | `#0F0F13` | `#1B1B1C` |
  /// | `surfaceContainer` | `#15151B` | `#232324` |
  /// | `surfaceContainerHigh` | `#232329` | `#2C2C2E` |
  /// | `surfaceContainerHighest` | `#2F2F36` | `#353638` |
  ///
  /// The page-to-chrome step is 1.155:1; the standard dark scheme's is
  /// 1.161:1. Both clear 1.15:1, so the two-tone rule survives pure black.
  /// What pure black does not carry is a shadow: elevation shadows are black
  /// on black. They are not what separates chrome here — the container ladder
  /// is, and the `outlineVariant` hairline reads 1.27:1 composited on the
  /// pure-black page where it reads 1.40:1 on the dark grey.
  ///
  /// Every ink role keeps its dark alias value. Measured against `#000000`:
  /// `onSurface` 20.10, `onSurfaceVariant` 13.94, `primary` 9.02,
  /// `error` 6.39, `warning` 10.98, `success` 10.44, `syntaxKeyword` 8.79,
  /// `syntaxString` 10.44, `syntaxNumber` 12.13 — all clear 4.5:1 with room.
  static ThemeData oled() => _build(Brightness.dark, oled: true);

  static ThemeData _build(Brightness brightness, {bool oled = false}) {
    final aliases = brightness == Brightness.light
        ? DshAliases.light
        : DshAliases.dark;
    final isLight = brightness == Brightness.light;
    final ColorScheme assembled = ColorScheme(
      brightness: brightness,
      // The page and its container ladder. The pin names `bg-base` and the
      // three layer tones; Material's five-step container family is mapped
      // onto the pin's neutral-bluish steps.
      surface: aliases.bgBase,
      surfaceDim: isLight ? _bluish60 : const Color(0xFF111113),
      surfaceBright: isLight ? _bluish00 : _bluish900,
      surfaceContainerLowest: isLight ? _bluish00 : _bluish1000,
      surfaceContainerLow: isLight ? _bluish50 : _bluish900,
      surfaceContainer: isLight ? _bluish60 : _bluish875,
      surfaceContainerHigh: isLight ? _bluish75 : _bluish850,
      surfaceContainerHighest: isLight ? _bluish150 : _bluish800,
      // Ink.
      onSurface: aliases.labelPrimary,
      onSurfaceVariant: aliases.labelSecondary,
      // Accent and its container.
      primary: aliases.buttonInfoFill,
      onPrimary: isLight ? _bluish00 : _bluish1000,
      primaryContainer: aliases.stateBusinessTertiary,
      onPrimaryContainer: isLight ? _blue900 : _bluish50,
      secondary: aliases.buttonInfoFill,
      onSecondary: isLight ? _bluish00 : _bluish1000,
      secondaryContainer: aliases.specificBubble,
      onSecondaryContainer: aliases.labelPrimary,
      tertiary: aliases.stateDonePrimary,
      onTertiary: isLight ? _bluish00 : _bluish1000,
      // Failure.
      error: aliases.stateErrorPrimary,
      onError: isLight ? _bluish00 : _bluish1000,
      errorContainer: isLight ? _red50 : _red900,
      onErrorContainer: isLight ? _red900 : _bluish50,
      // Separators.
      outline: aliases.borderL4,
      outlineVariant: aliases.borderL2,
      // Modal and inverse surfaces.
      shadow: const Color(0xFF000000),
      scrim: aliases.bgMask1,
      inverseSurface: aliases.toastBg,
      onInverseSurface: aliases.toastLabel,
      // Material 3 has no inverse-primary alias. deepseek-200 (:23) is the
      // pin's accent tint and clears 4.5:1 on both toast surfaces.
      inversePrimary: _deepseek200,
      surfaceTint: Colors.transparent,
    );
    final scheme = oled ? _oledSurfaceFamily(assembled) : assembled;
    final base = ThemeData(colorScheme: scheme);
    return base.copyWith(
      // The pin's `bg-base`; on the OLED appearance `surface` is true black,
      // which is the page that appearance wants.
      scaffoldBackgroundColor: scheme.surface,
      // Android ripple feel (no-op on iOS).
      splashFactory: InkSparkle.splashFactory,
      textTheme: _typography(base.textTheme),
      // The same chain on the primary theme: an AppBar title is the one text a
      // reader sees without a `TextTheme` role of its own, and a family left
      // null there would resolve both scripts by platform default again.
      primaryTextTheme: base.primaryTextTheme.apply(
        fontFamily: kUiFontFamily,
        fontFamilyFallback: kUiFontFamilyFallback,
      ),
      // Chrome and content sit on different tones: the transcript keeps the
      // page, while every frame around it — bar, dock, drawer — shares the
      // pin's sidebar fill. The reader never needs a rule to see where the
      // page stops.
      appBarTheme: AppBarTheme(
        backgroundColor: aliases.specificSidebarFill,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        centerTitle: false,
        titleSpacing: 4,
      ),
      dividerTheme: DividerThemeData(
        color: aliases.borderL2,
        thickness: 1,
        space: 1,
      ),
      // Material's `PopupMenuRoute` takes a single elevation and no backdrop
      // hook, so it cannot carry the pin's `--dsw-elevation-prominent` (a
      // stroke plus two soft layers, `Menu.module.css:16-18`) or the menu
      // blur. What it can carry is the material: the fill over the page
      // ([DshSchemeColors.menuSurfaceOpaque], since a route that cannot blur
      // cannot use the translucent fill), the `border-l1` hairline the menu
      // rebinds its elevation stroke to (`Menu.module.css:17`) through the
      // shape's side, the pin's `--dsw-radius-lg` menu corner
      // (`MenuSurface.module.css:3-5`), and no Material shadow at all —
      // `elevation: 0` with a transparent `shadowColor`, so nothing stacks
      // under a surface that has none. A menu that needs the three layers goes
      // through `showMenuSheet`, which draws them.
      popupMenuTheme: PopupMenuThemeData(
        elevation: 0,
        shadowColor: Colors.transparent,
        color: scheme.menuSurfaceOpaque,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(kRadiusLg),
          side: BorderSide(color: scheme.borderL1, width: 0.5),
        ),
      ),
      // The Material 3 menu family (`MenuAnchor`) reads `MenuStyle`, not
      // `PopupMenuThemeData`, and shares the popup's limit: a single elevation
      // and no backdrop hook. This is the same partial material for a call site
      // that does not pass its own `style:` — a call site that does (the
      // context ring, `context_ring.dart`) still wins, and only the house
      // sheet carries the blur and the soft layers.
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll<Color>(
            scheme.menuSurfaceOpaque,
          ),
          elevation: const WidgetStatePropertyAll<double>(0),
          shadowColor: const WidgetStatePropertyAll<Color>(Colors.transparent),
          surfaceTintColor: const WidgetStatePropertyAll<Color>(
            Colors.transparent,
          ),
          shape: WidgetStatePropertyAll<OutlinedBorder>(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(kRadiusLg),
              side: BorderSide(color: scheme.borderL1, width: 0.5),
            ),
          ),
        ),
      ),
      // A dialog and a sheet are raised surfaces: the pin's layer-2 fill, not
      // Material's tinted surface.
      dialogTheme: DialogThemeData(
        backgroundColor: aliases.bgLayer2,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(kShapeCard)),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: aliases.bgLayer2,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
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
      // Global Material 3 page transitions: smooth Zoom transitions on
      // Android and desktop, Cupertino slide on iOS/macOS.
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: ZoomPageTransitionsBuilder(
            allowSnapshotting: true,
          ),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.linux: ZoomPageTransitionsBuilder(
            allowSnapshotting: true,
          ),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: ZoomPageTransitionsBuilder(
            allowSnapshotting: true,
          ),
        },
      ),
      // All button styles share DshMotion.durationShort for tactile feedback.
      filledButtonTheme: const FilledButtonThemeData(
        style: ButtonStyle(animationDuration: DshMotion.durationShort),
      ),
      elevatedButtonTheme: const ElevatedButtonThemeData(
        style: ButtonStyle(animationDuration: DshMotion.durationShort),
      ),
      outlinedButtonTheme: const OutlinedButtonThemeData(
        style: ButtonStyle(animationDuration: DshMotion.durationShort),
      ),
      textButtonTheme: const TextButtonThemeData(
        style: ButtonStyle(animationDuration: DshMotion.durationShort),
      ),
      iconButtonTheme: const IconButtonThemeData(
        style: ButtonStyle(animationDuration: DshMotion.durationShort),
      ),
      // Accordion/Disclosure expansion animation style.
      expansionTileTheme: const ExpansionTileThemeData(
        expansionAnimationStyle: AnimationStyle(
          duration: DshMotion.durationMedium,
          curve: DshMotion.curveStandard,
          reverseCurve: DshMotion.curveExit,
        ),
      ),
      // A SnackBar is the pin's toast: its dark panel in both brightnesses,
      // with the toast's white ink. `inverseSurface`/`onInverseSurface` carry
      // the same aliases, so this only pins down what Material already
      // resolves for a floating snackbar.
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: aliases.toastBg,
        contentTextStyle: TextStyle(color: aliases.toastLabel),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(kShapeCard),
        ),
      ),
    );
  }

  /// The OLED surface family: the page at true black and the containers on
  /// a near-black ladder above it. Every other role keeps the dark alias
  /// value, so the ink palette and the [DshSchemeColors] dark branch are
  /// untouched. `surfaceContainerLowest` collapses onto the page — on a
  /// black page the least-emphasis container is the page.
  static ColorScheme _oledSurfaceFamily(ColorScheme base) => base.copyWith(
    surface: const Color(0xFF000000),
    surfaceDim: const Color(0xFF000000),
    surfaceBright: const Color(0xFF1A1A20),
    surfaceContainerLowest: const Color(0xFF000000),
    surfaceContainerLow: const Color(0xFF0F0F13),
    surfaceContainer: const Color(0xFF15151B),
    surfaceContainerHigh: const Color(0xFF232329),
    surfaceContainerHighest: const Color(0xFF2F2F36),
  );

  /// Reading-first scale, taken from the reference's own type sheet.
  ///
  /// The content tier is the reference's `--dsh-content-font-size`, 14px, on
  /// its body line of 24px (`gradient-shadow-text.css:89-92`); the secondary
  /// tier is 13px on a 20px line (`--dsw-font-xs-13`, :230-235). Titles wear
  /// the reference's one strong weight: its Figma 510 renders as 500
  /// (design-platform.css:1-3, `--dsw-font-s-strong-14-font-weight`, :225).
  static TextTheme _typography(TextTheme base) {
    // One chain for both scripts, before any per-style tweak: a style that
    // overrode the family would put its own script back on a second voice.
    final TextTheme themed = base.apply(
      fontFamily: kUiFontFamily,
      fontFamilyFallback: kUiFontFamilyFallback,
    );
    return themed.copyWith(
      titleLarge: themed.titleLarge?.copyWith(
        fontWeight: FontWeight.w500,
        letterSpacing: -0.2,
      ),
      titleMedium: themed.titleMedium?.copyWith(
        fontWeight: FontWeight.w500,
        letterSpacing: -0.1,
        height: 1.25,
      ),
      bodyLarge: themed.bodyLarge?.copyWith(height: 1.5),
      // The transcript's two reading steps are the reference's own markdown
      // base and its secondary size (`gradient-shadow-text.css:91-93`,
      // :232-234).
      bodyMedium: themed.bodyMedium?.copyWith(
        fontSize: DshType.markdownBase.size,
        height: DshType.markdownBase.lineHeight / DshType.markdownBase.size,
      ),
      bodySmall: themed.bodySmall?.copyWith(
        fontSize: DshType.xs13.size,
        height: DshType.xs13.lineHeight / DshType.xs13.size,
      ),
      labelLarge: themed.labelLarge?.copyWith(fontWeight: FontWeight.w500),
      labelSmall: themed.labelSmall?.copyWith(letterSpacing: 0.4),
    );
  }
}
