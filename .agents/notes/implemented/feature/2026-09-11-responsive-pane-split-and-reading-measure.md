# Agent Note: Two axes for the pane split, and a reading measure for the transcript

Status: implemented

## Problem

The chat surface split into a sidebar pane and a chat pane at
`maxWidth >= 720`. That is a width a phone reaches in landscape, where it
stands about 390dp tall: the split spent 320dp of that width on the sidebar
and left the transcript a ~100dp slit holding one or two lines. The breakpoint
was answering a question about width on a device whose constraint was height.

The same layout had no upper bound. On a 1280dp tablet the chat pane took
everything the sidebar left — about 960dp — so an assistant paragraph ran
past 180 characters a line, well outside the 50-75 characters a reader
tracks without losing the return sweep
([Fact 2](../../../../docs/design-standard.md): the space is a budget, and it
can be over-spent as easily as under-spent).

## Decision

- The split now requires both axes: `kTwoPaneMinWidth` 720 and
  `kTwoPaneMinHeight` 500. A rotated phone keeps the drawer, so a short
  surface is never divided.
- The transcript column is capped at `kReadingMeasure` 760dp and centred
  inside its pane. The cap binds only above it; a phone below 760dp lays out
  exactly as before, which is why the drawer and dock measurements are
  unchanged.
- Both numbers are named constants in `chat_screen.dart` beside the existing
  composer cuts, so the next surface that needs a breakpoint reads the
  existing ones rather than typing a pair of its own.

## Alternatives considered

- **Splitting on height alone**: rejected. A tall narrow surface (a small
  tablet in portrait at 600dp) has the height for two panes but not the width
  for two readable columns.
- **Shrinking the sidebar on a short surface** (320dp -> the 56dp rail):
  rejected for this change. It would keep the split at the cost of a second
  breakpoint, and a rotated phone's real problem is that four stacked bands —
  status bar, app bar, transcript, dock, bottom bar — have 390dp between them;
  the sidebar is only one claimant.
- **Padding the transcript rather than capping it**: rejected. Padding has to
  know the pane width and the sidebar's state to land the text in the same
  column; a centred `ConstrainedBox` gets the same result from the pane's own
  constraints.
- **Capping the assistant's prose only**: rejected. A capped body beside a
  full-width caret, tool row and produced-files row reads as a broken column,
  and code blocks already scroll horizontally inside whatever width they are
  given.

## Consequences

- `useTwoPanes` reads both `constraints.maxWidth` and `constraints.maxHeight`;
  a test pumps 780x390 and holds the drawer form, and 1600 wide holds the
  capped column.
- `ChatPanel._timelineBody` returns a centred `ConstrainedBox` around the
  transcript list, so the reading column and the row widths agree by
  construction rather than by two matching numbers.
- A future wide-screen shell that replaces the bottom bar with a navigation
  rail changes `kTwoPaneMinWidth`'s neighbours, not this decision: the split
  still requires the height.
