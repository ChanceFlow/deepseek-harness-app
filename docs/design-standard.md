# Design standard: a thin shell over the host's UI

Taste does not survive a handoff. These are the shell's design facts, so a
change has an answer before it is drawn and a reviewer can name what it
violates. The numbers that remain ours — the alias table, the shape scale,
the motion tokens — live in
[flutter/app/lib/theme/theme.dart](../flutter/app/lib/theme/theme.dart), owned
by [flutter/app/AGENTS.md](../flutter/app/AGENTS.md).

## The facts

Six observations, not preferences about interfaces.

1. **The pixels are the host's.** The page inside the WebView is the dsh web
   client, served and versioned by the host. The client does not draw the
   transcript, the composer, or any other chat surface.
2. **The shell is chrome, not a UI.** Dart draws one drawer and its grabber.
   Every pixel they take is a pixel the host's layout loses.
3. **The client owns two surfaces of its own.** The multi-host registry and
   Android notifications are why this app exists beyond a browser; both work
   with only the shell mounted.
4. **A host's page is not restyleable.** It arrives with its own type, colors,
   spacing and motion. Injecting CSS or shipping a Material port would fork
   the host's design and drift on every upstream change.
5. **Agents read this code cold.** A rule carried by taste drifts on the next
   change; one carried by a constant or a gate holds.
6. **A page cannot be resized to animate.** Its layout is settled for its
   viewport; resizing or scaling the WebView reflows the page and loses the
   reader's place.

## What follows

Each rule names the facts it answers to; disagree by disagreeing with its
facts.

- **The host's page owns its viewport.** The shell never injects a script or
  a stylesheet and never wraps page content in Flutter. `SafeArea` around the
  page is the one exception: the host ships no `viewport-fit` handling, so a
  cutout would cover its chrome (1, 2, 4).
- **The chrome stays one drawer.** A three-finger swipe down pushes the page
  96 dp and reveals a 96 dp drawer holding the host bubble strip and a round
  settings orb; a 32×4 grabber at the top edge is the fallback opener. A new
  chrome row takes one of those seats (2).
- **Pages move; they never resize.** The pages are one horizontal strip, not a
  `PageView`, translated to the active index; every page keeps its exact size,
  so the host never reflows. Scaling a page into a bubble or rounding it into
  a card is out (1, 2, 6).
- **Chrome takes the pin's tokens.** The drawer's fill is the base fill, its
  divider the 0.5 px `borderL2` hairline, its type the `xsStrong13` /
  `xxxs11` roles, its bubbles `bgLayer2` on `kRadiusMd` edges. A raw color or
  radius outside `theme.dart` is a gate failure; a framework component drawing
  Material's own chrome is overridden (2, 5).
- **No Material 3 port.** No `NavigationBar`, no per-screen `AppBar`, no
  `ColorScheme` remap of the host's page. The shell's `ColorScheme` exists
  only so the drawer reads the pin's aliases (1, 4).
- **The settings page is the registry's home.** Add, rename, URL edit,
  removal, the notification permission, appearance, language and about live
  behind the round orb; a host's liveness is its bubble's dot (2, 3).
- **Pooling is a design decision.** At most three WebViews stay live because
  memory is the phone's scarcest resource; a released host reloads rather than
  appearing broken, and the page is never unmounted while visible (2, 3).
- **Notifications are the shell's own surface.** An Android notification and
  a foreground toast are built from the adapter's roster and
  pending-interaction folds; neither needs the host's page mounted, and a tap
  opens the app on the current host (3).
- **Motion is the host's inside the page.** The shell animates only its own
  transitions, through `DshMotion`; the strip's sweep is 240 ms plus 60 ms per
  intermediate page, capped at 600 ms. A Dart animation inside the page would
  fight the page the host served (1, 4).

## Deciding a chrome change

Answer in order; a blocked question sends the change back, not forward.

1. **Is this the page's job?** If the host's page can show it, it belongs
   there. File it upstream rather than drawing a second surface (1, 4).
2. **Which drawer seat does it take?** The grabber, the bubble strip, or the
   settings orb. A fourth seat needs a decision note, not a widget (2).
3. **What does it cost in idle pixels?** Name the number and say what the
   reader gains for it. The page loses every one of them (2).
4. **Which existing token does it take?** An alias, a shape step, a motion
   token. A new value is a decision note (5).
5. **What proves it?** A widget test that pumps the real `ShellRoot` with a
   stand-in host view and asserts the rendered role or behavior
   ([docs/testing.md](testing.md)). There is no local screenshot pipeline; the
   chrome is reviewed as a widget tree (1, 5).

## Enforcement

`verify_theme_native` rejects a raw color, a `ThemeExtension`, or a numeric
radius anywhere under `flutter/app/lib/` outside `theme/theme.dart`, so the
shell cannot invent a value. Tests pump the shell under both brightnesses and
assert colors by role. Whether a chrome change earns its pixels stays review's
call, held against the six facts above. The wire contract the page and the
notification pipeline share is [docs/spec.md](spec.md).
