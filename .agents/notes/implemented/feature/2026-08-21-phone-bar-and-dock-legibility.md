# Agent Note: The phone bar names the session; the dock strips stay readable

Status: implemented

## Problem

A design pass over the phone surface — rendered at 400×844 with the real
Roboto and Material icon fonts, not read off the source — found four defects
that only appear at phone width:

- **The bar spent its line on the product name.** `_chatAppBar` already
  composed a session-titled bar and took a `compact` flag, but the narrow
  branch built a second, hardcoded `AppBar` carrying `l10n.appTitle`. Every
  session looked identical, and the facts that change — which workspace,
  which model — were nowhere on screen.
- **Six header verbs vanished on a phone.** The narrow bar carried no
  actions at all: jobs, outline, subagents, rename, fork, and archive were
  reachable at ≥720dp only (rename/fork/archive also live on the drawer's
  long-press).
- **The to-do strip reported a census, not the work.**
  `1 completed · 1 in progress · 1 pending` withheld the one fact a running
  session is asked for — which item is open — while the app's own
  `todo_write` tool row already answered it (`1/4 completed · audit A`).
- **The stats strip clipped mid-word.** It joined every group and let
  `TextOverflow.ellipsis` cut the tail: `… · Cache hit 75% · Inp…`. A
  permanent line that cannot be read costs space and returns nothing.

## Decision

- **One app bar builder, honoring `compact`.** The narrow branch calls
  `_chatAppBar(..., compact: true)`; the duplicate bar is gone. A compact bar
  stacks `titleMedium` session title over a `labelSmall`
  `onSurfaceVariant` second line from `sessionContextLine`: workspace
  basename · model display name. The workspace drops out when the session
  has no durable title (`displayTitle` already falls back to the cwd
  basename, and repeating it says nothing); the function returns null when
  neither fact is known, which renders the single-line title.
- **Phone verbs fold into an overflow.** `ChatHeaderActions` takes
  `compact`; at phone width it keeps the jobs pill and the outline toggle on
  the bar and moves subagents/rename/fork/archive into a
  `PopupMenuButton` behind `sessionMenuTooltip` (en "Session menu" / zh
  "会话菜单"). Wide bars keep all six seats.
- **The strip speaks the tool row's summary.** `todoPlanLabel` replaces
  `todoProgressLabel`, reusing `l10n.toolTodoPlanCompleted(done, total)` plus
  the first running item's content — the same rule `plan-summary.ts` gives
  the `todo_write` row, so the dock and the transcript agree.
- **Stats drop whole facts instead of clipping.** `fitStatsGroups` measures
  candidate prefixes with a `TextPainter` under the live `TextScaler` and
  keeps the longest that fits the `LayoutBuilder` width; the first group
  always survives. Group order now spends width by value: turns/steps →
  tokens → cache hit → durations → speeds.

## Alternatives considered

- **Two-line stats strip**: rejected — the dock's vertical budget is the
  scarce resource on a phone (see `2026-08-21-dock-budget`), and a second
  permanent line buys diagnostics at the transcript's expense.
- **Horizontally scrollable stats**: rejected — it hides facts behind a
  gesture nobody performs on a status strip and defeats glanceability.
- **Truncating the stats string at a character budget**: rejected — a count
  of characters is not a count of pixels; the painter measures what the user
  sees, including their text scale setting.
- **Keeping per-status to-do counts and appending the active item**:
  rejected — the counts crowd out the content at 400dp, and two summaries
  for one plan is the inconsistency being fixed.
- **Putting all six verbs on the phone bar**: rejected — six 48dp seats
  leave ~100dp for a session name; the M3 pattern is two or three actions
  plus an overflow.

## Consequences

- The phone bar now answers "which session, where, with what" without a tap,
  and the subtitle costs no extra bar height (it rides inside the standard
  56dp toolbar).
- Phone users reach subagents, rename, fork, and archive from the bar for the
  first time; the drawer's long-press verbs are unchanged.
- Widget tests pin the new contracts through real entry paths: the compact
  bar's title/subtitle and overflow contents, the wide bar keeping every
  seat, `sessionContextLine`'s three cases, the strip's plan line, and
  `fitStatsGroups` at wide/narrow/degenerate widths. Four tests asserting the
  old strings were updated, not deleted; their finders are now scoped to the
  surface they mean.
- The screenshots behind this pass came from a scratch `flutter test
  --update-goldens` harness loading the SDK's Roboto and
  `MaterialIcons-Regular.otf` through `FontLoader` — the default test font
  paints every glyph as a box, which hides exactly these defects. It is
  deliberately not committed (platform-dependent goldens would be a flaky
  gate); the before/after pairs are published at
  `http://127.0.0.1:8899/design/`.
- Deliberate scope deltas: per-message timestamp/copy rows still cost a line
  each (a long-press menu would collide with the in-flight touch-target
  work), and the empty hero still offers no first move.
