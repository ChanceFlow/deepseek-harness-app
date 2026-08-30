# Agent Note: Sidebar native Material components

Status: implemented

## Problem

The chat sidebar's browsing chrome was a hand-rolled port of the dsh web
sidebar — custom `InkWell` + `Container` rows and headers (folder-glyph group
headers, 44px session rows, the New Session bordered capsule, the section and
per-backend headers, the verbs sheet rows) with no native Material semantics.
The timeline and composer already rode native components (see
[2026-08-20-timeline-native-components.md](2026-08-20-timeline-native-components.md)
and
[2026-08-20-native-component-buttons.md](2026-08-20-native-component-buttons.md)),
so the sidebar was the remaining surface without native ripple, focus,
selection, expansion, and disabled semantics. The user asked the sidebar to
align with Flutter's native design, matching the timeline's adoption.

## Decision

The sidebar's browsing chrome rides native Material components themed to the
deepsuite flat visual — the same contract as the timeline. No new color
values; the generated deepsuite tokens stay the identity.

- **Group headers → `ExpansionTile`** in `session_panel.dart`. The tile is
  controller-driven via an `ExpansibleController` so the parent's browsing
  state stays the single source of truth: `didUpdateWidget` syncs an
  external `expanded` change (store seed, or the current group changing)
  through the controller, and `onExpansionChanged` only routes a value that
  differs from the last-rendered `expanded` to the parent — a programmatic
  sync never writes a browsing override. The group holding the active
  session never folds: its header is inert (`enabled: false`), and a scoped
  `Theme` points `disabledColor` back at the normal on-surface ink so the
  always-open header is not dimmed. The session-count caption rides beside
  the label ahead of the M3 chevron; the folder glyph keeps its
  accent-on-current tint.
- **Session rows → native `ListTile`** (`session_tree.dart`, shared with the
  Workspaces tab): 44px via `minTileHeight` + dense compact density, the
  16px status seat via `minLeadingWidth`, the deepsuite active fill via the
  per-tile `selectedTileColor`, the deepsuite hover via `hoverColor`, and the
  relative time (plus the management surface's always-visible verbs seat) in
  the trailing slot. `SessionSearchResultRow` becomes a native two-line
  `ListTile` (the native subtitle auto-indents under the title, matching the
  web `left: 20` inset). `SessionOverflowRow` becomes a native `TextButton`.
- **New Session capsule → native `OutlinedButton.icon`** carrying the same
  deepsuite surface tokens (elevated fill, l2 border, r12 shape, 38px).
- **Section and per-backend headers → native `IconButton` / `ListTile`**: the
  section's search seat is a standard `IconButton` (the custom
  `_HeaderIconButton` is deleted); the per-backend header is a `ListTile`
  with the live dot leading, label over host:port, and the Active/Standby
  badge trailing, keeping the nav-item fill on the active backend.
- **Verbs sheet rows → native `ListTile`** inside the transparent `Material`
  ink host the sheet's decorated container requires; the always-visible
  ellipsis seat becomes a compact `IconButton`. `_GroupSection` becomes a
  `StatefulWidget` owning the `ExpansibleController`; `_GroupHeaderRow` is
  deleted.

## Alternatives considered

- **Full M3 default look (abandon deepsuite parity)**: rejected — the user
  chose deepsuite visual with native components, not a re-skin toward M3
  defaults (same rejection as the timeline note).
- **Scoped `ListTileTheme` override for the sidebar**: rejected — `ListTile`
  exposes `selectedTileColor` as a constructor parameter, so no `Theme`
  wrapper is needed and the shared rows get the correct fill on both
  surfaces without a surface-specific theme.
- **Enabled current-group header that snaps back**: rejected — an enabled
  header would animate a collapse before re-expanding on every tap; the
  inert header (`enabled: false` + disabled-ink override) is a clean no-op.
- **Keep the 3px selected accent edge**: rejected — `ListTile` has no native
  edge chrome; fill-only selection matches the timeline adoption (option rows
  dropped the 1px ring). The `sidebarNavItemActiveAccent` token stays in use
  by the chat surface.

## Consequences

- The sidebar gains native ripple, focus, selection, expansion animation, and
  disabled semantics while keeping the deepsuite flat visual; the
  browsing-toggles contract (current group never folds, per-group override
  persistence, overflow control, backend grouping) is unchanged and still
  covered by the behavior suite.
- The Workspaces tab inherits native session rows through the shared
  `session_tree.dart` components; its own workspace-row chrome
  (`_WorkspaceRow`, `_UngroupedHeaderRow`) is unchanged — outside the
  sidebar scope.
- Deliberate web-fidelity deltas: the selected row drops the 3px accent edge
  (fill-only), the group header gains the M3 chevron and loses the
  expanded-hover fill, and the always-open group's header is inert rather
  than a no-op toggle. `ExpansionTile` removes collapsed children by default,
  matching the old `if (expanded)` row construction.
- One multi-backend sidebar test now `pumpAndSettle`s after expanding a
  standby group before tapping its row (the ExpansionTile must finish
  animating before the row is hit-testable). A new `session_panel_test` pins
  the native shapes — `ExpansionTile` group headers, `ListTile` session
  rows, the `OutlinedButton` New Session seat, and the `IconButton` search
  toggle.
- Partially supersedes the sidebar-chrome paragraphs of
  [2026-08-20-sidebar-config-trigger.md](2026-08-20-sidebar-config-trigger.md)
  and
  [2026-08-20-workspaces-tab-web-alignment.md](2026-08-20-workspaces-tab-web-alignment.md)
  where they describe the hand-rolled rows; their behavior contracts still
  stand.
- The collapsed rail's icon seats — stock IconButtons, the shared
  `secondaryContainer` selection role, and the pane-width constants — are
  owned by
  [2026-08-29-sidebar-rail-native-seats.md](../simplification/2026-08-29-sidebar-rail-native-seats.md).
