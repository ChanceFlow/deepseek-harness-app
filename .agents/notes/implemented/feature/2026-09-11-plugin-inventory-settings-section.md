# Agent Note: read-only plugin inventory in Settings

Status: implemented

## Problem

The host's `pluginInventory/list` Remote was already decoded end to end —
domain types in `flutter/packages/domain/lib/model/plugin_inventory.dart`,
`ChatRepository.listPluginInventory`, and the adapter decoder — but the client
rendered none of it. A phone user could not see which plugins a deployment
loads, which of them failed to start, or which plugins an agent preset pulls
in.

The decoded model matches the host projection exactly, and one detail in the
brief does not survive contact with the wire: the host's entry projection is
built as `{entryId, moduleName, enabled, fiberPhase}`
(`reference/deepseek-harness/packages/host/plugin-inventory/src/index.ts:78-83`,
typed at `.../src/types.ts:16-24`) and carries **no** `condition`. Conditional
enablement is a preset-row fact (`PresetRowEnablement.conditional` plus the
row's own `condition`, `types.ts:26-48`). A global entry is therefore only ever
enabled or disabled; the surface tags `conditional` where the model carries it.

## Decision

`flutter/app/lib/ui/settings/plugin_inventory_section.dart` is one
self-contained section: `PluginInventoryUiState`,
`PluginInventoryController`, `pluginInventoryControllerProvider`, and the
widgets. It reads once on construction and on Retry, and publishes the query as
controller state. A failed read publishes only a `failed` flag — the raw error
goes to `ErrorLogCollector` — so no transport text can reach the tree.

**Density.** The reference renders a two-column grid of disclosure cards with a
preset switcher (`PluginInventorySettingsTab.tsx:104-110`, `:401-476`), itself
collapsing to one column below 680px (`PluginInventorySettingsTab.module.css:427-430`).
A phone cannot show a module name, an enablement tag, and an entry id in half a
360dp row, so the adaptation is one full-width disclosure row per catalog item,
one disclosure per agent preset, and one collapsed global group; the global
plane opens by default only when no preset roster exists, mirroring the
reference's `globalOpen ?? presets.length === 0`. While a query is active the
catalog renders a flat match set, which keeps search results directly visible
instead of force-opening nested groups. `_Disclosure` wraps the framework
`ExpansionTile` and gates its body on the expansion signal: the framework keeps
collapsed children mounted and offstage, and a live 160-entry global plane
cannot pay to build every row's facts at Settings mount.

**Vocabulary.** The short module name is the title and the entry id the
secondary monospace detail (with a leading composition `include:` marker
dropped, as the reference does); both feed client-side search. Enablement tags
ride `ColorScheme` roles: `success` for enabled, `onSurfaceVariant` for
disabled, `warning` for conditional, and `error` for a `failed` root fiber,
which replaces the enablement tag the way the reference's `failedTag` does.
Non-`active` phases also carry the shared `StateDot`, and expanded rows state
the full specifier, the phase, and the row's condition. The section header
carries the read-only notice.

**Mount.** `settings_screen.dart` gained one import and
`const SettingsPluginInventorySection(),` between the Plugins & advanced
section and About (the file's own region was calm, so this was edited in
place).

## Alternatives considered

Editing `settings_screen.dart` to host the catalog was rejected: the file is
large and shared, so the section stays self-contained like `about_section.dart`
and `llm_providers.dart`. A preset switcher menu was rejected for a phone: one
disclosure per preset shows every composition at once. Tagging a mounted row
`conditional` whenever it carries a `condition` string was rejected because the
host reports the *effective* enablement separately; the expression stays a
detail. Skipping the reference's client-side "provided by preset" marking was
deliberate scope: the requirement is to show each preset's composition, not to
derive cross-plane provenance.

## Consequences

The section is read-only by construction: no controller action writes, and the
notice states that enable/disable/configuration stay on the host. Search covers
module name and entry id; a deployment with no roster still shows the global
plane. The new ARB keys are `settingsSectionPluginInventory` and the
`pluginInventory*` family in both locales. `settings_screen_test.dart` and the
design shots now mount the section against their quiet transport seams, where
the read fails and renders the generic failure state.
