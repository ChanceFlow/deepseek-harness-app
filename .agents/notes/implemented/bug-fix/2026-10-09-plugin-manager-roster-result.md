# Agent Note: The plugin-manager roster result is the array, not a field

Status: implemented

## Problem

Refreshing the plugin page raised
`FormatException: required field "bundles" missing or mistyped in
[value, path]` from `HarnessRepositoryImpl.listPluginBundles`. The bracketed
key list is the transport's own tells: `RpcResult.fromJson` parks a non-object
result under `{value: <raw>, path: <raw>}`
(`flutter/packages/network/lib/rpc_envelope.dart`), so the host had answered a
result that is not a JSON object — and the decoder was looking for a `bundles`
member inside it.

The pin answers a bare array. `pluginManager/listBundles` is
`@Remote listBundles(): Promise<BundleInfo[]>`
(`reference/deepseek-harness/packages/boot/plugin-manager/src/index.ts:279-280`)
and `pluginManager/listPlugins` is `@Remote async listPlugins():
Promise<PluginInfo[]>` (`:255-256`); the committed
`packages/extensions/tool-cordis/src/api-catalog.ts:1643,1656` carries the same
two signatures. The roster is therefore the result itself, and an empty
roster is an empty array — there is no `bundles` (or `plugins`) member to
require. Our decode was simply wrong.

The integration fake host carried the same wrong reading — it answered
`{bundles: [...]}` and `{plugins: [...]}` — so the suite agreed with the bug
and no test could catch it. `PluginManagerController._refreshNow` reads both
in one `Future.wait`, so both were broken and the page could not refresh.

A decoder that demands a wrapper key for a parked result is not failing loud;
it is failing **wrong**. The park is the transport's own convention, so an
answered call is never a malformed payload, and a decoder that reads it as one
reports a healthy host as breakage — invisible to a suite whose fake carries
the same mistake, and visible in production only as a user's device log.

## Decision

Both decoders read the envelope's `value` slot and require a JSON array there,
failing loud with the method name and the keys actually present when it is
anything else; each row still has to be an object with the fields its own
decoder requires. The fake host answers the real carrier — a bare array parked
under `value` — and the tests build their payloads through
`RpcResult.fromJson`, so the envelope park under test is the transport's.

## Alternatives considered

**Treat an absent `bundles` as an empty roster.** That is the reading the
crash suggests, and it would have stopped the crash. Rejected: it keeps
decoding a shape the host never sends, so a genuinely wrong key or a foreign
result would report an empty page instead of failing.

**Catch the decode failure in the controller and render an empty roster.**
Rejected: the page already renders a stated failure for a failed refresh; an
empty roster for a broken read is the silent-degradation failure mode, and it
would hide a real roster.

**Probe for either shape (`value['value'] ?? value['bundles']`).** Rejected:
permissive decoding keeps the wrong shape alive and makes the next shape
change invisible.

**Extract a shared bare-array-result helper and move the existing
`commands/list` and `fileReferences/list` decoders onto it.** Deferred, not
rejected on merit: both already read `value['value']` inline, and touching
unrelated decoders in this change widens a defect fix for no behavior gain.

## Consequences

The plugin page refreshes against a real 0.2.0 host, and the shape is stated
in [docs/spec.md](../../../../docs/spec.md) §18 so a future reader does not
re-derive the wrong key.

The other `pluginManager/*` decoders already match their pin shapes — the
`ChangeResult` methods and `registries`/`inspect` answer objects, and
`waitForInstall` handles its documented `null` — so they are unchanged.

`scripts/verify_wire_pin.py` compares endpoint names and stays clean; this
result-shape correction moves no coverage count.

The session events and projection keys the same log surfaced
(`agent/inbox/spliced`, `step/end`, `workspace/changes`, `team/task`,
`team/message/queued`, `team/message/delivered`, `turnOutline`,
`subagentTiming`, `sessionListMetadata`) are **not** folded here. The
reference client folds five of them, leaves the three `team/*` journal events
unfolded, and `sessionListMetadata` is host-folded into the list row's
`blank`/`updatedAt`, which this client already decodes; the port is scheduled
as its own change.
