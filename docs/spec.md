# DeepSeek Harness Android Client Spec

Status: draft for MVP
Target: Kotlin native Android client for an already running dsh web backend.
Related code: `app/`, `core/domain/`, `core/network/`, `core/harness-adapter/`.

## 1. Goal

Provide a native Kotlin/Jetpack Compose Android client that reproduces the
core Web chat experience of DeepSeek Harness while keeping every dsh wire
concept behind an anti-corruption layer.

## 2. Non-Goals

- No WebView UI, no React Native, no Flutter, no server-driven UI.
- No changes to the dsh backend in this phase.
- No client-side agent/tool execution; the backend remains the only harness runtime.
- No authentication layer in the first milestone; deployment hardening is external.

## 3. Architecture

```text
app                     Compose UI, ViewModel, Hilt DI
  -> core:domain        neutral models + repository contract
  -> core:harness-adapter   anti-corruption layer, dsh translation
  -> core:network       OkHttp RPC + WebSocket transport
```

Dependency rules:

- `app` may import `core:domain` and (for DI) the implementation modules.
- `app` must never import dsh types such as `SessionEvent`, `MuxFrame`, `HostFrame`.
- `core:domain` has no Android UI and no dsh types.
- `core:harness-adapter` is the only module allowed to know dsh method names and event shapes.
- `core:network` knows transport envelopes, HTTP paths, and WebSocket mechanics only.

## 4. Wire Contract

The backend is a `dsh web` host. The Android client uses the same HTTP/WebSocket
transport as the official Web client.

### 4.1 Unary RPC

```text
POST /api/<method>
Content-Type: application/json
```

```json
{
  "type": "client-request",
  "rpcId": "uuid",
  "method": "session.prompt",
  "payload": {}
}
```

Response:

```json
{
  "type": "server-response",
  "rpcId": "uuid",
  "result": {
    "ok": true,
    "value": {}
  }
}
```

Business failures return HTTP 200 with `result.ok == false` and an `RpcError`
whose `code` is machine-readable and whose `details` is code-specific.

### 4.2 Event streams

Two downlink-only WebSocket streams are required:

```text
/api/events.mux
/api/events.host
```

- Server frames are `ServerRequest` envelopes: `type`, `rpcId`, `method`, `payload`.
- `method` equals the frame payload `type`, e.g. `session/event`.
- Client messages on these sockets are protocol violations; the host closes 1008.
- GET on either path without an upgrade returns 426.

### 4.3 Interactive frames

Answerable mux frames use the echoed `rpcId` on `POST /api/respond`:

```text
approval/requested  ->  allowed-once | rejected
question/requested  ->  answers per question id
```

`/api/respond` returns a carrier receipt (`RpcReceipt`), not a server response.

## 5. Connection Lifecycle

A connection generation is healthy only when all three readiness facts hold:

1. `host.describe` RPC succeeded.
2. `/api/events.mux` WebSocket fired `onOpen`.
3. `/api/events.host` WebSocket fired `onOpen`.

After readiness, the client publishes `ConnectionPhase.CONNECTED`.

On any stream loss or handshake failure:

1. Publish `ConnectionPhase.RECONNECTING`.
2. Clear the stale `HostDescription`.
3. Retry with exponential backoff: base 500 ms, factor 2, cap 10 s.

After a new generation connects, the repository:

1. Refetches `session.list`.
2. Marks all open session stores stale.
3. Refetches `session.history` for each open session.
4. Replays buffered mux frames that arrived while history was loading.

## 6. Timeline Folding

Raw dsh session events are folded by `TimelineReducer` into neutral items.
`seq` is the deduplication boundary: an event whose `seq <= lastSeq` is ignored.

| dsh event | Android timeline item |
|---|---|
| `user/message` | `TimelineItem.Message` with `MessageRole.USER` |
| `assistant/chunk` | live `TimelineItem.Message` with `streaming = true` |
| `assistant/message` | final `TimelineItem.Message` with `streaming = false` |
| `tool/call` | `TimelineItem.ToolCall` with `status = RUNNING` |
| `tool/result` | paired `TimelineItem.ToolCall` with result/error status |
| `turn/end` (error/aborted/interrupted/max-tokens) | `TimelineItem.Error` |
| `approval/requested` | `TimelineItem.ApprovalRequest` |
| `question/requested` | `TimelineItem.QuestionRequest` |
| `approval/resolved`, `question/resolved` | removes the matching interactive card |
| `session/queue` | `TimelineItem.Queue` snapshot with queued/steering/context entries |

