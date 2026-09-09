# Agent Note: Unified animation system and motion tokens

Status: implemented

## Problem

Animation parameters across the client were fragmented across individual call
sites: raw `Duration(milliseconds: 200)` and arbitrary easing curves were typed
inline, bottom destination switches cut instantaneously without transition,
the foreground notification toast appeared and disappeared without entrance
choreography, and Android devices defaulted to 60Hz display refresh rates
rather than fluid 90Hz/120Hz native panels. Furthermore, interactive buttons
lacked tactile press response, creating a static feel compared to modern native
mobile applications.

## Decision

Establish a project-wide motion standard anchored in Material 3 principles:

1. **Tokens (`theme.dart`).** `DshMotion` centralizes motion tokens:
   - Durations: `durationMicro` (100ms), `durationShort` (200ms),
     `durationMedium` (300ms), and `durationLong` (450ms).
   - Curves: `curveEmphasized` (`easeInOutCubicEmphasized`), `curveEnter`
     (`easeOutCubic`), `curveExit` (`easeInCubic`), `curveStandard`
     (`easeInOutCubic`), and `curveSpring` (`easeOutBack`).
   - Reduced motion: `DshMotion.isReducedMotion(context)` queries
     `MediaQuery.disableAnimationsOf(context)` to collapse animations when
     requested by system accessibility settings.
2. **Android High Refresh Rate.** In `main.dart`, `_initDisplayMode()` calls
   `FlutterDisplayMode.setHighRefreshRate()` on Android at startup, guarded by a
   test-environment check so automated suites run without platform channels.
3. **Global Page and Destination Transitions.**
   - `DshTheme._build()` configures `pageTransitionsTheme` with standard
     `ZoomPageTransitionsBuilder(allowSnapshotting: true)` on Android/desktop
     and `CupertinoPageTransitionsBuilder` on Apple platforms.
   - `AnimatedIndexedStack` in `app_root.dart` wraps the destination stack in a
     subtle fade transition (`DshMotion.durationShort`, `curveEnter`) when
     tabs switch, while keeping all destination states and scroll positions
     mounted.
   - `NotificationToast` gains smooth slide-down and fade entrance/exit
     transitions via `AnimatedSwitcher` plus horizontal swipe-to-dismiss via
     `Dismissible`.
   - `showMenuSheet` applies `AnimationStyle` with `curveEmphasized`.
4. **Tactile Button and Control Feedback.**
   - All Material 3 button themes (`filledButtonTheme`, `elevatedButtonTheme`,
     `outlinedButtonTheme`, `textButtonTheme`, `iconButtonTheme`) take
     `animationDuration: DshMotion.durationShort`.
   - `DshTappable` (`ui/shared/tappable_feedback.dart`) provides a passive
     pointer-driven scale-down (0.96) and spring release (1.0), respecting
     reduced motion.

## Alternatives considered

- **Ad-hoc physics animations with external spring libraries (e.g., Sprung).**
  Rejected: brings third-party dependencies into the UI core; Flutter's native
  curved animations and `ZoomPageTransitionsBuilder` provide stock Material 3
  feel with zero binary overhead.
- **PageView for bottom destinations.** Rejected: destroys the unselected tab
  or requires complex keep-alive mixins; `AnimatedIndexedStack` preserves
  existing `IndexedStack` state semantics while adding smooth visual fading.
- **Relying solely on framework default button tap splash.** Rejected: ink
  splashes alone feel flat without subtle physical scale compression on down-tap.

## Consequences

- All screen transitions, tab switches, and popups follow unified easing.
- Hardcoded durations and curves at call sites are replaced by `DshMotion`.
- Android users on 90Hz/120Hz displays experience fluid 120fps physics.
- The motion system respects accessibility settings, automatically bypassing
  transitions when reduced motion is requested.
