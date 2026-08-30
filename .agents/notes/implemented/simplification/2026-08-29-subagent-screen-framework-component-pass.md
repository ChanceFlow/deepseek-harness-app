# Agent Note: Subagents screen componentized on framework rows and one shared state dot

Status: implemented

## Problem

The Subagents screen (`subagent_screen.dart`) was rejected in review as not
following the client's design language
([flutter/app/AGENTS.md](../../../../flutter/app/AGENTS.md) "Stock Material 3
is the aesthetic"): six hand-built `InkWell` + `ConstrainedBox(minHeight: 44)`
rows instead of `ListTile`; a hand-rolled error strip with a bare
`TextStyle(color: …)` instead of a banner; the read-only composer notice
wearing a fifth radius (12) and a hairline; a row-inline 12px
`CircularProgressIndicator` contradicting the timeline's sweep-only in-flight
language ([the sweep-only note](../bug-fix/2026-08-29-timeline-inflight-sweep-only.md));
`scheme.outline` used as a text color; a `fontSize: 13` override on
`bodyMedium`; a hand-rolled 200ms `AnimatedRotation` disclosure; and
un-named repeated numbers (44, `12 + 16 * level`, gap 10, halo 0.1 / core 0.6).
The halo-plus-core state dot existed in four hand-copied forms:
`SubagentStateDot`, the jobs sheet's `_StateDot` (`job_list_action.dart`),
the session tree's `RunningDot`/`DoneDot`/`WarningDot`, and — found on
audit — `BackendConnectionDot` importing the *subagent* copy across feature
directories. The parent-picker sheet chrome duplicated
`model_select.dart`'s menu-surface card verbatim; the two decision notes
([dropdown redesign](../feature/2026-08-25-redesigned-dropdown-selectors.md),
[composer sheet sync](../feature/2026-08-26-synced-composer-sheets-to-selector-rows.md))
record that chrome as the house convention, so it stays.

## Decision

Presentation-only pass; no data behavior moved.

- **Rows ride `ListTile`** (dense, `VisualDensity.compact`,
  `minTileHeight: _kRowMinHeight`): catalog, diagnostic, parent-selector,
  sheet session, branch-loading, and branch-error rows. The branch toggle
  keeps its own ink seat inside the tile's leading row; expanded state is
  the icon swap (`chevron_right` → `expand_more`), dropping the bespoke
  rotation curve. The sheet rows get a transparent `Material` ink host (the
  session-verbs sheet's idiom) because the menu card is a decorated
  container.
- **Errors ride the native `MaterialBanner`** (inline, `errorContainer`):
  the error is a standing fact of the UI-state stream, so it renders while
  the stream carries it — not as a queued snack event.
- **The branch loading row wears the timeline's activity language**: shared
  `ActivityDot` lead plus `SweepHighlight` over the row text on the
  2600ms `ToolCallRow` period, null controller under reduce-motion.
  Centered screen-level loaders stay (the sweep-only note's exception).
- **One shared dot**: `ui/shared/state_dot.dart` — `StateDot` +
  `StateDotState {ongoing, done, warning, error}` with
  `kStateDotHaloAlpha` 0.1 / `kStateDotCoreRatio` 0.6 named. All four
  prior copies consume it; the session-tree names stay as thin seats for
  their existing callers and tests.
- **Menu-sheet chrome preserved and named**: `kShapeMenuSheet` (12) and
  `kMenuSheetMaxHeight` (520) live in `theme.dart` beside the four-step
  scale, with the redesign note cited as the fifth radius's reason; the
  subagent picker and `_SessionVerbsSheet` adopt them.
- **Shape/type alignment**: the read-only notice drops its hairline and
  wears `kShapeCard` — tone separates it from the page; the read-only
  queue dock drops the `fontSize: 13` override back to the `bodyMedium`
  role and keeps its `QueueDock`-mirrored container (see Consequences).
  `scheme.outline` as text color becomes `onSurfaceVariant`.
- **Repeated numbers named** at the screen's top with their source facts
  (Material touch minimum, web catalog `12 + 16 * level` indent, web
  disclosure seat 32, glyph–text gap 10).

## Alternatives considered

- **`ScaffoldMessenger.showMaterialBanner`**: rejected — the message is
  stream state, not an event; re-shows would queue duplicates while the
  error persists.
- **`ExpansionTile` for catalog rows**: rejected — tapping a row opens the
  child while the chevron toggles the branch; one tile carries one
  disclosure, and the branch body needs the loading/error rows outside
  the tile.
- **Reusing `chat/QueueDock` for the read-only dock, and switching
  `model_select.dart`/`job_list_action.dart` literals to the new
  constants**: deferred — `chat/` is another line's jurisdiction in this
  pass; recorded as follow-ups.
- **Folding the shared dot into `session_tree.dart`**: rejected — its
  consumers span three features plus settings; the named dots there are
  already one call deep.

## Consequences

- `subagent_screen_test.dart` gained a design-language group asserting
  rendered types (`ListTile`, `MaterialBanner`, `ActivityDot`,
  `SweepHighlight` null controller under reduce-motion, `kShapeCard`
  borderless notice) and role colors read back under both
  `DshTheme.light()`/`dark()`; every pre-existing behavior test still
  passes, and the screen now has design shots (`subagents`,
  `subagents-error`, `subagents-child`) in the review catalog.
- `BackendConnectionDot` no longer reaches into `ui/subagents/`; the dot
  family has one geometry home.
- Fact repair in place: the 2026-08-22 command-lifecycle note still
  described `CommandRow`'s running lead as a 12px progress indicator —
  that was reverted by the sweep-only note and now reads as shipped.
- Cross-links, no supersession: catalog *semantics* stay owned by
  [todos projection and subagent view](../feature/2026-08-19-todos-projection-subagent-view.md)
  and the selector-row *language* by
  [composer sheet sync](../feature/2026-08-26-synced-composer-sheets-to-selector-rows.md);
  this note owns this screen's component choice and the dot consolidation.
