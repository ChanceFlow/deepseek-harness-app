# Agent Note: Settings split into App and Host settings; the word for a configured dsh instance becomes "host"

Status: implemented

## Problem

The Settings tab described only the host: every page read the active
backend's settings plane, and the tab had no settings of its own —
nowhere to put a preference that belongs to this phone (the app's
interface language being the first one). The vocabulary also drifted:
the registry pages said "backend" (后端) while every other surface
already said "host" (主机), so one concept carried two names.

## Decision

### Two categories, one tab

`SettingsScreen` (`flutter/app/lib/ui/settings/settings_screen.dart`)
gains a category row under the header — two capsules on the existing
`_ModeButton` vocabulary: **App settings** and **Host settings**. The
halves stay mounted in a category-level `IndexedStack`, so a switch
preserves each side's scroll and entry state as the section stack
does across section switches.

- **App settings** is device-local and host-free: the language row
  and the busy-Enter row. It renders with or without a reachable
  host; its rows persist through the shared `LocalStateStore`.
- **Host settings** is the previous surface unchanged in structure —
  scope bar (multi-host only), section capsules (Hosts, General,
  Models, Plugins, Agent presets, Credentials), section
  `IndexedStack` — plus the host error banner and activity line,
  which moved inside the host half so the App page never carries host
  state. The header refresh control appears only on the host category
  (it re-describes the host; the App page has nothing to refresh).

Host is the default category: a returning user still opens Settings
onto host General.

### The language preference

`AppLocalePreference { system, zh, en }`
(`flutter/app/lib/ui/settings/locale_preference.dart`) persists under
`app.localePreference` in the shared store, on the busy-Enter
controller's shape: UDF stream, optimistic write with snap-back,
`flush()` on select. `DshApp` watches `appLocalePreferenceProvider`
(a `StreamProvider` over the controller's stream) and maps the choice
onto `MaterialApp.locale` via `resolveAppLocale` — `system` (and the
unresolved-store window) delegates to the device locale. The zh/en
capsule labels render in their own language (中文 / English, the web
locale module's display names); the system entry is the only
localized label.

The busy-Enter row moved from host General to the App page: on
mobile the preference is device-local by construction (the composer
reads the shared store), so the honest category is App. The web keeps
it in host General because the web panel has no app plane.

### The rename

User-visible "backend"/后端 becomes "host"/主机 — the registry nav,
the add/edit sheet titles, the scope picker, the guard strings, and
both READMEs (the feature section is "Multiple hosts" now). The
registry page (nav label "Hosts") keeps its place as the Host
category's first section: it decides which host every other page
describes, and stays reachable when that host is not. Code
identifiers (`BackendConfig`, `BackendStore`, ARB key names) keep the
backend vocabulary — they name the registry concept, which the wire
layer never shows a user.

## Alternatives considered

- **Host-scoped language (the web's shape)** — the web stores its
  preference in the host's `locale` namespace. Rejected for mobile:
  the language must work before any host is reachable, and the
  App/Host split puts device-local preferences on the App side by
  definition.
- **Landing list with subpages (iOS-Settings style)** — rejected: it
  trades the one-tap capsule flips for a standard look, costs a
  second tap to any host section, and the tab's IndexedStack state
  preservation would need a navigator inside the tab.
- **App as a seventh section capsule** — rejected: it flattens the
  two kinds of settings the user asked to separate, and the section
  nav already scrolls with six capsules.
- **A theme row on the App page too** — deferred: the user named
  language; a theme preference is the same shape (a key, a row, a
  MaterialApp mapping) and can join later without structural change.
- **Renaming code identifiers to Host\*** — rejected: a
  cross-package rename with zero user-visible difference; the rename
  is about the word a user reads.

## Consequences

- The tab states its two kinds: App settings works with no host; Host
  settings alone carries the host error banner. A language tap
  re-localizes the whole app immediately, asserted end-to-end in
  `widget_test.dart` (中文 pins, 跟随系统 releases).
- The registry and scope designs are unchanged; only their visible
  words moved (see
  [multi-backend registry](2026-08-20-multi-backend-registry.md),
  [settings backend scope](2026-08-21-settings-backend-scope.md)).
  The parity note's busy-Enter placement and the i18n note's
  device-locale behavior are amended here (see
  [settings parity](2026-08-20-settings-section-parity.md),
  [bilingual i18n](2026-08-20-bilingual-i18n-zh-en.md)).
- Design shots: `settings-general` / `settings-hosts` pair against
  their pre-split renders; `settings-app` / `settings-app-zh` are new
  surfaces (the review harness gained a `host` builder — a
  root-scope tree per shot, the shape the screen's widget tests
  pump). Tests ride real entry paths; `_revealCapsule` scopes to the
  section nav's scrollable (the category row rides its own).
