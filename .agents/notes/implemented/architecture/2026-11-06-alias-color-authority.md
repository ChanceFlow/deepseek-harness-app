# Agent Note: The pin's alias table assembles the ColorScheme

Status: implemented

## Problem

`DshTheme._build` called `ColorScheme.fromSeed(seedColor: kDshBrandSeed)`, so
all 1,097 `colorScheme.*` reads resolved to M3's generated tones: lavender-
tinted surfaces where the pin has a neutral-bluish ladder, a seed `primary`
where the pin's send seat is `button-info-fill`, no `label-*` text ladder, no
state tokens. The alias extension existed but carried 11 % of the reads;
`fromSeed` decided the other 89 %.

## Decision

- **`DshAliases`** — one const table per brightness, 78 fields named after the
  pin's `--dsw-alias-*` tokens, each with the CSS line it comes from. Alpha is
  kept (`Color.fromRGBO`) wherever the pin composites over a parent, and
  `color-mix` values are `Color.lerp` of the same endpoints.
- **`ColorScheme` is assembled, not seeded.** `DshTheme._build` sets
  `surface`/`surfaceDim`/`surfaceBright`, the five-step container ladder,
  `onSurface`/`onSurfaceVariant`, `primary`/`primaryContainer`,
  `secondaryContainer`, `tertiary`, `error`, `outline`/`outlineVariant` (the
  `borderL4`/`borderL2` alphas), `scrim` (the mask), `inverseSurface` (the
  toast) and `surfaceTint: transparent` from the table. `fromSeed` and
  `kDshBrandSeed` are gone.
- **`DshSchemeColors` reads the table** through `scheme.aliases`, keeping its
  48 getters and adding exact state getters (`stateSuccess*`, `stateWarn*`,
  `stateDonePrimary`, `stateIdlePrimary`, `stateBusiness*`,
  `stateErrorSecondary`) for dots and fills.
- **OLED** keeps the pure-black page and near-black ladder, with the dark
  table's inks.
- **Two deliberate deviations.** `success` and `warning` stay our AA text
  inks; the pin's exact `state-success-*`/`state-warn-*` values are the new
  getters, so a dot is exact and a sentence stays legible. SnackBar takes the
  toast pair — light `bgLayer2` is white and M3's snackbar ink is white.
- **The rules said what the code now does**: the root conventions line,
  `flutter/app/AGENTS.md` (alias table plus the pin's anatomy) and
  `docs/design-standard.md` (the pin's sheet as the authority) no longer
  mandate stock Material 3.

## Alternatives considered

- **Keep `fromSeed` and retune the seed**: rejected — the five-step ladder,
  the six text tones and the alpha hairlines are not a function of a seed.
- **A `ThemeExtension` token layer**: rejected by `verify_theme_native` (a
  token layer is a recorded rejected alternative), so the table rides
  `ColorScheme` as `scheme.aliases` instead of a second lookup mechanism.
- **Repoint all 1,097 reads in one pass**: rejected — the role values now
  equal the aliases, so surfaces can migrate to `scheme.aliases` a pass at a
  time with no big-bang rename.

## Consequences

170 theme tests and the 1,660-test app suite pass; `verify_theme_native`
reports CLEAN. Every screen wears the pin's neutral-bluish/ink/blue palette in
both brightnesses without a widget edit. The dark `surfaceContainer` moved to
`#232324`, so the content-to-chrome step is 1.161:1 (OLED 1.155:1); the new
parity test pins all 78 aliases in both brightnesses.

The 24 previously unused aliases are now live. The next passes move reads from
`colorScheme.*` to `scheme.aliases` surface by surface, then the leftover M3
roles leave the scheme.
