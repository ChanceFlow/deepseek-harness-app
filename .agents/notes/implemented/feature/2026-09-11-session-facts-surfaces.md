# Agent Note: Rendering the session facts 0.1.5 decodes but never showed

Status: implemented

## Problem

The 0.1.5 wire pass decoded four families — durable workflow runs
(`tool-workflow/*`), hook audits (`hook/invoked` + `hook/result`), the sandbox
mode (`sandbox/mode`), and durable reminders (`schedule/change`) — into
`domain` types behind `ChatRepository`. The UI pass that followed left the two
transcript arms drawing `SizedBox.shrink()` and the two streams with no
consumer, so a blocked `PreToolUse` deny still read as an ordinary tool
failure, a fan-out run was invisible, and nothing named the session's
confinement level or its pending reminders.

## Decision

**Workflow runs render as a transcript card** (`workflow_run_row.dart`). The
header carries the run name, the member count and the status dot; the phases
are collapsed until asked, and each phase is a Material `ExpansionTile` whose
body is its member rows. The status vocabulary is the reference's: `running` /
`completed` / `failed` / `cancelled` / `interrupted`, with `interrupted` on the
warning state, not the error state. A member row whose child session id is
known pushes `SubagentRecordRoute` — the subagent surface the catalog already
pushes, pointed at the parent session and the member's child. The route resolves
the child's catalog mode from the parent's `subagent.list` row, because
`subagent.history` refuses a mode mismatch; a child the host no longer lists
stays a plain row rather than a seat that can only fail.

**Hook audits render inline in the turn** (`hook_audit_row.dart`), collapsed
to one line naming the point, the decision and the duration, expanding to
point, dialect, matcher, decision, exit code and stderr summary. The reference
renders nothing for this log-only family; the row exists because the deny's
value is its adjacency to the tool row it explains.

**The sandbox mode rides the access chip's tooltip**
(`sandbox_mode_fact.dart` + `PermissionSelectChip.tooltipDetail`). The chip is
already the composer's "what may this session touch" seat; a preset composes a
sandbox mode with an approval policy, so the effective `sandbox/mode` fact can
differ from the preset's own name and needs its own line. The line states the
mode when `sandbox/mode` has folded and otherwise says the fact is unreported:
never a default, never blank.

**Reminders render in the input dock** (`schedule_reminder_strip.dart`): one
collapsed header line with the count, the next target and an overdue count,
expanding to at most four rows of prompt plus local target and frequency. The
reference puts the catalog behind a session-header action; a 360dp bar has no
room for that popup, and the dock already owns the standing strips (todo, goal,
queue). An absent `schedules` publication states that the host reported
nothing; only a published empty list says "None active".

`ChatController` binds both session streams in `_bindSelected` and republishes
them on `ChatUiState`; the rebind reset keeps the leaving session's facts from
flashing under the entering one.

## Alternatives considered

- **A hook-audit row in the trajectory ledger only.** Rejected: a ledger
  record is a flat scan line, so the decision, exit code and stderr summary
  have no seats, and the deny loses its position beside the tool row.
- **A dedicated sandbox chip beside the access chip.** Rejected: the left
  group already fills a 320dp dock with its three seats, so the chip either
  forced the access chip to drop its label or ran the row into overflow.
- **A sandbox seat in the session header.** Rejected: the compact bar is
  icon-only and its overflow menu is session verbs; a confinement fact beside
  rename/archive reads as an action.
- **Hiding the sandbox line while the fact is unknown.** Rejected: the tooltip
  is always present, and a line that appears only after a runtime switch reads
  as "the mode changed", not "the mode was always unknown".
- **Rendering a deployment default for an absent sandbox fact.** Rejected: the
  effective mode is `override ?? deployment default`, and that default is a
  host-side composition this client cannot read; any value would be invented.
- **Opening every workflow member's child eagerly.** Rejected: a finished
  run's member ids are not guaranteed to be addressable, and the web client
  pre-filters to running subagents. This client opens on demand and surfaces
  the host's refusal on the subagent error banner.

## Consequences

- `ChatUiState` carries `sandboxMode` (a `SandboxModeFact?`) and `schedules`
  (a `List<ScheduleReminder>?`); null is the unreported state for both, never
  collapsed into an empty value.
- The composer's action row, its two-line wrap cuts, and the access chip's
  footprint are unchanged: the sandbox fact costs one tooltip line, not a seat.
- `SubagentController` gains `initialChildId`, resolved once the parent's
  catalog publishes the child's row; the jump reuses the existing subagent
  route, adding no navigation mechanism.
- The reminder strip is window-tolerant like its fold: a reminder created
  before the loaded history page stays invisible until its create folds.
- [The 0.1.5 decode note](../architecture/2026-09-11-decode-dropped-0-1-5-surface.md)
  no longer calls the two transcript arms placeholders.
