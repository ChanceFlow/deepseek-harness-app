# AGENTS.md — flutter/app (UI surface)

Supplements the [root conventions](../../AGENTS.md#conventions) and the
[workspace file](../AGENTS.md). This package owns the client's aesthetic and
every spatial decision: the adapter publishes facts, `app` places them.

## The dsh web client is the aesthetic

Every surface reads as the pin's own client at phone width. Why, and how to
derive the next value: [docs/design-standard.md](../../docs/design-standard.md).

- **The pin's token sheet is the authority.** `theme.dart` ports the
  `--dsw-alias-*` colors, the six radii and the `--dsw-font-*` ladder from
  `reference/deepseek-harness/packages/client/ui-theme/src/styles/`; a surface
  reads an alias, and `ColorScheme` is the shrinking compatibility shim.
- **Take the pin's anatomy before drawing one.** A step is a 24 px disclosure
  line, a session row 32 px, the composer a radius-28 card, pickers anchored
  popovers, confirmations centered 28 px modals, settings a full-viewport
  sheet. Hand-built chrome carries its reason in a decision note; standing
  exceptions are markdown, turn folding and the brand marks.
- **Colors come from the alias table.** `ColorScheme.aliases` carries the
  pin's values; `theme.dart` is their only home.

| Intent | Alias |
|---|---|
| Page and chrome | `bgBase`, `specificSidebarFill` |
| Raised surface, card, sheet | `bgLayer2`, `settingsCardFill` |
| Primary text, icons | `labelPrimary` |
| Secondary text, metadata | `labelSecondary`, `labelTertiary` |
| Hairline border, divider | `borderL2`, `borderL4` |
| Accent, selection, sent | `buttonInfoFill`, `stateBusinessPrimary` |
| User bubble | `specificBubble` |
| Failure | `stateErrorPrimary` |
| Warning, waiting on user | `stateWarnPrimary`, `stateWarnLabel` |
| Success, done | `stateSuccessPrimary`, `stateDonePrimary` |
| Code fence | `markdownCodeBlock`, `syntaxKeyword/String/Number` |

- **`theme.dart` is every token's home.** It holds the alias table, the
  elevation shadows and `DshSchemeColors`, so a call site writes
  `scheme.labelTertiary`, not a hex; `verify_theme_native` rejects a raw
  color, `Colors.<name>` or `ThemeExtension` under `lib/` outside it.
- **Two tones separate content from chrome.** The transcript sits on `bgBase`,
  every frame on the sidebar fill. One filled seat per surface: the pin's blue
  send circle.
- **Space divides; a rule is a decision.** A rule is the pin's 0.5 px hairline
  (`borderL2`/`borderL4`), drawn only where its sheet draws one. A row is as
  tall as its line: shrink the ambient icon size rather than wear the 24 px
  chevron; one-line rows take `height: 1.2`.
- **Shape comes from the named scale** in `theme.dart`: `kRadiusXs` 4,
  `kRadiusSm` 8, `kRadiusMd` 12, `kRadiusLg` 16, `kRadiusXl` 20, `kRadiusPanel`
  28, `kShapePill` 999. A further radius needs a reason, not a call-site
  number.
- **Motion follows `DshMotion` tokens in `theme.dart`**, the pin's
  `--ds-transition-*` durations and `--ds-ease-in-out` curve. Controls provide
  tactile feedback (`DshTappable`); pages ride `PageTransitionsTheme`.
  Hard-coded motion is rejected; reduced motion is honored.

## Structure and state

- **One directory per feature** under `lib/ui/` (`chat`, `workspace`,
  `models`, `subagents`, `goal`, `settings`), the screen's controller beside
  it. Controllers expose UDF state streams.
- **`lib/di/` is the only code that sees adapter or network types** (root
  import-boundary rule, enforced by `scripts/check_dart_imports.py`).
- **Every user-visible string is an ARB key** in `lib/l10n/app_en.arb` and
  `app_zh.arb`, both edited in the same change (`verify_i18n_arb` compares key
  sets and placeholder names); the generated `app_localizations*.dart` are
  committed
  ([the i18n note](../../.agents/notes/implemented/feature/2026-08-20-bilingual-i18n-zh-en.md)).
- **Telemetry stays optional at the call site.**
  `DebugTelemetry.instance?.event(...)` — the screen behaves identically when
  the facade is null ([packages/dev](../packages/dev/AGENTS.md)).

## Evidence

Widget tests pump the real tree with a real controller and assert what a user
would see: widget type, text, the color read back from the theme's alias
([docs/testing.md](../../docs/testing.md)). A color assertion pumps the same
surface under both `DshTheme.light()` and `DshTheme.dark()` (`l10nApp(theme:
…)`, then a pump past the theme lerp) — a hard-coded color passes one
brightness and fails the other. Tests mirror `lib/` paths under `test/`.
