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
/// - colours: the [DshSchemeColors] extension on [ColorScheme], so a row reads
///   `scheme.labelTertiary` rather than `scheme.onSurfaceVariant`;
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
/// call site reads `scheme.success` rather than naming a green, and a new
/// entry is added here or argued down to an existing role.
extension DshSchemeColors on ColorScheme {
  /// Success green. M3 carries `error` but no success counterpart; the light
  /// value is a deep green for text contrast >= 4.5:1 on light surfaces,
  /// the dark one green 300 for legibility on dark surfaces.
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
  /// (design-platform.css:230/:322), worn by the warning state dot
  /// (StateDot.module.css:37-39). Like `success`, this rides the palette's
  /// contrast steps around that anchor: light takes deep amber-brown
  /// (#8D4F00) for text-level contrast >= 4.5:1 on a light surface; dark takes
  /// the brighter amber-400 (design-platform.css:6) for legibility on dark surfaces.
  Color get warning => brightness == Brightness.light
      ? const Color(0xFF8D4F00)
      : const Color(0xFFF7AD31);

  /// The running row's label tone — the reference's dedicated
  /// `--dsw-alias-label-deep-diving` alias (design-platform.css:215 light,
  /// :333 dark), which a running Turn's status text wears instead of any
  /// accent role.
  ///
  /// Each value is that alias's own `color-mix`: light is 70% of the palette's
  /// `--dsw-static-deepseek-500` (rgb(65, 118, 230), :28) over
  /// `--dsw-static-blue-950` (rgb(23, 37, 84), :21); dark is 55% of
  /// `--dsw-static-deepseek-450` (rgb(86, 134, 254), :27) over
  /// `--dsw-static-neutral-bluish-400` (rgb(173, 178, 184), :62). Both stops
  /// are opaque sRGB, so `color-mix(in srgb, A p%, B)` is the componentwise
  /// `p·A + (1 - p)·B` that [Color.lerp] computes as `lerp(B, A, p)`.
  Color get labelDeepDiving => brightness == Brightness.light
      ? Color.lerp(_blue950, _deepseek500, 0.70)!
      : Color.lerp(_bluish400, _deepseek450, 0.55)!;

  /// The running row's sweep highlight — the reference's
  /// `--dsw-alias-label-deep-diving-shimmer` (design-platform.css:216 light,
  /// :334 dark), mixed the same way: light is 30% `--dsw-static-deepseek-500`
  /// over `--dsw-static-blue-950`; dark is 65% `--dsw-static-blue-300`
  /// (rgb(147, 197, 253), :11) over `--dsw-static-deepseek-400`
  /// (rgb(122, 170, 255), :26).
  Color get labelDeepDivingShimmer => brightness == Brightness.light
      ? Color.lerp(_blue950, _deepseek500, 0.30)!
      : Color.lerp(_deepseek400, _blue300, 0.65)!;

  /// Code-token colours for fenced blocks ([code_highlight.dart] classifies
  /// them, the markdown renderer paints them). Material 3 carries no syntax
  /// roles, and these three have to stay apart from each other *and* from
  /// `onSurface`, which the rest of the code body keeps wearing.
  ///
  /// Every value holds >= 4.5:1 against the surface a code block actually
  /// sits on — `surfaceContainerHigh`, #E5E1EB light / #34343B dark /
  /// #232329 in the OLED appearance — not against the page. Measured
  /// keyword / string / number: 7.29 / 5.00 / 4.94 in light, 5.17 / 6.14 /
  /// 7.14 in dark, 6.54 / 7.77 / 9.03 on the OLED code surface.
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

  /// The reader's own message container — the reference's dedicated
  /// `--dsw-specific-bubble` alias (design-platform.css:268 light, :386 dark),
  /// which is `--dsw-static-deepseek-50` in light (rgb(237, 243, 254), :29)
  /// and `--dsw-static-neutral-bluish-850` in dark (rgb(44, 44, 46), :71).
  /// Both are opaque sRGB; the dark value is the same on the OLED appearance,
  /// which moves only the surface family.
  Color get bubble => brightness == Brightness.light ? _deepseek50 : _bluish850;

  // The reference's alias layer, by name.
  //
  // `design-platform.css` publishes these on `body` (light, :167-282) and
  // rebinds them on `body[data-ds-dark-theme]` (:285-398). Each alias is a
  // `var()` of one static palette step or a `color-mix` of two, so no value
  // here is derived from the M3 seed: the chat window is painted by the pin's
  // palette, and a Material role is only the fallback where the pin names none.
  // `color-mix(in srgb, A p%, B)` over two opaque stops is the componentwise
  // `p·A + (1 - p)·B` that [Color.lerp] computes as `lerp(B, A, p)`.

