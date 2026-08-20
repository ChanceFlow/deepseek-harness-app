# Agent Note: Slash-command dispatch through commands/execute

Status: implemented

## Problem

Tapping `plan` in the ➕ command menu (or the plan chip's exit) never
triggered the harness's plan mode: the menu inserts the literal `/plan `
text and sending rode `session.prompt`, so the model received the line
as ordinary user content. The host's prompt handler does not parse
slash commands — an orphaned doc comment on `SessionsApi.prompt`
claims it does, but the handler (api-proxy.ts `sessions.prompt`)
creates a user message and follows up, no command registry involved.

Empirical ground truth against a live host (throwaway session):
`session.prompt` with one text block `/plan off` produced a model turn
reasoning about the text; `commands/execute` with
`args {agentId, line: '/plan', images: []}` produced
`command/run` → `plan/mode {active: true}` → `command/done` and never
touched the model.

## Decision

The dsh command system (reference): `CommandRuntime`
(packages/interaction/commands) is the registry — `parseCommand`
grammar `/^\/([a-z][a-z0-9_-]*)(?=$|[\t\n\r ])/`, guarded handlers,
`command/run`+`command/done` lifecycle events. Clients dispatch through
the typert remote bridge `commands/execute` (wire
`/api/commands/execute`, envelope `payload.args {agentId, line,
images}`; a session id addresses the agent). A matched command returns
`{commandId, result: {kind: success|error, text?}}`; an unmatched name
returns ok with no value slot. The web `CommandUiRuntime` submit table
(`matchEnter`): a line whose leading token names a host command routes
through `commands/execute` — args-tolerant when the command advertises
an input hint, bare-only otherwise (`if (!bare) return undefined` → the
prompt channel); unknown names and skills fall through to the prompt
channel (the model serves them).

The Flutter port follows that table on the static roster
(`command_roster.dart`, names/hints mirrored verbatim):

- Adapter (`harness_repository_impl.dart`): `executeCommand(sessionId,
  line)` posts `commands/execute`, decodes `CommandExecutionWire` (kind
  fail-loud on unknown values), maps the absent value slot to null
  (the miss). Domain gains `CommandExecution` and the repository
  method; spec §16 records the coverage.
- Controller (`chat_controller.dart` `_sendPrompt`):
  `_hostCommandLineFor` applies the table; matched lines run
  `_executeHostCommand` — an error result surfaces its text as the chat
  error banner and keeps the pending images (the web keeps the draft on
  a failed submission); success clears them (the state projections —
  plan chip, goal bar — carry the feedback, per the host's "state
  change is the feedback" contract). A null execution falls back to
  the ordinary prompt send (the live-directory miss); a dispatch
  failure does not — it surfaces as the error banner
  ([command-dispatch-failure-prompt-fallback](../bug-fix/2026-08-20-command-dispatch-failure-prompt-fallback.md)).
- The client-side `/goal <objective>` interception is removed: the host
  command owns the grammar (verified — `/goal Ship the MVP` through
  `commands/execute` creates the goal server-side and answers with the
  status text), so the manual `createGoal` short-circuit was a
  workaround for the missing dispatch, not a behavior of its own.

## Alternatives considered

- **Emulating commands client-side** (toggling plan state from
  projections, creating goals directly): rejected — the registry is
  host state; a client emulation drifts the moment a plugin changes a
  handler.
- **Relying on `session.prompt` per its orphaned doc comment**:
  rejected — the live handler proves otherwise; the comment describes
  no code path that exists.
- **Fetching the live roster via `commands/list`**: deferred — the
  static roster is verbatim-accurate today (verified against a live
  `commands/list`); the fetch adds an async dependency to the submit
  path and is recorded as a known limitation in spec §16.
- **Routing every slash-syntax line through `commands/execute`**: the
  miss-fallback makes it nearly equivalent, but it would execute
  bare-only commands WITH args (`/compact extra`) where the web sends
  them to the model — parity keeps the table.

## Consequences

The ➕ menu and the plan chip work through the real host registry: plan
mode toggles, goals create, permission presets switch, compaction runs
— each with its `command/run`/`command/done` pair in the log. Command
result texts on success are not surfaced (projections are the
feedback); error texts land in the chat error banner. New host commands
require a roster entry until `commands/list` is fetched. The
`sessions.ts` prompt doc comment remains the reference's own bug — this
note records the empirical contract so nobody re-trusts it.
