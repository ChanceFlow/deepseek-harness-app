# Agent Note: App 身份 — DSH Mobile 名称与 dsh 品牌图标

Status: implemented

## Problem

The Android client installed as a bare `app` label with the stock Flutter
launcher icon (default blue Flutter glyph at every density, no adaptive
icon). Task-switcher and launcher identity didn't match the product; the
in-app `appTitle` ("DeepSeek Harness") describes the backend product rather
than the mobile client. 用户要求更换应用名与图标，图标取
`reference/deepseek-harness` 里的标志性 dsh 图形。

## Decision

Rename the launcher/task identity to **DSH Mobile** and adopt the dsh
favicon glyph as the launcher icon:

- `AndroidManifest.xml` `android:label` goes `app` → `DSH Mobile`.
- ARB `appTitle` (en + zh) → `DSH Mobile`; `flutter gen-l10n` regenerates
  `app_localizations*.dart` (committed, byte-stable). The in-app AppBar
  (no-session and compact layouts) and the OS task-switcher label both
  resolve `appTitle`, so both follow the rename. `main.dart` comment prose
  updated to the new canonical name.
- The pub package name stays `app` (workspace-internal, drives
  `package:app/*` imports) and `applicationId` stays
  `com.deepseek.harness.app` — neither is user-visible identity.

Icon, generated from `reference/deepseek-harness/website/public/favicon.svg`
(the blue `#4D6BFE` glyph — the website favicon, the canonical icon of the
dsh visual identity):

- **Legacy launcher icons** (`ic_launcher.png` per density): transparent
  canvas, glyph at 80% of canvas, centered; 48/72/96/144/192 px.
- **Adaptive icon** (API 26+): `mipmap-anydpi-v26/ic_launcher.xml` +
  `values/colors.xml` (`ic_launcher_background` = `#FFFFFF`), foreground
  glyph (`ic_launcher_foreground.png`) at 60% of canvas inside the 66/108
  safe zone; 108/162/216/324/432 px. White plate keeps the glyph visible
  under launcher masks.
- Rasterization pipeline (kept out of repo, reproducible): resvg-js renders
  the favicon path at 1024 px; sharp composites glyph → canvas → downscales
  per density. sharp's composite-then-resize chain is bypassed (it validates
  overlay against the *resized* size and errors); composite first, store an
  intermediate buffer, then downscale.

`chat_screen_test.dart` assertion `find.text('DeepSeek Harness')` → `'DSH
Mobile'`, matching the real `appTitle` stream.

## Alternatives considered

- **Replace every "DeepSeek Harness" string in the UI** (brand wordmark in
  `session_panel.dart`, DeepSeek credential card in settings). Rejected:
  the wordmark is the dsh product mark reused in-app and the credential
  card names the DeepSeek provider — neither is the app's identity.
- **Rename the pub package and/or `applicationId`** (`app` → `dsh_mobile`).
  Rejected: `package:app/*` imports and the installed-app identity are
  workspace/install contracts, not display name; changing them is invasive
  and breaks re-installs over the previous build.
- **Flutter default icon only, no adaptive layer.** Rejected: modern
  launchers crop legacy PNGs; the adaptive set is the current Android
  standard and keeps the glyph inside the mask safe zone.
- **Icon on a brand-blue background.** Rejected: the favicon identity is a
  blue glyph on light/transparent; a white plate preserves that look while
  staying mask-safe.

## Consequences

- Launcher label, task switcher, and in-app empty-state title display
  "DSH Mobile" in both locales; the dsh glyph is the launcher icon on all
  API levels.
- The `.agents/notes` and README still name the backend product
  "DeepSeek Harness"; only the client display identity changed.
- Future icon regens need no Node tooling committed to the repo — the
  source SVG stays the single icon truth in `reference/`; the pipeline
  above reproduces the PNGs on demand.
- `values/colors.xml` is now committed alongside `styles.xml`; the adaptive
  XML is the API 26+ entry, legacy PNGs remain for older devices.