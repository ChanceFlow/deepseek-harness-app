# Agent Note: Step-row chrome and space-only division for the transcript

Status: implemented
Surface: `flutter/app/lib/ui/chat/chat_screen.dart`

## Problem

The transcript's one-line marker rows rendered at two different scales. A
context injection, a compaction marker and a `/command` row set their
labels in `bodyMedium` (15px) and let the stock 24px `ExpansionTile`
chevron set the row height, while every step row beside them — a tool
call, a thought, a hook audit — had already moved to `bodySmall` (12.5px)
with the ambient icon size shrunk to 18 so one line of text is one line of
row. The mismatch is worst inside an opened activity card, where the
inline injection row sits directly between a `Thought 4s` row and a `Read`
row and reads a size larger than both.

The injection row also carried none of the disclosure chrome its siblings
share: no `shape: Border()` / `collapsedShape: Border()`, so an expanded
row drew the tile's own full-width rules where the transcript divides with
space, and `minTileHeight: 28` with a `vertical: 3` tile padding put it on
a different rhythm.

One full-width rule survived in the transcript: the activity card drew a
hairline under its own header, on the web reference's `ChatView.module.css`
rule that the fold always rules itself off bottom. Every row inside that
card divides with space instead, so the header was the only line the reader
saw between two steps.

[The visual system](../feature/2026-08-21-visual-system.md) settled 12.5px
as the step-row size, inverting an earlier pass that had unified these
banner labels at 14px; the tool and reasoning rows moved with it, and
these three were simply left behind.

## Decision

The marker rows join the step-row family on the scale the visual system
set:

- `ContextInjectionRow` paints its role label, producer label and summary
  with `bodySmall`, and its disclosure takes `IconThemeData(size: 18)`,
  `minTileHeight: 30`, `tilePadding: horizontal 2`, and `Border()` for
  both tile shapes — the exact chrome `ToolCallRow` and `ReasoningRow`
  already carry.
- `CompactionRow` moves its title and count caption to `bodySmall` and its
  tile onto the same `minTileHeight: 30` / `horizontal 2` geometry.
- `CommandRow` moves the `/name` echo and its settlement text to
  `bodySmall`. It keeps its own 24px line: the row owns no disclosure, so
  its height is its text line, not a chevron box.
- `ActivityGroupRow` drops the hairline under its header. The phase divides
  from what follows with the header's own 8px tail, which is the
  [step-density decision](../feature/2026-08-21-steps-sidebar-fork.md)
  already recorded as "space divides, lines do not"; that decision covered
  every `ExpansionTile` shape and left this hand-drawn rule standing.

Per-row ink roles are untouched — a failed command keeps `error`, a
settled one keeps `onSurface`, and every marker keeps
`onSurfaceVariant` — as are the 14px leading glyphs and the 2x2 separator
dots, which already matched.

## Alternatives considered

- **Raise the step rows to 15px instead**, matching the marker rows as
  they stood. Rejected: the visual system chose 12.5px for a step row so
  the 15px prose keeps its hierarchy against it, and enlarging the
  disclosure rows would have loosened the whole transcript to fix three
  rows.
- **Only fix the context injection row**, the row the reader reported.
  Rejected: the compaction and `/command` rows carry the identical stale
  chrome, so the transcript would keep two marker sizes and the same
  report would return.
- **Give `CommandRow` a 30px box** so every marker row measures the same.
  Rejected: its height comes from having no disclosure to host. Padding a
  one-line row to match a chevron box trades a real fact for a coincidence.
- **Keep the header rule for reference parity.** Rejected: the reference
  is a desktop reading surface whose card is one element among many, while
  on a phone this fold is a step in the same column as the rows it
  contains. The repo's own space-divides decision is the closer authority.
- **Delete the unused `inline` path** on `ContextInjectionRow` and
  `ReasoningRow`, whose doc comments claim the activity card renders them
  without their own disclosure while the card in fact passes neither.
  Deferred: it is a separate dead-code question, not a scale one.

## Consequences

- Every one-line marker in the transcript reads at one size, the three
  disclosure rows measure one height, and no row in the transcript draws a
  full-width rule.
- `app/test/ui/chat/marker_row_scale_test.dart` pins the rule: the five
  labels report `bodySmall`, and the injection, compaction and tool rows
  report equal heights. Both assertions fail on the pre-change tree.
- The design catalog gains `marker-rows` and `marker-rows-expanded`, a
  fixture that stacks the marker rows in one column — the state in which a
  drift between them is visible at all. The existing `timeline-folding`
  shots carry the removed rule in their before column.
- Structural chrome stays out of the family: the turn boundary's
  letterspaced caption and the turn group header keep their quieter roles.
