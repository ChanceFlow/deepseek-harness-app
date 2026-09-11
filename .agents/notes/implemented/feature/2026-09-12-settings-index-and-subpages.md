# Agent Note: The Settings tab is an index; every subject is a page or a sheet

Status: implemented

## Problem

The Settings tab had become one scroll of everything. Nine sections —
host facts, language, appearance, ASR, error logs, busy-Enter, the whole
agent-preset roster, credentials, the provider directory, the namespace
JSON editors, the plugin inventory, About — shared one column of pixels,
so the subject a reader wanted sat thousands of device-pixels down and
every unrelated surface had to be scrolled past on the way. Two of those
surfaces were also the same setting twice: a row named "Agent preset"
opened a bottom-sheet picker, and directly under it the roster's cards
were *also* tappable to set the default. Both wrote
`agent-presets.default`, neither was authoritative, and which one a
reader found depended on how far they had scrolled.

## Decision

The tab is an index. The root renders one grouped card per subject and
one one-line row per surface, each row stating the current value where
the subject has one; the subject itself is one tap away.

- **Pushed page** — anything with content of its own: agent presets,
  credentials, the provider directory, the host settings namespaces, the
  plugin inventory, About, and the ASR and error-log surfaces that were
  already pages. `SettingsPageScaffold` gives each the app-bar title and
  a scrollable body; `settings_pages.dart` holds them.
- **Modal sheet** — a single choice over a short list, and every editor.
  Language, appearance, and busy-Enter behavior are four-option pickers
  that had cost three capsules and three card rows; they are now one row
  each with `showSettingsChoiceSheet` over
  `RadioGroup`/`RadioListTile`. The credential editor, host editor, and
  host sheet ride the same `showSettingsSheet` shell.
- **The host sheet** — the registry, the settings scope, and the scoped
  host's write/document facts, so the host dimension stays one row plus
  one sheet ([host split](2026-08-24-settings-app-host-split.md)).

**The default preset has exactly one selection surface.** The root row
states the current default and opens `SettingsAgentPresetsPage`, the
only place a preset is chosen: grouped Built-in / Custom cards, the same
`SelectAgentPresetDefaultAction` write, no second picker beside it. A
broken preset stays listed there (its directory owns the id) but is
inert, and an empty roster states the footer.

A pushed page is not a descendant of the tab, so it cannot watch the
tab's provider. `SettingsChannel` carries the last state, the intent
sink, and — when the tab is controller-backed — the controller's stream;
`SettingsLive` re-renders a page from it, so a write the page triggers
is visible without going back. `SettingsScreen` takes that stream as
`uiStateStream`; `SettingsRoute` passes it, and a test pumping a fixed
state leaves it null.

`settings_chrome.dart` is the one home for the vocabulary all of these
draw: heading, grouped card, hairline, index row, page scaffold, sheet
shell, choice sheet, capsules, badges. The plugin inventory and provider
sections carried byte-identical private copies of the heading, card, and
divider; they now import the shared ones.

## Alternatives considered

- **Keep one scroll, collapse the heavy sections.** Rejected: per-section
  disclosure is a worse index than an index — it still costs a full card
  per subject at rest.
- **Keep the preset picker sheet *and* the roster cards.** Rejected:
  that is the duplication this change exists to remove. The roster page
  wins because it is the only surface that can state why a preset is
  unavailable.
- **A nested `Navigator` for the Settings pages.** Rejected: the root
  navigator already gives the system back gesture, the app's page
  transition, and the route shape the ASR and error-log pages use.
- **Appearance as a page instead of a sheet.** Rejected: four mutually
  exclusive options are one choice, and its loading, unavailable, and
  failed states render in the sheet the same way.
- **Keep the write/document facts on the root.** Rejected: they describe
  the scoped host's settings plane, which the host sheet's scope choice
  controls.

## Consequences

- The root is about one screen: six headings and twelve rows, the
  headings the only text that does not name a surface.
- `settings_screen.dart` keeps the tab, the index, and the host and
  backend sheets; `settings_pages.dart` holds the pages and the
  credentials/plugins/presets bodies; `settings_chrome.dart` holds the
  shared chrome. The three replace one 2,890-line file.
- Every row that states a value reads it live, so the index is honest
  without being opened: `SettingsBadge` marks the ASR install count and
  the error-log count, and appearance states `Unavailable` rather than a
  plausible `System` when the host exposes no `ui-theme` namespace.
- Widget tests drive the new paths: sheets through an `_inSheet` finder,
  pages through the pushed route, and the preset write once, from the
  roster page.
- Design shots cover the index in both locales, the host sheet with its
  facts, and each new page and choice sheet.
