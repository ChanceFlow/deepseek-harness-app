# Agent Note: Chat timeline native component adoption

Status: implemented

## Problem

The chat timeline rows were hand-rolled ports of the dsh web chrome: manual
`InkWell` + `setState` expand/collapse with custom arrow icons, hand-drawn
question-option checkboxes and number chips, and zero native Material
components beyond buttons and progress indicators. The app shipped no
`ExpansionTile`, `ListTile`, `RadioListTile`, or `CheckboxListTile` anywhere,
so the timeline missed native ripple, focus, disabled, and selection
semantics and the M3 expansion animation. The user decided to keep the
deepsuite visual identity but adopt native components for the timeline row
chrome.

## Decision

Timeline row chrome rides native Material components, themed to the
deepsuite flat visual via new component themes in `DshTheme`:

- `ExpansionTileThemeData`: transparent backgrounds, no M3 card shape,
  label-toned text/icon colors, `childrenPadding` left 20 carrying the
  web IN/OUT inset.
- `ListTileThemeData` + `RadioThemeData` + `CheckboxThemeData`: the
  question-card option rows keep the web option fill on selection
  (`interactiveBgHover`), the radio uses the deepsuite accent, and the
  checkbox uses the on-surface fill with the foreground check of the
  hand-drawn seats they replace.
- `ReasoningRow` (the agent Think disclosure): `ExpansionTile`; the
  collapsed summary hides while expanded (mirrored via
  `onExpansionChanged`), preserving the web disclosure contract.
- `ToolCallRow`: `ExpansionTile` driven by an `ExpansibleController`;
  the `ToolExpansionPersistence` restore calls `controller.expand()` and
  user toggles write back through `onExpansionChanged`.
- `ContextInjectionRow`: `ExpansionTile`, converted from StatefulWidget
  to StatelessWidget (no expansion state left to own).
- Question option rows: single-select `RadioListTile` under a
  `RadioGroup<String>` (the 3.47 non-deprecated API), multi-select
  `CheckboxListTile`; the recommended badge and option descriptions stay.
  Each option row wraps in a transparent `Material` because `ListTile`
  paints its ink on the nearest Material ancestor and the question card
  behind it is a decorated container.

Retained as custom: `OutlineTimeline`/`TurnGroupHeader` turn collapse
(controller-owned `collapsedTurns` must survive scroll; `ExpansionTile`
state would fight the controller and `ExpansionPanelList` layout does not
fit the ledger), `MessageRow` bubble and `_StreamingCaret`, boundary
micro-labels (`TurnBoundaryRow`, `CompactionRow`), status dots, and the
`SweepHighlight` streaming glare (no native shimmer). `MarkdownText` and
its parser stay (see the markdown decision below). The custom-answer input
row keeps its hand-drawn leading seat: it is a typing surface, not a
selectable option.

## Alternatives considered

- Full Material 3 default look for the timeline (abandon web parity):
  rejected — the user chose deepsuite visual with native components, not
  a re-skin toward M3 defaults.
- Replacing `MarkdownText` with `flutter_markdown`: deferred — the
  streaming unclosed-fence state (`CodeBlock.open`) and per-pixel style
  control remain genuinely custom needs; [ADR-0001](../../../../docs/adr-0001-flutter-rewrite.md)
  records the original choice. Factual correction recorded here: the
  ADR's claim that `flutter_markdown` is discontinued is wrong — pub.dev
  shows it actively maintained (0.7.7+1, 2025-05) with no discontinued
  flag, and the underlying `markdown` parser is active (7.3.1, 2026-03).
  ADR-0001 stays as the dated historical record; this note carries the
  current state.
- `ExpansionTile` for turn groups: rejected — `initiallyExpanded` does
  not react to later external changes, so controller-owned collapse state
  would desync.
- `ExpansionTileController` (deprecated typedef): rejected in favor of
  `ExpansibleController`, its replacement (analyzer-clean).
- `maintainState: true` on expansion tiles: rejected — children removed
  while collapsed matches the old `if (_expanded)` behavior exactly, and
  ToolCallRow scroll persistence is already covered by the local-state
  restore path.

## Consequences

- Native ripple, expansion animation, focus/disabled handling, and radio/
  checkbox selection semantics now serve the timeline; the visual stays
  deepsuite-token-driven with no new color values. The row look itself
  remains as decided by the
  [chat timeline restyle](2026-08-20-chat-timeline-restyle-proposal-a.md)
- The web-fidelity deltas are small and deliberate: the trailing arrow is
  the M3 24px control (was a 14px custom glyph), selected option rows drop
  the 1px `borderL2` ring (fill only), and compact rows use the native
  dense geometry. No golden tests exist in the repo; acceptance is the
  behavior suite plus a device spot-check.
- Widget tests pin the new machinery through real entry paths: two new
  chat-screen tests cover the persisted-expansion restore and the
  collapse write-back; the existing tap-to-expand, RadioGroup single-
  select, and CheckboxListTile multi-select tests pass unchanged.
- The `_QuestionCheckbox`/`_QuestionNumberChip` widgets remain only for
  the custom-answer input row.