# Agent Note: Compaction marker and lifecycle reference parity

Status: implemented

## Problem

The mobile client's compaction display diverged from the reference web implementation (`CompactionItem.tsx` and `CompactionCommandCard.tsx`):
1. **Ad-hoc copy**: `CompactionRow` used handcrafted English and Chinese strings (`"Context compacted"` and `"Compacted N history items"`) omitting token count approximations and standard fallback states.
2. **Missing token counts and summary body**: `TimelineCompaction` only stored `shadowedCount`, discarding `shadowedTokenCount` and the markdown `summary` content emitted in `compaction/summary` wire events. The row rendered as an inert 24px label rather than an expandable disclosure displaying summary markdown.
3. **Incomplete `/compact` running state**: `CommandRow` rendered only the bare command name (`/compact`) with an activity dot during execution, lacking the `message.compaction.running` localized status copy (`"Compacting context…"` / `"正在压缩…"`).
4. **Duplicate injection risk**: The replacement `user/message` checkpoint event carrying `source.plugin = 'compact'` was not explicitly filtered in the timeline reducer, risking redundant context injection items in the transcript.

## Decision

Reconciled the domain model, adapter fold, and UI components against the reference contracts:
- **Domain model** (`TimelineCompaction` in `packages/domain/lib/model/timeline_item.dart`): Added nullable `shadowedTokens` (`int?`) and `summary` (`String?`). Expandability is derived dynamically via `isExpandable => summary != null` without storing a redundant boolean.
- **Adapter decoding and validation** (`TimelineReducer` in `packages/harness_adapter/lib/src/timeline_reducer.dart`): Compaction data is parsed from the `compaction/summary` log event. Malformed `shadowedSeqs`, `shadowedTokenCount`, and `summary` fields throw `FormatException` (fail-loud contract), while missing fields yield null. Replacement `user/message` checkpoint events matching `source.plugin = 'compact'` and non-null `compactionId` are filtered out.
- **Bilingual localization** (`app_en.arb` and `app_zh.arb`): Added verified keys matching reference `message.compaction.*` entries:
  - `contextCompacted`: `"Context compacted"` / `"上下文已压缩"`
  - `compactionRunning`: `"Compacting context…"` / `"正在压缩…"`
  - `compactionCompleted`: `"Compacted {items} history items (~{tokens} tokens)"` / `"已压缩 {items} 条历史记录（约 {tokens} tokens）"`
  - `compactionViewSummary`: `"View compaction summary"` / `"点击查看压缩摘要"`
  - `compactionSummaryUnavailable`: `"Compaction summary unavailable"` / `"压缩摘要不可用"`
- **Compaction disclosure row** (`CompactionRow` in `app/lib/ui/chat/chat_screen.dart`): Implemented as a stock Material 3 `ExpansionTile` with `isExpandable` gating `enabled` and `showTrailingIcon`. When `shadowedCount` and `shadowedTokens` are both present, renders the items + tokens caption. When counts are absent, follows reference fallback order: `compactionViewSummary` when expandable, otherwise `compactionSummaryUnavailable`. Expanded body renders `MarkdownText`.
- **Command running row** (`CommandRow` in `app/lib/ui/chat/chat_screen.dart`): When `command.name == 'compact'` is running, renders `/compact` followed by `compactionRunning`. Settled outcomes without checkpoint retain handler-authored outcome text.

## Alternatives considered

- **Retaining handcrafted single-count strings**: Rejected — diverging from upstream web locales produces inconsistent terminology and hides token savings from the user.
- **Empty expansion tile when summary is absent**: Rejected — reference `CompactionItem.tsx` explicitly disables expansion when `summary === null` rather than showing an empty container (`expandable = node.summary !== null`).
- **Introducing a session projection channel for compaction**: Rejected — examination of host `SessionProjectionMap` proved compaction data travels purely via log events (`compaction/summary`), not through host session projections.

## Consequences

Compaction displays across manual `/compact` and automatic transactions mirror reference web behavior and locale copy. The transcript renders structured items/tokens counts, allows interactive expansion to read the markdown summary when present, remains inert when truncated, and preserves fail-loud decoder guarantees for corrupted wire frames.
