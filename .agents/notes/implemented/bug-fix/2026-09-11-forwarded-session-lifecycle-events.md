# Agent Note: Forwarded Session lifecycle events and the unrecognised-event diagnostic

Status: implemented

## Problem

Two behavioral defects and one stale-contract finding in the adapter's
event-handling surface left parity gaps invisible on the pinned 0.1.5 host
(`dsh-v0.1.5-rc.2`, `fb2c4b9e698e30edb738bca4cf0618587db7d203`).

1. **Unrecognised session events were dropped silently.**
   `TimelineReducer._ingestEvent` switched on eleven event types with no
   default and no diagnostic, so the 0.1.5 types this client has no fold for —
   `hook/invoked`, `hook/result`, `schedule/change`, `sandbox/mode`,
   `team/member`, `team/task`, `llm/retry*`, the four `tool-workflow/*`
   (`packages/core/session/src/known-event-types.ts`) — vanished without a
   trace. Projection keys already reported an unknown key at debug
   (`mux.projection`); events did not, so a coverage gap could not be
   measured.

2. **The live forwarded-event fold dropped `api-session/added`.** A session
   another client creates arrives as an ordinary forwarded Remote Event on
   the `$events` stream, folded by `_applyForwardedEvent`; that fold handled
   only `agent-preset/selected`, so the new roster row never appeared. The
   client's old `case 'host/session-added'` arm was a **host-frame type** on
   the optional `/api/events.host` leg — not an alternate name for the
   forwarded event — and that leg never answers the upgrade on 0.1.5, so the
   arm was dead (it is deleted now; see the Decision). The flow was genuinely
   broken: the local `createSession` path refreshes `session.list` itself, but
   a remote creation reached this client only through the reconnect resync or
   a workspace-change pull, so a peer's session stayed invisible while
   connected.
   `_inferWorkspacesFromSessionsIfEmpty` runs only on a list pull and does not
   close the gap.

3. **Stale prose said a mode mismatch answers `subagent-not-found`.** On
   0.1.5, `history.ts` `validateAddress` throws `subagent/unauthorized` for a
   mode or ownership mismatch (lines 347, 367); `subagent/not-found` comes
   only from `rejectNotFound` for an unavailable child (line 377). The client
   has no branch on either code: `loadSubagentHistory` throws
   `DshBusinessException` and `SubagentController` renders `error.toString()`
   in the generic banner, so no user-visible mapping was wrong — only the
   comment and
   [this note's sibling](2026-08-29-subagent-lineage-events-typed-mode-and-sheet-visibility.md).

## Decision

1. **Report every unrecognised event type.** `TimelineReducer` takes an
   optional `AdapterDiagnosticListener`; the `_ingestEvent` default emits a
   debug `AdapterDiagnostic` with `context: 'timeline.event'`, the type and
   `seq` in the message and metadata, and the payload withheld (it can carry
   user text). The fold still publishes no item and never throws: the dsh
   `SessionEventMap` is merge-extensible, so an unknown type is expected
   input, not a client bug. `HarnessRepositoryImpl` passes its `_onDiagnostic`
   into every reducer it constructs (per-session states and
   `loadSubagentHistory`).

2. **Fold `api-session/added` by merging its summary.** `_applyForwardedEvent`
   gains one case dispatching to `_applySessionAddedEvent`, which decodes
   `args.first` with the existing `SessionWire` summary decoder, applies the
   summary's projection hints, and upserts the `_sessions` roster row while
   preserving the folded completion bit. No `session.list` round-trip is
   issued. The legacy `host/remote-event` frame and every `host/*` arm are
   deleted with the `/api/events.host` leg
   ([decision](2026-09-11-drops-routes-the-pinned-host-does-not-register.md)),
   so the `$events` `emit` item is the one forwarded-event transport. Removal
   and activity are folded by
   [their own decision](2026-09-11-forwarded-session-removal-and-activity.md).

3. **Correct the wire-code prose.** The adapter comment names
   `subagent/unauthorized` for the mode mismatch and `subagent/not-found` for
   an unavailable child, and this note's sibling is amended the same way.
   The three `flutter/app` comments that still named `subagent-not-found`
   for the mismatch were outside that change and are swept by
   [the child-history prose fix](2026-09-11-child-history-route-and-error-codes-in-prose.md),
   which also replaces the retired `subagent.history` route name.

## Alternatives considered

- **Make the default throw** so a new event type fails loud: rejected — the
  host event map is merge-extensible, and a client that throws on a type it
  does not render would break every turn that emits one.
- **Report each type once per reducer** to bound diagnostic volume: rejected —
  the count is the measurement, and the projection-key diagnostic mirrors one
  report per frame.
- **Include payload fields in the diagnostic**: rejected — payloads carry user
  text.
- **Rename the `host/session-added` arm to `api-session/added`**: rejected —
  wrong surface; the host-frame arms switched on a frame `type` delivered by
  the retired leg, while the forwarded name arrives nested in an `$events`
  `emit` item. The arm is deleted instead.
- **Re-pull `session.list` on `api-session/added`**: rejected — the summary is
  the complete row the pull would return and the web client merges it; a pull
  adds a round-trip and a second membership source.

## Consequences

- An unrecognised event type is visible in diagnostics with its `seq`.
- A session created by another client appears in the roster while connected,
  and the existing `SubagentController` membership diff sees a child spawn
  through the roster publication, feeding the debounced catalog refresh.
- Every `host/*` arm is gone with the leg; the integration test that pinned
  `host/session-added` now drives the forwarded `api-session/added` item and
  asserts the in-place upsert, and the `refreshSessions` diagnostic test
  drives its remaining `turn/end` and workspace-upsert triggers.
- Adapter tests pin both: `forwarded_session_events_test.dart` drives the real
  repository through the `$events` `emit` path and the real decoder, and
  `timeline_reducer_test.dart` asserts the diagnostic and that no payload text
  travels.
