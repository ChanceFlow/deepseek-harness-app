# Agent Note: Full workspace drift and error remediation

Status: implemented

## Problem

Subagent scans across all modules identified remaining DSH 0.1.2 wire drifts and silent failure modes:
1. Streaming partial text wiped: in `TimelineReducer`, `block-end` invoked `_extractText(block)` expecting a `Message` wrapper with a `content` list, clearing text/reasoning buffers mid-turn when a `ContentBlock` arrived.
2. Reconnection socket collision: `WebSocketDshEventSocket._sockets` was keyed only by path; asynchronous teardown of an old generation erased a newly connected socket, causing subsequent `send()` calls to drop stream `open` frames silently.
3. Stream error payload dropped: `ServerRequest.fromJson` discarded `map['error']` on stream error frames, and `DshBusinessException` omitted `details`.
4. Stale projections on session switch: `ChatController._bindSelected` cancelled subscriptions but retained old projections (`plan`, `todos`, `goal`, `contextPressure`, `sessionStats`), causing visual ghosting. Furthermore, newly created/forked sessions omitted skill loading.
5. In-flight IME corruption: `_CustomAnswerRow` and `_CustomAnswerField` allocated `TextEditingController` inside `build()`, leaking controllers and disrupting Chinese/Japanese composition.
6. Silent controller error swallowing: `_runCatchingForUi` across all controllers caught exceptions without forwarding them to `ErrorLogCollector.instance.captureError`. In `SubagentController` and `WorkspaceController`, chained actions cleared `_errorMessage` before display.
7. Missing domain equality: `BackendRegistryState` and `CommandExecution` lacked equality operators. `chatRepositoryProvider` never registered `ref.onDispose(repo.dispose)`, and `VoiceInputController` executed recorder stopping outside `try`.
8. Delayed timeline and session list updates: prompts sent had no optimistic visual feedback before HTTP admission; `session/follow` stream was never opened on the mux socket, leaving token chunks unstreamed; `/api/events.host` 502'd on gateway port 3083, freezing session list status updates; auto-scroll froze during thinking because `_followSignature()` ignored reasoning growth.

## Decision

1. Corrected `block-end` handling in `TimelineReducer` to extract text and reasoning directly from the block payload without wiping partial buffers. Supported both `event` and `session/event` frame discriminants.
2. Guarded socket removal in `WebSocketDshEventSocket` with `identical(_sockets[path], webSocket)`, failed loudly on unopened socket sends, and preserved error payloads in `ServerRequest.fromJson`.
3. Added `details` parameter to `DshBusinessException` and forwarded it in `DshRemoteInvoker`.
4. Reset all projections to `null` in `ChatController._bindSelected` on rebind, and ensured skills load on session creation and fork.
5. Converted custom answer inputs in `ChatScreen` to `StatefulWidget`s managing persistent `TextEditingController` instances across lifecycle hooks.
6. Bridged all controller `_runCatchingForUi` methods to `ErrorLogCollector.instance.captureError`, and prevented subsequent actions from resetting errors when initial mutations fail.
7. Added value equality and hash codes to `BackendRegistryState` and `CommandExecution`, made `QuestionItem.hashCode` order-independent, registered `ref.onDispose(repo.dispose)` on `chatRepositoryProvider`, and wrapped recorder stop inside `VoiceInputController`'s `try` block.
8. Added immediate optimistic user messages on prompt submit in `ChatController._sendPrompt`; dynamically opened and managed the `session/follow` logical stream on `/api/remote.mux` in `HarnessRepositoryImpl`; wired `turn/start`, `turn/end`, and `workspace/follow` `upsert` frames to immediately synchronize `_sessions.value`; included reasoning growth in `_followSignature()` to keep auto-scroll active during model thinking; and preserved collapsed thought summaries when settled.

## Alternatives considered

1. Re-instantiating `TimelineReducer` on every stream chunk: rejected because O(N) reconstruction per streaming token degrades frame rates on long conversations.
2. Exposing raw stream channels to UI controllers: rejected because it violates repository boundaries and leaks transport concerns into presentation widgets.
3. Global toast notifications for all swallowed controller errors: rejected because user-facing error banners and in-app error log collection provide actionable debugging without intrusive UI popups.

## Consequences

- Live streaming output preserves text and reasoning through block boundaries without mid-turn text loss.
- Reconnections cleanly preserve socket references and reliably re-open logical streams.
- Switching sessions immediately clears previous projection states without visual flicker.
- In-app Error Logs screen accurately reflects all runtime, network, and controller exceptions.
- Tests pass across all workspace packages and doc/code gates remain clean.