Text extraction handles `text` blocks and nested `tool-result` content.

## 7. Android UI Contract

``AppRoot` owns bottom navigation. `ChatScreen`, `WorkspaceScreen`, and
`ModelsScreen` are all stateless screens; each route owns a Hilt ViewModel
collecting `StateFlow` UI state. Chat additionally supports session search,
rename/fork, queue text edit/steer/remove, approvals, and questions
(multi-select, optionless text, custom text, and skip).

- `ChatUiState` is `@Immutable`.
- `ChatAction` is a `sealed interface`.
- `ChatViewModel` never exposes `MutableStateFlow`.
- Layout is local: the same `ChatUiState` renders one- or two-pane depending on
  available width; server data never dictates layout.

## 8. Security & Deployment

- The dsh backend's `/api` trust fence is reachability-only, not authentication.
- The client sends no `Origin`/`sec-fetch-site` headers; it relies on `Host`.
- Default base URL is `http://10.0.2.2:3080` for the emulator; set with
  `-PDSH_BASE_URL=http://<lan-ip>:3080`.
- Cleartext is enabled in debug manifests only.
- Production requires TLS termination in front of the backend.

## 9. Testing Strategy

- `core:network`: envelope round-trip tests.
- `core:harness-adapter`: timeline reducer tests for chunk/message/tool/approval folding;
  connection-generation tests with a fake transport and injected dispatcher;
  hermetic HarnessRepository fake-host integration tests for host workspace frames
  and mux session-event delivery.
- `app`: ViewModel tests with a fake `ChatRepository`.
- Integration with a real `dsh web` is opt-in: set `DSH_E2E_URL` and run
  `LocalDshE2eTest`; it is skipped otherwise.

## 10. Known Limitations and Deferred Work

- **Streaming is chunk-oriented, not final-block-oriented.** The reducer favors
  `text-delta`/`reasoning-delta`; provider adapters that emit only block events
  will still display finalized blocks from `assistant/message`.
- **Titles are display-only.** `session/projection` title frames and history
  projections are read, but identity always remains `sessionId`.
- **Turn grouping is a collapsible outline.** Logged `turn/start` events
  fold into `TimelineItem.TurnBoundary`; the chat timeline offers a flat view
  (divider rows) and an outline view whose group headers ("Turn N · X
  messages · Y tools" plus a per-tool status-count summary line, e.g.
  "bash 3✓ 1✗") collapse their rows on tap with an expand-all reset.
  Grouping is a pure UI-layer function over the folded timeline
  (`groupTimelineByTurn`, JVM-tested). Request-header grouping, compaction,
  and session-end markers stay deferred.
