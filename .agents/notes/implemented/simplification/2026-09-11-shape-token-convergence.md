# Agent Note: shape-token convergence

Status: implemented

## Problem

[theme.dart](../../../../flutter/app/lib/ui/theme/theme.dart) is the one home
for corner radii, and every surface is supposed to take a step from it. A
scan of `flutter/app/lib/**` found 119 numeric radius literals in 13
distinct values: 8 (41), 6 (18), 10 (13), 12 (12), 999 (8), 22 (6), 18 (5),
2 (3), 20 (3), 24 (3), 16 (3), 4 (2), 3 (2). Two surfaces one step apart
carried different numbers, and the shape bullet in
[flutter/app/AGENTS.md](../../../../flutter/app/AGENTS.md) listed four steps
while `kShapeMenuSheet` already existed.

## Decision

Every numeric radius maps to a named step in
[theme.dart](../../../../flutter/app/lib/ui/theme/theme.dart), chosen by the
component's role: sheets and dialogs, the composer dock, cards, floating
menu surfaces, chips and rows, and one new stadium step.

| old | count | step |
|---|---|---|
| 999 | 8 | `kShapePill` |
| 24 | 3 | `kShapeSheet` ×2, `kShapeDock` ×1 |
| 22 | 6 | `kShapeDock` |
| 20 | 3 | `kShapeCard` ×2, `kShapeDock` ×1 |
| 18 | 5 | `kShapeDock` |
| 16 | 3 | `kShapeCard` |
| 12 | 12 | `kShapeDock` ×4, `kShapeCard` ×3, `kShapeChip` ×3, `kShapeMenuSheet` ×2 |
| 10 | 13 | `kShapeChip` ×12, `kShapeCard` ×1 |
| 8 | 41 | `kShapeChip` ×39, `kShapeMenuSheet` ×1, `kShapeCard` ×1 |
| 6 | 18 | `kShapeChip` |
| 4 | 2 | `kShapeChip` |
| 3 | 2 | `kShapeChip` |
| 2 | 3 | `kShapeChip` |

The one added constant is `kShapePill` (999) for the eight stadium badges: a
status or error badge whose height its corners must match cannot ride
`kShapeChip`, which draws a rounded rectangle, and Material 3 carries a pill
as its own badge form. Its row joins the shape bullet in
[flutter/app/AGENTS.md](../../../../flutter/app/AGENTS.md), which lists all
six steps.

The composer's stacked strips — the goal bar, the schedule reminder, and the
queue dock — take `kShapeDock` so they share the composer card's silhouette.
`_ReadOnlyQueueDock`'s local `_kTopRadius` alias goes with them; the port's
seam is owned by [the queue-dock
note](../feature/2026-08-19-queue-dock-tab-persistent-draft.md).

[verify_theme_native.py](../../../../scripts/verify_theme_native.py) rejects
a numeric literal passed to `BorderRadius.circular(...)` or
`Radius.circular(...)` under `flutter/app/lib/` outside `theme.dart`, naming
file:line and the six steps. The check reads the comment-stripped file as
one string, so a formatter-split call cannot hide a number.

### Borderline

- **Micro-radii (2–4): seven sites.** The diff-line highlight
  (`chat_screen.dart`, `file_preview_sheet.dart`), the `HARNESS` wordmark
  badge, the 36dp image thumbnail, the question checkbox, the 10dp stop
  glyph, and the 6dp progress bar take `kShapeChip` (8), the closest step
  below the ring of controls. It rounds them further than the drawn micro
  radius; a dedicated micro step is not worth its row.
- **Circular hit targets.** The 22 and 18 sites are half their box height:
  44×44 icon buttons and 36×36 triggers and capsule buttons. `kShapeDock`
  (20) clamps to the half-height on boxes 40dp and shorter, so those stay
  stadiums; the 44×44 buttons lose 2dp of roundness. The capsule text field
  (`workspace_screen.dart`) and the 28dp job capsule take the same step.

## Alternatives considered

Keeping the thirteen literal values as they were: rejected, because the
scale then states a rule the code does not follow and the next surface
copies whichever neighbour it sat beside. Adding a sixth and seventh step (a
4dp micro radius, a 10dp control radius): rejected, because a step earns its
place by a component role, and only the stadium pill has one. Choosing by
numeric distance instead of role: rejected, because 12 sits one step from
both `kShapeCard` and `kShapeMenuSheet`, so proximity maps cards to menus. A
new `verify_shape_tokens.py` registered in `verify_all.py`: rejected,
because extending `verify_theme_native` keeps the aesthetic gate in one home
and needs no manifest change.

## Consequences

119 call sites read a named step and the scale is the only way through.
Visible deltas: micro-radii grow to 8, the composer strips round from 12 to
20, the 12dp nav rows and option rows drop to 8, and floating overlays (the
slash command palette at 8) rise to `kShapeMenuSheet`. Adding a step means a
constant in `theme.dart` plus its row in `flutter/app/AGENTS.md`; the gate's
violation text names the six that exist.
