# Agent Note: DSH 0.1.2 wire protocol adaptation

Status: implemented

## Problem

Upstream DeepSeek Harness (dsh) 0.1.2 migrates its RPC endpoints and streaming contracts to Typert Remote standards:
1. Endpoint naming shifted from dot-separated notation (`domain.method`) to slash-separated notation (`domain/method`).
2. Unary RPC request payloads on the wire now strictly require a single plain-object `args` wrapper (`{"type":"client-request","rpcId":"...","method":"domain/method","payload":{"args":{...}}}`). The host gateway rejects payloads lacking this structure with an error.
3. The multiplexed event WebSocket endpoint migrated from `/api/events.mux` to `/api/remote.mux`.

Prior to this change, only `commands/execute` adhered to the Typert Remote convention in the Flutter client, while all other endpoints and the connection manager used legacy `domain.method` naming, unwrapped payloads, and `/api/events.mux`.

## Decision

The Flutter client fully aligns with the DSH 0.1.2 wire protocol:

- **Endpoint naming & decoupling**:
  - `DshRpcEndpoints` in `rpc_map.dart` acts as the single central registry for all Typert Remote endpoints (`session/*`, `skills/list`, `subagents/*`, `goals/*`, `agentPresets/*`, `directoryPicker/*`, `workspace/*`, `settings/*`, `credentials/*`, `commands/execute`).
  - `DshRemoteInvoker` decouples repository business logic from wire transport details, implementing transparent version fallback via `kDshEndpointFallbacks` when a 404 is encountered against an older API Proxy backend.
- **Payload packaging & descriptor matching**:
  - `DshRemoteInvoker` automatically wraps payload maps in `<String, Object?>{'args': payload}` and ensures endpoints declaring a `request` or `_request` descriptor parameter match DSH 0.1.2 boundary validation, while unwrapping on fallback to legacy flat endpoints.
  - `AgentPresetListValueWire` treats `hasDocument` as optional (`wireBool` default false) matching DSH 0.1.2 `AgentPresetRoster`.
  - `RpcResult.fromJson` accepts non-map primitives (e.g. string path from `directoryPicker/createDirectory`) without throwing `FormatException`.
  - `executeCommand` strips its ad-hoc manual `'args'` wrapper.
  - `dsh_connection_manager.dart` uses `DshRemoteInvoker` for `host/describe`, tolerating its removal in 0.1.2.
  - `HttpDshRpcClient.call` in `package:network` guarantees that any payload sent on the wire contains the single `args` object wrapper.
- **Workspace listing 404 tolerance**: DSH 0.1.2 provides workspace state via the `workspace/follow` stream and mutation returns rather than a unary endpoint. `_loadWorkspaceListing` catches 404 responses gracefully so startup reconciliation and `refreshWorkspaces` complete quietly without raising transport errors, while mutations (`createWorkspace`, `renameWorkspace`, `deleteWorkspace`) apply their immediate result to local state.
- **WebSocket connection point**:
  - `dsh_connection_manager.dart` replaces `_eventsMuxPath = '/api/events.mux'` with `_remoteMuxPath = '/api/remote.mux'`.
  - All test fixtures and sockets across `network` and `harness_adapter` connect to `/api/remote.mux`.
  - `HarnessFakeRpc` test double supports both slash and dot notation and unwraps `payload['args']` when inspecting arguments.
  - Test mocks in `app/test/` support both `host/describe` and `session/list`.

## Alternatives considered

- **Per-call manual wrapping in `HarnessRepositoryImpl`**: rejected — manually typing `{'args': {...}}` across 40+ call sites introduces maintenance burden and risks omissions. Centralizing the wrapping in `_call` and defending at `HttpDshRpcClient.call` ensures total consistency.
- **Client-side translation shim / legacy fallback**: rejected — maintaining dual dispatch paths adds dead code and complexity. Upstream DSH 0.1.2 host enforces slash routes and `args` payload validation.
- **Post-transport rewrite via HTTP interceptor**: rejected — hiding protocol conversions in an interceptor obscures the wire contract from `harness_adapter`, which is the dedicated anti-corruption layer.

## Consequences

- The client is fully compatible with DSH 0.1.2 backends.
- Every outgoing unary RPC POST request reliably carries `domain/method` and a validated `{"args": {...}}` payload.
- Multiplexed event streams connect to `/api/remote.mux`.
- Wire contract documentation in [docs/spec.md](../../../../docs/spec.md) and [docs/spec.en.md](../../../../docs/spec.en.md) reflects the upgraded wire protocol.
