# Agent Note: Transcript rows are keyed by identity

Status: implemented

## Problem

The transcript matched its children by index and keyed each row with its own
transient state. A history page prepended above therefore re-inflated every
mounted row and took each element's `State` with it: an open activity fold
closed, the running row's clock restarted, and the persisted tool-row expansion
key moved with the call's status, so a fold the reader had opened was restored
under a key that no longer existed. Two rows could also share one identity — a
step's reasoning-only and reply-only projections carried the step's own id — and
the list then handed the second row the first row's element.

## Decision

Every transcript row takes one key derived from its kind and its own id, and
`transcriptRowKey` is the only source: items (`<kind>:<id>`), turn-process
sections (`turn-process:<ordinal>`), steering rows, both sentinels, the
older-history row (which had no key at all), and activity phases
(`window:phase:<n>`, an ordinal counted from the top of the loaded window, so a
Turn boundary arriving does not rename a phase). Transient state — a message's
streaming flag, a call's status — is deliberately not part of it; the tail's
follow signal names that state instead, so the behaviour the old key implied is
unchanged.

The list resolves a key to its index (`findItemIndexCallback`), and both the
transcript and a phase's member list build that index through one
`indexRowsByKey`, which throws when two rows share an identity rather than
letting the second take the first's element. Fold state lives in the
identity-keyed store the tool rows already use, read on mount and written on
toggle, so the reader's fold survives even a re-parent no key can prevent: a
phase becomes a child of a Turn section when its boundary enters the window,
and persistence is what carries the state across that remount.

Two identities were repaired rather than disambiguated: a step with reasoning
and a reply renders as `reasoning:<id>` and `message:<id>`, because one row kind
per rendered row is what identity means; and `TimelineHookAudit` gained `seq`,
the per-event sequence the reducer already tracked (the payload's `handlerId` is
not per-invocation).

## Alternatives considered

Keep positional keys and restore fold state from a side map: rejected — the
reader's fold is element state, and a second source of truth would drift.
Keep the transient state in the key: rejected — it re-keys on every settle,
which is the defect. `AutomaticKeepAliveClientMixin` on every row: rejected — it
hides the missing identity and pays memory for every row in a session.
Name a phase by the row above it: rejected — stable against a phase's own
members, but a prepend that changes that row re-keys the phase, which is the
case this phase exists for.

## Consequences

On one probe, a front insert went from re-inflating every mounted row (13/21/29
per page, with the running row's `State`, clock and fold all lost) to
re-inflating only the rows the page added (8/8/8, all three preserved). The raw
build count per insert is unchanged: reducing it belongs to the long-session
phase.

Accepted and pinned by test: a prepend that adds a phase above shifts every
later phase's ordinal, and the stored fold entry then belongs to another phase —
the price of naming a phase by its position in the window, which is also what
keeps a Turn boundary's arrival from renaming it.

The hook audit's two halves pair on the earliest unsettled invocation of a
handler rather than the first match by `handlerId`, so a handler that fires
twice inside one window no longer shows one row wearing the other's decision
and one stuck at invoked. The running row's clock re-arms when a Turn's start
arrives on a mounted row, which the verifier reached through the real widget.

The tool-row expansion key is persisted, and its format changed
(`tool:<id>:<status>` → `tool:<id>`): a fold saved by an older build is not
restored after the upgrade. The old format was unstable by construction. Phase
and Turn-section entries are stored under window-relative ordinals as well, so
loading a window at a different start can map a stored entry onto another
phase.

Still index-matched, with the same one-line fix, outside this phase: the
composer's queue dock and [subagent_screen.dart](../../../../flutter/app/lib/ui/subagents/subagent_screen.dart).

No visual change: 111 of the 115 design shots are byte-identical. The four
`turn-process-live*` shots capture a live sweep and vary between renders of one
revision, so they are evidence for neither identity nor difference.
