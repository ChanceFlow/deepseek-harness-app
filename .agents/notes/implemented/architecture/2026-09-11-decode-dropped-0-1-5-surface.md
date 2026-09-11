# Agent Note: Decoding the host surface the client dropped on 0.1.5

Status: implemented

## Problem

The pinned `dsh-v0.1.5-rc.2` host emits session events and forwarded Remote
events the Flutter adapter had no fold for, so each was invisible or
approximated from the wrong source.

- The slash-command roster was a frozen five-entry list, hiding
  host/plugin-registered commands; `pluginInventory/list` was unwired while
  `docs/spec.md` claimed plugin management was not a wire capability.
- A `cordis_run` call whose plugin ships a browser half blocks host-side on a
  `cordis/request-run` round trip the forwarded-event fold dropped, stalling
  the turn with no affordance.
- The reducer re-derived tool rows from raw args, ignoring each tool's
  persisted `output.presentationMeta`, and dropped the `hook/invoked` /
  `hook/result` audit pair, `sandbox/mode`, `schedule/change`, and the four
  `tool-workflow/*` run events. Sandbox state was inferred by string-matching
  `"file access denied"` in tool text.

## Decision

Each surface gets a hand-written decoder whose required fields throw with the
field name, a `ChatRepository` method using `domain` types only, and a reducer
fold:

- `commands/list` → `listCommands(agentId)` returning `CommandDescriptor`
  (`inputHint == null` is the wire's bare-only signal); `commands/change`
  ticks `observeCommandRosterChanges`.
- `cordis/request-run` / `cordis/request-run-resolved` → `CordisRunRequest` /
  `CordisRequestResolved` behind `observeCordisRunRequests`, answered by
  `resolveCordisRunRequest(requestId, CordisRunResolution)` →
  `dynamicCordisRunner/resolveRequestRun`. Rejection is the deliverable arm:
  an approval names a `pluginRunId` only a runtime that loaded the plugin's
  browser half can produce.
- `tool/result.meta` → sealed `ToolResultPresentation` (`read`, `diff`,
  `search`, `web`, persistent-terminal viewport) attached to
  `TimelineToolCall.presentation`. Diffs are read-only, matching the
  reference. No `{for: 'call'|'result'}` `view` envelope exists at 0.1.5:
  `SessionWireEvent` admits a closed key set, `assertSessionWireEvent` rejects
  any other member, and a live `session/page` probe carried no `view`.
- `hook/invoked` + `hook/result` → one `TimelineHookAudit` row paired by
  `handlerId` (log-only, no `surfaceOp`).
- `sandbox/mode` → `SandboxModeFact` via `observeSandboxMode`;
  `schedule/change` → the active `ScheduleReminder` list via
  `observeSchedules` (create/delete/dispatch; a fixed-rate record advances to
  its next anchor-aligned target). The schedule fold is window-tolerant — the
  reducer replays a history page, so a delete/dispatch naming a record created
  before the page is a no-op, while window-independent contract violations
  still throw.
- `tool-workflow/*` → one `TimelineWorkflowRun` keyed by `runId`. Updates
  arriving before the unique `run-start` stay pending; a run whose turn closed
  with no terminal event presents as `interrupted` for the run and its
  unsettled members, leaving its tool result row untouched.
- `pluginInventory/list` → `PluginInventorySnapshot` via
  `listPluginInventory`.
- `TimelineMessage.stepStartedAtEpochMs` carries the owning `step/start`
  event's logged time (the reference's `stepStartTime`) and
  `TimelineTurnBoundary.startedAtEpochMs` / `endedAtEpochMs` the `turn/start`
  / `turn/end` times, so TTFT and turn wall time are derivable; a field whose
  event fell outside the folded window stays null.

The reducer's switch names every newly covered type; any other type still
reaches the unrecognised-event diagnostic.

## Alternatives considered

- **Add the `view` field item 3 describes.** Rejected: no such payload exists
  on the wire, per the closed `SessionWireEvent` envelope and a live
  `session/page` probe. The persisted `meta` is the real, replayable
  equivalent.
- **Keep sandbox inference from `"file access denied"`.** Rejected: that text
  is a model-facing marker; `sandbox/mode` is the durable state.
- **Model the Cordis approval as a boolean.** Rejected: the wire union is
  `{ok, pluginRunId, waitingFor?}` / `{ok: false, reason, …}`; a boolean
  cannot name the activation the host validates the answer against.

## Consequences

- Six new endpoint constants; the wire-pin coverage block and README count
  move to 52 of 84 (`commands/list` leaves the out-of-scope list).
- A pending Cordis request cannot survive a `$events` generation boundary
  because forwarded `emit` items are not replayed; the web panel re-derives
  them from `dynamicCordisRunner/inventory`, which stays unwired here.
- The pinned `dsh web` deployment composes no `schedule` session projection (a
  live `session/list` probe carries no `schedule` key), so the durable
  `schedule/change` stream is the only source; a reminder created before the
  loaded history page stays unknown until its create folds.
- `bash` persists no `presentationMeta`, so its terminal card remains derived
  from result text, as in the reference.
- The `TimelineHookAudit` and `TimelineWorkflowRun` transcript arms render:
  the hook audit is one collapsed row at its own log position (a deny reads
  next to the tool row it explains), and the workflow run is a collapsible
  card whose member rows open that member's child transcript on the existing
  subagent route. The sandbox-mode fact rides a read-only composer chip beside
  the access preset, and the reminder set rides a dock strip. Placement and
  honesty rules are owned by
  [the session-facts note](../feature/2026-09-11-session-facts-surfaces.md).
