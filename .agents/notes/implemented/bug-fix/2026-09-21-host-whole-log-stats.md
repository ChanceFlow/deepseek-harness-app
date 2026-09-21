# Agent Note: The stats line reads the host's whole-log projections

Status: implemented

## Problem

`session_stats_fold.dart` re-implements the host's whole-log conversation
figures by folding the **loaded window**: `_statsFold.reset(_history)` runs on
every window change, and its value is what `observeSessionStats` publishes. So
the composer's stats line under-reported a fresh open, grew as more history was
paged in, and jumped while scrolling — exactly what the host's own projections
exist to prevent. The reference states it twice: `sessionStats` is "whole-log
conversation figures, independent of how much history a client has paged in"
(`packages/session/session-stats/src/types.ts`), and `tokenUsage` is
"accumulated across the complete durable log"
(`packages/llm/token-meter/src/projection.ts`); its stats pills say "every
figure rides the durable sessionStats projection, so paging and compaction
cannot change any of them; an assembly without the unit falls back to the
window-scoped fold wholesale" (`ui-chat/src/client/chat/StatsPills.tsx:319-326`).

A live probe of the 0.1.5 host (read-only, `session/list`) confirms both keys
are published per session: `sessionStats` `{turns, steps, llmMs, toolMs,
ttftMs, ttftSteps, decodeMs, decodeTokens}`, `tokenUsage`
`{uncachedInputTokens, outputTokens, cacheReadTokens, cacheWriteTokens}`.

## Decision

Both keys join the projection keys and ride the existing watermark, so a stale
baseline or list row cannot move them either. `_parseHostSessionStats` and
`_parseHostTokenUsage` decode them into the domain's `SessionWindowStats` — the
model already carried the host's field set (turns/steps/llmMs/toolMs/ttftMs/
ttftSteps/decodeMs/decodeTokens plus the billing sums), so no model change was
needed.

**Each half governs its own fields.** `_SessionState` keeps the two halves
separately (`_hostSessionStats`, `_hostTokenUsage`) and publishes a merged value
whose counters come from the host's `sessionStats` when it published one and
from the fold otherwise, and whose billing fields come from `tokenUsage` the
same way. A host that publishes only one of the two still gets the other figure
right instead of showing zeros, and an assembly that publishes neither keeps
today's fold wholesale.

**Billing keeps the reference's arithmetic.**
`SessionWindowStats.billedInputTokens` is
`uncachedInputTokens + cacheReadTokens + cacheWriteTokens` — the reference's own
`billedInputTokens` helper, and the denominator its cache-hit share divides by —
so the collapsed line's two figures and its percentage match the web client's.

**A complete baseline clears both halves.** A control baseline block omitting
`sessionStats`/`tokenUsage` means the host no longer publishes whole-log
figures, so the window fold governs again; the existing complete-block clearing
path calls `applyHostStats(clear: true)`.

`_SessionState` gained `refreshStats()`, and the five places that published
`_statsFold.value` directly now call it, so there is one publication point for
either source.

## Alternatives considered

- **Drop the fold and read only the host.** Rejected: an older host, or a
  deployment whose assembly omits the units, would then show zeros; the
  reference keeps the fold as its own fallback for exactly that case.
- **Publish the host value only when both halves are present.** Rejected: it
  couples two independent keys — a host with `sessionStats` but no `tokenUsage`
  would report window-scoped token totals while its counters were whole-log.
- **Model `uncachedInputTokens` and `cacheWriteTokens` on the domain model now,
  to add their detail rows.** Deferred: the collapsed line shows the same two
  figures and the same percentage either way; the detail rows are their own
  change on `StatsLine`.
- **Keep folding and merge the host value on top.** Rejected: a merge would
  have to pick a winner per field anyway, which is the per-half rule stated
  explicitly here.

## Consequences

- A session's turn/step counts, LLM and tool wall time, first-token and decode
  figures, and token totals no longer move when history is paged; a fresh open
  reports the durable totals immediately.
- New tests cover the host projections governing the line (including the summed
  billed input and the 90% cache-hit share) and a session the host reports no
  figures for keeping the fold.
- Live evidence is the read-only probe above; no host state was changed.
- Remaining gaps in this area, recorded in the parity backlog: the detail rows
  for cache-write and uncached input are not rendered, and `turnOutline` is
  still unread, so there is no turn rail or jump.
