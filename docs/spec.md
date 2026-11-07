# DeepSeek Harness Android Client Spec

Status: WebView shell shipped
([the shell decision](../.agents/notes/implemented/architecture/2026-11-06-webview-shell.md)).
Target: Android client for an already running dsh web backend.
Related code: `flutter/app/lib/shell/`, `flutter/app/lib/notifications/`,
`flutter/app/lib/backends/`, `flutter/packages/domain/`,
`flutter/packages/network/`, `flutter/packages/harness_adapter/`.

## 1. Goal

Render each configured host's own dsh web client in a WebView, so the chat
experience is the host's own page rather than a reimplementation, while the
client keeps two surfaces of its own: the multi-host registry and Android
notifications. Every dsh wire concept stays behind an anti-corruption layer;
the adapter still speaks the contract for notification folding.

## 2. Non-Goals

- No native re-implementation of the host's chat surface, no React Native,
  no design-system port. The host's page is the UI.
- No JavaScript bridge and no injected script: the page keeps its own
  navigation state, and the client reads the host API on its own socket.
- No changes to the dsh backend in this phase.
- No client-side agent/tool execution; the backend remains the only harness runtime.
- No client-side authentication: when authentication is desired, the separate
  `dsh-go-gateway` project provides it at the deployment layer (it can run with
  `DSH_GW_AUTH=none` for local/private deployments).

## 3. Architecture

The client is a WebView shell: one page per enabled host, laid side by side
on one horizontal strip; the 32×4 grabber pushes the strip down 96 px and
opens a 96 px drawer of host bubbles plus a settings orb, and nothing else is
drawn by Dart. The
notification pipeline is the client's own: the adapter keeps one event
socket per enabled host, folds `ChatRepository.observeSessions()`, and posts
Android notifications. There is no JavaScript bridge between the page and
Dart; the host's page and the adapter's socket are independent consumers of
the same host.

