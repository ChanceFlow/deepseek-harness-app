# Agent Note: The warning state dot is amber, not failure red

Status: implemented

## Problem

`StateDotState.warning` — the "waiting on the user" dot a session row
lights for a pending approval, plan-review, or question — painted
`scheme.error`. The reference web client paints it amber: the palette
defines `--dsw-alias-state-warn-primary` = `amber-500`
(`rgb(245, 158, 11)`) in both brightnesses
([design-platform.css](../../../../reference/deepseek-harness/packages/client/ui-theme/src/styles/design-platform.css)
:230/:322), and `StateDot.module.css:37-39` wires it to
`dot[data-state='warning']` while `error` keeps its own token. Worse than
the wrong pixel, the comment in `state_dot.dart` asserted "the web
palette has no separate warn token" — a false justification recorded in
code, one that would have made the next reader keep the bug. The
sidebar note it decorates
([archive-priority-pending](../feature/2026-08-20-sidebar-archive-priority-pending.md))
and the adapter fold both already say "amber"; only the widget and the
role table disagreed.

## Decision

- **`warning` joins `success` as a `theme.dart` non-role color.** M3
  has no warn role, so `DshSchemeColors.warning` carries it beside
  `success`, with the reference as its provenance. Web rides one
  amber-500 anchor in both themes; the client follows the `success`
  precedent and takes the palette's own contrast steps around it:
  light amber-600 (`0xFFDD8629`, the web's warn-label step) for
  text-level contrast on a light surface, dark amber-400
  (`0xFFF7AD31`) for legibility on dark. `state_dot.dart` maps
  `warning => scheme.warning`, and its comment now states the real
  reference facts with file:line.
- **The role table gains a warning row**: `Warning, waiting-on-user` →
  `warning`, split out of the old `Failure, destructive, warning` row;
  `error` keeps failure and destructive alone. This is the standing
  "new non-role color declared in theme.dart gains a row above" path,
  so `verify_theme_native` stays green.
- **Two status-semantics gaps closed with it.** Search-result rows drew
  only the running blue dot; they now run the same
  [SessionStatusDot](../../../../flutter/app/lib/ui/shared/session_tree.dart)
  state machine as the main row (pending amber / running blue / done
  green / idle empty), matching the web's `SearchResultItem`. And
  `_projectPending` in the adapter took `values.last` — the most recent
  arrival — where the web `buildListSnapshot`
  (`sessions/manager.ts:1033-1039`) takes the first non-approval status,
  so a question beside an approval names the interaction the composer
  can act on; the fold now mirrors that with `firstWhere`.

## Alternatives considered

- **Keep `warning` on the `error` color and fix only the comment.**
  Rejected: it preserves a direct conflict with the reference's
  semantics — red says failure, amber says waiting — and every
  warning-colored surface (session rows, jobs, subagents) inherits the
  bug.
- **Map `warning` to `tertiary`** (the nearest unused M3 accent role).
  Rejected: the seed is brand violet, so tertiary reads violet — neither
  the web's amber nor a "needs attention" hue. A role match without the
  reference's color is a new deviation, not a fix.

## Consequences

- The role table has a warning row, and `scheme.warning` is a legal
  call-site color beside `scheme.success`; job rows mapped to
  `StateDotState.warning` (stopping, killed) now read amber, as the
  web's warning StateDot does.
- Evidence: `session_tree_test.dart` pumps the warning dot under both
  `DshTheme.light()` and `DshTheme.dark()` and asserts the core reads
  back `scheme.warning` and not `scheme.error`, and asserts the search
  row runs the four-way state machine; the adapter integration test
  decodes approval+question frames through the real fold in both
  arrival orders and asserts the projection is the question (and falls
  back to the lone approval once the question resolves).
- Notes and code now agree on amber; the false "no warn token" claim
  exists nowhere on disk.
