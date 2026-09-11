# Agent Note: Cordis plugin approval card and the live command roster

Status: implemented

## Problem

Two dead ends on the phone.

A model `cordis_run` / `cordis_define` on a dynamically loaded plugin
blocks host-side until a person answers `cordis/request-run`, and the
host accepts the verdict through
`dynamicCordisRunner/resolveRequestRun`. The host forwarded both the
request and `cordis/request-run-resolved`, but the phone had no surface,
so the only way to release the blocked tool call was a browser page.

Separately, `command_roster.dart` mirrored a frozen six-name list, so a
host- or plugin-registered slash command was invisible and unrunnable
even though `commands/list` publishes the live roster and
`commands/change` ticks it.

## Decision

### Cordis approval card

`ChatUiState` carries `cordisRunRequests`, fed once from
`ChatRepository.observeCordisRunRequests()` (the request list is
registry-global; each request names its own session). The screen's
`_pendingCordisRequest` takes the first request with
`requiresApproval: true` and mounts `CordisRequestPanel` in the composer
seat, the same takeover slot as `ApprovalPanel` / `QuestionRow`.

The card shows the plugin identity (`name`, `pluginId`, `packageId`), the
`purpose`, the `mode` chip, and a notice stating that only rejection is
available. `RejectCordisRun` answers
`resolveCordisRunRequest(requestId, const CordisRunRejected())`.

Rejection is the only honest decision this client can deliver. An
approval's `ok:true` arm must name the exact Client activation
(`CordisRunApproved.pluginRunId`) the answering page created or attached
to, and only a browser plugin runtime
(`cordis-client-runner`'s orchestrator) can produce one; the host rejects
a resolution whose run id does not match. A rejection needs no identity,
refuses both halves, and is what releases the blocked call.

A request with `requiresApproval: false` mounts no card: the host already
started its own half and only needs a browser page to attach the Client
half, so there is no pending user decision and a Reject would cancel a run
nobody asked about.

The settled state is the card leaving the seat: the adapter drops a
request on `cordis/request-run-resolved`, and a locally acknowledged
answer drops it too. No "delivered" confirmation is shown because the
broadcast does not say who settled it or with what outcome (another page
may have approved).

An answer refusal raises `ChatUiState.cordisAnswerFailed`, rendered as the
localized `cordisAnswerFailed` sentence (the `commandFailed` pattern); the
raw host detail goes to the error log.

### Live command roster

`ChatController` pulls `listCommands(sessionId)` per session, caches it,
and clears every cache on `observeCommandRosterChanges()`, re-pulling the
selected session. A failed pull (a subagent-owned session answers
`session/agent-busy`) leaves `commands` null and logs a breadcrumb — it
never surfaces an error strip.

`ChatUiState.commands` is null until a pull settles, a non-null list
(including empty) once it does. `hostCommandLineFor`,
`hostCommandImageRefusal`, and `hostCommandIsBare` take the roster as an
argument defaulting to `kHostCommandNames`; the controller and composer
pass `hostCommandFacts(commands)` when a live pull settled. The static
list therefore survives only as the pre-first-pull fallback, which also
carries a `session/agent-busy` refusal.

Display reuses `hostCommandsFor`: a live name the client knows keeps its
localized description; a live-only name shows the host's own description
verbatim (the only text that exists for it). The static `hostCommands`
list is still the fallback display roster.

`/export` stays a client-side interception (`isBareSessionLogExport`):
the host handler only acknowledges the browser-owned transfer, so the
phone runs the local save regardless of registry membership.

## Alternatives considered

- **Fake an approval payload to unblock `cordis_run`**: rejected — an
  approval without a real `pluginRunId` is a lie the host rejects, and
  fabricating one would misreport state.
- **Render a Reject card for `requiresApproval: false`**: rejected — it
  is not a pending decision; the card would invite cancelling a run the
  host already started and would not release anything.
- **Show a "decision delivered" strip on resolve**: rejected — the
  broadcast omits the outcome and the settler, so the confirmation could
  claim a delivery another page made.
- **Replace the static roster outright (no fallback)**: rejected — a
  failed `commands/list` would empty the menu, and the built-ins are
  known-good.
- **Keep the frozen roster and only add commands by hand** (the previous
  deferral in [slash-command-dispatch](2026-08-20-slash-command-dispatch.md)):
  rejected — plugin commands are runtime data the client cannot mirror.
- **Localize live-only command descriptions**: rejected — the client has
  no ARB key for a name it has never seen.

## Consequences

A `cordis_run` waiting on a decision is now visible and clearable from
the phone; approving stays browser-only by design. Slash commands the
client never hard-codes appear in the `/` candidates and the ➕ sheet and
dispatch through `commands/execute` with their own hint and attachment
flags. The static roster's only remaining job is the pre-first-pull
fallback. `commands/change` invalidates every cached roster, so a plugin
that registers a command mid-session makes it dispatchable on the next
selected-session pull.
