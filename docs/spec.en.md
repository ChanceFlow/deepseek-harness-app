# DeepSeek Harness Android Client Spec (English Digest)

Status: MVP closed on the legacy Kotlin stack; Flutter rewrite in progress
(ADR-0001, ROADMAP.md).

## Goal
Flutter client for an existing `dsh web` backend.

## Non-Goals
No WebView/React Native/server-driven UI. No dsh backend changes. No auth in milestone 1.

## Architecture
`app -> domain -> harness_adapter -> network` (pub workspace under `flutter/`;
legacy Gradle modules frozen until parity).
`harness_adapter` is the only package that knows dsh wire vocabulary.

## Wire Contract
- Unary: `POST /api/<domain>/<method>` with `client-request` carrying payload wrapped in `args`, answer with `server-response`.
- Events: downlink-only WebSocket `/api/remote.mux` (required, the only downlink). Session running state, peer creation, removal and activity are not decoded from `host/*` frames: they arrive as the forwarded Remote Events `api-session/status`, `api-session/added`, `api-session/removed` and `api-session/activity` on the mux `$events` stream. `/api/events.host` is not a host route (the upgrade hangs, the gateway answers 502) and is no longer dialed.
- Interactive frames answer via `POST /api/respond`.

## Connection Lifecycle
Connected means the required `/api/remote.mux` socket opened and the gateway delivered its `$events` registration answer — the `ready` frame carrying `host.home` (the reference client's connection-generation handshake). A `ready` frame without `host.home`, a stream that closes first, or one that misses its 30 s deadline fails the generation; `host/describe` is not registered at 0.1.5 and `HostDescription` carries only the ready frame's `home` plus a version no route publishes (never defaulted).
Backoff on loss: 500 ms base, factor 2, cap 10 s.
Reconnect refetches session list and open histories, then replays buffered frames.

## Timeline Folding
Raw dsh events fold into `TimelineItem.Message`, `TimelineItem.ToolCall`,
`TimelineItem.ApprovalRequest`, `TimelineItem.QuestionRequest`, and `TimelineItem.Error`.
`seq` is the dedupe boundary.

## UI
`ChatScreen` is stateless; `ChatRoute` owns `ChatViewModel`. Layout is local to Android.

## Known Limitations
The MVP now includes workspaces (create/rename/delete/reorder via workspace.insertBefore), model and reasoning-effort selection, session search/create/rename/archive/fork, queue vs steer delivery, queue steer/remove, approvals, multi-select and custom-text questions (plan-review intents render a decision card with the markdown plan body and primary approve action), subagents, goals, titles, background jobs, page-at-a-time older-history loading, ledger-style turn boundaries and a collapsible trajectory outline (request-header prompt echoes, per-tool status summaries, compaction markers), non-destructive session archiving, in-app directory browsing (host.listDirectory/host.createDirectory), image attachments (inline prompt parts, imageLimits-gated, lazy session.attachment download), basic markdown rendering (fenced code/headings/nested bullets/block quotes/pipe tables/inline code/bold/italic/clickable links via a pure-Kotlin parser), image attachment thumbnails on pending chips with lazy-load retry, a previewable queue-edit dialog, a plan-mode header state mirrored from the plan session projection (/plan toggles it), the composer `/` skill-candidate source (one cached skill.list per session, literal /name insertion), session-log export (bare `/export` or the session-header seat downloads GET /api/session.export and saves the ZIP to Downloads on Android 29+, app-specific storage below), and a settings screen (settings.describe overview, per-namespace one-key patching via settings.update with revision CAS on writable hosts, and per-ref credential management: describe, credentials.set store/replace, credentials.unset clear; the whole plane is loopback-only on the host). Attachments beyond images, skill authoring, plan-review conversation intents, rich plan/trajectory rendering, schema-driven settings forms, settings replace/mutate, and attachment downsampling remain deferred; plugin management is not a wire capability (host-side composition, nothing to reproduce).


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


## Background Jobs
session/jobs mux frames fold into TimelineItem.Jobs. Jobs are live snapshots, not durable history.
