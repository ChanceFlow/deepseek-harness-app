# Agent Note: A subagent child is a resident, followed window

Status: implemented

## Problem

A child transcript was one `session/page` folded into a throwaway reducer
(`loadSubagentHistory`), and nothing kept it current:

- **A running child never updated.** No follow stream existed for a child, so
  a running subagent's new tool calls and reply were invisible until the
  reader left and re-entered; the view only reloaded after a prompt this
  client itself sent.
- **Older history was unreachable.** The read asked for one 50-message page
  and exposed no `hasMore`, so a child with more than a page hid the rest.
- **The cursor was pinned to the first page.** `throughSeq` came from
  `_sessionCursors[childSessionId] ?? 999999999` and was then written back
  from the page's last row, so every later read repeated that same window —
  the child's answer to a prompt could never appear even on the reload.

The reference has none of this: a child is a resident `Session` built with its
subagent address, opened over the same journal stream, paged with the follow
opening's cursor, and exposed to the chat view like any other
(`api/session-controller/src/client/sessions/session.ts:606-621,820-824`).

## Decision

**A child's address is resolved, not hard-coded.** `_subagentAddresses` records
`{direct parent, mode}` for every child this client has seen in a catalog row —
the only place a child's mode exists (`session/list` carries neither the mode
nor a usable ordinary-session address). `_sessionAddress(sessionId)` yields the
`subagent` address when the id is known, else the ordinary session address, and
the follow request, the history page and the resync re-arm all go through it.
The child's follow uses the same `assistantStream: true` flag a session does.

**`openSubagentSession` is the child's open.** It records the address and runs
the ordinary open path, with one deliberate difference: a failed first read
**propagates**. The subagent view has a catalog to fall back to and no
in-window error seat, so its banner states the host failure where an ordinary
session keeps the empty window it already shows plus a diagnostic. `openSession`
refuses a child that has no recorded address and says so, since only the
catalog supplies the mode.

**The app reads the child's window.** `SubagentController` no longer loads a
list: it opens the child and subscribes to `observeTimelineWindow(childId)`,
which carries rows, `hasMoreOlder` and the loading flags. A prompt needs no
reload — the follow delivers the queued message, the turn it starts, and the
reply. `LoadOlderChildHistory` pages through the same `loadOlderHistory` a
session uses, and the record view carries the transcript's own older-history
seat (reusing `OlderHistoryRow`).

## Alternatives considered

- **Keep the one-shot page and poll while the child runs.** Rejected: polling
  re-reads whole pages to discover increments, costs a round trip per tick,
  and still misses the live token stream the follow already carries.
- **A separate child-window implementation.** Rejected: the child page and
  follow take the same `SessionAddress`; a second implementation would fork the
  paging, cursor and resync rules that must not drift.
- **Address children by id alone (as before).** Rejected: the host validates
  the address against the durable descriptor and answers
  `subagent/unauthorized` on a mode mismatch, and a bare id cannot carry a
  mode at all.
- **Keep the swallowed first-read failure for children.** Rejected: the old
  child path closed the record and showed the host failure; silently rendering
  an empty transcript would read as "this child said nothing".

## Consequences

- A running child now streams its output, and a child longer than one page can
  be paged; the child's window shares `session/page`, the follow cursor and the
  resync path with every session.
- Live check against a 0.1.5 host: a `session/follow` addressed
  `{kind:'subagent', parentSessionId, childSessionId, mode:'continuable'}` with
  `assistantStream: true` is accepted and answers the child's snapshot with its
  cursor, records, `hasMore` and `assistantStream`.
- `_resync` now re-arms child windows too.
- Known gaps that remain, recorded in the parity backlog: an opened child is
  never unsubscribed (the adapter still has no close verb, so browsing many
  children keeps their follows alive), `assistant/attempt` still has no fold,
  and `subagent/descriptor` / `subagent/catalog` events publish no row.
