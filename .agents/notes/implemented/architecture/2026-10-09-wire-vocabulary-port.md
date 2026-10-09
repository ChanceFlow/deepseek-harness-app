# Agent Note: The last five unwired wire names reach the client fold

Status: implemented

## Problem

`docs/spec.md` §6.1 recorded nine dsh names the adapter reported as
`timeline.event` debug. Five were the reference client's own folds that this
client never made, so a reader saw gaps the reference does not have: steering
provenance on a human message admitted into a live turn, the step boundary
that separates a step's process from its answer, a turn's changed-file
announcement, the chat turn rail, and a subagent's active-turn timing.

Three were not ports at all — `team/task`, `team/message/queued`, and
`team/message/delivered` are journal events the reference folds **host-side**
into the `agentTeam` projection this client already decodes — and
`sessionListMetadata` is host-folded into the list row's `blank`/`updatedAt`,
which `SessionWire` already reads.

## Decision

Each port folds the reference's fact into the domain surface that already
carries that kind of fact, rather than inventing a parallel one.

* `agent/inbox/spliced` (`packages/core/agent/src/types.ts:96-102`) replays
  the durable pending next-turn/next-step lists. A later `user/message` whose
  id the `next-step` list claimed sets `TimelineMessage.steering`, mirroring
  the reference's `SteeringHistory.apply` — including that a claim is consumed
  by the message it names whatever that message's source kind, that an
  inserted identity stops being claimed, and that `outcome: 'canceled'` never
  claims.
* `step/end` (`packages/core/session/src/types.ts:301`) sets
  `TimelineMessage.stepEndedAtEpochMs`/`stepEndSeq` on the step's own
  assistant row, the reference's `stepEnd`. The row is found after the turn's
  own boundary, so a later turn reusing the step number cannot borrow it, and
  a step that assembled no message folds nothing. The stats fold keeps owning
  the step's count (`session_stats_fold.dart`), so nothing is counted twice.
* `workspace/changes` (`packages/deliverables/workspace-changes/src/types.ts:106`)
  sets `TimelineTurnBoundary.changesSeq` to the turn's latest announcement,
  the reference's `deliverables` node state; the summary itself stays on the
  host, served for that sequence while the Session lives.
* `turnOutline` and `subagentTiming` are session projections like the keys
  already folded: the value arrives on the history baseline, the
  `session/projections` read, and live `session/projection` frames, and each
  key gets a per-Session stream — `ChatRepository.observeTurnOutline`
  (`List<TurnOutlineEntry>`) and `observeSubagentTiming`
  (`SubagentTiming?`).

Every decoder fails loud on a malformed value — a `step/end` without its turn,
a `turnOutline` whose turns do not strictly increase (the host's own
`superRefine` invariant), an `active` interval without both ends. The
repository contains that failure as an adapter diagnostic and keeps the last
good value, the same posture the other projection folds take: a bad frame
never empties a surface.

`SettingsNamespace.base` is filled in the same change: the descriptor
publishes the redacted composition base layer
(`packages/settings/settings/src/index.ts:329-330`), and
`SettingsNamespaceWire` now decodes it instead of leaving the domain field
declared and never set.

## Alternatives considered

**Add a new `TimelineItem` variant per fact.** Rejected: each of the three
event facts belongs to a row that already exists (a message, a step's message,
a turn boundary), and a new variant would force every UI switch to grow a row
nothing yet renders.

**Fold `step/end` into the stats fold's accounting too.** Rejected: the stats
fold already counts the step; a second count would double the figure the
turn boundary sums.

**Port the three `team/*` events.** Rejected: the reference client has no
consumer for them — its client-side surface is the `agentTeam` projection,
which this client decodes — so folding them would invent a representation the
reference does not have.

**Leave `base` declared and unfilled.** Rejected: a declared-never-filled
field reads as data the host sends; it is either decoded or removed, and the
pin publishes it.

## Consequences

`docs/spec.md` §6 lists the three event folds beside the other folded events,
and §6.2 records the two projection keys with their domain accessors; §6.1
keeps only the four names that are not ports, with the reason each is not.

`scripts/verify_wire_pin.py` compares endpoint names, so the port moves no
coverage count and the gate stays clean. The rendering half — a steering
badge, a step's process range, a turn's changed-file card, the rail, a
child's timing — is the UI's; this change lands the facts and their tests.
