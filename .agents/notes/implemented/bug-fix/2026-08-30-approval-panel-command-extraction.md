# Agent Note: Approval panel shell command extraction and display

Status: implemented

## Problem

When a model requests privileged execution (such as `bash` or `pwsh`), the approval takeover panel (`ApprovalPanel`) previously rendered only the model justification headline (`request.reason ?? approveToolFallback(toolName)`) alongside a generic warning line (`toolRequestsPrivileged(toolName)`). If the agent provided no justification or an empty justification, the user saw no information about what command was about to run before clicking "Allow once" or "Reject" (Gitea issue #61).

The reference web implementation (`ApprovalPanel.tsx:23-32` and `ApprovalPanel.module.css:78-84`) extracts the concrete command line from the paired running tool call via `commandOf()` and renders it in monospaced code text within the scrollable takeover card body. Non-shell tools without a `command` argument field omit the command line with no empty box.

## Decision

Aligned `ApprovalPanel` and its composer dock call site in `ChatScreen` with the reference web implementation:

1. **`commandOf()` helper** (`approval_panel.dart`): Pure function port of reference `commandOf(call: RunningToolCall | undefined)`. Safely parses the tool call's JSON arguments string and extracts the `command` field when it is a non-empty string. Returns `null` if the call is null, arguments are unparseable/empty, or no `command` property exists (such as for file or edit tools).
2. **Call site correlation** (`chat_screen.dart`): The wire `approval/requested` event schema (`events.schema.ts:46`) carries `approvalId`, `toolName`, `callId`, and optional `reason`, but not the tool arguments. In accordance with reference data flow (`ApprovalPanel.tsx:43-48`), `ChatScreen` correlates the pending approval's `callId` against the active timeline slice to locate the matching `TimelineToolCall`, deriving `command` via `commandOf()` and passing it into `ApprovalPanel(command: ...)`.
3. **Monospaced presentation & capped scroll body** (`approval_panel.dart`): When `command` is present, renders a `SelectableText` styled with `fontFamily: 'monospace'` and `theme.colorScheme.onSurfaceVariant` under the justification and privilege warning. The panel body is bounded by `ConstrainedBox(maxHeight: 180)` and wrapped in `SingleChildScrollView`, matching the reference web `[data-approval-scroll]` constraint so long shell scripts scroll internally without displacing the Reject / Allow once action buttons off-screen. When `command` is null or empty, no extra space or empty container is rendered.

## Alternatives considered

- **Folding arguments into `TimelineApprovalRequest` at the wire adapter**: Rejected — examination of the authoritative wire schema (`packages/host/apiproxy/src/api/events.ts:72` and `events.schema.ts:46`) confirmed that `approval/requested` frames do not carry tool input or args. Arguments reside on `tool/call` session events. Scanning the current timeline slice by `approval.callId` preserves wire fidelity without inventing non-existent protocol fields.
- **Rendering fallback placeholder text when command is absent**: Rejected — reference `ApprovalPanel.tsx` uses `{command !== undefined && <div className={css.command}>{command}</div>}`. For non-shell tools like `edit` or `write`, rendering nothing under the headline matches upstream design.
- **Unbounded card height**: Rejected — a 40-line shell command in a fixed-height layout would push the action buttons below the viewport, preventing the user from answering. The scrollable capped body ensures the action buttons remain reachable.

## Consequences

Pending tool approvals for shell executions display the full command line in selectable monospaced text. Non-shell approvals remain visually clean without placeholder boxes. Keyboard and touch interactions on the action buttons remain accessible regardless of command length.
