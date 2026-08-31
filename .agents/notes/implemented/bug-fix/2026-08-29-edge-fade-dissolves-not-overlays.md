# Agent Note: The list continuation fade dissolves content, never overlays it

Status: implemented

## Problem

The sidebar's session tree and the workspaces list ported the web
WorkspaceBrowser `.fade` literally: a 24px `Positioned` gradient band
(`surfaceContainerLow`, alpha 0 → 1) painted above the list's bottom
edge. An overlay band is a second surface between the reader and the
rows — a selected session's `secondaryContainer` pill (and any accent
row) scrolling beneath it stays half-covered by translucent paint, so
its color bleeds through the "banner" with soft edges that read as
accidental frosted glass. The artifact was visible in any crowded list:
exactly the state the sidebar ships in.

## Decision

`ui/shared/edge_fade.dart` — `EdgeFade`: a `ShaderMask` with
`BlendMode.dstIn` whose gradient keeps the region opaque and ramps alpha
to 0 across the bottom `extent` (24px default). The list dissolves into
whatever surface it sits on — no layer above the rows, nothing to bleed
through, and the continuation hint survives because the rows fade
themselves at the viewport edge, the mobile-correct reading of the web
`.fade`. The mask consumes only the shader's alpha ramp, so callers pass
their own backdrop role (`surfaceContainerLow` on both the session panel
and the workspaces list) and it reads correct in light and dark.
Hand-built chrome: this SDK ships no edge-fade component; this note is
the standing reason.

`session_panel.dart` and `workspace_screen.dart` drop their `Stack` +
`Positioned` + `IgnorePointer` + gradient `Container` and wrap the
scroll region (tree or search-result list) in `EdgeFade` instead.

## Alternatives considered

- **Keep the overlay, "fix" its color**: rejected — the tone already
  matched the panel fill; the artifact is the form, not the value. Any
  alpha strip above live content still half-covers what scrolls beneath
  it.
- **Delete the continuation hint entirely**: rejected — the web records
  it as the list's affordance that content continues, and the sidebar
  scrolls constantly; a dissolve keeps the cue without the lie of a
  painted band.

## Consequences

- The two list regions own one fade implementation; a future sheet or
  rail that needs the cue wraps `EdgeFade` rather than copying gradient
  stops.
- The `ShaderMask` composites the visible scroll region only; per-frame
  repaint stays in the list's own dirty band and does not touch the
  rest of the panel.
- Widget evidence: the scroll region in both screens sits inside a
  `ShaderMask` with `blendMode: BlendMode.dstIn`, and the overlay band
  form is gone from the tree. (Note: unclipped `ListTile` ancestor `Ink`
  fills that escaped the viewport boundary during upward scroll are separately
  bounded by a region-local clipped `Material` in
  [2026-08-31-sidebar-ink-host-clip.md](2026-08-31-sidebar-ink-host-clip.md).)
