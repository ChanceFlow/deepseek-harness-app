# Agent Note: Projection watermarks and a replacing control baseline

Status: implemented

## Problem

Two ways session state could go backwards or stay stale.

**No ordering rule.** `_handleProjection` read the frame's `seq` and used it
for two keys only (`contextPressure`, `contextBreakdown`, with `<`); title,
goal, plan, todos, permissions, agentPreset and modelSelection were written
unconditionally, and `_applySessionProjectionValues` guarded nothing.
`refreshSessions()` runs on every `turn/end`, so a `session/list` response
captured before a rename or a todo write could land afterwards and revert the
visible value — the reference's projection store drops exactly that with one
rule, `if (row !== undefined && seq <= row.seq) return`
(`api/session-controller/src/client/sessions/projection-store.ts:134-139`),
and its list fold applies through the same store
(`manager.ts:500-506`).

**A baseline was merged, not replaced.** `_handleControlBaseline` pushed each
queue/jobs block to a session state *if one existed* and never cleared the ones
the baseline omitted, so a session the client had not instantiated yet lost its
queued-message seed, and a queue that emptied (or a job that finished) while
the app was disconnected kept showing its stale rows. The reference keeps the
maps at manager level, reseeds them from every baseline, hands each
instantiated session `queues.get(id) ?? []`, and seeds a lazily created session
from the same map (`manager.ts:672-701,288-297`). Its `seed` also deletes
projection rows the baseline omits, which is how a restarted host stops showing
a goal it no longer computes.

A third, smaller defect: a JSON `null` `title` or `agentPreset` projection was a
no-op (`_copySession`'s `title ?? session.title`), so a cleared title kept its
old text.

## Decision

**One watermark, one claim.** `_projectionSeqs[sessionId][key]` holds the seq
of the value in hand, and `_claimProjection` is the only gate: a value whose
`seq` is not newer is dropped whole, never partially applied. The live frame
path and every block path (control baseline, follow opening, list row,
`api-session/added`) go through it, so a block that raced a frame loses the
keys the frame owns and still wins the ones it carries alone. The two
context-key seq maps and their special cases are gone: the watermark is the
single ordering home.

A frame with no `seq` applies as the latest write and leaves the watermark
untouched: it cannot be ordered, and seq 0 would lose to every recorded value.
The reference requires a `seq`; this is the documented posture for input the
contract does not describe.

**A complete block replaces.** `_applySessionProjectionValues(..., complete:
true)` drops watermarks above the block's cut and clears every key the block
omits, which is the control baseline only: that frame *is* the host's whole
store for the generation. The other block sources keep "apply the keys I
carry" so a partial block cannot invent a clear.

**The baseline is retained, not replayed once.** `_baselineQueues` /
`_baselineJobs` are rebuilt from every baseline; each instantiated session is
pushed its own lists (an omitted id gets the empty list that clears its dock),
and `_sessionStateFor` seeds a session that opens later from the same maps.
`_resync` clears the retained maps and the watermarks with the rest of the
generation's out-of-band state.

**A list row loses to a newer projection.** `_toDomainSession` builds rows from
the list payload, so `_loadSessions` keeps the value in hand for `title` and
`agentPreset` when the row's own `asOfSeq` is not newer than the watermark —
higher-seq-wins at the one place the row is rebuilt.

`_copySession` gains `clearTitle` / `clearAgentPreset` (mirroring the existing
`clearAgentError`) so a null projection clears instead of preserving.

## Alternatives considered

- **Add guards key by key.** Rejected: the drift is the bug; one claim point is
  what makes the next key safe by default.
- **Treat a missing `seq` as 0.** Rejected: 0 loses to every recorded value, so
  a seq-less source would silently freeze the surface it feeds.
- **Let the control baseline patch (apply listed keys only).** Rejected: the
  reference's `seed` semantics are what clear a value a restarted host no
  longer publishes.
- **Keep the held value when a list row carries no block to compare.**
  Rejected: a host that publishes no projection block is saying it holds no
  value for that session; the fixture was made realistic instead.

## Consequences

- A racing list pull, follow opening or `added` event can no longer revert a
  title, goal, plan, todo, permission or model chip; `title`/`agentPreset`
  null now clears.
- A session opened after the generation's baseline shows the messages and jobs
  it already had; a queue that emptied or a job that finished clears.
- New tests cover the dropped older frame (including a later list pull), the
  complete block clearing an omitted key, and the baseline seeding a session
  opened later.
- Remaining gap, recorded in the parity backlog: the host's whole-log
  `sessionStats` / `tokenUsage` projections are still not read; the stats line
  re-folds the loaded window.