- **Settings namespaces patch one top-level key at a time.** For writable
  hosts (`describe.writable`), each namespace row opens an editor with two
  modes: key patch (`settings.update {ns, patch, expectedRevision}`) and
  whole-section replace (`settings.replace {ns, section, expectedRevision}`,
  object-only JSON). The revision from the last describe acts as the CAS
  guard, the host validates against the namespace schema, and the response
  view re-describes the page. `settings.mutate` (path-addressed set/unset
  ops) is wire-complete at the adapter (`SettingPathOp`); no dedicated UI —
  the two editor modes cover the same surface. Schema-driven forms (the
  Web's schema-form engine), secret-slot writes, and `settings.openDocument`
  stay deferred. `credentials.set`/`unset` store and clear writable
  credential refs; the whole plane stays loopback-gated.
- **No mid-stream token cancellation.** `session.cancel` is wired; per-turn UI
  behavior depends on backend event delivery.
- **Question cards are MVP-only.** Multi-select, optionless text, custom
  text, and per-question skip are supported; rich rendering and plan-review
  intents are not.
- **Queue editing is text-only.** Queued text items can be edited into a
  single text content block; non-text queued items disable the edit action,
  matching the Web client.
- **Goal editing is objective-only.** The MVP exposes the Web GoalBar edit
  verb; phase and blocked reason never change on edit, matching the host API.
- **Skills surface as the composer `/` source.** The session catalog comes
  from `skill.list {sessionId}` (name/description/whenToUse/modelInvocable),
  fetched once per session and cached like the Web client. While the draft is
  a single slash token, candidates filter by prefix (max 6); picking lands
  the literal `/name ` text — the host-side pre-step owns recognition. Skill
  authoring/management stays deferred.
- **Plan review is a question presentation intent.** The host's
  `exit_plan_mode` asks through the ordinary question channel with
  `intent {kind: 'plan-review', approve}`; the Android client parses the
  intent and renders a decision card — the detail slot (the markdown plan
  body) renders through MarkdownText, the approve option is the primary
  action, other options stay secondary, and answering rides the same
  `AnswerQuestion` flow. Generic questions render the generic editor.
- **Plan mode is projection-mirrored.** The `plan` session projection
  (`{active, pending}`, seeded from `session.history` projections and updated
  by `session/projection` frames) renders a chat-header state label;
  switching happens by sending the `/plan` slash command in the composer, as
  on the Web. The full plan-review conversation intents stay deferred.
- **Workspace ordering is durable via `workspace.insertBefore`.** Up/Down
  buttons anchor on the row above / two below (append past the end); the
  response carries the complete order and the adapter re-sorts the local list
  with it (the same path `host/workspace-order-changed` frames take, unknown
  ids keep relative order at the end). Drag-and-drop stays out of scope.
- **Plugin management is not a wire capability.** The host api exposes no
  plugin RPC (plugins compose host-side via cordis manifests and profiles);
  nothing for an Android client to reproduce — the deferred line retires.
  Skill authoring likewise stays host/filesystem-side; the client surface is
  the `/` candidate source.
- **Markdown rendering is a minimal pure-Kotlin slice.** Message bodies parse
  into blocks (fenced code with language label, headings 1-6, bullet lists
  nested to two rendered levels, block quotes, GFM pipe tables, paragraphs)
  and inline runs (code, bold, italic, links); an unterminated fence renders
  as an open `code (streaming)` block so streaming bodies stay readable.
  Links are clickable spans opening through the platform URI handler; tables
  render equal-weight columns on a tonal surface. The parser is plain
  JVM-tested Kotlin in `:app`; colors/fonts/shapes live in the Compose layer
  only.
- **Queue edit UI is a previewable dialog.** Editing a queued text item opens
  `QueueEditDialog` (Save no-ops on blank text, matching the Web composer
  constraint); non-text queued items keep the edit action disabled.
- **Attachments are images-only and MVP-scoped.** Picked images (png/jpeg/
  webp/gif) ride `session.prompt` as inline base64 parts after the text part;
  the host `imageLimits` projection (via `session.list`/`session.history`
  projections) gates media type, per-image bytes, and per-message count on the
  client, with fixture-matching defaults until the projection arrives. Timeline
  image blocks (`{type:'image', attachment:{...}}`) fold into `AttachmentRef`
  and download lazily through `session.attachment` (bytes cached, bounded).
  Re-encoding/downscaling, drag-drop, and clipboard paste stay out of scope.
- **Directory browsing is listing-only.** `host.listDirectory` /
  `host.createDirectory` power an in-app folder picker (navigate, create
  folder, select path back into the workspace field); manual workspace
  reordering and desktop `host.pickDirectory` dialogs remain out of scope.

## 11. Subagent Ownership

- A subagent is addressed by `parentSessionId` + `childSessionId`, never by display label.
- `SubagentEntry` exposes `id`, `kind`, `mode`, `activity`, `hasChildren`, `label`, and `reason`.
- `SubagentCatalog` carries `parentSessionId` explicitly and is scoped to that parent.
- MVP supports `subagent.list`, `subagent.history`, `subagent.prompt`, and `subagent.interrupt`.

## 12. Session Titles

- `session.list` `projections.values.title` is parsed on initial load.
- mux `session/projection` frames with `key == title` update `sessions` in place.
- Titles are display only; identity remains `sessionId`.

## 13. Goal Flow

- Domain carries `GoalRef`, `GoalProjection`, `GoalPhase`.
- Adapter wires `goal.create/pause/resume/edit/complete/clear`.
- Goal state is read from `session/projection` frames with key `goal`; it is never guessed client-side.
- Goal UI is parent/session scoped exactly like Subagents.

## 14. Background Jobs

- `session/jobs` mux frames fold into `TimelineItem.Jobs`.
- Job identity is backend-issued `id`; kind/status/detail/label stay display-only.
- Jobs are live snapshots, not durable session events; history replay does not reconstruct them.
