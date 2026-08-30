# Agent Note: Outline turn-group header restyled as a borderless ledger line

Status: implemented

## Problem

The collapsed view (outline mode) failed design review: its per-turn
`TurnGroupHeader` was one full-width `OutlinedButton` around a multi-line
`Column`. Five defects against
[flutter/app/AGENTS.md](../../../../flutter/app/AGENTS.md) "Stock Material 3
is the aesthetic":

1. Every turn wore a hairline frame in the ledger view — chrome drawing a
   border around content ("Two tones separate content from chrome"), while
   the flow mode's boundary voice had already settled on the quiet,
   borderless `TurnBoundaryRow` (a 14px hairline tick + letterspaced caption).
2. The fold state was a hand-typed `'▸ $label'` / `'▾ $label'` glyph spliced
   into the text — against framework-first, and against the disclosure
   convention the subagents pass just set (`chevron_right` → `expand_more`
   icon swap, no bespoke rotation curve;
   [the componentization note](../simplification/2026-08-29-subagent-screen-framework-component-pass.md)).
3. The tool summary was hand-typeset `bash 1✓ 1✗ · edit 1…` — check, cross,
   and ellipsis assembled from text characters instead of the shared
   `StateDot`.
4. The prompt echo rode `primary`; the role map puts metadata and previews
   on `onSurfaceVariant`.
5. `turnHeader`/`beforeFirstTurnHeader` interpolated bare counts, so a
   one-message turn rendered "1 messages".

## Decision

`TurnGroupHeader` is now one borderless `ListTile` (dense,
`VisualDensity.compact`, `minTileHeight: 30`, `contentPadding` horizontal 2
— the same column the tool rows ride, since an `ExpansionTile`'s
`tilePadding` *is* its inner `ListTile`'s `contentPadding`).

- **leading**: `TurnBoundaryRow`'s 14px `outlineVariant` hairline tick, then
  the shared `StateDot` for the turn's run state — any failed tool →
  `error`, else any running → `ongoing`, else `done`. With no tools in the
  group the dot stays home: the client states only what it was told. The
  tick was kept beside the dot (rather than replaced by it) so the outline
  header and the flow boundary speak one voice; the tile's leading slot
  absorbs both without crowding the title.
- **title**: `turnHeader` in `bodySmall` w600 `onSurface` — the tool rows'
  title typography.
- **subtitle**, one line, ellipsized: expanded echoes the quoted prompt in
  `onSurfaceVariant`; collapsed trades the echo for plain per-tool counts
  (`bash 2 · edit 1`) with an error-ink failure count trailing as its own
  `Text` (new key `turnFailedCount`, en "{count} failed" / zh
  "{count} 个失败") so a crowded summary ellipsizes before the error count
  does.
- **trailing**: `chevron_right` (collapsed) ↔ `expand_more` (expanded)
  under the tool rows' 18px `IconTheme.merge`; the before-first-turn group
  (`turn == null`) renders without `onTap` and without a chevron — inert
  like a boundary notice.
- Folding still swaps slivers instantly: no custom curve (motion stays a
  framework default).
- l10n: both header keys became intl plurals (`=1`/`other`, following the
  six existing plural keys; zh emits the `other` form only), and the
  committed gen-l10n output was regenerated.

`OutlineTimeline`'s sliver composition, the `group-N` sliver keys, and the
collapse persistence are untouched
([the slivers note](../architecture/2026-08-20-outline-timeline-slivers.md)).

## Alternatives considered

- **Keep the `OutlinedButton`, swap only the glyphs**: rejected — the frame
  itself is the violation; a bordered box around every turn still re-owns
  the content surface no matter what sits inside it.
- **`ExpansionTile`**: rejected — the fold is cross-sliver (the header and
  its rows are separate slivers so a collapsed turn contributes no row
  slivers at all, and rows build lazily); `ExpansionTile` can only hold its
  body inside the tile, which would rebuild the fold into eager per-turn
  children and forfeit the sliver structure.
- **Dot alone, no tick**: considered; kept both because the tick is the
  ledger's boundary voice, not decoration around the dot.

## Consequences

- `chat_screen_test`'s outline test now asserts the tile through the widget
  tree (`widgetWithText(ListTile, 'Turn 1 · 1 message · 3 tools')` — one
  string proving both the singular "1 message" and the plural "3 tools"),
  the icon swap, the `StateDot`, row removal and restoration, and the
  unchanged `Expand all` verb; a new test reads the prompt echo, the
  dot's core, and the failure count back from their theme roles
  (`onSurfaceVariant`/`scheme.error`) under both `DshTheme.light()` and
  `DshTheme.dark()`. `composer_bar_test`'s persistence restore locates the
  tile the same way.
- The design catalog gained `outline` and `outline-collapsed` shots. The
  shipped `busyState()` timeline carries no turn boundary — its outline is
  one inert before-first-turn group — so `outlineState()` reuses
  `busyState`'s chrome with a two-turn fold (a failed tool in turn 1, a
  running tool in turn 2).
- Partial supersession: [proposal A](../feature/2026-08-20-chat-timeline-restyle-proposal-a.md)
  keeps the flow-mode decisions; its outline sentence was fact-repaired in
  place and now defers this header's language to this note, which owns it.