  /// `--dsw-alias-bg-base` (:167 / :285): the page behind the transcript —
  /// neutral-bluish-00 (:56) / neutral-bluish-950 (:74).
  Color get bgBase => brightness == Brightness.light ? _bluish00 : _bluish950;

  /// `--dsw-alias-bg-layer-1/2/3` (:171-173 / :289-291): the raised surfaces
  /// above the page. Light keeps all three on the page tone; dark steps them
  /// 875 (:72) → 850 (:71) → 800 (:70).
  Color get bgLayer1 => brightness == Brightness.light ? _bluish00 : _bluish875;
  Color get bgLayer2 => brightness == Brightness.light ? _bluish00 : _bluish850;
  Color get bgLayer3 => brightness == Brightness.light ? _bluish00 : _bluish800;

  /// `--dsw-alias-border-l1` (:185 / :303): the lightest hairline, worn by the
  /// transcript's rules and the running row's divider.
  Color get borderL1 => brightness == Brightness.light
      ? const Color.from(alpha: 0.04, red: 0, green: 0, blue: 0)
      : const Color.from(alpha: 0.06, red: 1, green: 1, blue: 1);

  /// `--dsw-alias-border-l2` (:187 / :305): the standard container stroke.
  Color get borderL2 => brightness == Brightness.light
      ? const Color.from(alpha: 0.10, red: 0, green: 0, blue: 0)
      : const Color.from(alpha: 0.12, red: 1, green: 1, blue: 1);

  /// `--dsw-alias-border-l3` (:188 / :306): the floating-button stroke.
  Color get borderL3 => brightness == Brightness.light
      ? const Color.from(alpha: 0.12, red: 0, green: 0, blue: 0)
      : const Color.from(alpha: 0.16, red: 1, green: 1, blue: 1);

  /// `--dsw-alias-border-l4` (:189 / :307): the heaviest hairline.
  Color get borderL4 => brightness == Brightness.light
      ? const Color.from(alpha: 0.16, red: 0, green: 0, blue: 0)
      : const Color.from(alpha: 0.20, red: 1, green: 1, blue: 1);

  /// The reference's `color-mix(in srgb, var(--dsw-alias-border-l1) 75%,
  /// var(--dsw-alias-border-l2))` — the running row's hairline
  /// (`ChatView.module.css` `.runningDivider`, :141).
  Color get runningDivider => Color.lerp(borderL2, borderL1, 0.75)!;

  /// `--dsw-alias-label-primary` (:222 / :340): the reading tone — bluish-1000
  /// (:57) / bluish-50 (:64).
  Color get labelPrimary =>
      brightness == Brightness.light ? _bluish1000 : _bluish50;

  /// `--dsw-alias-label-secondary` (:223 / :341): the hovered row tone —
  /// bluish-700 (:67) / bluish-300 (:61).
  Color get labelSecondary =>
      brightness == Brightness.light ? _bluish700 : _bluish300;

  /// `--dsw-alias-label-tertiary` (:225 / :343): the row tone at rest —
  /// bluish-600 (:65) / bluish-400 (:62).
  Color get labelTertiary =>
      brightness == Brightness.light ? _bluish600 : _bluish400;

  /// `--dsw-alias-label-caption` (:214 / :332): the smallest furniture tone,
  /// worn by a separator dot — bluish-400 (:62) / bluish-600 (:65).
  Color get labelCaption =>
      brightness == Brightness.light ? _bluish400 : _bluish600;

  /// `--dsw-alias-label-dimmed` (:217 / :335): the disabled tone — bluish-200
  /// (:60) / bluish-750 (:68).
  Color get labelDimmed =>
      brightness == Brightness.light ? _bluish200 : _bluish750;

  /// `--dsw-alias-label-primary-dimmed` (:219 / :337): the compaction notice's
  /// old tone, one step off primary — bluish-950 (:74) / bluish-100 (:58).
  Color get labelPrimaryDimmed =>
      brightness == Brightness.light ? _bluish950 : _bluish100;

  /// `--dsw-alias-label-shimmer` (:224 / :342): the platform's translucent
  /// neutral sweep — `color-mix(neutral-1000 30%, transparent)` light (:41),
  /// `color-mix(neutral-00 45%, transparent)` dark (:40).
  Color get labelShimmer => brightness == Brightness.light
      ? const Color.from(alpha: 0.30, red: 0, green: 0, blue: 0)
      : const Color.from(alpha: 0.45, red: 1, green: 1, blue: 1);

