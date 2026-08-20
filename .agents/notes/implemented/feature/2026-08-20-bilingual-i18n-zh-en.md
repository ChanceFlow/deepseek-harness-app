# Agent Note: 中英双语国际化（flutter_localizations + ARB）

Status: implemented

## Problem

The Flutter client ships English-only copy hardcoded across ~25 UI files
(300+ user-facing literals), including screens, shared widgets, pure copy
resolvers (tool row titles, preset display, stats labels), and controller
diagnostics. 多语言版本（中英）要求全部用户可见文案可随设备语言切换，
且中文与英文文案质量需与现有 UI 对齐。

## Decision

Wire `flutter_localizations` + `intl` with ARB-based generation:

- `flutter/app/pubspec.yaml` gains `flutter_localizations` (SDK) and
  `intl`; `flutter: generate: true`; `flutter/app/l10n.yaml` configures
  `arb-dir: lib/l10n`, template `app_en.arb`, output
  `app_localizations.dart`.
- **Generated files are committed.** Flutter 3.47 removed
  `synthetic-package`; gen-l10n writes `lib/l10n/app_localizations*.dart`
  into the package. This is an explicit, SDK-mandated exception to the
  no-codegen rule (root AGENTS.md §Conventions: that rule targets wire
  DTO codegen — freezed/json_serializable/build_runner; flutter/AGENTS.md
  "no generated files" now links here). A regen must stay byte-identical:
  `flutter gen-l10n` from `flutter/app` with no drift.
- `DshApp` (main.dart) registers `AppLocalizations.delegate` +
  global delegates and `supportedLocales: [en, zh]`. Device locale drives
  the language; no in-app switcher in this MR (alternative below).
- **ARB key discipline:** every key has `@key` metadata in the template;
  placeholder metadata types all getter parameters (String/int, never
  Object); ICU plural syntax for counts, `use-escaping: true` in
  l10n.yaml for literal braces; apostrophes double in message values
  (`session''s`).
- **Pure copy resolvers thread `AppLocalizations`** instead of reading
  global state: `agentPresetDisplayName/Description`, `deriveToolRowModel`,
  `todoProgressLabel`, `permissionOptionLabel`, `presetIdLabel`,
  `goalPhaseLabel`, `formatJobDuration`, `_statusLabel`, `variantTitles`,
  `hostCommands` become functions taking `AppLocalizations` (or were
  converted to localized maps/lists). Widget call sites pass
  `AppLocalizations.of(context)!`.
- **AppDestination labels** become `label(AppLocalizations)` methods;
  `kHeroHeadline/kHeroPreview/kHeroChooseWorkspace` consts are removed in
  favor of ARB keys; `kVariantTitles`/`kHostCommands` consts become
  l10n-aware functions.
- **Controller diagnostics stay locale-neutral; the UI layer formats.**
  `ChatController._admitPendingImages` collects a structured
  `List<ImageRejection>` (mediaType/byteSize/room rejection reasons)
  instead of joining English strings into `errorMessage`; `ChatUiState`
  carries it; `chat_screen` renders each rejection through l10n.
  Non-image `errorMessage` (host error strings, action messages) stays as
  data — host-authored text is not translated client-side. A host
  command that errors with no message sets `ChatUiState.commandFailed`;
  the strip renders the localized `commandFailed` line (reference
  `command.failed`), keeping the controller English-free.
- **The host-command roster splits in two**: `kHostCommandNames` (const,
  wire names/hints for the controller's `/command` membership check) and
  `hostCommands(l10n)` (localized descriptions for UI rows).
- **System notifications localize at launch.** `TurnCompleteNotifier`
  resolves `lookupAppLocalizations(platformDispatcher.locale)` once in
  `initialize()` (main's `ensureInitialized` path), so the
  turn-complete title and Android channel strings follow the device
  language without context plumbing into the DI layer; the pre-init
  seat is en. `MaterialApp.onGenerateTitle` resolves the OS
  task-switcher label through l10n likewise.
- **Turn/end timeline errors localize in the UI layer.**
  `timeline_reducer` publishes the wire kind (`code`) plus host error
  detail only (`message`, empty for non-error kinds) — never composed
  English; `chat_screen` maps the known kinds (`error`/`aborted`/
  `interrupted`/`blocked`/`max-tokens`) to l10n keys (reference
  `message.turnError`/`maxTokens` family), falling back to `message`
  for unrecognized kinds. spec.md documents the contract.
- **Widget tests resolve localization** through a shared helper
  `test/l10n_app.dart` (`l10nApp(home: ...)`); every pump site switched
  from a bare `MaterialApp` to it. Pure-function tests (tool row model,
  stats line) construct en via `lookupAppLocalizations(Locale('en'))`.

## Alternatives considered

- **In-app language switcher (settings toggle + persisted locale).** Adds
  a settings surface, persistence, and rebuild plumbing; device-locale
  following covers the stated 中英 requirement. Deferred; the wiring here
  (supportedLocales, delegates) is switch-ready if it lands later.
- **Locale registry for system notifications** (a Riverpod
  `localeProvider` synced from DshApp, live-updating titles on locale
  switch). Rejected: notifications post only while backgrounded and the
  plugin caches Android channel metadata; resolving the launch-time
  locale once in `initialize()` covers device-language changes with a
  fraction of the plumbing. An in-app switcher (above) would revisit
  this.
- **Keep the "no generated files" stance and hand-write localizations.**
  Flutter 3.47 has no synthetic package; hand-rolled lookup tables would
  duplicate gen-l10n and rot; committing SDK output is the ecosystem
  default.
- **Localize inside controllers** (pass l10n into controller methods).
  Violates the UDF separation (controllers publish facts, not copy) and
  forces context plumbing into the DI layer; the structured-rejection
  path keeps controllers locale-free.
- **Fallback when `AppLocalizations.of(context)` is null.** Silent
  English fallback hides missing-delegate bugs in tests; the
  `!` + shared test helper fails loud instead.

## Consequences

- All user-facing copy in `flutter/app/lib/ui/**` (screens, shared
  widgets, composer chrome, presets, models, session panel, subagents,
  workspaces, settings) resolves through `AppLocalizations`; en and zh
  catalogs are complete and cross-checked (every en key has zh).
- Tests assert localized output through real entry paths (l10nApp
  wrapper); a widget pumped without delegates fails loudly.
- Pure copy resolvers are now locale-parameterized — call sites outside
  `app/` (none today; `domain` never imports app) stay clean.
- ARB keys are the single source of copy truth; adding a string means
  editing `app_en.arb` + `app_zh.arb` + regenerating (gate: gen-l10n
  determinism, `flutter analyze`).
- Caution: gen-l10n sorts placeholder parameters alphabetically in
  generated getters; call sites must follow the generated signature, not
  the ARB order.