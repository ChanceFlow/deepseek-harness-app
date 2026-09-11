# DeepSeek Harness Android Client Spec

Status: Flutter rewrite shipped (route A, [ADR-0001](adr-0001-flutter-rewrite.md);
(ADR-0001).
Target: Flutter client for an already running dsh web backend.
Related code: `flutter/app/`, `flutter/packages/domain/`,
`flutter/packages/network/`, `flutter/packages/harness_adapter/`.

## 1. Goal

Provide a native Flutter client that reproduces the core Web chat experience
of DeepSeek Harness while keeping every dsh wire concept behind an
anti-corruption layer.

## 2. Non-Goals

- No WebView UI, no React Native, no server-driven UI.
- No changes to the dsh backend in this phase.
- No client-side agent/tool execution; the backend remains the only harness runtime.
- No client-side authentication: when authentication is desired, the separate
  `dsh-go-gateway` project provides it at the deployment layer (it can run with
  `DSH_GW_AUTH=none` for local/private deployments).

## 3. Architecture

Module boundaries and dependency rules are owned by
[README §Module boundaries](../README.md#module-boundaries) and enforced by
`scripts/check_dart_imports.py`. The wire contract below is this spec's subject.

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

### 4.4 Registry-level pending interactions

Both transports feed a registry-global pending map, independent of any open
session store: a question tracks a `question`/`planReview` wait keyed by the
request id (a single binary plan-review intent classifies as `planReview`), an
approval tracks an `approval` wait keyed by its `approvalId`, and the matching
resolution — `question/resolved` / `approval/resolved`, a `cancel` item, or the
client's own answer — drops the key. `session.list` rows then carry a derived
`SessionSummary.pendingInteraction` (`approval` / `planReview` / `question`),
which notification detection and navigation surfaces read. Replays are
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
  session that is not the one on screen arms the sidebar's
  finished-but-unviewed completion dot; running again or opening the session
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

The pinned 0.1.5 tree registers no host-frame vocabulary and serves no
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
declared = 54
upstream = 84
identical = 52
missing = 32
client-only = 2
out-of-scope = agentPresets/read, agentPresets/copy, agentPresets/deletePreset
<!-- wire-pin:coverage:end -->

`declared` counts the client's endpoint constants; `upstream` counts every
unary Typert Remote method the pinned source tree registers (a superset of any
one deployment's loaded plugins; logical streams are excluded); `identical` is
their intersection; `missing` is registered upstream but not wired by the
client; `client-only` is declared by the client but not registered at 0.1.5 —
the reviewed names in
[scripts/gates_manifest.json](../scripts/gates_manifest.json)
(`wire_pin.declared_only_allowlist`). That list excuses a *declaration* only:
a name on it must have no call site under
`flutter/packages/harness_adapter/lib/src`, and one that is invoked fails the
gate as a defect. `out-of-scope` lists registered methods the client
intentionally does not wire: a name here must be a real pin method and must
stay unwired.

### 4.7 Non-RPC routes

One host route is a plain HTTP GET outside the typert RPC envelope: it answers
with a file body, so it has no `result` to unwrap and no method name for the
Remote registry. The client declares it in `DshHttpRoutes`
(`flutter/packages/harness_adapter/lib/src/rpc_map.dart`), deliberately
outside `DshRpcEndpoints`, whose members §4.6 compares against the pinned
Remote surface.

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

The client downloads the whole archive and buffers it, so a body truncated
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
| `assistant/chunk` | live `TimelineItem.Message` with `streaming = true` |
| `assistant/message` | final `TimelineItem.Message` with `streaming = false`, carrying its step's `usage` and the recorded stream's first-token time |
| `tool/call` | `TimelineItem.ToolCall` with `status = RUNNING`, its step, and its logged start time |
| `tool/result` | paired `TimelineItem.ToolCall` with result/error status |
| `tool/ptc-dispatch-start` | nested `TimelineItem.ToolCall` (`parentCallId` set) under its root call's `children` |
| `tool/ptc-dispatch` | settles the paired nested call; a start outside the folded window still publishes the settled outcome as a row |
| `turn/end` (error/aborted/interrupted/max-tokens) | `TimelineItem.Error` — `code` = the wire kind; `message` = host error detail only (empty for non-error kinds); the client localizes known kinds by `code`, falling back to `message` |
| `approval/requested` | `TimelineItem.ApprovalRequest` |
| `question/requested` | `TimelineItem.QuestionRequest` |
| `approval/resolved`, `question/resolved` | removes the matching interactive card |
| `session/queue` | `TimelineItem.Queue` snapshot with queued/steering/context entries — a live-only baseline: the history rebuild carries it over, and the session's next `session/subscribed` frame clears it before the generation's snapshot rebuilds it; required `items`/`id`/`placement`/`message` fields fail loud |
| `command/run` | `TimelineItem.Command` with `status = RUNNING` (name from the run event; `commandId` keys resolution) |
| `command/done` | resolves the paired `TimelineItem.Command` by `commandId` — `success` (with `text`) or `failed`; a `done` with no run in the window appends the settled card |

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
- The session header carries the session-log download action
  (`session_log_export_action.dart`): a compact seat that streams the open
  session's ZIP, turns into a spinner while the archive is in flight, and
  announces the settled outcome in a snack bar — the success line names the
  location the platform wrote to, the failure line is localized (the cause
  goes to the error log). It renders nothing without a selected session or
  without a composed export seam.

## 8. Security & Deployment

- The dsh backend's `/api` trust fence is reachability-only, not authentication.
  When authentication is desired, the separate `dsh-go-gateway` project provides
  it at the deployment layer (`DSH_GW_AUTH=none` for local/private deployments);
  the client itself performs none.
- The client sends no `Origin`/`sec-fetch-site` headers; it relies on `Host`.
- Default base URL is `http://10.0.2.2:3080` for the emulator; set with
  `-PDSH_BASE_URL=http://<lan-ip>:3080`.
- Cleartext HTTP is permitted only for the loopback/emulator routes the app's
  own default uses (`127.0.0.1`, `localhost`, `10.0.2.2`) via the committed
  `network_security_config.xml`; every other host must be HTTPS.
- Production requires TLS termination in front of the backend.

## 9. Testing Strategy

- `core:network`: envelope round-trip tests.
- `core:harness-adapter`: timeline reducer tests for chunk/message/tool/approval folding;
  connection-generation tests with a fake transport and injected dispatcher;
  hermetic HarnessRepository fake-host integration tests for host workspace frames
  and mux session-event delivery.
- `app`: ViewModel tests with a fake `ChatRepository`.
- Binary-download seam and session-log route: both run against a real
  loopback `HttpServer` (success, exact query parameters, non-200, and a body
  truncated below its declared length); the export's UI states run through the
  real chat controller over the fake repository.
- Integration with a real `dsh web` is opt-in: set `DSH_E2E_URL` and run
  `LocalDshE2eTest`; it is skipped otherwise.

## 10. Known Limitations and Deferred Work

- **Streaming is chunk-oriented, not final-block-oriented.** The reducer favors
  `text-delta`/`reasoning-delta`; provider adapters that emit only block events
  will still display finalized blocks from `assistant/message`.
- **Titles are display-only.** `session/projection` title frames and history
  projections are read, but identity always remains `sessionId`.
- **Compaction marks the shadowed range.** `compaction/summary` events fold
  into `TimelineItem.Compaction` keeping only the `shadowedSeqs` count;
  timelines render a "▤ Compacted N messages" marker. The summary body
  itself arrives as the following user message (host contract), so no extra
  rendering is owed.
- **Turn grouping is a collapsible outline.** Logged `turn/start` events
  fold into `TimelineItem.TurnBoundary`; the chat timeline offers a flat view
  (divider rows) and an outline view whose group headers show the counts, a
  request-header echo (the first user prompt folded to one line and
  truncated — `promptPreview`), and a per-tool status-count summary
  (e.g. "bash 3✓ 1✗"); headers collapse their rows on tap with an
  expand-all reset. Grouping and preview are pure UI-layer functions over
  the folded timeline (`groupTimelineByTurn`/`promptPreview`, JVM-tested).
  Compaction and session-end markers stay deferred.
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
- **Plugin management is read-only over the wire.** `pluginInventory/list`
  (`packages/host/plugin-inventory/`) returns the Cordis Loader's current
  non-group entries and, when a roster is composed, each agent preset's
  plugin composition; `ChatRepository.listPluginInventory` decodes it. The
  earlier "no plugin RPC" claim was false — the host composes plugins
  host-side, but it does publish this read-only inventory. Mutating verbs
  (mount/unmount, preset authoring) stay host-side. Skill authoring likewise
  stays host/filesystem-side; the client surface is the `/` candidate source.
- **Markdown rendering is a minimal in-app slice.** Message bodies parse into
  blocks (fenced code with language label, headings 1-6, bullet and ordered
  lists nested to two rendered levels, block quotes, GFM pipe tables,
  paragraphs) and inline runs (code, bold, italic, links). A single newline
  inside a block is a soft wrap that folds — to a space between Latin
  characters, to nothing where either side is wide (CJK), and to a kept
  break after two trailing spaces or a backslash — so a body wrapped at 80
  columns reflows to the phone's width; an indented line continues the list
  item above it. An unterminated fence renders as an open, `streaming`-
  labelled block so partial bodies stay readable. Links are clickable spans
  opening through the platform URI handler; a code block carries its own
  copy action, and every body is selectable. The parser is plain Dart under
  `app/lib/ui/chat/markdown/`; colors, fonts, and shapes live in the widget
  layer only ([docs/design-standard.md](design-standard.md)).
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
- `SubagentEntry` exposes `id`, `kind`, `mode`, `activity`, `hasChildren`, `label`, and `reason`. `mode` is the domain enum `SubagentMode` (`oneShot` / `continuable`), required on child rows: a child row with a missing or unknown wire mode fails loud at decode; diagnostic rows carry none.
- `SubagentCatalog` carries `parentSessionId` explicitly and is scoped to that parent; its `parentAvailable` gates the composer for the rows of that catalog level only.
- MVP supports `subagent.list`, `subagent.prompt`, and `subagent.interrupt`; a child's transcript is read through `session/page` carrying a `subagent` address (`{kind: 'subagent', parentSessionId, childSessionId, mode}`). The pre-0.1.5 `subagent/history` name stays declared in the endpoint registry as a declared-only constant with no call site.
- That `subagent` address carries the addressed row's own `mode`; the host matches it against the durable entry and answers a mismatch as `subagent/unauthorized`, and a child the catalog no longer lists as `subagent/not-found`. `subagent.prompt` and `subagent.interrupt` are pinned to `'continuable'` by the request schemas.
- The catalog tree is a host-reported fact: `subagent.list` reads durable
  state, so a cold host answers the parent's complete child tree.
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
- Goal UI is parent/session scoped exactly like Subagents.

## 14. Background Jobs

- `session/jobs` mux frames fold into `TimelineItem.Jobs`.
- Job identity is backend-issued `id`; kind/status/detail/label stay display-only.
- Jobs are live snapshots, not durable session events; history replay does not reconstruct them.

## 15. Agent Presets & Permissions

- `agentPresets/list` decodes the roster: entries
  (`id`, `trust system|user`, `isDefault`, optional `name`/`description`/
  `broken`) plus `authorable` and `hasDocument`. A bad `trust` value or a
  missing required field fails loud.
- `agentPresets/select` switches a blank session's preset and returns the
  echoed id; host refusals (`agent-preset-locked`, `agent-preset-not-found`,
  `agent-preset-invalid`, `agent-preset-read-only`) surface as
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
- `agentPresets/read`, `agentPresets/copy`, and `agentPresets/deletePreset`
  stay uncovered: a mobile client cannot manage the roster, only read it and
  switch blank sessions. 0.1.5 removed the 0.1.1 per-method loopback pin
  (`PRIVILEGED_METHODS`), so these are out of scope by product decision, not by
  a host-side privilege fence (§4.6).

## 16. Host Commands

- `commands/execute` (typert remote bridge: wire path
  `/api/commands/execute`, envelope `payload.args {agentId, line,
  images}`) executes one slash-command line through the host command
  registry — the line never reaches the model (`session.prompt` does not
  parse commands; the host's own docs notwithstanding, the model would
  receive the text as ordinary content). A matched command returns the
  settled execution (`commandId`, `result.kind` `success|error`,
  optional `text`); an unmatched name returns ok with no value slot.
  The `images` arg carries base64-encoded composer uploads
  (`{mediaType, data, name?}` in submission order); the host admission
  settles an error result when the command does not declare image
  acceptance (`plan` and `goal` do).
- The chat controller routes a submitted line whose leading token names
  a roster host command through `commands/execute` (args-tolerant when
  the command advertises an input hint, bare-only otherwise — the web
  `matchEnter` table); skills, unknown names, and unmatched host answers
  fall back to the ordinary prompt channel. A dispatch failure
  (transport abort, business error) does not: the line surfaces as the
  chat error banner instead — re-sending it would hand the model the
  literal command text. A submission carrying images refuses, in the
  composer before anything is sent, when the line dispatches as a
  command that does not accept them (web envelope policy: the draft and
  images stay in place); an accepting command dispatches with the
  images, and an error result keeps them for correction.
- A bare-only command (no input hint — `compact` and `export`) dispatches
  detached: the composer never holds its sending state while the host
  runs the command for as long as the HTTP request survives (the host
  aborts a command when its request connection drops). The outcome
  renders as the timeline command card folded from the `command/run` +
  `command/done` events, not a held sending state; only an immediate
  failure — a transport abort or an admission error that never entered a
  handler — surfaces in the chat error banner.
- A detached bare dispatch re-runs its transport once on a mid-flight
  socket drop: a `commands/execute` failure whose cause is a
  `SocketException` re-dispatches on a fresh connection (the host
  aborted the first attempt, so nothing settled and compaction is
  idempotent). Attached arg-taking commands never retry, and a second
  consecutive drop surfaces in the error banner. The first attempt's
  aborted `command/done` and the retry's outcome each fold into their
  own command cards.
- `/export` is the roster's one client-local command. The host registers
  it (description `Download this Session log as a ZIP archive`) but its
  handler only answers `Session log download requested.` — the browser
  owns the transfer there. A bare `/export` therefore never rides
  `commands/execute`: the controller runs the download itself (§4.7) and
  reports the platform's save location. Args follow the bare-only rule
  and ride the prompt channel, matching `compact`.
- `commands/list` is wired: `ChatRepository.listCommands(agentId)` decodes the
  addressed agent's live descriptor array (`{name, description, input?: {hint,
  attachments?}}`, name-sorted by the host). No advertised `input` is the
  wire's bare-only signal; an advertised hint makes the command
  args-tolerant. A subagent-owned child is refused `session/agent-busy`.
  The composer's `/` candidates, its ➕ sheet, and the submit decision table
  (`hostCommandLineFor` / `hostCommandImageRefusal` / `hostCommandIsBare`)
  consult the live roster once a pull settles; the static list in
  `command_roster.dart` is only the pre-first-pull fallback, which also
  carries a failed pull (`session/agent-busy`). `commands/change`
  invalidates every cached roster and re-pulls the selected session.

### 4.8 Session-event folds added on the 0.1.5 pin

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
  `view` payload therefore does not exist at 0.1.5; what the host ships is each
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
- **Schedule reminders.** The versioned `schedule/change` stream
  (`packages/schedule/schedule/src/types.ts`) folds into the active
  `ScheduleReminder` list: create, delete, and dispatch — a one-shot leaves
  the set, a fixed-rate record advances to its next anchor-aligned target.
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
- **UI mounts deferred.** Folding `TimelineHookAudit` and
  `TimelineWorkflowRun` publishes timeline items; the transcript's render
  arms for them are placeholders that draw nothing. The sandbox and
  schedule streams still mount no surface. The Cordis-request stream feeds
  the composer-seat approval card (`CordisRequestPanel`, reject-only), and
  the composer consults `listCommands` (see §4.7). Remaining mounts are UI
  changes under `flutter/app/lib/ui/**`, tracked separately from this wire
  pass.
