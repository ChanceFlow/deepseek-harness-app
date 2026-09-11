# Agent Note: Tool Inline Diff, Smart Failure Disclosure and Mobile Supervision UX

Status: implemented

## Problem

Reviewing autonomous coding agent operations on a mobile viewport suffered
from three critical supervisory friction points:
1. File edits via `edit` and `str_replace_editor` rendered raw escaped JSON
   with embedded newlines in a 280dp box instead of a visual diff. The file
   preview sheet showed only on-disk full text with no change highlighting.
2. When activity groups had failed tool calls, the parent card and child rows
   remained folded, requiring up to four drill-down taps to view stderr.
3. On compact 360dp screens, the top app bar packed five action seats beside
   the drawer trigger, crushing the session title into unreadable ellipses.
4. Voice recording lacked live transcription inside the bubble and offered no
   cancel action in tap-to-record mode.

## Decision

1. Extract unified line diffs in `tool_row_model.dart` for edit tools:
   `EditDiffModel` parses `old_string` and `new_string` into deletion and
   insertion lines. `ToolCallRow` renders `_diffSection` with red-tinted
   deletions (`-`) and green/primary-tinted insertions (`+`).
2. `FilePreviewSheet` adds a `SegmentedButton` toggle between `Diff` and
   `Full file` when opened with an initial diff, defaulting to `Diff`.
3. Auto-disclose failures: `_ActivityGroupRowState` and `_ToolCallRowState`
   automatically expand on failure, bringing the error summary and stderr
   directly into view without manual navigation.
4. Top app bar actions on compact viewports fold `Trajectory` and `Export` into
   the `PopupMenuButton` overflow menu, and render `JobListAction` only when
   background jobs are active, freeing over 120dp for the session title.
5. `_VoiceRecordBubble` renders live transcription directly above the waveform,
   adds Cancel and Send buttons for tap-to-record, unfocuses the keyboard on
   start, and triggers haptic clicks on slide-to-cancel threshold crossing.

## Alternatives considered

- **Full external diffing package**: Rejected; adds non-trivial runtime
  dependencies and native overhead. Hand-crafted line diffing over `old_string`
  and `new_string` suffices for agent tool replacements.
- **Side-by-side split diff**: Rejected on phone screens; a 360dp viewport
  cannot accommodate two readable code columns. Unified inline diff is the only
  format that respects the mobile space budget.
- **Permanent app bar icons on phone**: Rejected; crowding five icons left
  fewer than 80dp for session titles and parent branch context.

## Consequences

- `ToolRowModel` carries `diff` (`EditDiffModel?`).
- `FilePreviewSheet` accepts `initialDiff` and provides interactive tab switching.
- Compact phone headers retain full title readability while keeping trajectory
  and export accessible from the session menu.
- Voice input provides real-time visual feedback and safe hands-free controls.
