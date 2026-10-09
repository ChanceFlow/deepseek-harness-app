# Agent Note: Plugin configuration is not on the wire, so the namespace view says so

Status: implemented

## Problem

Settings → **Plugins & advanced** → the second row opened a flat editor that
renders **every** Host namespace unfiltered (`_PluginsCard` over
`SettingsUiState.snapshot.namespaces`). Two lies follow. A raw field — the live
example is `ui-chat.transcriptView` — appears with its wire key as its only
label and no field help. And a plugin's own configuration appears on that flat
list instead of on the plugin that owns it, where the pin puts it
(`ui-plugin-manager`: "A plugin that registers a configuration page is edited
here, on its own page").

## Decision

**The pin's tabs stay unbuilt — they are desktop chrome. The wire's own
generated-page switch is the target, and until that decode lands the page is
labelled for what it is.**

1. The pin binds a namespace to a plugin through a **hard-coded constant in
   that plugin's own companion client package**, not through Host metadata:
   `ui-settings-agent-loop/src/client/index.ts:47` and
   `ui-settings-web-search/src/client/index.ts:57` register their page into
   `plugins.item` *while the Host serves their namespace*
   (`ctx.configForms.whileServed([NS], …)`). Settings' **Built-in plugins**
   section is a shell over the `settings.plugins.tab` slot whose one shipped tab
   is the read-only inventory (`ui-settings-plugins/README.md`). This client is
   one binary with no companion packages, so reproducing those tabs would invent
   an ownership fact the Host never states.
2. The Host cannot supply the binding either. `SettingsDescriptor` is
   `{ns, autoGenerate, schema, value, revision, base?, user?, applies, secrets?}`
   (`reference/deepseek-harness/packages/settings/settings/src/index.ts:20-31`),
   and `ns` is the Loader **registration id** — `describe()` sets
   `ns: entry.options.id` (`:315`, `:326`). The settings Remote forwards exactly
   `autoGenerate` and `schema` with the value layers
   (`.../packages/api/settings-controller/src/index.ts:51-52`): no package
   identity rides the payload. The payload that does name packages carries no
   namespaces (`.../packages/host/plugin-inventory/src/types.ts:17-26`) and keys
   its entries by a different id (`entryId = pluginEntryId(entry.id)`,
   `.../packages/host/plugin-inventory/src/index.ts:90`). The two cannot be
   joined.
3. What the wire does carry is the pin's **own fallback**: `autoGenerate`
   ("Whether the UI may generate a page when no custom page exists", `:22-23`)
   plus `schema`, the projected form schema that carries the plugin's field
   labels. The pin's generic renderer is schema-driven and labelled. This client
   drops both: `SettingsNamespace`
   (`flutter/packages/domain/lib/model/settings.dart`) decodes `ns, applies,
   revision, hasUserLayer, secretCount, value, user, base`. The unlabelled
   editor is therefore a decode gap, not a Host limitation.
4. Until that decode lands (tracked with the adapter owner), the page states
   what it is: **Host namespace values**, whose intro says the keys are the
   Host's raw values, that this client does not receive a plugin's field labels
   yet, and that a plugin's own configuration page belongs to the plugin serving
   the namespace.

## Alternatives considered

- **Fake the tabs by joining `settings/describe` to `pluginInventory.list`.**
  Rejected: the descriptor names no package, the inventory names no namespaces,
  and their ids live in different spaces, so the join would be a guess dressed
  as a fact.
- **Hard-code a client-side plugin→namespace table, as the pin's companion
  packages effectively do.** Rejected: that table is an artifact of which
  packages a deployment composes; a phone asserting it would claim ownership the
  Host never stated, and drift the moment a deployment differs.
- **Leave the flat editor presented as plugin configuration.** Rejected: that is
  the lie the reader hit — a raw field, unlabelled and inert, under a plugin
  heading.
- **Change nothing until the schema decode lands.** Rejected: the retitle and
  the raw notice are correct before and after that change, and the raw view
  survives for every namespace the Host generates no page for.

## Consequences

- The raw namespace view stays, honestly labelled, for namespaces the Host does
  not offer a generated page for.
- When the schema decode lands, each namespace the Host marks `autoGenerate`
  gains its own labelled page rendered from `schema`, and the flat list stops
  standing in for plugin configuration.
- No surface claims a plugin owns a namespace until the Host states it.
