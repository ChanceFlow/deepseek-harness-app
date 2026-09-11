# Agent Note: The optional pure-black OLED appearance

Status: implemented

## Problem

The dark scheme's page is M3's standard dark grey — `surface` `#121318` in the
brand-seeded scheme
([theme.dart](../../../../flutter/app/lib/ui/theme/theme.dart)). On an OLED
phone that is a lit pixel under every line of the transcript: a long coding
session pays for it in power, and in a dark room the near-black grey
backbleeds instead of disappearing. A reader who wants the panel dark had no
seat for it — the Appearance row offered light, dark, and follow-system
([theme_preference.dart](../../../../flutter/app/lib/ui/settings/theme_preference.dart)) —
and the host's `ui-theme.preference` union is closed at
`light`/`dark`/`system` (`THEME_PREFERENCES`,
[theme-settings.ts](../../../../reference/deepseek-harness/packages/client/ui-theme/src/theme-settings.ts)).

## Decision

- **`DshTheme.oled()`** keeps the M3 dark roles and moves only the surface
  family: `surface` (page and transcript) to true black `#000000`, and the
  containers onto a near-black ladder — `surfaceContainerLow` `#0F0F13`,
  `surfaceContainer` `#15151B`, `surfaceContainerHigh` `#232329`,
  `surfaceContainerHighest` `#2F2F36`. The `DshSchemeColors` inks keep their
  M3 dark values, so nothing else re-tunes and no `ThemeExtension` is added.
- **The two-tone rule still holds by tone.** The page-to-chrome step is
  1.155:1 against the dark scheme's 1.132:1, so the transcript separates from
  its frames with no rule drawn; the ladder carries the hierarchy the grey
  carried.
- **OLED is device-local.** The host union cannot store it, and whether a
  panel lights a black pixel is a fact about this phone, not the host's shared
  user document. The flag rides the existing `LocalStateStore` under
  `app.oledAppearance`, absent by default; light/dark/system keep riding
  `settings.describe`/`settings.mutate` unchanged, so no stored value changes
  meaning and an untouched device behaves exactly as before.
- **The Appearance selector gains a fourth seat** — light, dark, OLED,
  follow-system — in the same stock `SegmentedButton`. OLED flips the local
  flag and leaves the host document alone; a host seat clears the flag and
  writes the host preference as before. `appThemeModeProvider` pins dark while
  OLED is on and `appDarkThemeProvider` swaps `DshTheme.dark()` for
  `DshTheme.oled()` in [main.dart](../../../../flutter/app/lib/main.dart).
- **Measured ink contrast on the pure-black page**, in the style the
  light-mode `warning`/`success` fixes used
  ([recommended-badge-contrast.md](../bug-fix/2026-08-22-recommended-badge-contrast.md));
  every text role clears 4.5:1:

| role | on `#000000` |
|---|---|
| `onSurface` | 16.21:1 |
| `onSurfaceVariant` | 12.30:1 |
| `primary` | 12.34:1 |
| `error` | 12.37:1 |
| `warning` | 10.98:1 |
| `success` | 10.44:1 |
| `syntaxKeyword` | 8.79:1 |
| `syntaxString` | 10.44:1 |
| `syntaxNumber` | 12.13:1 |

  The syntax trio sits on `surfaceContainerHigh`, not the page, where it
  measures 6.54 / 7.77 / 9.03:1; `outlineVariant`, a hairline rather than ink,
  reads 2.25:1 on the page against 1.99:1 on the dark grey. No role failed, so
  no ink had to be re-chosen.

## Alternatives considered

- **Replace `DshTheme.dark()` outright with pure black.** Rejected: it removes
  the reader's choice, and a black page cannot carry the tonal elevation the
  grey does for readers who never wanted it.
- **Scale the dark surface ladder down proportionally** (halve each role's
  luminance). Rejected by measurement: the page-to-chrome step falls near
  1.06:1, under the dark scheme's 1.132:1, and chrome dissolves into the page.
- **A per-role user palette.** Rejected: that is the custom token layer
  [docs/design-standard.md](../../../../docs/design-standard.md) rejects, and
  it moves colour decisions out of the role map and into every call site.
- **Follow the system's OLED hint.** Rejected: Android exposes no such signal
  to the client, and a wrong guess repaints the app without the reader asking.

## Consequences

- The Appearance row has four seats; `theme_preference_test.dart`'s old
  three-seat assertion and `dsh_theme_test.dart`'s two-theme loops now cover
  the third appearance — a deliberate update of the old count, not a weakened
  assertion. `settingsAppearanceOled` lands in both ARBs, and `flutter
  gen-l10n` output is regenerated.
- Pure black costs the elevation shadows: a black shadow on a black page
  renders nothing. Chrome is separated by the container ladder instead, and
  the `outlineVariant` hairlines the app already draws read more strongly on
  black than on the dark grey.
- The Appearance selector still renders only when the host exposes `ui-theme`.
  The OLED flag survives that gate — it restores from the local store on
  launch and resolves the app theme — but choosing it requires the exposed
  row, so a phone whose host loopback-gates the namespace cannot reach the
  seat.
- Evidence: `dsh_theme_test.dart` asserts the OLED surface is true black
  (luminance 0), the container ladder rises off it, the two-tone step is at
  least the dark scheme's, and every ink role clears 4.5:1 read back from the
  theme's own roles; `theme_preference_test.dart` round-trips the flag through
  the store, leaves it absent by default, and pumps the row under the app's
  real theme resolution to assert a tap on OLED paints the pure-black surface.
