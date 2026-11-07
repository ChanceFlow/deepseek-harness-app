# Agent Note: The grabber is the only way in, and motion is transform-only

Status: implemented

## Problem

Two facts from real use. The three-finger swipe did not fire reliably on
device: a `Listener` above a `WebView` sees pointers, but whether three
touches arrive as three pointers, as one synthesized gesture, or get
consumed by the platform view differs per ROM and per page, so the gesture
was either dead or late. And the drawer felt rough: every animation tick
called `setState` on `ShellRoot`, which re-resolved the registry, re-ran the
pool reconciliation, and rebuilt the whole shell around a platform view, while
the strip moved by changing a `Positioned.left` — a layout offset, not a
transform. A page that re-lays-out every frame is the expensive case for an
Android WebView.

The user's call: remove the gesture; the small top handle is enough.

## Decision

**One entry point, and only transforms move.**

- **Delete the gesture.** `shell_gestures.dart`, its detector and its tests
  are gone; no `Listener` sits on the page. The WebView keeps every pointer,
  so a three-finger page gesture can never be misread as shell input, and the
  32×4 grabber is the single, always-findable opener. Closing is tap-outside,
  back, or picking the current bubble.
- **Derive, do not assign, per frame.** The displayed page is
  `_displayedPage`: the sweep controller's curve-interpolated value while the
  sweep animates, the settled `_page` otherwise. Frame callbacks no longer
  write state; `_page` is only written by a settled interaction (sweep
  completion, drag update, registry reseat).
- **Rebuild only the moving layer.** The strip and the drawer each sit in an
  `AnimatedBuilder` over `Listenable.merge([_expose, _sweep])`, so a frame
  repaints the strip's transform and the drawer's transform, not the shell,
  not the provider graph, not the pool.
- **Translate, never re-lay-out.** `ShellPageStrip` lays the row out once
  inside an `OverflowBox` and moves it with `Transform.translate`. The drawer
  slides with `Transform.translate`, and the bubble row moves the same way.
  A frame costs one matrix update per moving layer.

## Alternatives considered

- **Keep the gesture and make it more forgiving** (long-press fallback, a
  two-finger variant, an overlay detector): each adds another way to
  mis-classify a touch the page also wants, and none fixes the platform
  variance that made it unreliable in the first place.
- **Keep the tick-driven `setState` but add `RepaintBoundary`s.** The shell's
  build would still re-resolve the registry and the pool each frame; the
  boundary only avoids paints, not the work that preceded them.
- **Move the pages with a `PageView`.** It disposes distant pages, so the
  WebView loses its state; the strip exists to avoid exactly that.
- **Animate the drawer with a height/`SizeTransition`.** Height changes force
  layout of the page below it, which is the cost we are removing.

## Consequences

- One obvious way to open the drawer; discovery rests on the handle being
  visible whenever the drawer is closed (it is hidden only while exposed).
- The sweep still moves a platform view, so a slow page can still raster-slow
  the animation on a weak device; the build/layout side is now flat, which is
  what made it feel uneven rather than merely heavy.
- `_displayedPage` is read during build; anything that changes page position
  outside a controller tick (drag) still calls `setState`, because a drag
  update is a pointer event, not a frame callback.
- A future drag-to-pan on the strip would need a new gesture decision; the
  page owns gestures today, so that stays out.
