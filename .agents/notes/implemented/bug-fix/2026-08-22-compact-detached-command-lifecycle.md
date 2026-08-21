# Agent Note: Compact survives the send flow — idle transport, detached bare commands, command cards

Status: implemented

## Problem

Tapping `compact` (or sending `/compact`) started but never finished
through the app's send flow. The host log proved the dispatch itself
worked: `command/run cmd-…` landed and compaction began, then 35–47 s
later `command/done` settled as `kind: error, "This operation was
aborted"`. The abort is the host tying the command's lifetime to the
request connection: `dsh-client-connection`'s bridge aborts the request
signal on `res.on("close")` when `!res.writableEnded`. The Flutter app's
HTTP RPC client built a bare `http.Client()` whose socket sat idle with
the dart:io default (15 s) while the host spent the whole compaction
budget computing server-side — no bytes crossed the wire before the
response landed, so the platform closed the socket mid-run. The same
compaction completed in 33.8 s from a stable Linux client
(`POST /api/commands/execute {args: {agentId, line: "/compact",
images: []}}` → success, "Compacted 120 history items (~79154 tokens)."),
so the host side was healthy; only the app's connection dropped.

Two prior notes record the axes: the transport-hardening note deferred a
request deadline (a full compaction runs over a minute — the web remote
path applies no deadline either), and
[command-dispatch-failure-prompt-fallback](2026-08-20-command-dispatch-failure-prompt-fallback.md)
deferred detached execution because the timeline rendered no command
lifecycle cards.

## Decision

Three changes close the loop:

- **Idle transport** (`http_dsh_rpc_client.dart`): the default client is
  now `IOClient(HttpClient()..connectionTimeout = 10 s ..idleTimeout =
  5 min)`. `kDshRpcIdleTimeout` overrides the socket idle window only —
  it is not a request deadline, so a 30+ s compaction with no bytes in
  flight stays legal. The socket no longer closes mid-computation.
- **Detached dispatch for bare commands** (`chat_controller.dart`): a
  line whose roster command has no input hint (today only `/compact`)
  dispatches through `commands/execute` with `detached: true` — the
  composer never holds its sending state while the host runs the command
  for as long as the HTTP request survives (web `runDetached` parity).
  The attached path (hinted commands — `plan`, `goal`, `permission`,
  `feedback`) keeps `_isSending` until settlement. An immediate
  failure — transport abort or admission error that never entered a
  handler — still surfaces in the error strip (published even when
  detached; there is no `command/done` to fold into a card), and the
  line is never re-sent.
- **Command lifecycle cards** (`timeline_item.dart`,
  `timeline_reducer.dart`, `chat_screen.dart`): the reducer folds
  `command/run` → a `TimelineCommand` with `status = running`, and
  `command/done` resolves the card in place by `commandId` (`success`
  with `text`, else `failed`); a done whose run fell outside the folded
  window appends the settled card with name `unknown`. `CommandRow`
  renders `/name` plus the host-authored outcome text — running shows a
  12 px progress indicator, success a check icon, failure an error icon
  tinted with the error scheme. The card carries no composed UI copy:
  the host owns the outcome text (web parity). The cards land in the
  current turn group (direct log-only appends; no turn wraps them).

Spec §6 documents the two event folds; spec §16 documents the detached
bare-command contract and the transport profile.

## Alternatives considered

- **A client-side request deadline sized for compaction**: rejected —
  the web remote path applies none (plain `fetch`, caller's signal only);
  the app stays symmetric, and the transport fix removes the only
  observed abort.
- **Keep attached dispatch and surface only the error banner** (the
  previous behavior): rejected — a 30–70 s compaction holds the composer
  hostage and the failure still aborts the run; detached dispatch plus
  the card is web-faithful and frees the user.
- **Emit the command card only for `/compact`** (a client-side special
  case): rejected — the reducer folds the generic `command/run` +
  `command/done` lifecycle, so any host command the roster admits renders
  its card for free.

## Consequences

`/compact` now dispatches detached: the composer frees immediately, the
host connection survives the idle computation, and the outcome renders as
the timeline command card (running → success with the host's text, or
failed with the abort text) instead of a held sending state. An immediate
transport failure still surfaces in the error strip. The reducer's
exhaustive fold gains two wire events and the spec's coverage table
records them. Command cards appear in whichever turn group is current —
including the pre-first-turn null group — matching the web's direct log
appends.
