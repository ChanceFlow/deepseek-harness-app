# Reference to deepseek-harness

This directory contains the upstream dsh repository as a **git submodule**, not a filesystem
symlink. The submodule pins a specific official dsh commit, so the Android contract source of
truth is reproducible across clones. dsh is under active development with breaking changes —
the pin is the wire contract; do not assume compatibility with a different dsh version.

- Pinned commit: `66491b05e3f05ad35bcdd4f6cd7ed26041d9e3db` (official `dsh-v0.2.2-rc.1`).
- Registration-source digest: `24a58530a55f05a716800ee9e0759bd5a9ab22af186027b62d8dba11c08ff916`
  (sha256 over the 41 source files that declare a registration plus the Gateway endpoint
  constants, fed as `relpath\0bytes\0` in sorted path order; regenerate with
  `python3 scripts/verify_wire_pin.py --print-digest`).
- Wire contract source of truth: `reference/deepseek-harness/packages/api/` — the Typert
  Remote services the gateway registers. DSH 0.1.2 replaced the dot-namespaced
  `packages/host/apiproxy/src/api/rpc-map.ts` registry with slash-namespaced Typert Remote
  services, and that file no longer exists in the 0.2.2 tree.
- Remote method registration: a `class … extends TypertRemoteService` plus its
  `super(ctx, '<serviceKey>'[, { namespace }])` binding and the `@Remote` decorators on
  its methods (`reference/deepseek-harness/packages/typert/protocol/src/index.ts` defines
  the decorator); the declaration scan is what [scripts/verify_wire_pin.py](../scripts/verify_wire_pin.py)
  derives the registered surface from. The class may be exported as `export default class`
  and a decorated method may be a generator (`async *name`); the gate parses both forms.
- Connection lifecycle: `reference/deepseek-harness/packages/client/connection/src/client/connection.ts`
- Web routes and the event mux: `reference/deepseek-harness/packages/client/connection/src/api-path.ts`
  and `reference/deepseek-harness/packages/api/gateway/src/stream-protocol.ts` (`/api/remote.mux`).
- Render/UI decision reference: `reference/deepseek-harness/packages/client/ui-*/`

## The deployed fork

The client is deployed against a downstream fork of this tree, not against the
official tag alone. The fork's `dsh-v0.2.2-rc.1-chance.0` release is built on
the pinned official tag and is the host the phone line is upgraded with. Its
derived surface is **189 unary methods and 21 streams** against the pin's 184
and 21: the five additions are `agentTeams/setEnabled`, `forgePanel/diffBases`,
`mcpManager/probe`, `mcpManager/restart`, and `web/listProviders`, all additive
and none called by this client. The pin therefore stays the official tag: it is
reproducible from the public remote, and it loses no coverage against the fork.
Verify that on a fork bump by deriving the surface from the fork tag with the
same scan (`scripts/verify_wire_pin.py`'s `pin_endpoints`), not by reading a
changelog.

The fork's `subagents/prompt` and `subagents/interruptByUser` registrations use
the `@Remote({ name, resources })` decorator form; the gate's decorator parser
reads a bare string or `mode`, so pinning the fork tree would fail loudly rather
than silently mis-derive. That is one more reason the pin is the official tag.

The fork's own commits are otherwise wire-neutral — no Remote method, stream, or
event shape the client consumes differs from the pin. What it adds is behavior
the phone never encodes: its client classifies private LAN hostnames as local
connection state, its Web bundle ships additional declarative agent presets (the
roster a host composes changes; the `agentPresets/*` wire contract does not), and
it carries `llm-pi-ai` replay fixes plus the release-mirroring tooling that
publishes the fork's own tags. The `/api` trust fence is not among them: the
fork's classification feeds `ctx.connection` state, while
`packages/client/connection/src/api-request-trust.ts` keeps the pinned rule.

Upstream repository:

<https://github.com/deepseek-ai/deepseek-harness>

The submodule is the executable reference used by git; the hyperlink above is the
human-clickable reference.

To re-pin, check out another official tag in the submodule and update the pinned-commit and
registration-source digest lines above in the same change:

```sh
git -C reference/deepseek-harness fetch --tags origin
git -C reference/deepseek-harness checkout dsh-v<version>
git -C reference/deepseek-harness describe --tags          # confirms the new tag
python3 scripts/verify_wire_pin.py --print-digest          # the new digest for the record
# update the pinned-commit and digest lines above, then:
python3 scripts/verify_wire_pin.py                         # must be CLEAN
git add reference/deepseek-harness                         # the parent records the new gitlink
git submodule status                                       # confirm parent and checkout agree
```

**Wire parity is gated.** `scripts/verify_wire_pin.py` (the `wire-pin` gate in
`verify_all.py docs`) derives the registered method surface from the `TypertRemoteService` +
`@Remote` declaration sites, compares it with
`flutter/packages/harness_adapter/lib/src/rpc_map.dart`, and fails on any divergence that is
not a reviewed client-only name in `gates_manifest.json`. It also checks this file's pinned
commit and registration-source digest, the privileged/out-of-scope classification and derived
counts in `docs/spec.md` §4.6, the README coverage sentence, and the adapter suite's fake host
for a reintroduced name-folding map. Re-run it after every re-pin; a re-pin that skips it is
unverified.

Three things the gate cannot see, so verify them by hand when the pin moves: a method registered
by a runtime-built binding rather than a literal `super(ctx, '<key>')`; the gap between
the tree-wide declaration surface it derives and one deployment's loaded plugin set (the
bundle patches under `deepseek-harness/packages/bundle/*/cordis.patch.yml`) — the scan is a
documented superset, so an endpoint served only by an unmounted experimental package would
pass; and the stream endpoints the client opens with a literal string rather than through
`DshRpcEndpoints` (`workspace/follow`, `session/control`, `session/follow`, `$events`, the
per-session `job/list`, the per-job `job/follow`, and the per-terminal `terminal/follow` /
`terminal/retain`), which the gate never compares. An unparsable registration fails the
gate loudly rather than being skipped.
