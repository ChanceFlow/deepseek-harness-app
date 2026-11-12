# Agent Note: The `agentTeam` decoder accepts both host contract lines

Status: implemented

## Problem

A device diagnostic report from build 0.4.1-alpha.1615 carried 84 identical
`FormatException: required field "members" missing or mistyped in [enabled,
tasks]` entries from `decodeAgentTeamProjection`. The app stayed alive — a
decode failure is contained per value, so the phone kept running — and the
on-device diagnostics feature surfaced the repeats
([diagnostics note](../feature/2026-11-12-diagnostics-log.md)).

Two host lines publish the same projection key with different fields. The app
pins `dsh-v0.2.2-rc.1` (submodule commit `66491b0`); its
`packages/experimental/agent-team/src/projection.ts` `teamProjectionSchema`
carries `{members, tasks, failure?}`. The deployed host runs the fork's
`dsh-v0.2.2-rc.1-chance.0-2` line, which already publishes the shape that
lands in `dsh-v0.2.2-rc.2` (tag dated 2026-11-11, commit `ddac967`):
`packages/team/agent-team/src/projection.ts` `teamProjectionSchema` carries
`{enabled, tasks, failure?}` — the roster moved to the subagent panel. rc.2 is
1568 commits ahead of rc.1, which is its merge-base. The decoder required
`members`, so an rc.2-shape host rejected the whole projection on every
baseline and reconnect: one malformed contract, 84 log entries.

## Decision

- `tasks` is the only required field. Both lines carry it, so absence or a
  wrong type fails loud naming `tasks`.
- `members` is optional. Absent decodes to an empty roster, the rc.2 shape; a
  present but mistyped value still fails loud naming `members`.
- `enabled` decodes through `wireBool` and defaults to false; `AgentTeam`
  carries it and equality and hash include it, so an rc.1 projection is
  unchanged.
- `DiagnosticGate`
  ([diagnostic_gate.dart](../../../../flutter/packages/harness_adapter/lib/src/diagnostic_gate.dart))
  folds identical decode failures. The key is `context|runtimeType|message`;
  the first occurrence emits, repeats inside a 60 s window are suppressed, and
  the first emission after the window carries ` (N repeats suppressed)`.
  `_tryDecode` routes `FormatException` and `TypeError` through the gate. The
  value is still rejected: fail-loud data, fail-quiet log.
- The pin stays `dsh-v0.2.2-rc.1` in this change. Hosts upgrade independently
  of the app, so the client accepts both lines; moving the pin to rc.2 is a
  separate 1568-commit parity project (its subagent control and projection
  types moved too), not a bug fix.

## Alternatives considered

- Bump the submodule pin to `dsh-v0.2.2-rc.2` in this change. Rejected on
  scope and risk: the 1568 commits cover the subagent control and projection
  types the client folds, so the bump is its own parity project. It stays the
  follow-up.
- Drop the `agentTeam` decode. Rejected: `observeAgentTeam` and
  `loadAgentTeam` are exposed `ChatRepository` methods, a host may publish the
  key, and failing loud on a malformed value is the repository contract.
- Default `members` to empty without failing a mistyped value. Rejected: a
  present but wrong-typed array is still malformed; only absence is the rc.2
  signal.

## Consequences

- One client accepts both lines: an rc.1 host renders the roster, an rc.2 host
  renders the board and the team-mode bit, and neither logs a decode
  diagnostic.
- A malformed `agentTeam` still fails its value and now logs once per window;
  the recap keeps the suppressed count visible.
- Wire coverage does not move — this is a projection, not an endpoint — and the
  pin and its digest are unchanged.
- [dsh_wire_types_test.dart](../../../../flutter/packages/harness_adapter/test/dsh_wire_types_test.dart)
  pins both shapes, a missing `tasks`, and a mistyped `members`;
  [harness_repository_integration_test.dart](../../../../flutter/packages/harness_adapter/test/harness_repository_integration_test.dart)
  pins one diagnostic for a repeated malformed projection;
  [diagnostic_gate_test.dart](../../../../flutter/packages/harness_adapter/test/diagnostic_gate_test.dart)
  pins the window and the recap.
- The
  [Agent Team roster note](../feature/2026-09-29-agent-team-roster-and-task-board.md)
  owns the rc.1 roster surface; this note owns the dual-line decode.
