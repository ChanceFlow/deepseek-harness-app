# Agent Note: Sidebar settings trigger and destination persistence

Status: implemented

## Problem

The web sidebar's foot carries the settings entry (the `sidebar.settings`
seat: gear glyph plus label, bottom-pinned under a hairline divider), but
the Flutter chat sidebar had no such trigger — Settings was reachable only
through the bottom bar. The sidebar's browsing toggles (per-group
expansion overrides, per-group overflow expansions) also died with the
widget: nothing survived an app restart.

## Decision

SessionPanel (`flutter/app/lib/ui/chat/session_panel.dart`) pins a
settings footer under the browsing region in both wide forms — pane and
drawer. The row follows the web trigger vocabulary (ui-settings-general
`chrome.tsx` `TriggerContent`, `SettingsRoot.module.css` `.trigger`):
hairline divider (`ds.divider`), 44px touch height, 18px
`Icons.settings_outlined` in label-secondary ink, `interactiveBgHover`
hover and press fill. The web hides the label in the collapsed rail
column (the `wide` gate); every mobile form is wide enough for the
one-word label, so both the pane and the drawer show icon plus label.

The selection is app state, not panel state:
`appDestinationProvider` (`flutter/app/lib/ui/root/app_destination.dart`)
— a `NotifierProvider<AppDestinationNotifier, AppDestination>` whose
`select` method is the single mutation path. AppRoot watches it (the
bottom NavigationBar routes through the same notifier) and the footer
trigger calls it directly; no callback chain runs from the sidebar into
the root scaffold. Tapping the trigger lands on the Settings destination,
and the bottom bar follows because both read one provider.

The destination and the browsing toggles persist through the shared
LocalStateStore (`flutter/app/lib/local_state/`):

- `app.destination` (int, the AppDestination index): restored when the
  store provider resolves, written on every select.
- `sidebar.groupOverrides` (`Map<String, bool>`) and
  `sidebar.overflowExpanded` (`List<String>`): SessionPanel seeds both
  once the store resolves and writes both on every toggle.

The group-override contract carries two always-on rules no override
defeats (the active session never hides behind a fold the user must
hunt through): the group holding the active session is always expanded
— its header toggle is a no-op — and within any group the active
session rides first (same-group pinning), which also keeps it above
the collapsed-session overflow limit. Non-current groups default
folded and follow their overrides.

Until the store resolves, every surface behaves as with an empty store
(the defaults); a user toggle inside that pre-load window outranks the
persisted snapshot — seeding is skipped, live intent wins. Decoders
re-check each JSON member (the round-trip yields `Map<String, dynamic>`),
so a malformed entry drops out instead of throwing.

Tests (`flutter/app/test/ui/chat/session_panel_test.dart`) drive real
SessionPanel instances with the chat screen's standard callbacks. Real
disk IO never completes inside a testWidgets fake-async zone, so the
persistence tests assert the store's synchronous cache write-through and
restore a fresh widget instance seeded from the same store; the disk
round-trip belongs to the store's own suite. Toggles schedule the
store's debounce timer, so every writing test pumps fake time past the
debounce window — a pending timer fails the test invariant.

## Alternatives considered

- **Callback from the panel to the root scaffold**: rejected — the
  destination has several writers (bottom bar, sidebar trigger); a
  provider removes the coupling a callback chain creates.
- **StateProvider plus a top-level select helper**: rejected — the
  restore-on-load / write-on-change contract needs one home, and a
  Notifier method is that home; a bare StateProvider leaves persistence
  wiring to every call site.
- **Wrapping only the footer row in a Consumer**: rejected — the seed
  and the toggle writes need `ref` in the panel state anyway;
  ConsumerStatefulWidget is the smaller total diff.
- **Disk-level assertions in the widget tests**: rejected — the
  fake-async zone starves real IO (a temp-file flush never completes
  inside testWidgets); the synchronous cache is the seam the panel
  owns.

## Consequences

The sidebar carries the settings entry in both mobile forms; the
collapsed rail form keeps its icon-only controls with no settings seat —
the bottom NavigationBar keeps Settings one tap away there. The selected
destination survives restarts, as do the browsing toggles. The
AppDestination enum lives in app_destination.dart beside its provider.
The fake-async IO constraint binds every future widget test that touches
the store: build the store synchronously, assert the cache, pump past
the debounce, never await IO in-zone.
