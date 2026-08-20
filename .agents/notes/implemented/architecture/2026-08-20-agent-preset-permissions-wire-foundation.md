# Agent Note: Agent-preset and permission-select wire coverage

Status: implemented

## Problem

The composer's Access seat and the preset-mode surfaces need two wire facts
the adapter did not carry: the agent-preset roster (`agentPreset.list`) and
the per-session permission select (the `permissions` session projection).
The mobile client had no preset switching anywhere, no permission chip, and
no device-local persistence for UI state the user expects to survive an app
restart (composer drafts, reading position, expansion states, navigation
destination).

## Decision

Coverage follows the reference submodule shapes exactly
(`host/apiproxy/src/api/agent-presets.schema.ts`, `events.ts`, and
`interaction/permission-presets/src/types.ts`):

- `agentPreset.list` and `agentPreset.select` are exposed as
  `ChatRepository.listAgentPresets()` / `selectAgentPreset()`; roster rows
  decode with fail-loud required fields, and `trust` maps to a domain enum
  that rejects unknown values.
- The `permissions` projection rides the existing per-session
  `session/projection` dispatch (`_handleProjection`): a value frame decodes
  the select onto a `StateStream` behind `observePermissions`, a `null` or
  malformed frame yields null (chip hidden — the same posture as the goal /
  plan / todos projections, which tolerate bad frames by clearing), and
  unknown keys stay ignored because the projection key set is open and
  host-owned.
- `agent-preset/selected` arrives as a `host/remote-event` frame with
  `args [sessionId, agentPreset]`; it folds the session summary in place via
  `_copySession`. Other forwarded events are ignored silently for the same
  open-set reason.
- `agentPreset.read`/`copy`/`openDocument`/`remove` are loopback-pinned and
  deliberately uncovered (docs/spec.md §15): a mobile client reads the roster
  and switches blank sessions; it cannot manage preset files.

Device-local UI-state cache: `flutter/app/lib/local_state/` adds
`LocalStateStore` — a JSON document in the app documents directory (the
`BackendStore` file posture, atomic temp+rename writes) behind synchronous
cached reads. It is a UI cache, not wire data: a corrupt or unreadable
document is an empty cache rather than an error, and a failed write drops
that update silently, because every key it carries is regenerable. Writes
coalesce through a 500 ms debounce so keystroke-frequency callers cost one
disk write per quiet interval; `flush()` forces the write for tests and
shutdown paths. Values are plain JSON and keys are owned by their writing
surface (`chat.draft.<sessionId>`, `app.destination`, …).

## Alternatives considered

`shared_preferences` was rejected: another plugin dependency for a need the
existing File+JSON posture already covers, and `BackendStore` is the in-repo
precedent to mirror. Fail-loud decoding for live projection frames was
rejected because projections are push state and the established goal/plan/
todos handling clears on malformed input; failing the stream would tear down
the composer for one bad frame. Seeding permissions from `session.list`
projections was deferred: the first live frame is a sufficient first value
for the chip, and list seeding can be added when a surface needs pre-open
state.

## Consequences

The domain gains `AgentPresetEntry`/`AgentPresetRoster` and
`PermissionSelect`/`PermissionPresetOption`; `ChatRepository` gains three
seams with default implementations, so existing test doubles that `extend`
keep compiling while `implements`-style fakes must add the members.
`docs/spec.md` §15 records the coverage and the loopback omissions. UI
surfaces can now render the access chip, offer preset switching for blank
sessions, and persist their state across restarts through one store; the
store's corrupt-tolerance means a damaged document silently resets those
surfaces to defaults instead of failing them.

## Testing

`harness_repository_integration_test.dart` covers the roster decode, the
select payload+echo, the host-refusal code path, the negative fixture
(missing `authorable` throws), projection publish / last-wins / null-clear /
unknown-key-ignore, and the remote-event summary fold.
`app/test/local_state/local_state_store_test.dart` covers load gating,
roundtrip+delete, corrupt-file recovery, and flush durability.
