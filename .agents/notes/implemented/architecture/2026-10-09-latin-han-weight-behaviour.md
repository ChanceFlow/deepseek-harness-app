# Agent Note: The Latin/Han pair, measured across the shipped weights

Status: implemented

## Problem

The owner's follow-up on the font — the scripts read wrong when the text is *not*
bold — makes the question weight-dependent, and
[the font-chain note](2026-10-09-ui-font-chain-latin-and-han.md) settled the
family question at one weight: cap height, x-height and regular stems. It never
compared the two scripts across the weights the UI paints, so "the pair is
compatible" was a regular-weight fact being read as a general one.

## Decision

**No weight change is justified; the measured behaviour is recorded and pinned.**

Measured (96px em, engine Roboto against the platform Han face; `stroke` = the
mode of the run lengths through a vertical stroke, `bar` = the same through a
horizontal one):

| weight | Latin `H` stem/bar | Han `十` stem/bar | stem H/L | bar H/L |
|---|---|---|---|---|
| 300 | 6 / 5 | 5 / 5 | 0.83 | 1.00 |
| 400 | 9 / 8 | 8 / 7 | 0.89 | 0.88 |
| 500 | 12 / 10 | 10 / 10 | 0.83 | 1.00 |
| 600 | 14 / 12 | 11 / 11 | **0.79** | 0.92 |
| 700 | 14 / 12 | 13 / 12 | 0.93 | 1.00 |
| 900 | 16 / 13 | 16 / 14 | 1.00 | 1.08 |

- **The steps are the reference's own.** Body and secondary are 400
  (`gradient-shadow-text.css:91`, :232), titles and labels 500 (:190, :211,
  :225), markdown strong 600 (:98), headings 700 (:63) — the same four weights
  the app paints, so "our step is too light" is not the finding.
- **Regular is not the worst case.** 600 is (0.79): Roboto ships no 600, so the
  engine substitutes Bold — measured, w600 and w700 render identically (stem 14,
  bar 12, ink 2324) — while the Han face's `wght` axis renders a true 600. The
  reference's stack behaves the same way on the same face (CSS font matching
  takes the ≥600 instance), so this is the face, not the token.
- **The two scripts differ in opposite directions at every step.** Han strokes
  are 7–21% thinner, but Han carries 1.05–1.44× the ink per em of line at the
  shipped sizes (13/14/22px) and its ideographic body is 1.22–1.26× the Latin
  cap. At 13–14px the stroke rasterizes to the same 2px in both scripts, so what
  a reader sees at the body step is the Han's density, not a thin stroke.
  A heavier Han weight closes the stroke gap and **widens** the density gap, so
  no weight can match both.
- The platform Han face is the pair Android itself makes for Roboto, and the
  reference's Han faces (PingFang SC, Microsoft YaHei) are heavier designs still,
  so its mixed text shares the property. Closing the difference is a face or
  optical-size decision — bundling a Han face (17.7 MB, needs sign-off) or
  adjusting the Han's optical size — not a step change.

`font_pairing_test.dart` now pins what a step change would move: at each shipped
step the resolved family, the Han fallback list and the weight of a Latin run and
of a Han run in one paragraph, plus the set of shipped weights (exactly the
reference's four). `shots/font-weights_*.png` renders the same mixed sentence at
400/500/600/700, light and dark.

## Alternatives considered

- **Raise the Han weight for the regular step.** The measurement supports the
  size of the nudge — Han at 500 matches Roboto 400's stroke — but the
  platform's Han face is a static 400/700 build on the devices we ship to, so the
  step cannot be honoured there, and the nudge trades a thinner stroke for more
  ink in sentences that are already 20% blacker. Not taken.
- **Another Han family for the regular step.** The chain's three declared names
  are one design (Noto Sans CJK / Noto Sans / Source Han Sans); the only heavier
  faces are device-vendor ones, which would make the pairing depend on the phone.
  Not taken.
- **Move the 600 step to 500 so Roboto stops substituting Bold.** It would
  lighten the reference's own strong step, and the reference renders 600 with the
  same face the same way. Not taken.
- **Report "no defect" and change nothing.** Taken — with the guard and the
  picture, so the next reader has numbers rather than an impression.

## Consequences

The theme does not change; the ladder stays the reference's. A step whose weight
drifts, or a run carrying its own, fails `font_pairing_test.dart`. The
difference the owner sees is real and now quantified per weight — a CJK face's
density beside a Latin one — and its levers (a bundled face, an optical size) are
the owner's decision, not a theme edit.
