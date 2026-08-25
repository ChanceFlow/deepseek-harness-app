# Agent Note: Redesigned dropdown select components to Material 3 bottom sheets

Status: implemented

## Problem

Dropdown selectors across the client (such as the Hero workspace chip on the home screen, the new-session workspace dialog, the prompt delivery mode picker in the composer, and the active speech model selector in ASR settings) used raw Flutter `PopupMenuButton`, `DropdownButtonFormField`, or dialogs with stacked `OutlinedButton`s. These native components rendered unformatted, sharp-cornered overlays (such as `proj — /tmp/proj`) and inconsistent styling compared to the modern menu-surface bottom sheet pattern used by `ModelSelect`, `AgentPresetSeat`, and `PermissionSelectChip`.

## Decision

Replaced raw dropdown menus and button-stacked dialogs with dedicated Material 3 modal bottom sheets and styled selection cards:
- **`WorkspaceChip` (`empty_hero.dart`)**: Replaced `PopupMenuButton<String>` with a tap-to-open modal bottom sheet (`_WorkspaceSheet`) featuring folder icons in high-surface containers, bold workspace titles, compact secondary path subtitles, session count pills, active checkmark indicators, and empty-state handling.
- **`_NewSessionDialog` (`session_panel.dart`)**: Upgraded to a card-based M3 selection dialog with a dedicated "Default" session card (Home icon and badge) and scrollable workspace cards.
- **`_PromptModeButton` / `PopupMenuEntryShim` (`chat_screen.dart`)**: Replaced raw `PopupMenuButton<PromptMode>` with a capsule trigger with mode glyphs (`Icons.schedule_send_outlined` / `Icons.bolt_outlined`) opening a menu-surface sheet with active checkmarks.
- **`_ActiveModelSelector` (`asr_models_screen.dart`)**: Replaced `DropdownButtonFormField` with an active model card showing speech recognition glyph, model name, languages subtitle, and a bottom sheet for downloaded models.

## Alternatives considered

- *Retain `PopupMenuButton` with custom `PopupMenuItem` layouts*: Native popup menus still float at arbitrary anchor positions, lack the spacious touch targets, elevation, and backdrop dimming appropriate for mobile touch interaction, and feel disconnected from the rest of the bottom-sheet design system.
- *Full-page picker routes*: Excessive navigation overhead for quick 1-tap workspace or mode switches.

## Consequences

- All dropdown and selection interactions across the app follow the uniform `surfaceContainer` + `kM3ShadowElevation3` + 12px/14px radius bottom sheet design system.
- Tests in `empty_hero_test.dart`, `preset_seat_test.dart`, and `chat_screen_test.dart` assert the structured title/path widgets rather than compound strings.
- Design shots (`workspace-sheet`) visually track the new workspace selection surface.
