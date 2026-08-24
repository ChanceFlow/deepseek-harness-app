# Agent Note: Settings split into App and Host; the host dimension collapses to one word and one sheet

Status: implemented

## Problem

The Settings tab described only the host, and it said "host" three
times on one screen: the "Host settings" category capsule, the
"Hosts" section capsule inside it, and the "Hosts" page header under
that. Three overlapping surfaces managed the same fact — the scope
bar (which host the pages describe), the Hosts section (the
registry), and the scope picker sheet — while the tab had no settings
of its own: nowhere for a preference that belongs to the phone (the
interface language first). The vocabulary also drifted: registry
pages said "backend" (后端) while every other surface said "host"
(主机).

## Decision

### Two categories, one word

The tab carries two categories picked by capsules under the header —
**App** (应用) and **Host** (主机); the screen title already says
Settings, so the capsules drop the suffix. The host category is the
default. Both halves stay mounted in a category-level IndexedStack.

The word "host" appears exactly once on the surface: the category
capsule. The host half leads with the **host bar** — the scoped
host's live dot, label, `endpoint · version`, and chat-Active badge —
always rendered (even single-host: the identity is worth seeing),
and its sheet owns the whole host dimension: picking the settings
scope (check mark), the registry (add / rename / repoint / remove
through the per-host edit sheet), and switching the chat-active host
(Set-as-chat-host lives in the edit sheet — the rows select scope
only, the two choices the scope note separated stay separated). The
section nav shrinks to General / Models / Plugins / Agent presets /
Credentials. The unreachable-host gate opens the same sheet instead
of jumping to a section.

Scope semantics are unchanged ([settings backend scope](2026-08-21-settings-backend-scope.md)):
follow-active until pinned, pin survives chat-active switches, a gone
pin resets. The App page (language, busy-Enter) carries no title —
the category capsule names it — just the intro caption and the rows.

### The language preference

`AppLocalePreference { system, zh, en }`
(`flutter/app/lib/ui/settings/locale_preference.dart`) persists under
`app.localePreference` in the shared store on the busy-Enter
controller's shape (UDF stream, optimistic write with snap-back,
`flush()` on select). `DshApp` watches `appLocalePreferenceProvider`
and maps the choice onto `MaterialApp.locale` via `resolveAppLocale`
— `system` delegates to the device locale. The zh/en labels render in
their own language (中文 / English, the web locale module's display
names); only the system entry is localized.

### The rename

User-visible "backend"/后端 became "host"/主机 (both READMEs
included); code identifiers keep the backend vocabulary — the wire
layer never shows them to a user.

## Alternatives considered

- **Keep the Hosts section, rename it**: rejected — renaming
  ("Host list") only decorates the triple "host" stack; the sheet
  removes it.
- **Row tap switches the chat-active host (the old page's verb)**:
  rejected — it conflates the two choices the
  [scope note](2026-08-21-settings-backend-scope.md) separated; the
  edit sheet owns the active switch, the row owns scope.
- **Host-scoped language (the web's shape)**: rejected for mobile —
  the language must work before any host is reachable.
- **Landing list with subpages**: rejected — the capsule/IndexedStack
  vocabulary keeps one-tap flips and per-page state.
- **Theme row on the App page too**: deferred — the user named
  language; the shape (a key, a row, a MaterialApp mapping) fits
  later without structural change.

## Consequences

- The surface states its two kinds; App works with no host; the host
  dimension is one bar + one sheet. A language tap re-localizes the
  whole app, asserted end-to-end in `widget_test.dart` (中文 pins,
  跟随系统 releases).
- Registry flows ride the sheet (list/switch-active, pin, single
  host, add, edit/repoint/guards, unreachable gate) in
  `settings_screen_test.dart`; the former scope-bar widget tests are
  host-sheet tests.
- Design shots: `settings-general` / `settings-hosts` (the sheet)
  pair against the first-pass renders; `settings-app` /
  `settings-app-zh` carry the App page. The review harness's `host`
  builder (a root-scope tree per shot) stays.
- The settings-tab parity note's busy-Enter placement and the i18n
  note's device-locale behavior are amended here (see
  [settings parity](2026-08-20-settings-section-parity.md),
  [bilingual i18n](2026-08-20-bilingual-i18n-zh-en.md)).
