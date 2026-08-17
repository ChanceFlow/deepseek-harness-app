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
rename/fork, queue steer/remove, approvals, and questions.

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
- `core:harness-adapter`: timeline reducer tests for chunk/message/tool/approval folding.
- `app`: ViewModel tests with a fake `ChatRepository`.
- Integration with a real `dsh web` is manual or CI opt-in until a hermetic backend fixture exists.

## 10. Known Limitations and Deferred Work

- **Streaming is chunk-oriented, not final-block-oriented.** The reducer favors
  `text-delta`/`reasoning-delta`; provider adapters that emit only block events
  will still display finalized blocks from `assistant/message`.
- **No session title in list rows yet.** Titles are available through session
  projections and are not read in this milestone.
- **No settings screen yet.** Workspaces and model selection are MVP screens;
  credential and plugin settings remain out of scope.
- **No subagent/settings screens yet.** MVP focuses on the high-frequency chat/workspace/model workflows.
- **No mid-stream token cancellation.** `session.cancel` is wired; per-turn UI
  behavior depends on backend event delivery.
- **Question cards are MVP-only.** Multi-select is supported, but rich rendering
  and plan-review intents are not.

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
- Adapter wires `goal.create/pause/resume/complete/clear`.
- Goal state is read from `session/projection` frames with key `goal`; it is never guessed client-side.
- Goal UI is parent/session scoped exactly like Subagents.

## 14. Background Jobs

- `session/jobs` mux frames fold into `TimelineItem.Jobs`.
- Job identity is backend-issued `id`; kind/status/detail/label stay display-only.
- Jobs are live snapshots, not durable session events; history replay does not reconstruct them.
