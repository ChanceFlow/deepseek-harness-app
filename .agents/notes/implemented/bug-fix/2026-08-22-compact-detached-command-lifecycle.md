# Agent Note: Compact survives the send flow — retry-on-transport-drop, detached bare commands, command cards

Status: implemented

## Problem

Tapping `compact` (or sending `/compact`) through the app's send flow
started but never finished: the host log proved the dispatch worked
(`command/run cmd-…` landed, compaction began), then 35–67 s later
`command/done` settled as `kind: error, "This operation was aborted"`.
The abort is the host tying the command's lifetime to the request
connection — `dsh-client-connection`'s bridge aborts the request signal
on `res.on("close")` when `!res.writableEnded`. The Flutter app's HTTP
RPC client threw `DSHTransportException api/commands/execute
SocketException Software caused connection abort` at the same moment:
the phone's network path tore down the long-idle in-flight connection
(no bytes cross the socket while the host compacts), the client saw the
socket die before the response landed, and the host saw the connection
close.

The same request from a stable Linux client completed in 33.8–79 s
(`POST /api/commands/execute {args: {agentId, line: "/compact",
images: []}}` → success), and the aborted durations varied
(35.5/45/47/66/67 s) instead of hitting a fixed wall — a fresh
connection after an abort succeeded at 79 s. So the host is healthy and
the drop is the phone path; the fix must live client-side. dart:io
exposes no TCP keep-alive control (only `tcpNoDelay`), so the client
cannot hold the connection open; the app must instead compensate when
the drop happens.

Two prior notes record the axes: transport-hardening deferred a request
deadline (a full compaction runs over a minute — the web remote path
applies no deadline either), and
[command-dispatch-failure-prompt-fallback](2026-08-20-command-dispatch-failure-prompt-fallback.md)
deferred detached execution because the timeline rendered no command
lifecycle cards.

## Decision

Three changes close the loop:

- **Retry on transport drop for detached bare commands**
  (`harness_repository_impl.dart`): `ChatRepository.executeCommand` takes
  `retryOnTransportAbort`. When set and the first dispatch throws a
  `DshTransportException` whose cause is a `SocketException` (a
  mid-flight drop before any response bytes), the adapter re-dispatches
  once on a fresh connection after a 1 s drain pause; a second drop
  rethrows. The host aborts a command the moment its HTTP request dies,
  so an in-flight drop never settles a result — the retry is a clean
  re-run, and compaction is idempotent (an aborted compaction leaves the
  session unchanged). The chat controller sets the flag only for the
  detached bare command path (`/compact`), never for attached
  arg-taking commands whose side effects could double-apply.
- **Detached dispatch for bare commands** (`chat_controller.dart`): a
  line whose roster command has no input hint (today only `/compact`)
  dispatches through `commands/execute` with `detached: true` — the
  composer never holds its sending state while the host runs the command
  for as long as the HTTP request survives (web `runDetached` parity).
  The attached path (hinted commands — `plan`, `goal`, `permission`,
  `feedback`) keeps `_isSending` until settlement. An immediate failure
  still surfaces in the error strip; the line is never re-sent either
  way.
- **Command lifecycle cards** (`timeline_item.dart`,
  `timeline_reducer.dart`, `chat_screen.dart`): the reducer folds
  `command/run` → a `TimelineCommand` with `status = running`, and
  `command/done` resolves the card in place by `commandId` (`success`
  with `text`, else `failed`); a done whose run fell outside the folded
  window appends the settled card with name `unknown`. `CommandRow`
  renders `/name` plus the host-authored outcome text — running leads
  with the timeline's `ActivityDot` while the row sweep carries the
  in-flight signal
  ([timeline in-flight signal is sweep and status line](2026-08-29-timeline-inflight-sweep-only.md)),
  success a check icon, failure an error icon
  tinted with the error scheme. The cards land in the current turn group.

Spec §6 documents the two event folds; spec §16 documents the detached
bare-command contract and the retry profile.

## Alternatives considered

- **TCP keep-alive on the RPC connection**: rejected — dart:io exposes
  only `tcpNoDelay` via `SocketOption`; SO_KEEPALIVE would need a
  platform-channel FFI path out of scope for this client.
- **A client-side request deadline sized for compaction**: rejected —
  the web remote path applies none (plain `fetch`, caller's signal
  only); the app stays symmetric, and the retry removes the observed
  abort instead of masking it with a timeout.
- **Overriding the socket idle window (`idleTimeout`)** (an earlier
  attempt): rejected after inspection — dart:io `idleTimeout` bounds
  only pooled idle connections, never an in-flight request, so it cannot
  prevent the mid-compaction drop; the knob was reverted.
- **Retry every command dispatch on transport abort**: rejected — a
  command that already had side effects could double-apply; the retry is
  scoped to the benign bare path.

## Consequences

`/compact` now dispatches detached and self-heals a phone-path drop: the
first attempt's aborted `command/done` folds into its card, the retry's
success folds into a second one, and the composer stays free throughout.
An immediate transport failure (or a second consecutive drop) still
surfaces in the error strip. The reducer's exhaustive fold gains two
wire events and the spec's coverage table records them.
