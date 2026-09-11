# Agent Note: Turn deliverables, per-message run metrics, and host appearance

Status: implemented

## Problem

The reference web client closes a finished turn with two facts this phone
client lacked. A compact row lists the files the turn produced, derived from
its successful mutation tool calls — never the closing prose
(`reference/.../client/ui-deliverables/src/client/ProducedFiles.tsx`,
`turn-deliverables.ts:50-107,131-154`). The closing assistant's action row
carries `· Ran for 15s · TTFT 1.2s · 34 tok/s` folded from step timings
(`ui-chat/src/client/chat/TurnUsagePanel.tsx:132-181`,
`contract/turn-metrics.ts:42-51`). The phone showed neither: the transcript
had only a per-message HH:mm clock and a turn-aggregate `StatsLine` above the
composer.

Appearance was the third gap. The web persists a `light`/`dark`/`system`
preference in the host user-settings document's `ui-theme` namespace
(`ui-theme/src/theme-settings.ts:9-21`, `client/index.ts:231-239`). `main.dart`
set `theme`/`darkTheme` with no `themeMode`, so the app only followed the OS.

## Decision

**Produced files come from settled mutation calls.** `produced_files.dart`
extracts a path from a `completed`, non-error `write`, `edit`, or
`str_replace_editor` call with the reference's per-tool argument validation
(string `content`; a real `edit` replacement; a complete mutating editor
command). Reads, unsupported tools, malformed JSON, and failed calls
contribute nothing; paths keep first-seen order and are deduped per turn.
Turns come from the transcript's `TimelineTurnBoundary` rows, so paths cannot
spill; the row attaches to the turn's last assistant message with text, and
the newest turn's row waits until the session stops running (the reference
renders at `turn/end`). A call logged after the closing reply is excluded
from its snapshot, matching `producedForClosing`.

`ProducedFilesRow` renders up to six basename chips plus a localized `+N
files` counter between the message body and its action row. A chip opens the
existing in-app preview sheet: `host.openPath` is loopback-privileged, so a
directly-connected phone cannot ask the host desktop to open a file — the
preview is the affordance the client can honor.

**Per-message metrics state only measured boundaries.** The action row
renders decode throughput over `firstTokenAtEpochMs..createdAtEpochMs` (the
reference's `completedTime`) and the message's reported token total —
`usage.totalTokens`, or the sum of the buckets the host did send. Run wall
time and TTFT are omitted: `TimelineTurnBoundary` carries no `turn/start` /
`turn/end` time and the adapter does not expose the owning `step/start` time.
An absent figure stays absent; nothing is zero-filled or approximated.

**Appearance reads and writes the host namespace.**
`theme_preference.dart` owns `ThemePreference`, `ThemePreferenceController`,
and `ThemePreferenceRow`. The controller describes `ui-theme`, reads
`preference`, and writes it with the described revision as CAS guard over
`settings.mutate` — the same machinery the agent-preset default uses. The
selection updates optimistically, reverts on refusal, and the row states
unavailability (with retry) rather than showing `system` as if it were
stored. `appThemeModeProvider` resolves the chat-active backend's value for
`main.dart`, which sets `themeMode`. The active backend is the target so the
control always affects the theme the user sees.

## Alternatives considered

- **Derive produced files from the closing prose or a path regex.** Rejected:
  the reference's vocabulary is the durable tool-call family, and a file must
  list whether or not the model named it.
- **`host.openPath` for a chip.** Rejected: loopback-privileged; a direct
  connection can only list paths, so the promise would fail on the device the
  client targets.
- **Label the first-token..message interval "Ran for".** Rejected: it is the
  decode window, not turn wall time; a mislabeled measured number is worse
  than an omitted one.
- **Derive turn duration from the first message's first token to the closing
  message.** Rejected: it drops pre-token and post-message time, so the
  figure would be invented.
- **Persist the theme device-locally like the locale preference.** Rejected:
  the host namespace is the contract the web persists, and honoring a value
  the user set elsewhere requires reading it.
- **Render hook-audit and workflow-run rows in this pass.** Rejected as out
  of scope; the new `domain` variants get exhaustive arms that render nothing
  in the transcript and ledger, so they stay addressable for their own
  surface.

## Consequences

- `main.dart` needs `import 'ui/settings/theme_preference.dart';` and
  `themeMode: ref.watch(appThemeModeProvider).value ?? ThemeMode.system`.
- `settings_screen.dart` mounts `ThemePreferenceRow` in
  `_AppPreferencesSection` (import plus one padded child).
- Startup issues one `settings.describe` per active backend; a non-loopback
  or absent namespace degrades to `system` and a breadcrumb, never a crash.
- New ARB keys: `producedFilesLabel`, `producedFilesMore`,
  `producedFilesOpen`, `messageTokensPerSecond`, `messageTokenUsage`,
  `settingsAppearanceTitle`, `settingsAppearanceLight`,
  `settingsAppearanceDark`, `settingsAppearanceSystem`,
  `settingsAppearanceUnavailable`, `settingsAppearanceSaveFailed`.
- Hook-audit and workflow-run timeline variants decode but render nothing in
  the chat transcript and trajectory ledger until their own surface lands.
