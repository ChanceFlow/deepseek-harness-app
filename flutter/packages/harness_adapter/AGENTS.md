# AGENTS.md — packages/harness_adapter (dsh anti-corruption layer)

Supplements the [root conventions](../../../AGENTS.md#conventions) and the
[workspace file](../../AGENTS.md). This package is the only code that
understands the dsh wire protocol; everything here protects that seam.

- **Wire shapes come from the reference submodule, never memory.** Before
  encoding/decoding anything, read the owning source under
  `reference/deepseek-harness/` — the map is in
  [reference/README.md](../../../reference/README.md): RPC schemas under
  `packages/host/apiproxy/src/api/`, connection lifecycle in
  `packages/client/connection/src/client/connection.ts`.
- **Decoders are hand-written and fail loud.** Required fields throw with the
  field name on absence or type mismatch; optional fields are the only ones
  with defaults ([wire_json.dart](lib/src/wire_json.dart)). No codegen, no
  permissive `Map<String, dynamic>` passthrough into `domain`.
- **Method names live in one registry.** RPC method strings are declared in
  [rpc_map.dart](lib/src/rpc_map.dart); adding coverage means adding there,
  a DTO in `wire_json.dart`, and the reducer/stat fold if events flow —
  procedure: [dsh-wire-parity skill](../../../.agents/skills/dsh-wire-parity/SKILL.md).
- **Translation state is a pure fold.** `timeline_reducer.dart` and the stat
  folds are pure functions from wire events to `domain` timeline state; no
  Flutter imports (the [import gate](../../../scripts/check_dart_imports.py)
  rejects them), no UI placement decisions.
- **Neutral vocabulary at the boundary.** Exports speak `domain` types only;
  dsh vocabulary (`SessionEvent`, `MuxFrame`, `HostFrame`, method names)
  never crosses this package's public API.
- **Fixtures come from recorded wire traffic.** Tests decode JSON captured
  from the reference web client or the submodule's contract files; the
  opt-in tier replays against a real host
  ([docs/testing.md](../../../docs/testing.md)).
