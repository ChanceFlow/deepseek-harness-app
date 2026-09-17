# Agent Note: Idempotent timeline multiple invocations and resident follow streams parity

Status: implemented

## Problem

In `reference/deepseek-harness/`, session streams and timeline state are managed by `Session` and `SessionManager` with two strict architectural invariants:
1. `Session.open()` is strictly idempotent: if a session is already open, it resolves immediately; if an open is in flight, all callers share the same `openPromise`. Multiple calls never issue duplicate network RPCs or reset window state.
2. Sessions remain resident after creation so their remote streams keep running off-screen. Switching between sessions or viewing background sessions does not sever active downlinks.

In contrast, the Flutter client had three critical architectural flaws:
1. **Destructive non-idempotent `openSession`**: Every call to `openSession(sessionId)` on an already-opened session invoked `state.reload()`. This broadcast `isLoading = true`, called `session/page` RPC, and completely replaced `_history` with only the latest 50 messages, resetting the reducer and wiping out all older messages the user had loaded through pagination (`loadOlderHistory`).
2. **Single-follow channel bottleneck**: `HarnessRepositoryImpl` kept only a single `_followedSessionId`. Opening another session immediately sent a MUX `cancel` for the previous session's `session-follow` stream, turning other active listeners (like trajectory views, background subagents, or off-screen tabs) into dead streams.
3. **Redundant UI resets on re-selection**: In `ChatController._selectSession`, selecting the currently active session unconditionally cleared `_timelineWindow` to empty and tore down all stream bindings, causing jarring UI flickers on drawer re-taps or deep links.

## Decision

**Idempotent `openSession` with in-flight coalescing.**
- In `HarnessRepositoryImpl`, if `_openSessionId == sessionId && state.isReady`, `openSession` returns `Future.value()` immediately without any network calls or state churn.
- In `_SessionState`, `ensureLoaded` coalesces concurrent invocations onto `_openFuture`. When multiple callers (such as `ChatController`, `WorkspaceController`, or widget mounts) open the session simultaneously, they share a single network call.
- `_SessionState.reload` is converted to a non-destructive merge: when re-visiting an opened session, it fetches the latest tail events and merges any unseen events into `_history` while fully preserving previously prepended older history. It no longer flashes `isLoading = true` or wipes the reducer.

**Multi-session resident follow streams.**
- `HarnessRepositoryImpl` replaces the single `_followedSessionId` field with a set `_followedSessionIds`.
- Following a new session no longer cancels the previous session's downlink. Opened sessions remain resident and keep streaming events off-screen, matching the reference architecture.
- Downlinks are canceled only when a session is explicitly removed/archived or when the repository is disposed. On connection recovery, all active session follow streams resume.

**Current-session selection guard in `ChatController`.**
- `ChatController._selectSession` checks `_selectedSessionId == sessionId`. When selecting the currently active session, it preserves the existing `_timelineWindow` and stream subscriptions, only updating the selection sequence and landing intent.

## Alternatives considered

- **Per-listener reference counting on the downlink.** Rejected: upstream reference maintains off-screen session residency rather than tearing down downlinks when UI components unmount. Retaining active session streams ensures zero-latency switching and background turn capture.
- **Forcing a full reload on every session selection.** Rejected: this was the exact cause of lost pagination history and blank UI flashes. Merging tail events while retaining older paged events provides instant switching and history continuity.

## Consequences

- Multiple calls to `openSession` are safe, non-destructive, and coalesced.
- User pagination (`loadOlderHistory`) is preserved across session switching and re-selection.
- Off-screen sessions continue streaming without interruption; switching back reflects new messages without loading spinners.
- New test in `harness_repository_integration_test.dart` asserts concurrent `openSession` coalescing and pagination preservation.
