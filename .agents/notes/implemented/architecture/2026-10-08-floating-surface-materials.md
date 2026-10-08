# Agent Note: Floating surfaces take the pin's material their pin home names

Status: implemented

## Problem

The 0.2.0 design-language port moved the transcript rows onto the pin's aliases
([the design-language note](2026-10-08-dsh-0-2-0-design-language.md)), but the
floating family still drew Material chrome: a `surfaceContainer` /
`surfaceContainerHigh` fill, a 1px `outlineVariant` border and
`kM3ShadowElevation3`. The pin has no such single recipe. It draws a **modal**
card on the opaque secondary layer and a **menu** on a translucent fill that
assumes a blurred page behind it, so a surface that takes the wrong one reads at
the wrong weight in both brightnesses, and a 1px border doubles the half-pixel
ring the elevation already draws.

## Decision

**A floating surface takes the material its pin home names.**

- A **modal** is `border-radius: var(--dsw-radius-panel)`,
  `background: var(--dsw-alias-bg-layer-2)`, `border: 0` and
  `box-shadow: var(--dsw-elevation-prominent)`
  (`reference/deepseek-harness/packages/client/ui-primitives/Modal.module.css`
  `.dialog`, :33-46). The ring is the elevation's own half-pixel stroke, so no
  border and no `kM3ShadowElevation*` stands beside it. In Dart:
  `scheme.bgLayer2`, `kRadiusPanel`, `DshElevation.prominent(scheme)`.
- A **menu** is `--dsw-specific-menu` over `--dsw-menu-backdrop-filter`, the
  `--dsw-alias-border-l1` stroke rebound into `--dsw-elevation-stroke-color`,
  `--dsw-elevation-prominent` and the `--dsw-radius-lg` corner
  (`ui-primitives/Menu.module.css` `.list`, :15-31, and
  `ui-primitives/MenuSurface.module.css`, :3-5). `showMenuSheet`
  (`flutter/app/lib/ui/shared/menu_sheet.dart`) draws that material; a caller
  contributes content only.

The family lands like this:

- **Job list** (`flutter/app/lib/ui/chat/job_list_action.dart`) — a menu
  (`ui-jobs/src/client/JobListAction.module.css` `.menu`, :41-65, whose
  `max-height: min(480px, …)` is `kJobsSheetMaxHeight`). It opens through
  `showMenuSheet`; the sheet previously drew no card at all and rode the
  framework's fill and elevation.
- **Workspace action sheet** (`_WorkspaceActionSheet` in
  `flutter/app/lib/ui/workspace/workspace_screen.dart`) — a menu
  (`ui-primitives/Menu.module.css` `.list`); the ⋮ verbs open through
  `showMenuSheet` and its hand-drawn card is gone.
- **Directory browser** (`DirectoryBrowserDialog`) — a modal; the pin's browser
  widens Modal's own card (`ui-directory-picker-browse/src/client/DirectoryBrowser.module.css`
  `.dialog.dialog`, :1-14). The bottom-docked phone form takes the modal chrome
  on all four corners, with its 8px bottom seam.
- **Workspace dialogs** (`_DsModalCard`: rename workspace, rename session,
  delete, new folder) — the same modal chrome.
- **Preview sheet notice** (`flutter/app/lib/ui/chat/file_preview_sheet.dart`)
  — an in-preview panel: `bgLayer2`, `kRadiusLg` and `prominent`, no border
  (`ui-sidebar-documentpreview/src/client/office/FontNotice.module.css`
  `.panel`, :14-31; the pdf page surface takes the same shadow,
  `.../pdf/PdfBody.module.css` `.surface`, :43-48). `kRadiusLg` is the pin's
  own panel step and is deliberate at the banner's height.

**A surface that draws its own material opens on a transparent sheet with
`elevation: 0`.** `showModalBottomSheet`'s transparent background alone still
leaves Material's sheet elevation under the card, which stacks a second shadow
below the ring.

**A doc comment states what the code does.** `_DsModalCard`'s comment claimed a
`bgLayer2` fill and an inverted hairline while the code painted
`surfaceContainerHigh`, a 1px `outlineVariant` border and `kM3ShadowElevation3`.
The code moved to the modal chrome and the comment now states it.

## Alternatives considered

Draw one hand-made modal card per sheet: rejected — three copies of the same
material drift apart, and `showMenuSheet` already draws the menu one. Give the
workspace action sheet the modal chrome because its phone form is a bottom
sheet: rejected — the sheet form is ours, the pin's own taxonomy (Menu, not
Dialog) owns the material. Paint a `bgLayer2` card on the job list despite its
`--dsw-specific-menu` pin home: rejected — that fill is translucent by design
and assumes the backdrop filter, so an opaque card is a different surface. Keep
`kShapeChip` on the paged-window notice: rejected — the pin's document-preview
panels take `--dsw-radius-lg`, and the near-stadium reading at 34px is the
pin's proportion rather than a defect. Keep an existing M3 shadow and add the
ring on top: rejected — two elevation systems read as one heavy edge.

## Consequences

Every menu in this family opens through one opener, so a menu from the
workspace tree and one from the chat header draw the same card, and the dialogs
and the directory browser share one modal chrome. Every value stays a named
token, so `verify_theme_native.py` holds it in `theme.dart`. Three remainders
are named rather than hidden: the composer's attach sheet (`_CommandSheet` in
`flutter/app/lib/ui/chat/chat_screen.dart`, outside this pass's files) still
draws the framework's sheet; `showMenuSheet` does not yet pass `elevation: 0`
(`flutter/app/lib/ui/shared/menu_sheet.dart`); and the job list, the workspace
action sheet and the directory browser have no design shot yet — the notice has
one (`preview-truncated`), the rest are reviewed from the widget tests.
