# Agent Note: Native component controls — composer, input dock, sidebar

Status: implemented

## Problem

The composer and its dock carried custom-drawn controls — 28–34px circles
painted with `Material + InkWell + Container(BoxShape.circle)` — instead
of native Material components. The ➕ tool, the model seat, the primary
send/stop circle, the queue-dock row actions, and the sidebar's search
capsule were all hand-rolled: no Material
ripple/focus semantics for some, no standard tap-target behavior, and
more surface code to maintain. The mobile client should feel native on
Android while keeping the DeepSuite brand palette.

## Decision

**Standard Material components, DeepSuite brand colors, per-seat sizing.**
The mobile client deliberately diverges from the dsh web InputBar's
hand-drawn control vocabulary: native components win, the brand tokens
stay.

- **Primary send/stop → `FloatingActionButton.small`** (40px, `heroTag:
  null` so sibling send/stop FABs never fight over the shared hero). The
  seat keeps the composer's "no idle blue" rule by resolving per state:
  brand `buttonInfoFill` + white glyph when actionable, neutral
  `specificSelector` + `labelTertiary` glyph when idle (the FAB has no
  separate disabled colors — the constructor's `backgroundColor` /
  `foregroundColor` already swap). `disabledElevation: 0` keeps the idle
  seat flat. Tooltips (`Send`/`Stop`/`Sending`) are unchanged, so the
  existing tap-by-tooltip tests hold.
- **Composer tool seats (➕ and ModelSelect) → standard `IconButton`** with
  `IconButton.styleFrom`: `specificSelector` fill, `onSurface` glyph,
  `interactiveBgHoverSolid` hover, `CircleBorder` shape — the web `.add`
  family's visual on the component's surface, at the standard 40px M3
  footprint. `DsCircleButton` (`circle_button.dart`) is deleted; both
  consumers are converted.
- **Queue-dock row actions → standard `IconButton`** constrained to the
  web's 28px visual (`BoxConstraints.tightFor(28, 28)`, `padding: zero`)
  so the compact 36px dock rows keep their height; disabled rows render
  the 45%-alpha tertiary glyph via `disabledForegroundColor`.
- **Sidebar search capsule → inline M3 `SearchBar`** (the expand /
  collapse / clear / live-query flow is unchanged): elevation and tint
  forced off, transparent fill, the capsule's `borderL2` side and r10
  shape, and `BoxConstraints.tightFor(height: 36)` keep the compact
  capsule footprint; `autoFocus` keeps the keyboard opening on expand.
- **Composer context-occupancy ring → determinate
  `CircularProgressIndicator`**: the hand-drawn `_RingPainter`
  (CustomPaint, 14px ring, 2px stroke) is deleted; the native component
  renders the same secondary arc on the outline-variant track at the
  same footprint and gains the component's progress semantics. The rest
  of the timeline keeps its native-but-DeepSuite-styled form: message
  bubbles and tool-flow cards are decorated Containers (chat surfaces
  have no Material equivalent), status dots stay hand-drawn indicators
  (halo + core has no Material counterpart), TurnGroupHeader already
  uses `OutlinedButton`, and running/ok/error tool glyphs already use
  `CircularProgressIndicator`/`Icon`.
- **Theme**: `DshTheme` gains a `floatingActionButtonTheme` — brand
  background/foreground, 40px `smallSizeConstraints`, light elevations,
  `disabledElevation: 0` — so any un-styled FAB defaults to the brand
  instead of Material's default `secondaryContainer`.

## Alternatives considered

- **Full Material You dynamic color**: rejected — the client keeps the
  DeepSuite palette as its identity; system-color takeover would sever
  the generated-token provenance the theme relies on.
- **Global `iconButtonTheme` with a `CircleBorder` default**: rejected —
  a blanket circular shape would change every IconButton app-wide
  (settings, workspace, dialogs) beyond the confirmed scope; the composer
  and sidebar seats style themselves locally.
- **M3 `SearchAnchor` full-screen search view**: rejected — it replaces
  the inline expand/collapse flow the sidebar contracts with; the inline
  `SearchBar` keeps the exact interaction while upgrading the component.
- **Keep the 28px custom circles**: rejected — the point of the change is
  native components; only the dock rows keep a 28px footprint because
  their 36px rows are a layout constraint.
- **`ImageButton`/`RawMaterialButton`**: rejected — `IconButton` and
  `FloatingActionButton` provide the standard semantics (ripple, focus,
  disabled, tooltip) with less surface code.

## Consequences

`circle_button.dart`, the `_RingPainter` custom painter in
`todo_panel.dart`, and the `_RingPainter` in `context_ring.dart` are
deleted; composer, dock, sidebar, and context-ring controls are standard
Material widgets styled with DeepSuite tokens. The composer card and
dock strips grow slightly on the tool seats (40px standard vs 28px
visuals) as the intended M3 footprint. Tests assert the native shapes:
FAB-state transitions in `composer_bar_test.dart`, status glyph icons in
`todo_panel_test.dart`, `SearchBar` flow in `session_panel_test.dart`,
and the determinate `CircularProgressIndicator` at the occupancy
fraction in `context_ring_test.dart`; existing tap-by-tooltip tests are
untouched. The sidebar session-row verbs moved to the long-press menu
during the same window (feat/sidebar-session-actions-status), so the
per-row archive seat this note first targeted no longer exists — its
native-ification dropped out of the merge, not a regression.
Partially supersedes the custom-circle vocabulary in
[2026-08-20-composer-mobile-parity.md](2026-08-20-composer-mobile-parity.md)
— its access/preset/draft decisions still stand.