  /// `--dsw-alias-interactive-bg-hover` (:213 / :331): the row wash under the
  /// pointer — rgb(38, 49, 72) at 6% / white at 8%.
  Color get interactiveBgHover => brightness == Brightness.light
      ? const Color.from(
          alpha: 0.06,
          red: 38 / 255,
          green: 49 / 255,
          blue: 72 / 255,
        )
      : const Color.from(alpha: 0.08, red: 1, green: 1, blue: 1);

  /// `--dsw-alias-interactive-bg-active` (:209 / :327): the pressed wash.
  Color get interactiveBgActive => brightness == Brightness.light
      ? const Color.from(
          alpha: 0.10,
          red: 38 / 255,
          green: 49 / 255,
          blue: 72 / 255,
        )
      : const Color.from(alpha: 0.14, red: 1, green: 1, blue: 1);

  /// `--dsw-alias-interactive-bg-hover-solid` (:212 / :330): the opaque
  /// companion of [interactiveBgHover], for a surface that cannot show a wash —
  /// bluish-75 (:69) / bluish-800 (:70).
  Color get interactiveBgHoverSolid =>
      brightness == Brightness.light ? _bluish75 : _bluish800;

  /// `--dsw-alias-markdown-code-block` (:230 / :348): the code surface — the
  /// fence, the tool body, the command body — bluish-50 (:64) / bluish-900
  /// (:73).
  Color get markdownCodeBlock =>
      brightness == Brightness.light ? _bluish50 : _bluish900;

  /// `--dsw-alias-markdown-code-block-banner` (:229 / :347): the fence's
  /// header strip — bluish-50 (:64) / bluish-850 (:71).
  Color get markdownCodeBlockBanner =>
      brightness == Brightness.light ? _bluish50 : _bluish850;

  /// `--dsw-alias-markdown-inline-code` (:233 / :351): the inline-code chip —
  /// neutral-50 (:49) / neutral-800 (:53).
  Color get markdownInlineCode =>
      brightness == Brightness.light ? _neutral50 : _neutral800;

  /// `--dsw-alias-markdown-placeholder` (:234 / :352): the skeleton tone
  /// behind a streaming block — bluish-60 (:66) / bluish-850 (:71).
  Color get markdownPlaceholder =>
      brightness == Brightness.light ? _bluish60 : _bluish850;

  /// `--dsw-alias-markdown-tag` (:235 / :353): the citation/tag chip —
  /// bluish-75 (:69) / bluish-850 (:71).
  Color get markdownTag =>
      brightness == Brightness.light ? _bluish75 : _bluish850;

  /// `--dsw-alias-state-business-primary` (:240 / :358): the brand state mark
  /// — deepseek-500 (:28) / deepseek-400 (:26).
  Color get stateBusinessPrimary =>
      brightness == Brightness.light ? _deepseek500 : _deepseek400;

  /// `--dsw-alias-state-error-primary` (:250 / :368): the failure mark —
  /// red-600 (:80) / red-400 (:76).
  Color get stateErrorPrimary =>
      brightness == Brightness.light ? _red600 : _red400;

  /// `--dsw-alias-state-success-primary` (:253 / :371): the settled mark —
  /// green-500 (:36) in both brightnesses.
  Color get stateSuccessPrimary => _green500;

  /// `--dsw-alias-state-idle-primary` (:252 / :370): the queued mark —
  /// neutral-300 (:46) / neutral-600 (:51).
  Color get stateIdlePrimary =>
      brightness == Brightness.light ? _neutral300 : _neutral600;

  /// `--dsw-alias-state-warn-primary` (:257 / :375): the "waiting on you"
  /// mark — amber-500 (:7) in both brightnesses.
  Color get stateWarnPrimary => _amber500;

  /// `--dsw-alias-state-warn-label` (:256 / :374): the warn tone a *label*
  /// wears — amber-600 (:8) in both brightnesses.
  Color get stateWarnLabel => _amber600;

  /// `--dsw-alias-turn-trigger-bg` (:265 / :381): the trigger notice's fill —
  /// the code surface in light, the pointer wash in dark.
  Color get turnTriggerBg =>
      brightness == Brightness.light ? markdownCodeBlock : interactiveBgHover;

  /// `--dsw-alias-turn-trigger-bg-hover` (:266 / :382): its hovered fill — the
  /// pointer wash in light, the pressed wash in dark.
  Color get turnTriggerBgHover =>
      brightness == Brightness.light ? interactiveBgHover : interactiveBgActive;

  /// `--dsw-specific-bubble-highlight` (:267 / :385): the bubble's own accent,
  /// the selection/highlight inside the reader's message — deepseek-200 (:23) /
  /// bluish-750 (:68).
  Color get bubbleHighlight =>
      brightness == Brightness.light ? _deepseek200 : _bluish750;

