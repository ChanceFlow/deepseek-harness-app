# Agent Note: Sidebar scroll region clipped transparency Material hosts ListTile ink

Status: implemented

## Problem

In the sidebar's session list, the active backend's section header row (a
`ListTile` with `selected: true`, `selectedTileColor: scheme.secondaryContainer`,
rounded corners, and an Active pill) left a saturated blue bleed/stain (沁色)
across surrounding chrome (`_SectionHeader`, search capsule, and panel gaps)
when scrolled upward. Prior changes (replacing overlay bands with
`BlendMode.dstIn` `EdgeFade` in
[2026-08-29-edge-fade-dissolves-not-overlays.md](2026-08-29-edge-fade-dissolves-not-overlays.md)
and neutralizing overscroll glow in
[2026-08-30-sidebar-overscroll-glow-neutralized.md](2026-08-30-sidebar-overscroll-glow-neutralized.md))
addressed overlay films and overscroll arcs, but the stain persisted on live
scroll.

The defect is structural in Flutter Material: `ListTile.tileColor` and
`selectedTileColor` paint via `InkDecoration` (`packages/flutter/lib/src/material/list_tile.dart`),
which renders directly onto the canvas of the NEAREST ANCESTOR `Material`
rather than in the row's own render slot. As the SDK `ink_decoration.dart`
documentation notes: "Wrapping the [Ink] in a clipping widget directly will
not work since the [Material] it will be printed on is responsible for
clipping." Because the nearest ancestor `Material` spanned the entire sidebar
panel, scrolled tiles (and rows within `cacheExtent` past the viewport)
painted ink rects on that panel-wide canvas outside the list region.
Intermediate clips (`ListView` viewport, `ShaderMask` bounds) could not
intercept ink drawn on the ancestor `Material`.

## Decision

Wrap the scrolling list region inside `EdgeFade` in a local clipped
transparency `Material`:

```dart
Material(
  type: MaterialType.transparency,
  clipBehavior: Clip.hardEdge,
  child: ScrollConfiguration(
    behavior: _SidebarScrollBehavior(glowColor: scheme.outlineVariant),
    child: list,
  ),
)
```

The composition order is:
1. `Expanded` (flex bounds)
2. `EdgeFade` (`BlendMode.dstIn` `ShaderMask` bottom dissolve)
3. `Material` (`MaterialType.transparency` with `Clip.hardEdge` ink host)
4. `ScrollConfiguration` (`_SidebarScrollBehavior` glow neutralization)
5. `ListView` (tree or search results)

`MaterialType.transparency` renders no background fill of its own, preserving
the underlying `surfaceContainerLow` panel tone. `Clip.hardEdge` forces the
`Material` to clip all descendant ink features (`ListTile` selection rects,
splash ripples) to its own viewport-sized bounds. Placing `Material` inside
`EdgeFade` ensures the bottom dissolve ramp continues to fade ink fills
alongside text and icons.

Applied to `session_panel.dart` (`_buildWideChildren`, covering wide pane and
drawer modes) and `workspace_screen.dart` (`_browsingRegionBody`). Individual
rows (`_SessionTile`, `_GroupSection`, `_BackendSectionHeader`) rely on the
ambient ink host and require no restyling.

## Alternatives considered

- **Clip individual `ListTile` rows or switch to Container fills**:
  rejected — `ListTile` ink paints on the ancestor `Material`, so wrapping
  individual rows in `ClipRect` does not clip the ink. Replacing `ListTile`
  with custom containers would forfeit stock Material 3 ink splash
  feedback, selection state semantics, and dense typography rhythm.
- **Move the root `Material` below the header area**: rejected — the panel
  header controls (New Session button, search toggle) require an ambient
  `Material` for ink splash resolution. Splitting or moving opaque Materials
  adds redundant layers and risks background tone mismatches.
- **Use opaque `MaterialType.canvas` for the list region**: rejected — an
  opaque list backdrop breaks the alpha-dissolve compositing of `EdgeFade`
  and hard-codes a surface role that may differ across container contexts.

## Consequences

- Saturated `secondaryContainer` fills on scrolled `ListTile` rows (active
  backend headers, selected session pills) are clipped strictly to the list
  viewport boundary, eliminating bleed across header chrome.
- The `EdgeFade` bottom continuation fade continues to dissolve row fills and
  text smoothly into the panel background.
- Tested structurally in `session_panel_test.dart` and visually through the
  `sidebar-scroll-bleed` design shot under both light and dark themes.
