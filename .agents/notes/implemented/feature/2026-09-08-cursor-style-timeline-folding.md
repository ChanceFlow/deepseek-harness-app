# Agent Note: Cursor and Windsurf style timeline folding

Status: implemented

## Problem

Consecutive tool executions and model reasoning in the chat transcript created
heavy visual clutter and consumed excessive vertical screen space on mobile.
Tool groups previously rendered with bulky boxed containers and mechanical
per-tool counters ("3 operations · bash 1 · edit 1 · read 1") rather than
semantic, human-readable activity summaries (such as "Explored 3 files, 2 searches").
Reasoning blocks lacked duration headers ("Thought 10s") and clean, distraction-free
folding.

## Decision

Aligned transcript folding with the visual paradigm of Cursor Composer and
Windsurf Cascade:

1. **Semantic tool-call aggregation**: Created `deriveToolGroupSummary` in
   `flutter/app/lib/ui/chat/tool_group_summary.dart`. It classifies tool runs
   into files explored (`read`), searches (`grep`, `glob`, `web_search`),
   modifications (`edit`, `write`), and commands (`bash`, `pwsh`). It generates
   bilingual high-level summaries such as `Explored 3 files, 2 searches`
   (`浏览了 3 个文件，2 次搜索`) when settled, and active in-flight descriptions
   (`Reading AGENTS.md`) while running.
2. **Sleek Action Chip component**: Refactored `ToolGroupRow` in
   `flutter/app/lib/ui/chat/chat_screen.dart` into a compact, low-chrome action
   chip with rounded corners (`kShapeChip`), subtle hairline border, leading
   activity indicators, and an indented vertical timeline guide line when expanded.
3. **Thought duration header**: Enhanced `ReasoningRow` in
   `flutter/app/lib/ui/chat/reasoning_row.dart` with `thoughtDuration`
   (`Thought 10s` / `已思考 10秒`) and `thinkingDuration` (`Thinking · 3s` /
   `思考中 · 3秒`), clean collapsed headers, and an indented quote guide for
   expanded thought content.
4. **Localization**: Added bilingual ARB keys to `app_en.arb` and `app_zh.arb`
   and regenerated localizations via `flutter gen-l10n`.
5. **Phase-level execution folding and modularization**: Extracted `foldTimelineActivities`
   and `TimelineToolGroup` into `flutter/app/lib/ui/chat/timeline_folding.dart`.
   Assistant messages with empty text (intermediate step thoughts or protocol
   artifacts) no longer fragment tool runs within an execution phase;
   intermediate thoughts merge into a unified thought block with cumulative
   duration, and a phase's members coalesce into one card. Standalone
   single tool calls remain direct `ToolCallRow`s to prevent double-expansion
   friction. The phase shape was later revised — the card now holds the
   thoughts and the injected-context rows too; see
   [one activity card per phase](2026-09-10-one-activity-card-per-phase.md).
6. **Wire reasoning duration derivation**: Tracked reasoning block start and
   end timestamps in `TimelineReducer` (`packages/harness_adapter/lib/src/timeline_reducer.dart`)
   to populate `ChatMessage.reasoningDuration`, ensuring historical sessions and
   live streams both carry duration headers.

## Alternatives considered

- **Fragment tool groups at intermediate thought steps**: Rejected — autonomous
  agent loops emit thoughts or empty assistant messages between steps, which
  previously broke grouping into runs of 1 and completely bypassed `ToolGroupRow`.
- **Wrap single isolated tool calls into group chips**: Rejected — wrapping a
  single tool call forces two taps to inspect output; single calls already display
  as compact rows.
- **Hardcode tool labels in widget code**: Rejected — violates the root bilingual
  ARB contract (`flutter/app/AGENTS.md`) and causes drift between locales.
- **Display raw tool lists without folding**: Rejected — autonomous agent turns
  can execute tens of consecutive tool calls, pushing conversational context off screen.
- **Retain heavy card styling**: Rejected — heavy multi-border cards visually
  dominate the transcript, breaking the light, fluid conversational flow.

## Consequences

Agent activity streams present a clean, rhythmic timeline where each
execution phase tucks into one lightweight, collapsible card. Users can tap the
card to expand its steps and inspect detailed inputs and outputs — since
[one activity card per phase](2026-09-10-one-activity-card-per-phase.md) that
card carries the phase's thoughts and injected context as well as its tool
calls.
Semantic tests and widget tests assert both the collapsed summaries and the
interactive expand/collapse transitions.
