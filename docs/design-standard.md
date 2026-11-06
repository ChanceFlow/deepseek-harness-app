# Design standard: a thin shell over the host's UI

Taste does not survive a handoff. This document states the design facts of
the WebView shell, so a change has an answer before it is drawn and a reviewer
can name which fact it violates. The numbers that remain ours — the alias
table, the shape scale, the motion tokens — live in
[flutter/app/lib/theme/theme.dart](../flutter/app/lib/theme/theme.dart), whose
ownership rules are in [flutter/app/AGENTS.md](../flutter/app/AGENTS.md).

## The facts

Five observations about this product, not preferences about interfaces.

1. **The pixels are the host's.** The page inside the WebView is the dsh web
   client, served by the host and versioned with it. The client does not draw
   the transcript, the composer, settings, or any other chat surface.
2. **The shell is chrome, not a UI.** Dart draws exactly one bar and one
   drawer around the page. Every pixel they take is a pixel the host's layout
   loses on a phone.
3. **The client owns two surfaces of its own.** The multi-host registry and
   Android notifications are the reasons this app exists beyond a browser;
   both work with nothing but the shell mounted.
4. **A host's page is not restyleable.** It arrives with its own type,
   colors, spacing and motion. Injecting CSS or shipping a Material port would
   fork the host's design and drift on every upstream change.
5. **Agents read this code cold.** A rule carried by taste drifts on the next
   change; one carried by a constant or a gate holds.

## What follows

Each rule ends with the facts above it answers to; disagree with a rule by
disagreeing with its facts.

- **The host's page owns its viewport.** The shell never injects a script or
  a stylesheet and never wraps page content in a Flutter surface. `SafeArea`
  around the page is the one exception, because the host ships no
  `viewport-fit` handling and a cutout would otherwise cover its chrome (1,
  2, 4).
- **The chrome stays one bar and one drawer.** A 44 px host bar carries the
  active host's label, its reachability dot and the switcher; a 280 px drawer
  lists hosts with add and select. A new chrome row has to take the place of
  one of those, not sit beside it (2).
- **Chrome takes the pin's tokens.** The bar's fill is the sidebar fill, its
  divider the 0.5 px `borderL2` hairline, its type the pin's `sStrong14` /
  `xxs12` roles, its drawer the `specificSidebarFill` with square edges. A
  raw color or radius outside `theme.dart` is a gate failure, and a framework
  component that draws Material's own chrome is overridden (2, 5).
- **No Material 3 port.** No `NavigationBar`, no per-screen `AppBar`, no
  `ColorScheme` remap of the host's page. The shell's `ColorScheme` exists
  only so its own bar and drawer read the pin's aliases (1, 4).
- **The drawer is the registry's home.** Add and select live there today; a
  rename, URL-edit, removal or per-host TLS-certificate seat belongs in the
  host row rather than on the page. A host's health is one dot on the bar; a
  second status surface belongs in the host row too (2, 3).
- **Pooling is a design decision.** At most three WebViews stay live, because
  memory is the phone's scarcest resource, and a released host reloads rather
  than appearing broken. The page is never unmounted while it is visible (2,
  3).
- **Notifications are the shell's own surface.** An Android notification
  (and a foreground toast) is built from the adapter's roster and
  pending-interaction folds. They never need the host's page mounted, never
  inject into it, and a tap opens the app on the current host (3).
- **Motion is the host's inside the page.** The shell animates only its own
  transitions and uses `DshMotion` for them. A page-level animation added in
  Dart would fight the page the host served (1, 4).

## Deciding a chrome change

Answer in order; a blocked question sends the change back, not forward.

1. **Is this the page's job?** If the host's page can show it, it belongs
   there. File it upstream rather than drawing a second surface (1, 4).
2. **Which of the two chrome seats does it take?** The bar or the drawer. A
   third seat needs a decision note, not a widget (2).
3. **What does it cost in idle pixels?** Name the number and say what the
   reader gains for it. The page loses every one of them (2).
4. **Which existing token does it take?** An alias, a shape step, a motion
   token. A new value is a decision note (5).
5. **What proves it?** A widget test that pumps the real `ShellRoot` with a
   stand-in host view and asserts the rendered role or behavior
   ([docs/testing.md](testing.md)). No local screenshot pipeline exists: the
   page is the host's, and the chrome is reviewed as a widget tree (1, 5).

## Enforcement

`verify_theme_native` rejects a raw color, a `ThemeExtension`, or a numeric
radius anywhere under `flutter/app/lib/` outside `theme/theme.dart`, so the
shell cannot invent a value. Tests pump the shell under both brightnesses and
assert colors by role. Whether a chrome change earns its pixels stays review's
call, held against the five facts above. The wire contract the page and the
notification pipeline share is [docs/spec.md](spec.md).
