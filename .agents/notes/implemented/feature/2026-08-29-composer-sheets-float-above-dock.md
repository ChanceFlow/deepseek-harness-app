# Agent Note: Composer sheets float above the dock; the roster loses its search

Status: implemented

## Problem

Every thumb sheet the composer opens — the ➕ command roster, the delivery
mode, model seat, permission seat, preset seat, and the empty-hero
workspace picker — assembled the same card chrome inline (six copies of
the MenuDropdown-family `Padding → Container → ConstrainedBox`) and sat
flush at the screen's bottom edge, covering the composer the reader just
left and crowding the home indicator. The roster additionally carried
the web PopupSelectView search field with `autofocus: true`: opening it
raised the keyboard straight onto the few rows the reader came to tap,
and the sheet's filtered-empty state was a dead end until the query was
cleared. On mobile the roster is short — five host commands, the
session's skills, one attach row — so the query box bought nothing and
cost the whole target list.

## Decision

- `ui/shared/menu_sheet.dart` — `showMenuSheet`: the one opener for the
  MenuDropdown-family card (surfaceContainer fill, `kShapeMenuSheet`
  radius, `outlineVariant` hairline, elevation-3 shadow, 4px inner
  padding, `menu-sheet-card` key). All six composer sites are its
  callers; the per-site content is a plain `builder`.
- `ui/shared/dock_anchor.dart` — `DockAnchor`: the chat panel binds a
  GlobalKey to `_InputDock` and publishes it at the panel root, so any
  sheet opener in the panel measures the dock's on-screen rect.
  `sheetGeometry` returns `(lift, maxHeight)`: the card seats `gap` (8px)
  above the dock's top edge, capped to the space actually left. Screens
  with no composer dock (settings, subagents) resolve through the
  fallback to the legacy 8px bottom seam — those sheets did not move.
- The roster's search field is gone: `_CommandSheet` is stateless, shows
  host commands, skills, and the attach row unconditionally, and the
  `searchCommandsHint` / `noMatchingCommands` ARB keys are deleted in
  both locales. The web keeps its search (desktop roster, keyboard at
  hand); this client's deviation is this note.

## Alternatives considered

- **Keyboard-aware bottom sheet (`anchorPage` / `viewInsets` padding)**:
  rejected — the dock is a body child, not a scaffold footer, so
  `anchorPage` has nothing to anchor to; viewInsets math would have to
  re-derive the dock's position anyway.
- **Keep the search, drop only the autofocus**: rejected — an inert query
  box above a six-row list is still chrome that filters nothing worth
  filtering, and the user asked for it gone.
- **Per-site `Padding(bottom: measured)` without the anchor**: rejected —
  measuring the dock needs an ancestor the openers don't have; the
  GlobalKey + InheritedWidget pair is the same code without six ad-hoc
  geometry helpers.

## Consequences

- The sheet chrome is one implementation: a future restyle touches one
  file. The six former inline copies (including the mode shim's borderless
  variant) all render through it now.
- Widget tests pin the contract through the real screen: the opened card
  carries no `TextField`, its bottom clears the dock's top (measured
  through `DockAnchor`), and picking a command still inserts `/plan ` in
  the composer.
- Sheet max heights are dock-relative: on a short viewport the card
  caps at the space above the dock instead of a fixed 440/520.
