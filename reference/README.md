# Reference to deepseek-harness

This directory contains the upstream dsh repository as a **git submodule**, not a filesystem
symlink. The submodule pins a specific official dsh commit, so the Android contract source of
truth is reproducible across clones. dsh is under active development with breaking changes —
the pin is the wire contract; do not assume compatibility with a different dsh version.

- Pinned commit: `fb2c4b9e698e30edb738bca4cf0618587db7d203` (official `dsh-v0.1.5-rc.2`).
- Registration-source digest: `e4d5aace6a5457558cfdb7af77a27410aebcfcca151e5a6d7891cc2bb1745597`
  (sha256 over the 21 source files that declare a registration plus the Gateway endpoint
  constants, fed as `relpath\0bytes\0` in sorted path order; regenerate with
  `python3 scripts/verify_wire_pin.py --print-digest`).
- Wire contract source of truth: `reference/deepseek-harness/packages/api/` — the Typert
  Remote services the gateway registers. DSH 0.1.2 replaced the dot-namespaced
  `packages/host/apiproxy/src/api/rpc-map.ts` registry with slash-namespaced Typert Remote
  services, and that file no longer exists in the 0.1.5 tree.
- Remote method registration: a `class … extends TypertRemoteService` plus its
  `super(ctx, '<serviceKey>'[, { namespace }])` binding and the `@Remote` decorators on
  its methods (`reference/deepseek-harness/packages/typert/protocol/src/index.ts` defines
  the decorator); the declaration scan is what [scripts/verify_wire_pin.py](../scripts/verify_wire_pin.py)
  derives the registered surface from.
- Connection lifecycle: `reference/deepseek-harness/packages/client/connection/src/client/connection.ts`
- Web routes and the event mux: `reference/deepseek-harness/packages/client/connection/src/api-path.ts`
  and `reference/deepseek-harness/packages/api/gateway/src/stream-protocol.ts` (`/api/remote.mux`).
- Render/UI decision reference: `reference/deepseek-harness/packages/client/ui-*/`

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

Two things the gate cannot see, so verify them by hand when the pin moves: a method registered
by a runtime-built binding rather than a literal `super(ctx, '<key>')`, and the gap between
the tree-wide declaration surface it derives and one deployment's loaded plugin set (the
bundle patches under `deepseek-harness/packages/bundle/*/cordis.patch.yml`) — the scan is a
documented superset, so an endpoint served only by an unmounted experimental package would
pass. An unparsable registration fails the gate loudly rather than being skipped.
