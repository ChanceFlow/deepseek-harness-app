# Agent Note: Sidebar rail seats ride stock Material controls

Status: implemented

## Problem

Collapsing the wide-pane sidebar to its icon rail produced a form that
violated the client's design language
([flutter/app/AGENTS.md](../../../../flutter/app/AGENTS.md) "Stock Material 3
is the aesthetic"). Three rail IconButtons — the brand-row toggle, the New
Session seat, and the search seat — carried hand-spun chrome:
`constraints: minWidth: 40, minHeight: 40` plus `padding: EdgeInsets.zero`,
`color: scheme.onSurfaceVariant` (which restates the M3 IconButton's own
default foreground), and mixed glyph sizes 16/20/22. The rail's New
Session seat wore `Icons.chat_bubble_outline` while the expanded pane's
filled button carries `Icons.add_comment_outlined` — one verb, two glyphs —
and the bubble is also the bottom-nav Chat tab's glyph. The selected rail
avatar painted `onSurfaceVariant` ink on a `secondaryContainer` fill,
against the repo's contrast-pair rule (the recommended-badge fix). The
widths 56 and 320 were literals duplicated across `chat_screen.dart` and
`session_panel.dart`, and the same 200ms `Curves.easeInOut`
`AnimatedContainer` was mounted twice around the pane.

## Decision

- **Widths and gap become theme constants.** `kRailWidth` 56 — the web
  shell's closed-sidebar width (`SIDEBAR_COLLAPSED` in
  `reference/deepseek-harness/packages/client/ui-layout/src/client/columns.ts`:
  a 24px icon column between 16px paddings, same width as the Material 3
  NavigationRail spec) — `kSidebarWidth` 320, this app's fixed wide
  pane shared with the drawer (the web sidebar is drag-resizable 264–420;
  the app fixes one width), and
  `kRailControlGap` 12, the web rail's control rhythm
  (`WorkspaceBrowser.module.css` rail-control margins). All live in
  `theme.dart` per the second-use rule.
- **The rail column is stock `IconButton`s**: default 48px interactive seat
  (`_InputPadding` guarantees it inside `ButtonStyleButton`; the hand-spun
  40 + zero padding defeated it), default 24px glyph, default
  `onSurfaceVariant` ink. No color or size override survives. The New
  Session seat carries `add_comment_outlined`, the expanded pane's verb
  glyph; the composer-➕ distinction stays commented at the filled button.
- **One animation site.** The panel's root is now a plain `Container`
  (`width: rail ? kRailWidth : null`): its old `AnimatedContainer` width
  tween was inert — the null end lerps to unconstrained and the parent's
  tight constraint wins throughout. The two-pane row's single
  `AnimatedContainer` in `chat_screen.dart` is the slide's owner. Its
  200ms `Curves.easeInOut` predates this pass (the native-M3 strip of
  2026-08-21) and is kept: a linear width slide reads as a snap at both
  ends of a pane the user is watching fold, and the web shell animates the
  same slide. That recorded reason keeps the bespoke curve a per-change
  decision, not a new constant.
- **Selection is one role pair, shared with the tree.** The selected rail
  avatar fills on `secondaryContainer` — the same role the tree's
  `SessionTreeRow` passes as `selectedTileColor` — and its letter pairs to
  `onSecondaryContainer` (filled seats never keep quiet ink); a resting
  avatar is `surfaceContainerHigh` with `onSurfaceVariant` letter ink, one
  raised step above the rail's `surfaceContainerLow` chrome per the role
  table. The `ColorScheme` role is the shared definition; tests pin both
  surfaces to it. The seat rides the
  framework's own `IconButton.isSelected`, which emits
  `Semantics(selected:)` and the selected widget state.
- **The avatar list is app-local.** The web rail renders no session seats
  (the WorkspaceBrowser rail holds two 36px controls, the shell rail nav
  icons), so the list follows the app's own pattern: the rail is
  a switching surface and keeps no status seat — running/completed dots
  stay the expanded tree's contract.

## Alternatives considered

- **Keep the 40px hand-spun constraints**: rejected — a sub-48 seat faked
  by leftover padding, with an ink override that only restates the
  framework default and a lost 48px touch guarantee.
- **Port the StateDot status seat into the rail avatars**: rejected — no
  web counterpart, no seat inside a 28px circle, and status is the tree's
  job; the rail selects, it does not report.
- **Drop the collapse slide (or fall back to the default linear)**:
  rejected — the animation is a pre-existing deliberate decision doing
  real work; only its duplication was removed.
- **Hand the rail width to the host alone (drop the panel's own)**:
  rejected — the panel self-declares its rail geometry so any host
  mounting it at loose constraints still gets 56, and both files now read
  the same constant.

## Consequences

- The rail collapses/expands with identical visuals: the removed inner
  animation never visibly tweened (parent constraints dominated).
- Tests pin the contract: the rail column declares `kRailWidth` and the
  painted pane settles on `kRailWidth`/`kSidebarWidth` (drawer included);
  the three control seats carry no hand-spun ink/size/constraints and
  resolve to `onSurfaceVariant` at 24px under both brightnesses; the
  selected avatar equals the selected row's fill role in both themes; the
  New Session glyph is identical across forms; the selected seat reads
  `isSelected` to semantics.
- A `sidebar-rail` design shot renders the form at 720dp by widening only
  its own viewport inside the shot's `act`; `_kPhone` — the catalog-wide
  device — is untouched.
- Extends, and cross-links with,
  [the native-component sidebar pass](../feature/2026-08-21-sidebar-native-components.md);
  the contrast-pair rule reused here is
  [the recommended-badge fix](../bug-fix/2026-08-22-recommended-badge-contrast.md).
