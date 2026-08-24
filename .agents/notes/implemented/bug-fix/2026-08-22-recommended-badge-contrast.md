# Agent Note: Recommended badge painted invisible by wrong M3 role pairing

Status: implemented

## Problem

The question card's recommended badge — the chip beside an option whose
label ends in `(Recommended)` / `（推荐）` — rendered with the M3 role
pairing inverted: `primaryContainer` as ink on a `secondaryContainer`
chip. Both are tone-90 containers in the brand-seeded scheme
(light `#DEE1FF` on `#DFE1FA`), measuring **1.00:1 contrast in light and
1.02:1 in dark** — the badge text was painted but effectively invisible in
both themes. A user reviewing the real question card (real session data,
option `会话行归档（web 平价）(Recommended)`) reported the badge did not
render; the widget tree contained the text, the pixels did not.

## Decision

`_QuestionOptionTile`'s badge now uses the M3 container pairing:
`primaryContainer` chip with `onPrimaryContainer` ink. Contrast rises to
**7.25:1 in both themes** (WCAG AAA), and the chip reads as the accent
surface the web badge is (web: `--dsw-specific-sidebar-nav-item-active-
accent` fill with dark ink). A regression test pumps the card under both
`DshTheme.light()` and `DshTheme.dark()` and reads the painted roles back:
text style color equals `scheme.onPrimaryContainer`, the chip's
`BoxDecoration.color` equals `scheme.primaryContainer`.

## Alternatives considered

- **`onSecondaryContainer` ink on the existing `secondaryContainer` chip**:
  semantically correct but 2.86:1 — visible yet below the 4.5:1 that small
  text earns; rejected.
- **Keep `primaryContainer` as ink, darken the chip**: fights the role
  system; rejected — the fix is to choose roles, not hand-tune colors.

## Consequences

- The badge is legible in both themes; the fix is visual only, no layout or
  wire change.
- The design catalog gained `question` / `question-zh` shots (the zh twin
  renders the chrome the phone's zh locale shows), covering the chip on the
  review page; PNGs remain gitignored outputs.