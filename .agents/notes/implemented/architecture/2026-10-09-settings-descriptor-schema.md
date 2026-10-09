# Agent Note: The settings descriptor's schema and autoGenerate reach the domain

Status: implemented

## Problem

`settings.describe` answers one row per profile plugin entry: a
`SettingsNamespaceView` carrying `ns`, `autoGenerate`, `schema`, the three
value layers, `applies`, `secrets`, and `revision`
(`reference/deepseek-harness/packages/api/settings-controller/src/index.ts:48-60`,
derived from `packages/settings/settings/src/index.ts:20-31`). The Flutter
client decoded every member except `schema` and `autoGenerate`, so a namespace
whose plugin registers no custom settings page reached the UI as a name and a
JSON blob: no field kinds, no labels, no defaults, and no host permission to
draw a page at all.

Nothing else can supply that text. `pluginInventory/list` rows carry no
namespaces, and a row's `entryId` is a different id space from the `ns` this
descriptor keys on (`packages/host/plugin-inventory/src/types.ts:17-26`; `ns`
is the Loader entry id, `packages/settings/settings/src/index.ts:326`).

## Decision

`SettingsNamespace` carries `autoGenerate` and `schema`, decoded by
`decodeSettingsSchema` in
`flutter/packages/harness_adapter/lib/src/dsh_wire_types.dart`.

`autoGenerate` is the host's permission to generate a page when no custom page
exists (`index.ts:22-23`). A row that omits it decodes to false: a host that
withheld the field offers no page.

`schema` is `form.toJSON()`, schemastery's serialized schema rather than a
bespoke projection. Its wire form is `{uid, refs}`: `refs` maps a uid to one
node's plain JSON, and a node's child positions (`sKey`, `inner`, `list`,
`dict`) hold uids into that same table, because one schema may reference a node
twice or an ancestor (`vendor/schemastery/src/index.ts`, `toJSON` and the
`options.refs` branch of the `Schema` constructor). The domain keeps the table
— `SettingsSchema.root` plus `SettingsSchema.nodes` — and resolves children
through `dictOf`/`listOf`/`innerOf`/`sKeyOf`, so a recursive `lazy` schema
cannot loop.

A node carries `type`, `meta`, and the positions its kind uses: `value` on a
`const`, `inner` on `array`/`dict`/`lazy`/`transform`, `list` on
`union`/`intersect`/`tuple`, `dict` on `object`, `sKey` on `dict`, `bits` on
`bitset`. `type` is an open set — `Schema.extend` lets a plugin register a kind
— so an unrecognized kind rides through and a renderer falls back.

`SettingsSchemaMeta` decodes every key the pinned `Meta` declares: `default`,
`required`, `volatile`, `disabled`, `collapse`, `hidden`, `loose`, `role`,
`extra`, `link`, `description`, `comment`, `pattern`, `max`, `min`, `step`,
`badges`. A `description` is either one string or a locale map whose `''` entry
is the unlocalized text; `labelFor(locale)` reads the localized entry, then
`''`, then `comment`. An option list is a `union` of `const` nodes, read
through their `value`.

Decoding fails loud, naming the offending key, on an envelope that is not an
object, a missing or empty `refs` table, a refs key that is not a uid or a node
object, a node without `type`, a child reference the table does not carry, and
mistyped `meta` members. An empty form is never the result of a decode failure.

## Alternatives considered

**Keep the node and `meta` as raw JSON maps.** Rejected: a map passthrough
into `domain` is what the hand-written-DTO rule forbids, and every renderer
would re-derive the vocabulary above.

**Build a nested tree instead of a uid table.** Rejected: `z.lazy` makes a
recursive Config representable, so a wire-driven tree would not terminate.

**Tolerate a malformed or absent schema as an empty form.** Rejected: that
silent degradation is the defect this change fixes.

**Label fields from `value` or from `pluginInventory/list`.** Rejected: a
value carries no kinds, defaults, or bounds, and the inventory carries no
namespaces.

## Consequences

The wire and the domain now carry the projection a generated settings page
needs; rendering it from `SettingsSchema.dictOf` and
`SettingsSchemaMeta.labelFor` is the settings UI's half. The live contract is
stated in [docs/spec.md](../../../../docs/spec.md) §10 (Known Limitations and
Deferred Work).

A `transform` node arrives with `inner` and no `callback`: `describe` rebuilds
the form through `plainSchema` before it serializes, rehydration turns the
recorded callback source into a function, and JSON drops it.

`scripts/verify_wire_pin.py` compares endpoint names, so this result-shape
change moves no count and the gate stays clean; the shape claim rests on the
pin citations in the code, not on that gate
([wire-pin gate](../process/2026-09-11-wire-pin-gate.md)).

Two adjacent gaps stay open. `SettingsNamespace.base` is declared in the domain
but never filled, because `SettingsNamespaceWire` does not decode the
descriptor's `base` layer; and a secret slot's value still has no write path.
Neither is needed to render a generated page.
