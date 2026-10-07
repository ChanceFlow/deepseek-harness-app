# Agent Note: The Agent Team roster and task board reach the phone

Status: implemented

## Problem

An Agent Team was invisible to this client. The pinned host publishes the Lead
session's whole team state — the durable roster and the shared, non-deleted task
board — as the `agentTeam` Session projection
(`packages/experimental/agent-team/src/projection.ts` `key: 'agentTeam'`), and
the reference web panel reads it straight out of the shared Session store. This
client's projection decoder knew `subagentCatalog`, `todos`, `plan`, `goal`,
`permissions`, `contextPressure`, `inbox`, and the stats keys, and dropped
`agentTeam` into the unknown-key path: a session running a team rendered as an
ordinary session.

Two facts made the gap more than a missing screen. The projection is the *only*
route to team state — there is no `team/*` Remote namespace, so no amount of
RPC coverage would have found it. And `TeamMemberProjection.phase` is durable
only: `running` and `inactive` are not on the wire, so a roster built from the
projection alone would have shown every active member as idle.

## Decision

Mirror the reference panel's data path and its read-only posture.

- `domain/model/agent_team.dart` carries the vocabulary: `TeamMemberPhase`,
  `TeamTaskStatus`, `TeamMember`, `TeamTask`, `AgentTeam`, and the derived
  `TeamMemberActivity` (`running` / `inactive` / `provisioning` / `failed`) with
  the derivation rule attached to the member — an `active` member reads its
  running bit from live Session status, a provisioning or failed one keeps its
  durable phase, and a Session the roster does not know reads inactive.
- The adapter decodes the value in both projection paths: the batched
  `_applySessionProjectionValues` (baseline, `session/follow` snapshot and
  `session/list` hints) and the single-key `_handleProjection` frame, which
  needed its own `agentTeam` arm.
- `observeAgentTeam(sessionId)` is the live stream; `loadAgentTeam(sessionId)`
  is the non-activating `session/projections` read that seeds it, so a panel
  opened before any control frame renders immediately instead of flashing
  hidden. Absence stays `null`: a host that mounts no Agent Teams package never
  carries the key, and an empty team must not look like an unmounted one.
- `TeamPanel` is presentation only — a real widget fed a real `AgentTeam` — and
  `TeamAction` owns the projection read, the Lead resolution, and navigation.
  The Lead is a teammate's `parentSessionId` when the conversation is a child,
  else the session itself, the same rule the reference derives from the subagent
  address. Selecting the Lead opens that session; selecting a teammate pushes
  the existing `SubagentRecordRoute` with the child id.
- The board stays read-only, as on the web: team agents mutate tasks through
  their tools, and the wire serves no client mutation. A host-rejected persisted
  record renders as a failure banner *above* the last valid roster and board.

## Alternatives considered

Build the roster from the client's own `session/list` children instead of the
projection: rejected, because the list carries no team membership, no role, no
task ownership, and no board — and a team's members are exactly what the
projection names.
Show `running` from the projection's `phase`: rejected as wrong; the phase is
durable, so an active teammate mid-turn would read idle forever.
Skip the cold `session/projections` read and rely on control frames: rejected
because the first paint after opening the panel would render nothing, and the
reference's panel is populated from a store that already holds the value.
Add task mutation controls: rejected, because the wire has none — inventing
local state would misrepresent what the team actually agreed.
Fail the whole projection on one bad row: rejected; the reference's view is
host-validated before publication, and dropping a session's entire panel over a
member field would hide a working team.

## Consequences

`declared` and `identical` are unchanged — this is a projection, not a new
endpoint — so the wire-pin block and the README coverage sentence stay put. A
phone now shows a running team and lets a person move between its members, and
the panel degrades to hidden on a host without the experimental package. The
panel is not a mailbox view and carries no message timeline: the projection has
none, which the reference documents as its own limitation.
