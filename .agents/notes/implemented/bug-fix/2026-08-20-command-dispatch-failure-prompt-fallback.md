# Agent Note: Command dispatch failure must not re-route to the prompt channel

Status: implemented

## Problem

A user tapping `compact` in the ➕ menu and sending `/compact` saw the
model answer the line as ordinary content — the exact defect the
dispatch fix
([slash-command-dispatch](../feature/2026-08-20-slash-command-dispatch.md))
had closed for `/plan`. The host log proved the dispatch itself worked:
`command/run cmd-…-5` landed, compaction started, and 45 s later
`command/done` settled as `kind: error, "This operation was aborted"`
(the client's HTTP request died mid-compaction — a full compaction of
that session takes ~69 s). The controller's `_runCatchingForUi` swallows
every exception into `null`, and `_executeHostCommand` read `null` as
"command unmatched" — so it fell back to `sendMessage(line)` and the
model received the literal `/compact` (turn 76 of the incident session;
two later retries show the user fighting the same hole until one landed
after the agent went idle).

## Root cause

Two outcomes were conflated on one `null`:

- **Unmatched** — the host answers `ok` with no value slot (a preset
  that does not compose the command). The web `matchEnter` consults the
  live directory before dispatch and routes a miss to the prompt
  channel, so the fallback is web-faithful here.
- **Dispatch failure** — the RPC throws (transport abort, business
  error). The web's `execute()` surfaces the throw to the composer
  notice; it never submits the line. The app instead re-sent the line
  as a prompt — turning a network failure into model input.

## Decision

`_executeHostCommand` (chat_controller.dart) catches the
`executeCommand` exception itself and surfaces it as the chat error
banner (`errorMessage`, images kept, `isSending` released) — never the
prompt fallback. Only a genuine `null` return still falls back to the
prompt send, preserving the roster-miss semantics for preset-dependent
registries. The wire contract is unchanged: `commands/execute` carries
no timeout on the web remote path either (the browser's generic
connection RPC uses plain `fetch` with only the caller's signal), so a
long compaction stays legal and the app adds no client-side deadline.

Re-verified against the live host (`commands/list` for the incident
session): `compact`, `export`, `feedback`, `goal`, `permission`,
`plan` — the static roster's five names and hints match verbatim;
`export` stays excluded (its host handler only acknowledges the
request; the ZIP download is a browser-plugin observer the app cannot
host).

## Testing

`chat_controller_test.dart`: "a dispatch failure surfaces the error and
never prompts the model" — the fake repository throws on the dispatch
and the test asserts the error banner, `isSending == false`, and an
empty `sentMessages`. The existing unmatched-fallback and error-result
tests pin the two surviving paths.

## Alternatives considered

- **A client-side timeout on `commands/execute`** sized for compaction
  (minutes): rejected — the web remote path applies no deadline either
  (plain `fetch`, caller's signal only), so the app stays symmetric and
  the failure contract alone fixes the observable defect.
- **Detached execution for bare commands** (web `runDetached`: free the
  composer immediately, render the outcome from the `command/run`/
  `command/done` timeline events): implemented
  ([compact-detached-command-lifecycle](2026-08-22-compact-detached-command-lifecycle.md)) —
  bare-only commands dispatch detached and the timeline folds the
  lifecycle into command cards; the error banner now carries only an
  immediate transport/admission failure, never a mid-run abort.
- **Removing the null→prompt fallback entirely** (treat every miss as
  an error, like the web's execute-level unmatched notice): rejected —
  the app's roster is static while the host registry is preset-scoped;
  the fallback keeps preset differences web-faithful (a web `matchEnter`
  directory miss also rides the prompt channel).

## Consequences

A network failure mid-command now leaves the line unsent (error banner,
images kept) instead of leaking command text into the model's context;
the user retries when the connection recovers. Slow commands (a
full-session compaction can run over a minute) no longer hold the
sending state: bare commands dispatch detached and their outcome renders
as the timeline command card
([compact-detached-command-lifecycle](2026-08-22-compact-detached-command-lifecycle.md)).
