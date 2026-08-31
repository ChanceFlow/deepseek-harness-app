# Agent Note: Sidebar overscroll glow neutralized to outline variant

Status: implemented

## Problem

Users reported host-accent blue bleeding from behind the top banner of the
sidebar when scrolling. In the sidebar layout, the scrollable list viewport
(session tree and search results) begins flush below the brand row and the
section header banner. Under Android platforms or configurations where the
framework's `GlowingOverscrollIndicator` is active, the default
`MaterialScrollBehavior` decorates scroll overshoots with a glow arc colored
`ColorScheme.secondary` (brand blue). When dragging downwards at the top of
the list, this saturated blue glow paints across the boundary between the
list and the header, reading visually as accent color leaking from beneath
the top banner.

## Decision

`_SidebarScrollBehavior` in `session_panel.dart` extends
`MaterialScrollBehavior` and overrides `buildOverscrollIndicator` to route
the overscroll glow color to `scheme.outlineVariant` (the neutral hairline
border role), while preserving `StretchingOverscrollIndicator` on Material 3
stretch-supported Android configurations. `ScrollConfiguration` applies this
behavior locally to the sidebar's scrolling regions (session tree, search
results, and rail avatars). The glow remains visible as a quiet edge affordance
without introducing saturated brand blue bleed across the header boundary.

## Alternatives considered

- **Keep framework default blue glow (`scheme.secondary`)**: rejected — paints
  a high-contrast brand blue blur across the top boundary that conflicts
  with the neutral sidebar chrome and appears as an active/ongoing state leak.
- **Global app-wide `ScrollBehavior` override**: rejected — modifies overscroll
  indication across every screen (chat transcript, models, settings, workspaces);
  the top-edge flush-banner bleed issue is specific to the sidebar's layout.

## Consequences

The sidebar's pull-to-overscroll glow matches the neutral outline-variant
hairline tone in both light and dark themes. Widget tests in `session_panel_test.dart`
assert the overscroll indicator color against `scheme.outlineVariant` under both
brightnesses and verify that `StretchingOverscrollIndicator` continues to build
under Material 3 defaults. (Note: upward scroll tile fill bleed across the top
boundary is separately clipped via a local `Material` ink host in
[2026-08-31-sidebar-ink-host-clip.md](2026-08-31-sidebar-ink-host-clip.md).)