  /// `--dsw-specific-input-major` (:269 / :387): the composer's field fill —
  /// the page in light, bluish-850 (:71) in dark.
  Color get inputSurface =>
      brightness == Brightness.light ? _bluish00 : _bluish850;

  /// `--dsw-menu-surface-fill` (:271 / :389), published as
  /// `--dsw-specific-menu` (:273 / :392): the translucent menu sheet —
  /// rgb(248, 249, 250) at 58% / rgb(67, 69, 74) at 45%.
  Color get menuSurfaceFill => brightness == Brightness.light
      ? const Color.from(
          alpha: 0.58,
          red: 248 / 255,
          green: 249 / 255,
          blue: 250 / 255,
        )
      : const Color.from(
          alpha: 0.45,
          red: 67 / 255,
          green: 69 / 255,
          blue: 74 / 255,
        );

  /// [menuSurfaceFill] over the page it would have blurred: the fill
  /// alpha-composited onto [bgBase].
  ///
  /// The pin only ever paints the fill over `--dsw-menu-backdrop-filter`
  /// (`MenuSurface.module.css:27`), so its 58% / 45% alpha assumes a blur behind
  /// it. A surface that cannot blur — Material's `PopupMenuRoute` takes no
  /// backdrop hook — wears this composite instead of a see-through panel.
  Color get menuSurfaceOpaque => Color.alphaBlend(menuSurfaceFill, bgBase);

  /// `--dsw-alias-button-floating-fill` (:196 / :314): the scroll-to-bottom
  /// pill's fill — the page in light, bluish-850 (:71) in dark.
  Color get buttonFloatingFill =>
      brightness == Brightness.light ? _bluish00 : _bluish850;

  /// `--dsw-alias-button-floating-hover` (:197 / :315): its hovered fill —
  /// bluish-75 (:69) / bluish-800 (:70).
  Color get buttonFloatingHover =>
      brightness == Brightness.light ? _bluish75 : _bluish800;
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

/// The design-platform static palette steps the alias layer reads
/// (`design-platform.css:5-82`). The names are the pin's own families: `bluish`
/// is its `neutral-bluish`, `neutral` its `neutral`, plus the brand ramps. They
/// stay private — the aliases on [DshSchemeColors] are their only consumers.
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
/// why [DshSchemeColors.menuSurfaceFill] is 58% / 45% alpha — the fill has a
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

  /// Light scheme seeded from the brand violet.
  static ThemeData light() => _build(Brightness.light);

  /// Dark scheme seeded from the brand violet.
  static ThemeData dark() => _build(Brightness.dark);

  /// The optional OLED appearance: the M3 dark roles on a pure-black page.
  ///
  /// Only the surface family moves — `surface` (the page and the transcript)
  /// becomes true black, so an OLED panel lights no pixel behind the content
  /// the reader spends the session in, and the container family steps up
  /// from it in near-black tones:
  ///
  /// | role | OLED | standard dark |
  /// |---|---|---|
  /// | `surface` | `#000000` | `#121318` |
  /// | `surfaceContainerLow` | `#0F0F13` | `#1B1B21` |
  /// | `surfaceContainer` | `#15151B` | `#1F1F25` |
  /// | `surfaceContainerHigh` | `#232329` | `#292A2F` |
  /// | `surfaceContainerHighest` | `#2F2F36` | `#34343A` |
  ///
  /// The page-to-chrome step is 1.155:1, at or above the dark scheme's
  /// 1.132:1, so the two-tone rule survives pure black. What pure black does
  /// not carry is a shadow: elevation shadows are black on black. They are
  /// not what separates chrome here — the container ladder is, and the
  /// `outlineVariant` hairlines the app already draws read 2.25:1 on the
  /// pure-black page where they read 1.99:1 on the dark grey.
  ///
  /// Every ink role keeps its M3 dark value. Measured against `#000000`:
  /// `onSurface` 16.21, `onSurfaceVariant` 12.30, `primary` 12.34,
  /// `error` 12.37, `warning` 10.98, `success` 10.44, `syntaxKeyword` 8.79,
  /// `syntaxString` 10.44, `syntaxNumber` 12.13 — all clear 4.5:1 with room.
  static ThemeData oled() => _build(Brightness.dark, oled: true);

  static ThemeData _build(Brightness brightness, {bool oled = false}) {
    final seeded = ColorScheme.fromSeed(
      seedColor: kDshBrandSeed,
      brightness: brightness,
    );
    final scheme = oled ? _oledSurfaceFamily(seeded) : seeded;
    final base = ThemeData(colorScheme: scheme);
    return base.copyWith(
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
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(kShapeCard),
        ),
      ),
    );
  }

  /// The OLED surface family: the page at true black and the containers on
  /// a near-black ladder above it. Every other role keeps the seeded dark
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
