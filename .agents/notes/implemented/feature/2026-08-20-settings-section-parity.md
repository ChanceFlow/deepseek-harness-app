# Agent Note: Settings tab parity with the web settings panel

Status: implemented

## Problem

The mobile Settings tab rendered one flat list — two fact rows, raw
namespace JSON cards, credentials — while the dsh web client ships a
settings panel with a section nav (General / Models / Plugins / Agent
presets) whose rows are interactive preferences. Users could not reach
the busy-Enter preference, the default agent preset, or a readable
preset roster from the phone.

## Decision

The tab mirrors the web panel's shape at phone width: a horizontal
capsule nav (`SettingsRoot.module.css` `.navList` vocabulary, on the
app's `_ModeButton` capsules) over an `IndexedStack` of pages in the
web nav order — General, Models, Plugins, Agent presets — plus a
mobile-only Credentials page (the web manages secrets inside the Models
provider editors; the phone keeps them directly addressable).
`IndexedStack` preserves each section's scroll and disclosure state
across switches. Header, error banner, and refresh chrome stay as the
web panel header.

General holds the interactive rows the web registers:

- Enter behavior while busy — Queue/Steer capsules persisted to the
  shared `LocalStateStore` under `chat.busyEnterBehavior`
  (`busy_enter_preference.dart`; a UDF controller per store via
  `busyEnterPreferenceProvider`, so the composer's busy-send path reads
  the same key). Device-local: no wire call.
- Agent preset default — options from `ChatRepository.listAgentPresets`
  (broken presets excluded, web `presetOptions` rule), display via the
  shared `agentPresetDisplayName` helper, picker on the menu-surface
  sheet. The write is the web `writeDefaultPreset` shape:
  `updateSetting('agent-presets', 'default', '"<id>"')` with the
  namespace revision from the last `describeSettings` as CAS guard.
  The control is disabled while the host reports read-only.
- Host-writes and settings-document fact rows stay (web General facts).

The Agent-presets page renders the roster as the web section's grouped
cards (Built-in / Custom): display name, 4-line-clamped description
offered in full via long-press tooltip, mono id; the default card reads
selected (layer-2 fill, primary border) with an 'In use' mark; a broken
preset carries the error border, 'Failed to load' badge, verbatim
reason, and a disabled body. Tapping a healthy non-default card is the
same default write as the General row. Authoring is host-only: copy,
delete, and the compose-viewer verbs ride loopback-pinned RPCs a mobile
client cannot reach, so the page carries a one-line tertiary footnote
instead of those actions, and an empty roster renders only that
footnote.

The roster loads inside the describe refresh; its failure keeps the
last good roster and surfaces through the existing error banner. The
tab stays describe-gated: on a non-loopback connection the body remains
the error state even though `agentPreset.list` itself is reachable —
the default write needs the settings plane anyway.

Plugins page: the namespace disclosure cards unchanged under the web
Plugins heading. Models page is scoped to existing adapter coverage:
the DeepSeek API-key card (`DEEPSEEK_API_KEY` credential state, set/
unset through the same editor sheet) plus the read-only notice; the
web's provider-directory joins and schema-driven profile editors need
RPCs the adapter does not expose.

## Alternatives considered

- Bottom-sheet per section instead of an IndexedStack nav — loses
  cross-section orientation and scroll state; the capsule row keeps
  the panel's two-pane reading at phone width.
- `selectAgentPreset` for the default write — that verb selects a
  preset for one session; the default is a settings field (web writes
  the namespace), so the settings update path is the faithful port.
- Rendering the presets section when describe fails — rejected: the
  General facts and the write path both need the snapshot, so the page
  would render half-alive; the web section's remote availability is a
  follow-up if a lane wants it.

## Consequences

Deferred: the permission-preset default row (the web reads the dynamic
preset enum from the `permission` namespace's schema; the adapter's
settings projection carries no schema or namespace value, so neither
the options nor the current `defaultPreset` is expressible without new
coverage) and custom-provider CRUD (`llm.providers` directory plus
schema reads). Both need adapter coverage another lane owns. Tests
drive the real screen through a real `SettingsController` with a
recording repository double, a temp-file `LocalStateStore`, and
hit-testable visibility assertions across the IndexedStack pages.
