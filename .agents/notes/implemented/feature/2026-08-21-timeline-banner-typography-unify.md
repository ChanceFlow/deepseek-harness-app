# Agent Note: Timeline banner typography — unify agent-action rows to 14px

Status: implemented

## Problem

The agent-action banner rows of the chat timeline rendered their labels at
mixed sizes: the Think (reasoning) and Recall/Context-injection rows and the
Compaction row used `bodySmall` (12px), while the Tool-call row title already
used `bodyMedium` (14px). Side by side the mismatch was visually obvious —
"读取" and "思考" read at different sizes even though both are the same kind
of row chrome. The expanded bodies, turn boundary (11px caption), and the
turn group header (12px) were not part of the complaint.

## Decision

Unify the **collapsed banner chrome** of all agent-action rows to the web
reference size — `bodyMedium` (14px), matching the Tool-call title that
already sat at 14px and the web rows' 14px/24px rhythm. Per-row label ink
(`labelSecondary` / `labelPrimaryDimmed` / `labelTertiary`, error ink for a
failed tool summary) is unchanged; only the text role moves from `bodySmall`
to `bodyMedium`.

Changed rows:

- `ReasoningRow` (Think): title and collapsed summary.
- `ContextInjectionRow` (Recall / Context injection): role label, producer
  label, and summary.
- `ToolCallRow`: summary and parallel-active suffix (title was already
  `bodyMedium`; its monospace stack stays — a documented choice in the
  restyle note).
- `CompactionRow`: title and shadowed-count text.

Explicitly out of scope, per the user's selection:

- Expanded bodies (reasoning body stays `bodySmall`, context-injection body
  stays markdown).
- `TurnBoundaryRow` (11px letterspaced caption) and `TurnGroupHeader`
  (12px) — structural chrome, not banner labels.

## Alternatives considered

- Unify to 12px (`bodySmall`) across all rows: rejected — it would shrink the
  Tool-call title (14px) and diverge from the web reference (14px/24px).
- Unify 14px including structural chrome and expanded bodies: rejected — the
  user scoped the change to banner labels/titles/summaries only; structural
  rows have their own quieter roles.
- Drop the Tool-call title monospace: rejected — monospace is a deliberate
  font-family choice from the restyle note, not a size inconsistency.

## Consequences

- All collapsed agent-action rows now share one 14px banner label size; the
  timeline's horizontal rhythm reads consistently.
- Color roles are untouched, so no token or theme change was needed.
- Widget tests exercise the rows through the real screen path and pass; no
  test pinned the old sizes.
- Future banner labels should use `bodyMedium` unless a row has a documented
  reason for a different size.
