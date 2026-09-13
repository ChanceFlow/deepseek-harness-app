# Agent Note: Single-row composer and command draft preservation parity

Status: implemented

## Problem

1. **Two-row composer bloat**: `ComposerBar` previously laid out its controls in a vertical `Column`: the `TextField` on row 1, and an M3 `Wrap` toolbar holding tools and seats on row 2. Even when idle and empty, the dock consumed over 100dp vertically (nearly 14% of a 360×740dp phone screen), violating the repository design principles ("Space is the budget", "A row is as tall as its line", and "Disclosure defaults closed" in `docs/design-standard.md`).
2. **Draft-wiping bug on command pick**: When a user already had draft text in the composer and picked an input-hinted host command like `/plan` (or a skill) from the `+` menu or slash candidates, `onPickCommand` unconditionally assigned `_draftController.text = '/$name ';`, completely destroying the user's draft instead of non-destructively preserving and prepending the command token.
3. **Slash autocomplete parity gap**: `SlashSkillCandidates` previously only queried `skills`, completely omitting all host slash commands (`/plan`, `/goal`, `/compact`, `/permission`, `/feedback`) when typing `/`.

## Decision

1. **Single-row composer layout**: Restructure `ComposerBar` into a clean horizontal `Row`:
   - Left cluster: `_PlusButton`, the voice mode seat, `ModelSelect` (when available), and flexible `PermissionSelectChip`. The mode seat was `VoiceMicButton` here until [the hold-to-talk pass](2026-09-13-hold-to-talk-composer.md) moved the microphone onto the band above the row.
   - Center: `Expanded(TextField)` with borderless input, 1 to 4 lines dynamic expansion.
   - Right cluster: `ContextRing` and primary action (`_PrimarySendButton` for Send/Stop).
   - Ephemeral states (`PlanChip` when plan mode is active, pending image thumbnails, and `SlashSkillCandidates` autocomplete) move to dynamic accessory trays above the single row that take zero height when idle.
   - **Superseded**: the one-row layout cannot hold the draft field beside a
     live session's seats — the field collapsed to zero width on a phone. The
     dock is two bands again; see
     [the two-band dock note](../bug-fix/2026-09-10-composer-two-band-dock.md).
2. **Non-destructive command claim (`_applyCommandToDraft`)**: Picking an input-hinted command (`/plan`, `/goal`, `/permission`, `/feedback`) or skill replaces only the leading slash token if present, preserving any existing draft text after a space (`'/$name $remainder'` or `'/$name $trimmed'`). Bare commands (e.g. `/compact`) dispatch immediately via detached `SendPrompt('/$name')` without touching the user's draft, matching Reference Web (`InputMachine.onBeginCommand`).
3. **Comprehensive slash candidate search**: `SlashSkillCandidates` now merges both `hostCommands(l10n)` and `widget.skills`, ranking and rendering matching host commands (with terminal icon, hint, and description) alongside skills.
4. **Flexible permission chip layout**: Wrap `PermissionSelectChip`'s internal label text in `Flexible` and constrain maximum width so that on narrow split-pane widths (e.g. 442dp), the single-row flex never overflows.

## Alternatives considered

- *Hide all tools inside the Plus sheet and leave only `[+] [TextField] [Send]`*: Rejected because existing widget tests assert direct seat presence for `ModelSelect` and `PermissionSelectChip`, and power users benefit from direct access to the model and permission seats in the single line.
- *Keep a 2-row layout but reduce padding*: Rejected because the user specifically requested a true single-row design to eliminate the bulky, bloated appearance.
- *Wipe draft on command pick if user confirms*: Rejected because Reference Web never prompts or wipes draft text on command pick; it non-destructively adopts `claim.token + draft.slice(span.end)`.

## Consequences

- The composer dock is a single 48~52dp row in its idle state while the host publishes no access chip; with one mounted the layout is superseded by [the two-band dock](../bug-fix/2026-09-10-composer-two-band-dock.md), which is 102dp idle on a 360dp phone.
- Users can compose messages and prepend `/plan` or `/goal` at any time without losing typed text.
- Typing `/` in the composer reveals both host commands and skills.
- All existing and new widget tests pass without regressions.
