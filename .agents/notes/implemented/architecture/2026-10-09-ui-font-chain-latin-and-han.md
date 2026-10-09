# Agent Note: One UI family chain carries Latin and Han

Status: implemented

## Problem

The app named a family for code text only
([`kCodeFontFamily`](../../../../flutter/app/lib/ui/theme/theme.dart)); every
other text style left `fontFamily` null, so Latin and Han were both resolved by
the platform's own chain and nothing recorded which pair that was. On Android
that pair is Roboto plus whichever Han face the device's font configuration
picks.

The design harness was no better evidence. `_loadFonts`
([`design_shots_test.dart`](../../../../flutter/app/test/design/design_shots_test.dart))
registered the host's Han face under a family named `NotoSansCJK` — a name no
device resolves and no theme names — and `_withRealFonts` repointed the text
themes at `Roboto` + `['NotoSansCJK']`. Every shot painted a third chain, chosen
by whichever face the host happened to have (`NotoSansSC.ttf`,
`NotoSansCJK-Regular.ttc`, or `wqy-microhei.ttc`), so a divergence between the
theme and the evidence could not fail a test; it could only look wrong in a PNG.

## Decision

**The theme declares one family chain for both scripts, and the harness
registers the faces under those names.**

- `kUiFontFamily` is `'Roboto'`; `kUiFontFamilyFallback` is the platform's Han
  families (`Noto Sans CJK SC`, `Noto Sans SC`, `Source Han Sans SC`) and then
  `sans-serif`. That is the shape of the pin's `--dsw-font-family`
  (`reference/deepseek-harness/packages/client/ui-theme/src/styles/base.css:7-8`):
  Latin faces first, Han faces inside one list, per-glyph resolution left to the
  engine. The pin names no face that Android ships, so the Latin entry is the
  one Android ships and the Han entries are the family the pin itself pairs with
  a platform sans on every platform it names.
- `_typography` applies the chain before any per-style tweak, and
  `primaryTextTheme` wears it too, so no role can drift onto a second voice.
- The harness registers the host's Han face under every declared Han name, by
  the "first hit wins" rule the code face already uses, and repoints nothing:
  a shot resolves the chain the phone asks for.
- [`font_pairing_test.dart`](../../../../flutter/app/test/ui/theme/font_pairing_test.dart)
  asserts the chain on every published style in all three appearances and, for a
  paragraph carrying a Latin run and a Han run, the family and fallback list
  each run resolves through. The harness carries its own guard: it fails unless
  the families it registered are the ones the theme declares.

The pair is metric-led, read from the faces with `OS/2`: cap height 0.711 em and
x-height 0.528 em for Roboto Regular against 0.733 em and 0.543 em for the Han
face — within 3% on both axes — both at weight class 400, and their regular
stems agree within a pixel at 96px. The Han face in the cache is a variable font
whose default instance is weight 100, but the engine maps the requested
`FontWeight` onto the `wght` axis (measured ink at 96px: 3331 / 6475 / 7803 /
10957 for w100 / w400 / w500 / w900), so the shots paint regular Han.

## Alternatives considered

- **Bundle Noto Sans SC (OFL-1.1) so one family covers both scripts.** The only
  device-independent way to make the two scripts one design, and the licence
  permits redistribution. It adds 17.7 MB (the variable build of the face; a
  static regular is ~10 MB) to every APK, and it replaces Roboto with the Han
  family's Source Sans-derived Latin everywhere. Left to the owner: the app
  ships the platform pair until a decision says otherwise.
- **Prefer the platform's Han family as the primary family.** Free, and gives
  one family for both scripts wherever the device ships it — but it changes
  every Latin glyph, and its determinism stops at the device whose Han face is
  the Noto one. Not taken: it is a look decision, not a defect fix.
- **Name a Han face that no platform ships.** A request the platform must refuse
  on most devices, which puts resolution back to the default chain this note is
  fixing.
- **Leave the family unset and fix the harness alone.** Pixels on Android are
  unchanged either way — the declaration states the pair the platform was
  already resolving, and the harness now resolves the same one; the defect it
  removes is the unnamed contract, which is what let a reviewer argue about a
  screenshot instead of reading a test. The measured before/after `prose` shots
  are pixel-identical.

## Consequences

A device whose Han default is not the Noto family now asks for it by name before
falling back, so mixed-script text no longer inherits an arbitrary Han design;
a device that ships none of the named families resolves exactly as before. The
chain is one list: changing the family for one script and not the other fails
`font_pairing_test.dart`, and a harness that stops registering the declared names
fails its own guard. Bundling a face remains open, and needs the APK-size and
licence decision named above.
