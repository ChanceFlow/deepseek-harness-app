# Agent Note: The deployment's default permission preset

Status: implemented

## Problem

The permission plane has two facts on two surfaces, and the phone carried
only one of them. A *session's* preset is switchable from the composer's
access chip (the chip submits `/permission <preset>`, mirroring web
`ui-permission-presets` `choose`). The *deployment default* a new session
starts from is a settings write: the reference reads
`permissionPresets/catalog` for the composed table and patches
`defaultPreset` inside the settings namespace `permission`
(`packages/client/ui-permission-presets/src/client/settings-store.ts`
`permissionDefaultOf` + the write), a `settings.general` row at order -20.

The phone had no such row and never called `permissionPresets/catalog`: the
catalog was one of the 48 upstream endpoints the client did not declare, so a
deployment could not change what a new session starts on from the phone at
all, and the access chip's options (a *session* projection) were the only
presets visible anywhere.

## Decision

- **`permissionPresets/catalog` joins the registry** and decodes into
  `PermissionPresetCatalog {options, defaultOptions, defaultPreset}` — a model
  deliberately distinct from `PermissionSelect` (one session's projection).
  `loadPermissionPresetCatalog()` is the repository method.
- **A new page owns the default**: Settings → Chat → *Default permission
  preset* (`ui/settings/permission_defaults.dart`). It offers exactly
  `defaultOptions` — a host may compose a preset that is switchable per
  session but not acceptable as a deployment default — and marks the
  namespace's own `defaultPreset`, falling back to the catalog's when the
  namespace carries no value (`permissionDefaultOf`'s rule).
- **The write is one key patch with the described revision**:
  `UpdateSettingAction(ns: 'permission', key: 'defaultPreset', expectedRevision: <describe revision>)`
  through the existing settings controller, so the CAS guard, the refresh and
  the error log are the settings plane's, not a second write path.
- **The page names the other surface.** Its intro says the current session
  switches from the composer's access chip; the two are one tap apart and
  read identically otherwise.
- **A host without the service, or a read-only document, states it.** A
  catalog read failure renders *"this deployment composes no permission preset
  catalog"* instead of an empty choice; `writable: false` shows no selection
  and lands no write, with the read-only line under the rows.

## Alternatives considered

- **Drive the page from the session projection (`permissions`)**: rejected —
  that value is per session (it carries `currentValue`, not a default) and a
  host composes `custom` there; a deployment default has its own table.
- **Offer `options` rather than `defaultOptions`**: rejected — the host
  distinguishes the two precisely so an operator can withhold a preset from
  new sessions while keeping it switchable inside one.
- **Write through `settings/mutate` path ops (as the web store does)**:
  rejected for the phone — `settings/update` already patches one top-level
  key with the same revision guard, and a second settings verb for one field
  would add a wire path with no other caller.
- **Put the picker in the composer's access chip sheet**: rejected — the chip
  is the *session* control; mixing a deployment write into it would change
  every future session from a control that otherwise touches one.

## Consequences

The zero-key state is safe: a namespace without `defaultPreset` shows the
catalog's effective default, and a host that composes no permission service
gets a page that says so. The page reads the namespace through the settings
channel (a pushed page is not a descendant of the Settings tab), so a write
lands in the same snapshot the rest of settings reads. Coverage moves to
declared 85 / identical 83 / missing 45.

## Testing

`packages/harness_adapter/test/harness_repository_integration_test.dart`
covers the catalog endpoint and the decode of both tables plus the default
(including an option without a description).
`app/test/ui/settings/permission_defaults_test.dart` covers the rows and the
marked selection, a pick writing only `defaultPreset` with revision 7, the
namespace value overriding the catalog default, the no-catalog notice, and the
read-only document writing nothing. A design shot
(`settings-permission-defaults`) renders the page against the fixture catalog.
