# AGENTS.md — flutter/app (UI surface)

Supplements the [root conventions](../../AGENTS.md#conventions) and the
[workspace file](../AGENTS.md). This package owns the client's aesthetic and
every spatial decision: the adapter publishes facts, `app` places them.

## Stock Material 3 is the aesthetic

Every surface reads as a stock Android app.

- **Reach for the framework component before drawing one.** Rows, groups,
  menus, dialogs, and controls ride `ListTile`, `ExpansionTile`,
  `RadioListTile`/`CheckboxListTile`, `FloatingActionButton`,
  `OutlinedButton`, `IconButton`, `Dialog`. Hand-built chrome or a
  `CustomPainter` carries its reason in the change's decision note; the
  standing exceptions are the markdown renderer, the outline timeline's turn
  folding, and the brand fish logo.
- **Colors come from `ColorScheme` roles.**
  `Theme.of(context).colorScheme` is the source:

| Intent | Role |
|---|---|
| Page background, scaffold | `surface` |
| Grouped or raised surface, menu, sheet | `surfaceContainerLow/High/Highest` |
| Primary text, icons | `onSurface` |
| Secondary text, metadata, inactive glyph | `onSurfaceVariant` |
| Divider, hairline border | `outlineVariant`, `outline` |
| Accent, selection, active state | `primary`, `primaryContainer` |
| User bubble | `primaryContainer` / `onPrimaryContainer` |
| Failure, destructive, warning | `error`, `errorContainer` |
| Modal scrim | `scrim` |
| Success, completed state | `success` (the one non-role color, see below) |
| Ink host that must stay invisible | `Colors.transparent` |

- **`theme.dart` is the home for a color Material 3 has no role for.** It
  holds the elevation shadow constants and the `DshSchemeColors` extension,
  which is why a call site writes `scheme.success` rather than a green. A new
  non-role color is declared there and gains a row above in the same change.
  `verify_theme_native` rejects a `Color(0x…)`, a `Colors.<name>`, or a
  `ThemeExtension` anywhere under `lib/` outside that file, so the map is the
  only way through.
- **Motion, elevation, and shape are framework defaults.** The M3 durations
  and `Theme` shapes carry animation and geometry; a bespoke curve or radius
  is a per-change decision with a reason, not a house style.

## Structure and state

- **One directory per feature** under `lib/ui/` (`chat`, `workspace`,
  `models`, `subagents`, `goal`, `settings`), the screen's controller beside
  it. Controllers expose UDF state streams.
- **`lib/di/` is the only code that sees adapter or network types** (root
  import-boundary rule, enforced by `scripts/check_dart_imports.py`).
- **Every user-visible string is an ARB key** in `lib/l10n/app_en.arb` and
  `app_zh.arb`, both edited in the same change (`verify_i18n_arb` compares the
  key sets and the placeholder names); the generated
  `app_localizations*.dart` files are committed
  ([the i18n note](../../.agents/notes/implemented/feature/2026-08-20-bilingual-i18n-zh-en.md)).
- **Telemetry stays optional at the call site.**
  `DebugTelemetry.instance?.event(...)` — the screen behaves identically when
  the facade is null ([packages/dev](../packages/dev/AGENTS.md)).

## Evidence

Widget tests pump the real tree with a real controller and assert what a user
would see: the found widget type, its text, the color read back from the
theme's role ([docs/testing.md](../../docs/testing.md)). A color assertion
pumps the same surface under both `DshTheme.light()` and `DshTheme.dark()`
(`l10nApp(theme: …)`, then a pump past the theme lerp) and compares against
that theme's role — a hard-coded color passes one brightness and fails the
other. Tests mirror `lib/` paths under `test/`.
