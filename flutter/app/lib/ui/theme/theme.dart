/// App theme — native Material 3, seeded from the DeepSeek brand violet.
///
/// Components ride stock M3 roles ([ColorScheme] from [ColorScheme.fromSeed]);
/// no dsh-web design-platform tokens are ported. What this file adds beyond
/// the scheme is the part M3 leaves to the product: a reading-first type
/// scale, one shape language, and the component defaults that keep chrome
/// from competing with the transcript.
library;

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

  /// Text shimmer glint highlight for the turn status row (port of the web
  /// chat `turnStatus` linear text gradient in `ChatView.module.css`).
  /// In light mode, sweeps a bright sky-blue highlight (the web palette's
  /// `--dsw-static-deepseek-200`, `#D3E2FF`) across the darker primary text;
  /// in dark mode, sweeps an off-white highlight (`#FFFFFF`) across the pastel
  /// primary text for clear legibility and high dynamic contrast.
  Color get statusGlint => brightness == Brightness.light
      ? const Color(0xFFD3E2FF)
      : const Color(0xFFFFFFFF);

  /// Code-token colours for fenced blocks ([code_highlight.dart] classifies
  /// them, the markdown renderer paints them). Material 3 carries no syntax
  /// roles, and these three have to stay apart from each other *and* from
  /// `onSurface`, which the rest of the code body keeps wearing.
  ///
  /// Every value holds >= 4.5:1 against the surface a code block actually
  /// sits on — `surfaceContainerHigh`, #E5E1EB light / #34343B dark — not
  /// against the page. Measured keyword / string / number: 7.29 / 5.00 / 4.94
  /// in light, 5.17 / 6.14 / 7.14 in dark.
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

/// Corner radii for the app's surfaces: sheets and dialogs, the composer
/// dock, cards, menu sheets, chips and rows, and the stadium pill. A
/// surface takes a step from this scale; `verify_theme_native` rejects a
/// numeric radius at every other call site.
const double kShapeSheet = 28;
const double kShapeDock = 20;
const double kShapeCard = 14;
const double kShapeChip = 8;

/// The stadium step: a full pill. Error and status badges read as pills,
/// not as the rounded rectangles `kShapeChip` draws, and Material 3
/// carries a pill as its own badge form. The value exceeds half the
/// tallest badge, so every height resolves to a stadium.
const double kShapePill = 999;

/// The menu-surface bottom-sheet card (the web MenuDropdown family):
/// picker sheets — model seat, workspaces, prompt mode, parent session —
/// ride a `surfaceContainer` card with an `outlineVariant` hairline, the
/// elevation-3 shadow, and this one radius, one step inside `kShapeCard`
/// so a floating menu reads tighter than an in-page card. The form is the
/// recorded house convention of
/// [the dropdown-selector redesign](../../../../../.agents/notes/implemented/feature/2026-08-25-redesigned-dropdown-selectors.md);
/// this constant is the fifth radius that note carries.
const double kShapeMenuSheet = 12;

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

/// Global unified motion design tokens: durations, easing curves, and
/// accessibility helpers for all animations across the app.
abstract final class DshMotion {
  /// 100ms: micro-interactions (icon rotation, state-dot morph, splash, fade).
  static const Duration durationMicro = Duration(milliseconds: 100);

  /// 200ms: small components and controls (buttons, tooltips, badges, chips).
  static const Duration durationShort = Duration(milliseconds: 200);

  /// 300ms: medium containers and disclosures (toasts, sheets, accordions, FABs).
  static const Duration durationMedium = Duration(milliseconds: 300);

  /// 450ms: full-page route transitions and large surface changes.
  static const Duration durationLong = Duration(milliseconds: 450);

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
