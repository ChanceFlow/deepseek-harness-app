# Agent Note: Sync the composer ➕ and model sheets to the selector row system

Status: implemented

## Problem

The 2026-08-25 dropdown redesign moved the workspace chip, new-session
dialog, prompt-mode button, and speech-model selector to the mobile
selector-row system: an icon header with a count pill, and rows built
from a 36px icon tile, a 13.5w600 title, an 11.5 secondary line, and a
`check_circle_rounded` selection mark. The composer's ➕ command sheet and
the `ModelSelect` sheet kept their earlier web form (bare 13px text rows,
plain `Icons.check`, no header), so those two surfaces read as a
different generation from the rest of the picker family.

## Decision

Restyle the two remaining composer sheets to the established selector
system, changing presentation only:

- **`_CommandSheet` / `_CommandRow` (`chat_screen.dart`)**: added the
  shared sheet header (primary `Icons.terminal` glyph + Commands title +
  visible-row count pill); each row now carries a 36px `surfaceContainerHigh`
  tile — `Icons.terminal` for host commands, `Icons.auto_awesome` for
  skills, `Icons.image_outlined` for the attach-images tail row — above
  the bold `/name` label with the description as its secondary line. The
  search field, filtering, roster order, and insert behavior are unchanged.
- **`ModelSelect` (`model_select.dart`)**: pane headers paint their glyph
  in `primary`; the root navigation cells (`Model`, `Effort`) and the
  model/effort option rows gained the same 36px tile (`Icons.memory`,
  `Icons.speed`) via a shared `_RowTile`, the active row lifts its tile to
  the `primaryContainer` pair, and selection moved from `Icons.check` to
  `check_circle_rounded` in `primary`. Panes, preference memory, and
  selection dispatch are unchanged.

## Alternatives considered

- **Leave the two sheets web-aligned**: rejected — the web form was the
  pre-redesign generation the 2026-08-25 note already moved away from,
  and two surfaces outside the system is exactly the inconsistency that
  note closed for the other pickers.
- **One shared cross-file row widget**: deferred — the row skins differ
  (selection mark vs plain action, trailing chevron vs nothing); a
  parameterized widget would carry more knobs than the duplicated
  scaffold, so `app` keeps the pattern per file. Promote to `ui/shared/`
  when a third surface needs the same row.

## Consequences

All bottom-sheet pickers — workspaces, prompt mode, speech model, agent
preset, commands, and the model seat — share one row language. The
composer sheet tests (`chat_screen_test.dart`, `model_select_test.dart`)
keep passing unchanged because every text and behavior contract held.