Module boundaries and dependency rules are owned by
[README §Module boundaries](../README.md#module-boundaries) and enforced by
`scripts/check_dart_imports.py`. The wire contract below is this spec's
subject; §4-§6 and §11-§20 document it and the adapter's folds, not surfaces
the client draws. The host's page draws its own.

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
  "method": "session/prompt",
  "payload": {
    "args": {}
  }
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

One downlink-only WebSocket stream is required:

```text
/api/remote.mux     required — the mux downlink
```

`/api/remote.mux` is the only downlink the host serves on current revisions.
The earlier `/api/events.mux` fallback is removed: it keyed on an HTTP 404 the
host never returns, so it could not fire. `/api/events.host` is not a route at
all — the gateway hangs its upgrade rather than answering, then closes the
dial as a 502 — so the client no longer dials it, and the `hostFrames` seam
and its folds are deleted. Every forwarded Host event the client folds rides
the mux `$events` stream (§4.5).

- Server frames are `ServerRequest` envelopes: `type`, `rpcId`, `method`, `payload`.
- `method` equals the frame payload `type`, e.g. `session/event`.
- Client messages on these sockets are protocol violations; the host closes 1008.
- GET on the path without an upgrade returns 426.
- The client offers `permessage-deflate` on the upgrade handshake; the host
  decides whether it negotiates. The client sends no keep-alive pings
  (dart:io 3.13's `pingInterval` can close healthy sockets with goingAway)
  and a cancelled downlink closes with a 2 s bound instead of waiting on the
  peer's close frame.

### 4.3 Interactive requests

A decision the reader must make — `ask_user_question`, its `plan-review`
intent, and a tool-approval prompt — arrives as a **forwarded Remote Event
waterfall** on the `$events` stream, not as a mux frame:

- The client opens the logical stream on `/api/remote.mux` with
  `{type: open, streamId: remote-events, endpoint: $events, payload: {args: {}}}`.
- Downlink items are `{type: item, streamId: remote-events, value: …}` whose
  value is `{type: 'ready', clientId, host}`, `{type: 'emit', event, args}`,
  `{type: 'waterfall', event, eventId, agentId, request}`, or
  `{type: 'cancel', eventId}`.
- `user-questions/request` and `approval/request` are the waterfall events this
  client answers; every other forwarded waterfall is delegated back with a
  `next` outcome. The frame's `agentId` is the session the request belongs to
  (the host projects the Agent out of `request`).
- The answer is a `POST` to the `$events/result` RPC:

```text
$events/result  { clientId, eventId, outcome }
outcome         { kind: 'result', value } | { kind: 'next' } | { kind: 'rejected', error }
value           user-questions: { answers: [{ id, selected, custom? }] }
                approval:       allowed-once | rejected
```

A dismissed question refuses the waterfall with `{name: 'UserQuestionError',
code: 'ASK_CANCELLED'}`. Answering or cancelling settles the local card; a
`cancel` item ends a request the host dropped, and a new stream generation
re-delivers every still-pending waterfall to the registering client.

The 0.1.1 mux frames (`question/requested`, `approval/requested` and their
`/resolved` counterparts, answered on `POST /api/respond` with a carrier
receipt) stay supported as the legacy path, and the adapter folds both
transports into one pipeline.

A **timed** `ask_user_question` (0.2.0) outlives that waterfall. The host row
`tool-ask-user` may run `mode: timed`, where the call carries a foreground wait;
when the wait ends the host continues the turn, and the call's own result
records the timeout. The still-answerable calls are then published as the
`userQuestions` session projection
(`{active: [{callId, questions, state: open | continued}], settled}`), and a
reply travels as `userQuestions/answer {agentId, callId, answer}` — the agent
address is the same `agentId` every other agent-scoped verb takes. An accepted
reply is steered into the agent as a user message whose source is
`user-question-reply`, so it appears as a new turn rather than as the original
call's result. The projection is one pending interaction here; an answer
travels through `userQuestions/answer` whenever the row is `continued`, and a
dismissal calls no host.
The reference's countdown (the `userQuestions/attachWait` stream, which holds
the claim and reports the remaining milliseconds) and its `settled` transcript
row are not mirrored (§10).

### 4.4 Registry-level pending interactions

Both transports feed a registry-global pending map, independent of any open
session store: a question tracks a `question`/`planReview` wait keyed by the
request id (a single binary plan-review intent classifies as `planReview`), an
approval tracks an `approval` wait keyed by its `approvalId`, and the matching
resolution — `question/resolved` / `approval/resolved`, a `cancel` item, or the
client's own answer — drops the key. `session.list` rows then carry a derived
`SessionSummary.pendingInteraction` (`approval` / `planReview` / `question`),
which notification detection reads. Replays are
idempotent by key; keys for sessions that disappear from `session.list` are
pruned, and a session's keys re-baseline in-band on its mux-generation
`session/subscribed` frame — the generation's replay follows that frame on the
same stream, so clearing on the connected publish would race the burst and wipe
a baseline that already landed.

A pending request is live state, not history: `question/requested` and
`approval/requested` never enter the session log, so a history rebuild (the
reconnect resync) keeps the open request cards instead of dropping them with
the events they replaced.

### 4.5 Forwarded Host events

The `$events` stream also carries ordinary forwarded Host events as
`{type: 'emit', event, args}` items. The client folds the names it has a
consumer for and acknowledges the rest on the diagnostic sink — the
forwarded set is an open host allowlist
(`API_REMOTE_FORWARDED_EVENTS` in
`packages/api/remotes/src/remote-events.ts`):

- `agent-preset/selected` — `args [sessionId, agentPreset]` folds the session
  summary's `agentPreset` in place (§15).
- `api-session/status` — `args [sessionId, running]`
  (`packages/api/session-controller/src/types.ts`). The running→idle edge for a
  session that is not the one being watched arms its finished-but-unviewed
  bit, which the notification fold reads; running again or viewing the session
  clears it, and the first observation of a session seeds the running baseline
  without arming. `session/list` pulls fold the same edge through the same
  baseline, so a turn that finished while the stream was down still arms on the
  reconnect pull.
- `api-session/added` — the single arg is the new session's `SessionSummary`,
  the same summary `session.list` carries (`types.ts`). It upserts the roster
  row in place — decoded by the `SessionWire` summary decoder, with the
  summary's projection hints applied and the folded finished-but-unviewed bit
  preserved — so a session created by another client appears without a
  `session.list` round-trip.
- `api-session/removed` — `args [sessionId]`. A subagent child keeps its roster
  row with `running: false` (the subagent catalog still navigates the child's
  history after its Agent ends — web `handleSessionRemoved` records a status
  mutation for an `origin: 'subagent'` summary); every other session leaves the
  roster on the event instead of on the next `session/list` pull.
- `api-session/activity` — `args [sessionId, updatedAt]`. Advances the row's
  activity time, which is the roster's ordering key, so a working session
  re-sorts live rather than on the next pull. A session the roster does not
  hold yet is ignored; its summary arrives with `added`.
- `commands/change` (no args) — the registry's membership moved, so any cached
  roster is stale. `ChatRepository.observeCommandRosterChanges` publishes the
  tick; a surface re-pulls `listCommands`.
- `cordis/request-run` — the single arg is a `DynamicCordisRunRequest`
  (`packages/extensions/cordis-host-runner/src/types.ts`): a `cordis_run`
  tool call whose plugin ships a browser half is blocked host-side until this
  is answered. It folds into the pending-request mirror behind
  `ChatRepository.observeCordisRunRequests`; the answer rides
  `dynamicCordisRunner/resolveRequestRun` (§4.8).
- `cordis/request-run-resolved` — `{requestId, outcome}`; another page
  answered or the host cancelled it, so the local pending mirror drops the
  request.
- `approval/request` / `user-questions/request` — waterfalls, delivered
  through the pending-request pipeline above rather than this fold.

The remaining allowlisted names (`api-session/error`,
`credentials/reference-updated`, `goal/activation-changed`, the
`cordis/dynamic-*` and `cordis/inspect-*` family, `llm/adapters-updated`,
`settings/document-updated`) are forwarded and currently have no fold here;
each is enumerated in the adapter's switch so a new name is a deliberate gap
rather than a silent drop. `api-session/error` is the one of those with a
user-visible consequence — it carries an Agent-level failure message the web
client puts on the Session handle, and `domain.SessionSummary` has no field to
hold it yet, so folding it needs a model field and a roster surface rather than
a switch arm.

The pinned 0.2.2 tree registers no host-frame vocabulary and serves no
`/api/events.host` route: the host dropped `host/session-status`,
`host/session-added` and `host/session-removed` by 0.1.2-alpha.1, and the
client neither dials the leg nor listens for those names. Session running
state, peer creation, removal and activity therefore each have exactly one
frame source — the `api-session/*` events above.

### 4.6 Wire coverage

`scripts/verify_wire_pin.py` derives this block from two registries — the
client's `DshRpcEndpoints` constants in
`flutter/packages/harness_adapter/lib/src/rpc_map.dart` and the pinned tree's
Typert Remote registration sites (`class … extends TypertRemoteService` plus
`@Remote` decorators under `reference/deepseek-harness/packages/**/src`, and
the Gateway's `$events/result` constant) — and fails when either registry
moves without this block and the README coverage sentence moving with it. It
also fails a declared-only allowlist name that the wire layer actually
invokes.

<!-- wire-pin:coverage:begin -->
declared = 105
upstream = 184
identical = 103
missing = 81
client-only = 2
out-of-scope = productAnalytics/enabled, productAnalytics/report
<!-- wire-pin:coverage:end -->

`declared` counts the client's endpoint constants; `upstream` counts every
unary Typert Remote method the pinned source tree registers (a superset of any
one deployment's loaded plugins; logical streams are excluded); `identical` is
their intersection; `missing` is registered upstream but not wired by the
client; `client-only` is declared by the client but not registered at 0.2.2 —
the reviewed names in
[scripts/gates_manifest.json](../scripts/gates_manifest.json)
(`wire_pin.declared_only_allowlist`). That list excuses a *declaration* only:
a name on it must have no call site under
`flutter/packages/harness_adapter/lib/src`, and one that is invoked fails the
gate as a defect. `out-of-scope` lists registered methods the client
intentionally does not wire: a name here must be a real pin method and must
stay unwired.

The comparison is by **name only**. A payload or result shape that changes
under a stable name — a renamed argument, a codec swap such as base64 to
multipart — is invisible here, so a shape claim rests on the reference citation
in the client code, not on this block.

The 81 unwired methods are accounted for by kind: 18 `forgePanel/*` and 12
`liveshareShares/*` are the 0.2.2 experimental change-request/worktree and
live-share panels, which the shipped web-app bundle does not mount; 11
`dynamicCordisRunner/*` render a live component in a browser or desktop surface the
adapter does not drive; 9 `cuaAccess/*` are the experimental computer-use
access plane; 5 `speech/*` describe the host speech plane, which the adapter does
not wire; 4 `account/startSignIn|cancelSignIn|signOut|
hasRunningAccountTasks` need an OAuth / platform callback the adapter does not drive; 4 `pluginMarket/*` belong to the optional custom-index service
(the web-app bundle mounts none of it); 4 `session/*` are the new passive
Snapshots (`events`, `state`, `wait`, `observe*` are streams) plus
`initializeDefaultModel`, which a created session already inherits; 3
`pluginManager/{listVersions,readBundleDetail,updateBundle}` would let a caller
update host plugin packages, which the host's page owns; 2 `cotTranslation/*`, 1 `actionCards/act`, 1
`claudeCodeMods/pressBand`, and 1 `pluginRecommendations/describe` are
experimental client-UI plugins absent from the shipped bundle; 1
`officeToPdf/generation` is the reference's browser-side PDF-cache invalidation
probe, which the adapter never reads ([office-to-PDF
wire](../.agents/notes/implemented/feature/2026-10-12-office-to-pdf-preview-wire.md));
1 `directoryPicker/pick` and 1 `settings/openSettingsDocument` open host-side
desktop dialogs and editors, while the host's page owns its workspace picker; the 2 `productAnalytics/*` are this block's `out-of-scope`
pair (the reference web client never calls them either); and the last
`goals/get` is a recorded overlap with its `path:line` evidence in the decision
notes (it carries only activation, which the notification fold never reads).

A stream the client opens with a literal string rather than through
`DshRpcEndpoints` — `workspace/follow`, `session/control`, `session/follow`,
`$events`, the per-session `job/list`, and the per-job `job/follow` and
per-terminal `terminal/attach` / `terminal/retain` — is outside this block's
comparison entirely, so a renamed or withdrawn stream route has to
be caught by hand or by the opt-in real-host tier. The same blindness covers a
unary endpoint called by a literal: this gate reads the `DshRpcEndpoints`
registry, so a call site that bypasses the registry is invisible to it. Routing
every unary call through `DshRpcEndpoints` is what keeps the block meaningful; a
stream name stays a literal because the block compares unary registrations, and
a constant for one would read as a client-only name.

### 4.7 Non-RPC routes

The client declares one host route that is a plain HTTP GET outside the typert
RPC envelope: it answers with a file body, so it has no `result` to unwrap and
no method name for the Remote registry. The client declares it in
`DshHttpRoutes` (`flutter/packages/harness_adapter/lib/src/rpc_map.dart`),
deliberately outside `DshRpcEndpoints`, whose members §4.6 compares against the
pinned Remote surface.

The pin serves further non-RPC routes the client does not declare, so this
section is the client's list, not the pin's: `GET|HEAD /api/file?path=<absolute>`
returns one file's whole bytes (no `Range`, capped by the attachment image
limit, MIME from the extension,
`reference/deepseek-harness/packages/api/session-controller/src/media-references.ts`),
and `present-open` / `changes-open` open or reveal a delivered path on the host
itself (`.../client/ui-deliverables/src/present-open.ts`).

| Route | Methods | Body | Client surface |
|---|---|---|---|
| `/api/session.export` | `GET`, `HEAD` | `application/zip` | `SessionLogExportRepository.exportSessionLog` |

`GET /api/session.export?sessionId=<id>[&includeDescendants=true]` streams
the session tree's log archive: `session.jsonl` for the root, one
`subagents/<id>/…` tree per descendant when `includeDescendants=true`, and
`media/<attachmentId>.<ext>` for every referenced attachment, with
`content-disposition: attachment; filename="dsh-session-<id>.zip"` (the id
collapsed to `[A-Za-z0-9_-]`). The host answers 400 for a missing or empty
`sessionId` or an `includeDescendants` other than `true`/`false`, 404 when the
session is unknown, 500 when the export services are unconfigured or the
stored log cannot be read, and otherwise 200 with `content-type:
application/zip`. Sources:
`reference/deepseek-harness/packages/session-query/session-log-export/src/index.ts`
(`SESSION_LOG_EXPORT_PATH`, the 400/404/500 branches) and `.../src/archive.ts`
(`sessionLogZipFilename`).

The adapter downloads the whole archive and buffers it, so a body truncated
below its declared length fails the call instead of settling as a short file.
Its deadline is a third case beside the adapter's short unary deadline and its
explicitly unbounded agent calls: 5 minutes, long enough for a large tree over
a slow link and still bounded (`kSessionLogExportTimeout`).


## 5. Connection Lifecycle

A connection generation is healthy when both required readiness facts hold:

1. `/api/remote.mux` WebSocket fired `onOpen`.
2. The mux delivered the `$events` registration answer: an item
   `{type: 'item', streamId: 'remote-events', value: {type: 'ready', clientId,
   host: {home}}}` (`reference/deepseek-harness/packages/api/gateway/src/
   stream-protocol.ts` `RemoteEventReadyFrame`). This is the pinned contract's
   readiness handshake — the reference client publishes exactly this frame's
   host facts as `ConnectionHostInfo` (`.../client/connection/src/client/
   connection.ts`, `.../api/gateway/src/client/remote-events.ts`) — and the
   client adopts it in place of the removed `host/describe` probe. A `ready`
   frame without its required `host.home`, a mux stream that closes before it,
   or one that does not arrive before the 30 s deadline fails the generation
   loudly; no default host description is substituted.

`HostDescription` carries only what the ready frame publishes: the account
`home` used to abbreviate displayed paths, plus a `version` that stays null —
no pinned route publishes a host version, so it is never fabricated. The
0.1.1 probe's other fields are gone: `cwd`, `provider`, and `model` are
per-session facts (`session/list` rows and `session/modelCatalog`), and
`attachedSessions` and `canOpenPath` are published nowhere. There is one
downlink leg only; §4.2.

After readiness, the client publishes `ConnectionPhase.CONNECTED`.

On any stream loss or handshake failure:

1. Publish `ConnectionPhase.RECONNECTING`.
2. Clear the stale `HostDescription`.
3. Retry with exponential backoff: base 500 ms, factor 2, cap 10 s.

After a new generation connects, the repository:

1. Refetches `session/list` (the workspace roster needs no pull: it rides the
   `workspace/follow` stream's per-generation baseline, §4.4).
2. Marks every opened root session store stale.
3. Refetches `session/page` for each of those sessions. A subagent child is
   never rebuilt here: its history is addressable only through its durable
   parent address, which the subagent view owns.
4. Replays buffered mux frames that arrived while history was loading.

The mux-open burst flows before the `CONNECTED` publish, so no live mirror is
re-baselined in this list: each session's `session/subscribed` frame drops
its pending-interaction keys, its queue projection, and its buffered queue
snapshot in-band, and the generation's replayed frames rebuild them after it
on the same stream.

### 5.1 后台保活

Android 在应用离开前台（含锁屏）后会把进程当 cached process 冻结：Dart
isolate 停转，mux 上再无活动，这一代连接静默死亡——上面那套退避重连要等
回前台才有机会跑。因此只要还有在飞的活（running 或等待用户的根会话），
客户端就启动前台服务：`MainActivity` 的 `dsh/keep_alive` 通道驱动
`DshKeepAliveService`（API 34+ 用 `specialUse` 类型，29–33 回退
`dataSync`；持有 `PARTIAL_WAKE_LOCK` 与一条低优先级常驻通知），进程不再
进入 cached 状态，熄屏下 socket 存活到回合结束。最后一个会话落定后 30 秒
停止服务；空闲时的后台断连仍按上面的退避重连，Doze 期间的网络挂起是已知
边界。范围与取舍见
[后台保活前台服务](../.agents/notes/implemented/feature/2026-09-11-background-keep-alive-foreground-service.md)。

## 6. Timeline Folding

Raw dsh session events are folded by `TimelineReducer` into neutral items.
`seq` is the deduplication boundary: an event whose `seq <= lastSeq` is ignored.
The dsh event map is merge-extensible, so an unrecognised type contributes no
item instead of throwing; it is not swallowed, though — the reducer reports the
type and its `seq` at debug on the adapter diagnostic channel (`timeline.event`,
never the payload), so a wire-coverage gap stays measurable.

| dsh event | Android timeline item |
|---|---|
| `turn/start` | `TimelineItem.TurnBoundary`; a later `turn/end` folds the turn's summed step `usage` onto it |
| `step/start` | no item — records its `(turn, step)` as the step owning the rows that follow (code-dispatch sub-calls carry no step on their own event) |
| `user/message` | `TimelineItem.Message` with `MessageRole.USER` |
| `assistant/chunk` (v1 log format) | live `TimelineItem.Message` with `streaming = true` |
| `assistant/message` | final `TimelineItem.Message` with `streaming = false`, carrying its step's `usage` and the recorded stream's first-token time |
| `tool/call` | `TimelineItem.ToolCall` with `status = RUNNING`, its step, and its logged start time |
| `tool/result` | paired `TimelineItem.ToolCall` with result/error status |
| `tool/ptc-dispatch-start` | nested `TimelineItem.ToolCall` (`parentCallId` set) under its root call's `children` |
| `tool/ptc-dispatch` | settles the paired nested call; a start outside the folded window still publishes the settled outcome as a row |
| `turn/end` (error/aborted/interrupted/max-tokens) | `TimelineItem.Error` — `code` = the wire kind; `message` = host error detail only (empty for non-error kinds); the client localizes known kinds by `code`, falling back to `message` |
| `approval/requested` | `TimelineItem.ApprovalRequest` |
| `question/requested` | `TimelineItem.QuestionRequest` |
| `approval/resolved`, `question/resolved` | removes the matching interactive card |
| `agent/inbox/spliced` | no item — rebuilds the durable pending next-turn/next-step lists; a later `user/message` whose id the `next-step` list claimed carries `steering = true` on its `TimelineMessage`, the reference's `SteeringHistory` classification |
| `step/end` | no item — bounds the step the rows before it belong to: the step's own assistant `TimelineMessage` carries `stepEndedAtEpochMs`/`stepEndSeq`, the reference's `stepEnd`. The step's *count* stays the stats fold's (`session_stats_fold.dart`), so nothing is counted twice |
| `workspace/changes` | no item — the turn's `TimelineTurnBoundary` carries `changesSeq`, the latest announcement's seq (the reference's `deliverables` node state). The changed-file summary itself stays on the host and is served for that seq |
| `session/queue` | `TimelineItem.Queue` snapshot with queued/steering/context entries — a live-only view the adapter publishes from the session's `inbox` projection: the history rebuild carries it over, and the session's next `session/subscribed` frame clears it before the generation's snapshot rebuilds it; required `items`/`id`/`placement`/`message` fields fail loud |
| `command/run` | `TimelineItem.Command` with `status = RUNNING` (name from the run event; `commandId` keys resolution) |
| `command/done` | resolves the paired `TimelineItem.Command` by `commandId` — `success` (with `text`) or `failed`; a `done` with no run in the window appends the settled card |
| `deliverables/presented` | no item — folds the event's `files` onto the `present` call named by its `callId`, so a declaration rides that call's own row; a declaration whose call lies outside the folded window publishes nothing |

Text extraction handles `text` blocks and nested `tool-result` content.

Live token deltas are the one fact the durable log does not carry: a 0.2.0 host
publishes them as cursorless `assistant-stream` frames on a `session/follow`
opened with `assistantStream: true`
(`packages/api/session-controller/src/history.ts:163`, `types.ts` `SessionFollowFrame`).
`TimelineReducer.ingestAssistantStreamFrame` folds those frames into the same
streaming partial as `assistant/chunk`, continued by `attemptId` + `revision` +
a dense `index` instead of `seq`, and the opening snapshot's
`assistantStream` baseline seeds the partial for a reply that is already in
flight. Neither the frames nor the baseline touches durable history.

### 6.1 Unwired vocabulary

Four names in the dsh vocabulary stay unfolded, and none is a port. The
three `team/*` journal events are not a client surface: the reference folds
them **host-side** into the `agentTeam` projection, which this client already
decodes. `sessionListMetadata` needs no client fold at all, because the host
folds it into the list row this client reads.

| name | kind | Reference | Verdict |
|---|---|---|---|
| `team/task` | session event | declared `packages/experimental/agent-team/src/types.ts:234`; folded host-side by `packages/experimental/agent-team/src/projection.ts:387-388` (`agentTeam`) | **do not port** — the client-side surface is the projection this client already decodes |
| `team/message/queued` | session event | declared `packages/experimental/agent-team/src/types.ts:236`; the same `agentTeam` fold | **do not port** — same projection surface |
| `team/message/delivered` | session event | declared `packages/experimental/agent-team/src/types.ts:238-243`; the same `agentTeam` fold | **do not port** — same projection surface |
| `sessionListMetadata` | projection | registered host-side `packages/api/session-controller/src/list.ts:80` | **covered** — the host folds it into the row's `blank`/`updatedAt` (`list.ts:109,148`), which `SessionWire` decodes |

### 6.2 Projection folds

Session projection values reach the client on four carriers — `session.list`
and `session.history` baselines, `session/projections`, and live
`session/projection` frames. The keys below are folded into a per-Session
stream the UI reads; a malformed value is reported as an adapter diagnostic
and leaves the last good value standing, never an empty one.

| key | Domain surface | Fold |
|---|---|---|
| `turnOutline` | `ChatRepository.observeTurnOutline` → `List<TurnOutlineEntry>` | every started turn's rail facts: `turn`, `turn/start` `seq`, bounded `prompt` and `response` previews, strictly increasing by turn (`packages/session/session-turn-outline/src/projection.ts:61-71`) |
| `subagentTiming` | `ChatRepository.observeSubagentTiming` → `SubagentTiming?` | a descriptor-backed child's `settledMs`, the open turn's `active` interval, and `lastTurnCompleted` (`packages/subagent/subagent/src/projection.ts:32-42,107-115`) |

## 7. Android UI Contract

The surface is the host's page, not a Dart widget tree.

- **One WebView per enabled host.** `HostWebView` loads
  `BackendConfig.baseUri` with JavaScript enabled and nothing injected. Hosts
  live side by side on one horizontal strip at exactly the viewport width;
  switching translates the strip (never resizes a page), so the host's page
  never reflows and never reloads. A jump from host A to host C sweeps past B
  in `240 ms + 60 ms` per intermediate page, capped at 600 ms.
- **The host pool bounds memory.** `HostPoolPolicy.maxLive` defaults to 3
  (the active host plus two warm neighbours). Beyond the budget the
  least-recently-used page is released and reloads from its URL when next
  selected; the active host is never evicted, and editing a host's URL bumps
  its revision so the page reloads in place.
- **The shell draws only its chrome.** The 32×4 grabber opens the exposé: the
  strip drops by the drawer height and a 96 px drawer shows one bubble per
  host (identity, reachability and live/sleeping state) plus a settings orb.
  The page keeps every gesture; the shell installs no pointer listener, so a
  WebView pan can never be mistaken for shell input. There is no host
  bar, no bottom navigation, no per-screen app bar, and no Material 3 port of
  the host's UI.
- **The registry is device-local.** The settings orb opens a native Flutter
  page with host add, rename, URL edit, enable/disable, TLS-certificate trust
  and removal, plus appearance, language and notification-permission rows.
- **The host page keeps its own state.** Cookies and `localStorage` are
  per-origin, so each host's last session restores itself. The shell wraps
  the page in `SafeArea` because the page ships no viewport-fit handling.
- **Notifications do not ride the page.** The adapter keeps one event socket
  per enabled host; `ChatRepository.observeSessions()` folds the roster into
  `AppNotificationCenter`, which posts an Android notification, with a
  tappable foreground toast composed by `ShellLifecycle`. Copy states the
  user's result first (`New reply`, `Approval needed`) and names the subject
  second (session, workspace, host) from one module shared by the toast and
  the system notification; channels are `New replies`, `Needs your input`,
  `In progress` and `Background connection`. The pipeline runs
  with only the shell mounted, reads nothing from the host's page, and a tap
  brings the app forward on the current host. The keep-alive foreground
  service keeps those sockets alive while work is in flight (§5.1).

The shell's own tokens live in `flutter/app/lib/theme/theme.dart`; the host's
page owns every pixel inside the WebView.

## 8. Security & Deployment

- The dsh backend's `/api` trust fence is reachability-only, not authentication.
  When authentication is desired, the separate `dsh-go-gateway` project provides
  it at the deployment layer (`DSH_GW_AUTH=none` for local/private deployments);
  the client itself performs none.
- The adapter's API socket sends no browser `Origin`/`sec-fetch-site` headers
  and relies on `Host`; the host's page in the WebView is an ordinary browser
  origin and carries whatever `dsh web` expects.
- Default base URL is `http://127.0.0.1:3080`; set another with
  `--dart-define=DSH_BASE_URL=http://<host>:3080` (the emulator reaches its
  host at `10.0.2.2`).
- Cleartext HTTP is permitted only for the loopback/emulator routes the app's
  own default uses (`127.0.0.1`, `localhost`, `10.0.2.2`) via the committed
  `network_security_config.xml`; every other host must be HTTPS.
- Production requires TLS termination in front of the backend.

## 9. Testing Strategy

- `packages/network`: envelope round-trip tests.
- `packages/harness_adapter`: timeline reducer tests for
  chunk/message/tool/approval folding; connection-generation tests with a
  fake transport and injected dispatcher; hermetic HarnessRepository
  fake-host integration tests for host workspace frames and mux
  session-event delivery.
- `app`: shell tests drive `ShellRoot` with a stand-in host view, so the host
  pool, switching and the chrome need no platform view; notification tests
  drive `AppNotificationCenter` from the fake repository's roster stream.
- Binary-download seam and session-log route: both run against a real
  loopback `HttpServer` (success, exact query parameters, non-200, and a body
  truncated below its declared length).
- Integration with a real `dsh web` is opt-in: pass `--dart-define=DSH_E2E_URL=…`
  and run `LocalDshE2eTest`; it is skipped otherwise. The define is what carries
  the target, because `flutter test` forwards only a fixed set of environment
  variables to the test process.

## 10. Known Limitations and Deferred Work

- **No JavaScript bridge, so a notification is not a deep link.** The host's
  page keeps its navigation state to itself; a notification tap brings the app
  forward on the current host rather than opening the session that finished.
- **The host pool caps warm pages at three.** A fourth host reloads when
  selected, and each live page costs roughly 100–200 MB.
- **Cookies ignore ports.** Two hosts on the same domain at different ports
  share storage; distinct hosts or subdomains are safe, a path-mounted
  single-origin gateway is not.
- **The host page ships no safe-area handling and no `viewport-fit`.** The
  shell wraps it in `SafeArea`; inside the page, a device cutout is the host's
  layout to fix.
- **Native extras are gone with the native screens.** Voice input and its
  on-device ASR, the in-app error-log viewer, gesture shortcuts, and the
  aggregated cross-host workspace view have no place in the shell; the host's
  page owns those surfaces now.
- **Host editing is controller-only.** The drawer adds and selects a host, but
  no shell editor yet exposes rename, URL edit, removal, or the per-host
  TLS-certificate opt-in; those registry actions have no screen of their own.
- **Notification coverage is roster-shaped.** A finished turn is a
  `running → idle` edge on `api-session/status` (§4.5), reconciled on the
  reconnect pull; the finished-but-unviewed bit drives the ongoing work row,
  and a pending approval or question notifies from the registry pending map
  (§4.4). The shell reports no watched session, so a turn finishing in the
  page on screen still notifies.

## 11. Subagent Ownership

- A subagent is addressed by `parentSessionId` + `childSessionId`, never by display label.
- `SubagentEntry` exposes `id`, `mode`, `activity`, `hasChildren`, and `label`. `mode` is the domain enum `SubagentMode` (`oneShot` / `continuable` / `unknown`), required on every roster row: a row with a missing mode — or one whose wire literal this build does not know — fails loud at decode. `hasChildren` is derived from `mode` (only a continuable child can host descendants) and `activity` from the session roster's own running bit, because the projection publishes neither.
- `SubagentCatalog` carries `parentSessionId` explicitly and is scoped to that parent.
- The roster is the parent Session's `subagentCatalog` projection, read through `session/projections`; `subagents/prompt` and `subagents/interruptByParent` remain the control verbs, and a child's transcript is read through `session/page` carrying a `subagent` address (`{kind: 'subagent', parentSessionId, childSessionId, mode}`). The pre-0.1.5 `subagent/history` name stays declared in the endpoint registry as a declared-only constant with no call site.
- That `subagent` address carries the addressed row's own `mode`; the host matches it against the durable entry and answers a mismatch as `subagent/unauthorized`, and a child the catalog no longer lists as `subagent/not-found`. `subagent.prompt` and `subagent.interrupt` are pinned to `'continuable'` by the request schemas.
- The catalog tree is a host-reported fact: the projection folds the parent's
  own durable `subagent/catalog` events, so a cold host answers the parent's
  complete child tree.
  `SubagentController` seeds the pre-selected parent's catalog once the
  host's `session.list` includes that session; each landed snapshot
  replaces the tree, and live events never merge catalog rows.
- `session.list` rows carry the spawning parent as `SessionSummary.parentSessionId`. A child appearing under — or leaving — the selected parent or an expanded branch schedules one debounced `subagent.list` re-pull for that parent (web manager `scheduleCatalogRefresh`); a removal or a running-state flip folds that child's catalog-row activity locally first (lit or dimmed, web `updateCatalogActivity`). Event re-pulls are independent of the cold seed's once-per-parent gate.
- Subagent children never surface as selectable parents: the picker sheet applies the app-wide `sessionVisible` rule alongside the sidebar.

## 12. Session Titles

- `session.list` `projections.values.title` is parsed on initial load.
- mux `session/projection` frames with `key == title` update `sessions` in place.
- Titles are display only; identity remains `sessionId`.

## 13. Goal Flow

- Domain carries `GoalRef`, `GoalProjection`, `GoalPhase`.
- Adapter wires `goal.create/pause/resume/edit/complete/clear`.
- Goal state is read from `session/projection` frames with key `goal`; it is never guessed client-side.
- Goal state is parent/session scoped exactly like Subagents.

## 14. Background Jobs

- The adapter opens one `job/list` stream per followed session
  (`packages/api/job-controller/src/index.ts`, `@Remote({ mode: 'stream' }) list`)
  and republishes each `{type: 'rows', jobs}` frame as the `session/jobs` frame
  the fold owns, so `TimelineItem.Jobs` keeps one decode site. 0.1.7 deleted the
  control baseline's `jobs` block, which was the only earlier source.
- Job identity is backend-issued `id`; kind/status/detail/label stay display-only.
  `JobView` is a superset of the deleted `SessionJob`, so an added field is
  ignored rather than decoded.
- Jobs are live snapshots, not durable session events; history replay does not reconstruct them.
- `job/follow` is the per-job retained-output observation, opened by literal for
  one `(session, job)` pair while a row is expanded. Its frame union is closed:
  `opened {job, from}` (always first — `from` is the anchor the next `output`
  continues at), `output {chunks, next, lossy?}`, and the terminal
  `status {job}`, which ends the stream. Omitting `from` anchors at the job's
  oldest retained byte, never at zero, so a re-expansion resumes from the last
  published `next` instead of replaying the retained head. A frame or chunk
  flagged `lossy`/`gapBefore` is a retention gap the surface reports above the
  output rather than gluing non-adjacent text together.
- `job/kill` (unary, `request`-wrapped) stops a job on a human's behalf. Its only
  business code is `job/not-found` — the session's list no longer carries a
  killable row, covering both an unknown id and another session's job — and
  `outcome: 'already-finished'` is a success. The kill is not the model's own, so
  the owning agent still receives the standard completion notice.

## 15. Agent Presets & Permissions

- `agentPresets/list` decodes the roster: entries (`id`, `isDefault`,
  optional `name`/`description`/`broken`). 0.1.7 dropped the per-row `trust`
  and the roster-level `authorable`, so the roster is path-free and
  trust-free; a missing required field fails loud.
- `agentPresets/select` switches a blank session's preset and returns the
  echoed id; host refusals (`agent-preset-locked`, `agent-preset-not-found`,
  `agent-preset-invalid`) surface as
  `DshBusinessException` with the host code.
- The forwarded owner event `agent-preset/selected` (a `$events` `emit` item
  with `args [sessionId, agentPreset]`, §4.5) folds the session summary's
  `agentPreset` in place. Other forwarded events are ignored — the
  allowlist is open and host-owned.
- The `permissions` session projection (mux `session/projection`, key
  `permissions`) decodes the permission select (`options` of
  `value`/`name`/optional `description`, plus `currentValue`) onto
  `observePermissions`. A `null`-valued or malformed frame yields null —
  the same hidden state as a host composing no permission service.
  Unknown projection keys are ignored (the key set is open).
- `agentPresets/read` stays uncovered: a mobile client cannot manage the
  roster, only read it and switch blank sessions. 0.1.7 deleted `copy`,
  `deletePreset`, and the preset-directory settings methods along with the
  trust and authoring facts they served, so the app shows the roster as one
  flat list and offers no authoring affordance. The 0.1.1 per-method loopback
  pin (`PRIVILEGED_METHODS`) is gone from the pin, so these are out of scope
  by product decision, not by a host-side privilege fence (§4.6).

## 16. Host Commands

- `commands/execute` (typert remote bridge: wire path
  `/api/commands/execute`, envelope `payload.args {agentId, line,
  submittedAttachments}`) executes one slash-command line through the host
  command registry — the line never reaches the model (`session.prompt` does not
  parse commands; the host's own docs notwithstanding, the model would
  receive the text as ordinary content). A matched command returns the
  settled execution (`commandId`, `result.kind` `success|error`,
  optional `text`); an unmatched name returns ok with no value slot.
  The `submittedAttachments` arg carries base64-encoded composer uploads
  (`{type: 'image', mediaType, data, name?}` in submission order); the
  descriptor validates the key and the tag strictly, so an untagged or
  differently-named slot fails the whole call
  (`gateway/arguments-invalid`). The host admission settles an error
  result when the command does not declare attachment acceptance
  (`plan` and `goal` do).
- The host's page owns command dispatch, the composer's attachment policy,
  and the bare-only/args-tolerant decision; the wire admits both, and a command
  whose handler answers without a value slot is a successful no-op.
- `commands/list` is wired: `ChatRepository.listCommands(agentId)` decodes the
  addressed agent's live descriptor array (`{name, description, input?: {hint,
  attachments?}}`, name-sorted by the host). No advertised `input` is the
  wire's bare-only signal; an advertised hint makes the command
  args-tolerant. A subagent-owned child is refused `session/agent-busy`.
  `commands/change` invalidates every cached roster.

## 17. Agent Teams

- Agent Teams reach this client as a **Session projection**, never an RPC
  namespace. The host publishes `agentTeam` on the control stream
  (`{type: 'projection', sessionId, key, value, seq}`), and it also rides the
  `session/control` baseline, the `session/follow` snapshot, `session/list`
  hints, and the `session/projections` read — the same four-carrier path every
  other projection takes (`packages/experimental/agent-team/src/projection.ts`
  `key: 'agentTeam'`).
- The value is the Lead Session's `TeamProjection`: `members` (durable roster
  rows with `phase` `provisioning`/`active`/`failed` and an optional `error`),
  `tasks` (the non-deleted board, each row carrying `revision`, `subject`,
  `description`, `status`, `blockedBy`, `writeScopes`, optional `ownerName`,
  `ready`, and `writeScopeWarnings`), and an optional `failure`.
- Absence is null, never an empty team: a host that mounts no Agent Teams
  package simply never carries the key, and the header action stays hidden. An
  empty team and an unmounted one must not look the same.
- `failure` is terminal on the host: it keeps the last valid roster and board
  and stops applying records, so the panel shows that failure above them rather
  than presenting stale rows as current.
- Activity is derived, because `phase` is durable only: an `active` member reads
  running from live Session status with the roster as the fallback, and a
  Session the roster does not know reads inactive. Provisioning and failed
  members keep their durable phase.
- The Lead of a conversation is the subagent address's parent when the session
  is a teammate, else the session itself. Selecting the Lead opens that
  Session; selecting a teammate opens its addressed child through the same
  route the subagent catalog uses (`session/page` with the child address).
- The board is read-only: team agents create and update tasks through their own
  tools, and no client mutation control exists on the wire.

## 18. Plugin Management

The host's page owns every plugin surface below; these are the wire facts the
adapter decodes.

- `pluginInventory/list`'s `managementAvailable` is the gate: false means the
  host composes no plugin manager, so the surface offers no roster and no
  install action rather than calling methods the deployment does not register
  (`packages/host/plugin-inventory/src/index.ts` sets it from
  `ctx.get('pluginManager') !== undefined`).
- The roster is two reads: `pluginManager/listBundles` (installed and optional
  bundles with their switchable rows) and `pluginManager/listPlugins` (loaded
  entries with their patch targets). Each answers its rows as the bare JSON
  array the method returns — `BundleInfo[]` and `PluginInfo[]`
  (`packages/boot/plugin-manager/src/index.ts`), never an object field — so an
  empty roster is an empty array, not a missing key. A row or bundle is
  switchable only when the host addressed it; `readOnlyReason`
  (`management-required` | `unaddressable`) is why a roster row cannot be
  changed, and it renders as a reason rather than a disabled control with no
  explanation.
- Every mutating method answers a `ChangeResult`, and expected refusals are
  *values* inside it (`error.code`), never transport errors: `changed`,
  `application` (`applied` | `restart-required` | `overridden` | `failed` |
  `cancelled`), `stage`, `target`, optional `error`, `packageResult`,
  `pendingBuilds`, `bundle`, and `failedAt`.
- Installation is inspect → install → enable, three separate steps:
  `pluginManager/inspect` resolves the spec (a refusal is a value with its
  `problem`, and a network refusal names every registry asked);
  `pluginManager/installBundle` runs pnpm **with `enabled: false`** so
  activation is always deferred; `pluginManager/setBundleEnabled` activates.
  Progress is pushed, not polled: `plugin-manager/install-state` carries the
  phase (`installing` | `cancelling` | `applying`) with the registry attempt
  being asked, and `plugin-manager/install-log` carries the package run's
  output chunks.
- A client-minted `requestId` is what makes the host emit those events, and
  `pluginManager/waitForInstall` reconciles a lost unary reply: null means the
  host has no record of that request, which the surface reports as
  *unconfirmed* rather than guessing an outcome. `pluginManager/cancelInstall`
  answers `cancelled` | `too-late` | `not-running`; `too-late` means the host is
  already applying, so the pushed phase must not regress.
- A failure carrying `pendingBuilds` is the host refusing to run package build
  scripts: retrying with those names in `approvedBuilds` is the human's
  explicit acceptance, and the surface offers exactly that.
- `pluginManager/removeBundle` is the only destructive operation and the only
  confirmed one. `plugin-manager/changed` (a reason: `plugin` | `bundle` |
  `install` | `remove`) means the profile's composition moved, so every roster
  read is stale and the page re-reads rather than assuming.
- `pluginManager/listVersionExemptions` / `setVersionExemption` carry the saved
  `name@version` → runtime-version ledger. A grant needs the exact *current*
  runtime version and `acceptRisk: true`, so the wire pair lists and revokes
  and leaves granting to a flow that has just been refused for a version mismatch.
  The reference Web page has no exemption UI at all; the pair is a deliberate,
  wire-only addition (decision note:
  [Plugin management](../.agents/notes/implemented/feature/2026-09-29-plugin-management.md)).
- The Web page's `plugins.*` configuration slots (arbitrary React components
  other client plugins contribute), the `configForms` settings surface, and
  `ctx.pluginNavigation` are the host page's own; the wire describes none of
  them.

## 19. Scheduled Tasks

The host's page owns the scheduler surface; these are the wire facts the
adapter decodes.

- The `schedule` namespace is **nine unary methods**: `deliveryLimits`,
  `create`, `list`, `catalog`, `view`, `history`, `run`, `deleteInactive`, and
  `edit`. `create`, `list`, `view`, `history`, `run`, and `edit` each take one
  `Schedule*Request`; `catalog`, `deliveryLimits`, and `deleteInactive` take no
  arguments. `list` answers a page object (`items`, `shown`, `total`, `limit`,
  `offset`); `catalog` answers a bare array and therefore rides the transport's
  `value` slot.
- **Tasks are host-wide, not Session reminders.** Each row carries a
  `target` (`session` | `new_once` | `new`), `involvedSessionIds`, a status of
  `active` | `paused` | `ended`, and the `updatedAt` revision an editor sends
  back as `expectedUpdatedAt`. The record unions add `rrule` to the pinned
  six timing kinds, and a task may now be created, viewed, run on demand, and
  paused/resumed from the client.
- The shipped 0.2.2 web-app bundle **mounts the schedule service and its UI**,
  so a stock host serves this surface. The page still probes `catalog` and
  renders `gateway/invocation-unavailable` as a stated absence for a host that
  patches the row out.
- The record union is keyed by `kind` (`after`, `at`, `every`, `daily`,
  `weekly`, `cron`, `rrule`) and the decoder enforces each variant's own
  required fields: a `weekly` row without weekdays, a `daily` row without its
  time or zone, a `cron` row without its expression, or an `rrule` row without
  its two-line rule fails loud rather than rendering as some other rule.
  Instant-based kinds (`after`, `at`, `every`) store only the UTC instant and
  carry no zone; the wall-clock kinds always carry one.
- Every mutation is an **edit under compare-and-update**: `schedule/edit`
  carries `action: 'update' | 'delete'`, and an update carries a `patch` with
  only the changed fields plus the observed `expectedUpdatedAt`. A stale
  revision answers `schedule_conflict`, an unknown task `schedule_not_found` —
  as values inside the result, with no write performed. An omitted patch field
  keeps the committed value, so editing a name alone never resets when the task
  runs.
- Business failures travel **inside the value** for `edit`, `view`, `run`, and
  `history`; argument validation that fails before storage raises
  `schedule/input-invalid` with one of the package's own codes. A delivery
  against an archived Session target raises `schedule/target-archived`.
- `schedule/history` pages newest-first by exclusive message-id cursor
  (`before` → `nextBefore`) with a required limit of 1…100; a missing task or
  an evicted cursor answers a code. `earlierRecordsUnavailable` and
  `earlierRecordsPruned` are separate facts and are reported separately: the
  first says records may be missing, the second says an append removed them.
  A legacy receipt carries no prompt, and the surface never substitutes the
  task's current instruction for it.
- **The `schedule/change` Session event is historical.** New tasks live in the
  host store and emit no Session event; the durable `schedule/changed` Cordis
  event drives a catalog re-read. This client keeps folding version-1
  `schedule/change` records from existing logs (the chat reminder strip reads
  them), but that strip cannot show a task created through the modern surface;
  the settings page's catalog is the authority.
- The page's list is the cross-session catalog with a status filter and a
  search over the stored name, the instruction, and the involved Session ids —
  never a resolved session title, which is the reference's own limit. It
  offers edit (including an rrule field), pause/resume through `edit`, manual
  `run`, and the confirmed edit-delete; it still has no create form, which is
  deferred work rather than a wire limit now that `schedule/create` exists.
- A deleted task takes its saved deliveries with it. Archiving a session with
  active tasks is refused host-side unless the caller stops that activity, and
  unarchiving does not restore them; workspace deletion does not touch
  schedules at all.

## 20. Terminals

The host's page owns the terminal surface; these are the transport facts.

- The `terminal` namespace is **six unary methods plus two streams**:
  `environment`, `shells`, `list`, `create`, `rename`, `close`, and the
  `attach` / `retain` streams. Every method but `list` takes the Agent lookup,
  whose wire field is **`agentId`** — never `sessionId`
  (`TypertLookupMap.agent = TypertLookup<Agent, SessionId>` names the field
  `${key}Id`, and the host refuses an unknown argument outright).
  `terminal/list` and `terminal/retain` take the bare `sessionId`, which is
  what lets them serve a dormant session.
- A terminal **outlives its attachment**. Detaching — collapsing the panel,
  switching tabs, losing the transport — never ends the process; only `close`
  (or host disposal, or unattended reclamation) does. Reconnecting opens a
  *fresh* attachment, and the previous attachment keeps neither input control
  nor its sequence anchor.
- **One duplex stream carries both directions.** `terminal/attach` sends
  `snapshot`, `output`, `state`, and `ack` frames down while the client sends
  `TerminalInput` commands up on the same mux stream: `{type: 'write', sequence,
  data}` and `{type: 'resize', sequence, cols, rows}`, numbered consecutively
  from one per attachment. The host acknowledges each accepted command with an
  `ack` echoing its sequence; a refused command carries `refusal:
  'read-only' | 'not-running'` and is never replayed.
- **There is no resume offset.** A generation opens with `snapshot` and
  continues with `output` frames numbering strictly `sequence + 1`. A gap
  cannot be patched, so it is recovered by re-attaching and replaying a new
  snapshot. Output missed while detached is visible only if the host's bounded
  scrollback still holds it; the page never claims otherwise.
- `snapshot` carries the complete bounded screen, the terminal's metadata, and
  `writable`; `output` carries a chunk and its sequence; `state` carries
  metadata plus the current `writable`; `ack` settles one input command. Input
  control belongs to the attachment itself: `writable: false` is how a second
  window learns it is read-only, and taking control is a new attachment, not a
  method.
- `retain` is the one hold a **dormant** session can take, and its single frame
  (`retained`) is the acknowledgement; the stream stays open while the hold
  lives. It is not a window manager: the reference's multi-pane, drag-resize
  window layout is client-side and has no wire representation.
- `terminal/create` is **idempotent for an open identity**: the id is minted by
  the client and stable across reconnects. Sizes are clamped host-side to
  `maxCols` / `maxRows` from `environment`, and input is bounded by
  `maxInputBytes` plus the stream's `maxBufferedBytes` inbox. A caller clamps
  its proposal to those maxima before sending and never proposes a degenerate
  size.
- **The sandbox is not extended to a terminal.**
  `terminal/create` allocates a shell with the host's own system-user
  permissions, independent of the Agent's sandbox and approval policy; the
  host's page says so where a terminal is started and never implies the agent's
  restrictions apply.
- Business failures are `terminal/unavailable`, `terminal/control-unavailable`
  (with `reason: 'read-only' | 'not-running'`), and `terminal/limit-reached`
  (with `limit`). Losing control is not a transport failure: the terminal stays
  attached and read-only. A failed cleanup keeps the terminal for a retry
  rather than reporting a close that did not happen.
- Rendering belongs to the host's page, which lazy-loads `@xterm/xterm` for a
  full grid. The shell draws no terminal and keeps only the transport facts
  above (decision note:
  [Terminals](../.agents/notes/implemented/feature/2026-09-29-terminals.md)).
- ZMODEM, `ui-sidebar-terminal`'s window holds, and the browser's
  terminal-pool prewarming have no wire surface and are not mirrored.

### 4.8 Session-event folds

The reducer folds five event families the client previously dropped. Each
decoder reads its field names from the pinned source named below; a required
field that is absent or mistyped throws with that field name, and each type is
enumerated in the reducer's switch so a genuinely unknown type still reaches
the §4.5 diagnostic.

- **Tool result presentation.** The host's `presentCall`/`presentResult`
  functions never cross the wire: `SessionWireEvent`
  (`packages/api/session-controller/src/types.ts`) admits only `type`, `seq`,
  `time`, `data`, `ignorable`, `surfaceOp`, and `sourceEventSeqs`, and
  `assertSessionWireEvent` rejects any other member. A `{for: 'call'|'result'}`
  `view` payload therefore does not exist on the wire; what the host ships is each
  tool's persisted `output.presentationMeta` as the `tool/result` event's
  `meta` member. The adapter narrows that opaque member into
  `ToolResultPresentation` arms — `read` (path, offset, numbered lines,
  totalLines, lang), `diff` (path/oldText/newText hunks, read-only: the
  reference diff card carries no accept/reject), `search` (`shape` `matches`
  with per-file grouped lines, or `paths`; `truncated`/`total`), `web`
  (`kind` `search` with sources/answer, or `fetch` with url/statusCode), and
  the persistent-terminal `viewport`/`waitReason`/`sessionStatus` payload. A
  payload with no recognized shape yields `null` — the reference's generic
  fallback; a recognized card with a missing member throws. `bash` persists no
  metadata, so its terminal card stays re-derived from the result text, as in
  the reference.
- **Hook audit.** `hook/invoked` + `hook/result` are log-only
  (`packages/hooks/hook-protocol/src/events.ts`; not a `SurfaceEventType`).
  They fold into one `TimelineHookAudit` row paired by `handlerId`, so a
  blocking `PreToolUse` deny reads as an audit record (`decision`, `exitCode`,
  `stderrSummary`, `durationMs`) instead of an ordinary tool failure.
- **Sandbox mode.** The log-only `sandbox/mode` event
  (`packages/sandbox/sandbox-policy/src/session-mode.ts`) folds to the
  session's effective `SandboxModeFact` (mode + `source: 'delegation'`);
  `ChatRepository.observeSandboxMode` publishes it. This is the durable fact;
  the `[sandbox: file access denied under …]` text in a tool result remains a
  model-facing marker, not the state source.
- **Schedule reminders (historical).** The versioned `schedule/change` event
  (`packages/schedule/schedule/src/types.ts`) is inert in 0.2.2: new tasks live
  in the host store and publish no Session event. The fold into the active
  `ScheduleReminder` list (create, delete, dispatch) is kept only so logs
  written before the host-level store still render; a one-shot leaves the set,
  a fixed-rate record advances to its next anchor-aligned target.
  The fold is window-tolerant because the reducer replays a history page, not
  the complete log: a delete/dispatch naming a record created before the page
  is a no-op rather than an error, while the window-independent contract
  violations (`version` other than 1, a one-shot dispatch carrying
  `acceptedAt`, a fixed-rate dispatch without one) still fail loud.
  `ChatRepository.observeSchedules` publishes the list.
- **Durable workflow runs.** The four `tool-workflow/*` events
  (`packages/workflow/tool-workflow/src/types.ts`) fold into one
  `TimelineWorkflowRun` keyed by `runId`, following the reference
  conversation node (`packages/client/ui-workflow-run/src/client/
  workflow-definition.ts`): a tail carrying only updates stays pending until
  the unique `run-start` arrives, members group into phases by first-seen
  order (the absent phase is the distinct `missing` key), and a run whose turn
  closed with no terminal event presents as `interrupted` for the run and its
  unsettled members — the workflow tool's own `tool/result` row is unchanged.
- **Cordis plugin approvals.** See §4.5 for the forwarded request and
  `dynamicCordisRunner/resolveRequestRun` for the answer. The host's
  `DynamicCordisRunResolution` union is modelled in full
  (`CordisRunApproved`/`CordisRunRejected`/`CordisRunFailed`). An approval
  names the exact `pluginRunId` an answering page created by loading the
  plugin's browser half; the Android client has no such runtime, so rejection
  is the decision it can deliver — and the one that releases the blocked
  `cordis_run` call. Settled requests also drop on
  `cordis/request-run-resolved`, and the pending mirror clears at a `$events`
  generation boundary because forwarded `emit` items are not replayed
  (`packages/api/gateway/src/index.ts`); re-deriving pending approvals from
  `dynamicCordisRunner/inventory` (the web panel's `reconcileApprovals`) is
  not wired here.
- **Latency boundaries.** `TimelineMessage.stepStartedAtEpochMs` is the
  owning `step/start` event's logged `time` and `firstTokenAtEpochMs` the
  first token delta's; their difference is the reference's TTFT
  (`client/ui-chat/src/client/contract/turn-metrics.ts`,
  `assistantStepReading`). `TimelineTurnBoundary.startedAtEpochMs` /
  `endedAtEpochMs` are the `turn/start` / `turn/end` event times, so a
  surface can show a turn's wall time. A field whose event fell outside the
  folded window stays null and the UI omits it — no figure is derived or
  defaulted.
- **Folded items with no shell surface.** Folding `TimelineHookAudit`,
  `TimelineWorkflowRun`, the sandbox fact, the schedule reminders and the
  Cordis-request mirror publishes adapter facts that the WebView shell draws
  nothing from: the host's page owns the transcript and the composer. They
  stay wired because the adapter's job is the contract, and the notification
  fold reads the same stream.
