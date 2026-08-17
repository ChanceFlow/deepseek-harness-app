# DeepSeek Harness Android Client Spec (English Digest)

Status: draft for MVP.

## Goal
Kotlin-native Android client for an existing `dsh web` backend.

## Non-Goals
No WebView/React Native/Flutter/server-driven UI. No dsh backend changes. No auth in milestone 1.

## Architecture
`app -> core:domain -> core:harness-adapter -> core:network`.
`core:harness-adapter` is the only module that knows dsh wire vocabulary.

## Wire Contract
- Unary: `POST /api/<method>` with `client-request`, answer with `server-response`.
- Events: downlink-only WebSockets `/api/events.mux` and `/api/events.host`.
- Interactive frames answer via `POST /api/respond`.

## Connection Lifecycle
Connected means `host.describe` success plus both WebSocket streams open.
Backoff on loss: 500 ms base, factor 2, cap 10 s.
Reconnect refetches session list and open histories, then replays buffered frames.

## Timeline Folding
Raw dsh events fold into `TimelineItem.Message`, `TimelineItem.ToolCall`,
`TimelineItem.ApprovalRequest`, `TimelineItem.QuestionRequest`, and `TimelineItem.Error`.
`seq` is the dedupe boundary.

## UI
`ChatScreen` is stateless; `ChatRoute` owns `ChatViewModel`. Layout is local to Android.

## Known Limitations
MVP now includes workspaces, model selection, session search/rename/fork, queue steer/remove, approvals, and questions. Settings, subagents, and rich plan/trajectory rendering remain deferred.


## Subagent Ownership
Address by parentSessionId + childSessionId. Never derive identity from labels.
MVP supports subagent.list, subagent.history, subagent.prompt, subagent.interrupt.


## Session Titles
Initial titles come from session.list projections.values.title.
Live title projection frames update the session list. Titles are display only.


## Goal Flow
GoalRef/GoalProjection/GoalPhase are domain models.
Adapter wires goal.create/pause/resume/complete/clear; state comes from projection key=goal.
UI is session-scoped.
