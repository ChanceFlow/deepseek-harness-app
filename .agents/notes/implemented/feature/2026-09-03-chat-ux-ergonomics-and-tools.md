# Agent Note: Chat UX ergonomics, adaptive bubbles, and session tool discovery

Status: implemented

## Problem

Several mobile ergonomics, rendering, and discoverability gaps accumulated across the chat experience:

1. **Persistent keyboard**: Timeline scrolling and taps on empty history failed to dismiss the soft keyboard.
2. **Rigid user bubbles**: `_UserBubble` and `PendingSteeringRow` forced an 82% width via `FractionallySizedBox`, bloating short messages.
3. **Table column crushing**: Pipe tables divided columns evenly without horizontal scrolling, breaking text on narrow screens.
4. **Unbounded tool output**: `ToolCallRow` expanded payloads lacked height caps, letting large logs stretch the view.
5. **Orphaned session tools**: `ModelsRoute` had no navigation entry, and `GoalRoute` was only reachable during an active goal.
6. **Minute ContextRing target**: A 14×14dp touch footprint next to Send/Stop invited accidental cancellations.
7. **Unconstrained Todo checklist**: `TodoPanel` expanded all items without a vertical bound, pushing conversation content off-screen.
8. **Truncated stats**: `StatsLine` dropped trailing metrics on compact viewports without an inspection path.
9. **Execution clutter**: Loose tool calls and reasoning expanded into dozens of rows instead of a clean, Cursor-style summary.

## Decision

- **Keyboard dismissal**: Added `keyboardDismissBehavior: onDrag` to the transcript `ListView` and outline `CustomScrollView`. Wrapped `_timelineBody` in a translucent `GestureDetector` that unfocuses primary focus on tap.
- **Adaptive bubble width**: Replaced `FractionallySizedBox` with `LayoutBuilder` capping `maxWidth` at `min(constraints.maxWidth * 0.82, 525)`.
- **Table horizontal scroll**: Wrapped `_tableBlock` in a `SingleChildScrollView(scrollDirection: Axis.horizontal)` with a minimum 84dp column width.
- **Tool output protection & copy**: Constrained expanded tool payloads to `maxHeight: 280` inside `SingleChildScrollView` with a quick-copy icon button.
- **Session tool discovery**: Added `Models` and `Goal` destinations to `ChatHeaderActions` alongside `Subagents` in the overflow menu and tablet strip.
- **ContextRing touch target**: Expanded `ContextRing` interactive bounds to 36×36dp with an 18dp radial ripple while keeping the 14×14dp visual indicator centered.
- **Todo checklist ceiling**: Bounded expanded `TodoPanel` items to `maxHeight: 200` with internal scrolling.
- **Interactive session stats**: Bound `StatsLine` to an `InkWell` opening `showMenuSheet` detailing turns, steps, durations, TTFT, throughput, tokens, and cache hits.
- **Cursor-style tool collapsing**: Consecutive completed tool calls group into `TimelineToolGroup` and `ToolGroupRow` as a summary card (`N tool calls · bash 2, edit 1`), collapsed by default and expandable on demand. In-flight tools remain live.
- **Reasoning duration tracking**: `ReasoningRow` tracks elapsed time, displaying live seconds while streaming and a "Thought for Xs" caption when done.

## Alternatives considered

- **Card collapse for tables**: Rejected because pipe tables represent arbitrary structured data; horizontal scrolling preserves document fidelity.
- **Floating copy button**: Rejected because it obscures monospace text; placing it next to the gutter label provides a clean tap target.
- **Bottom tab for Models**: Rejected to preserve the three-destination root layout (`Chat`, `Workspaces`, `Settings`); session tools belong in the conversation header.
- **Increasing visual ring size**: Rejected because a 40dp ring overpowers the toolbar; expanding the touch box preserves aesthetic balance.
- **Hiding entire turn in outline**: Rejected for normal chat flow because hiding replies prevents reading answers; collapsing only intermediate steps keeps conversations readable.

## Consequences

- Conversation history can be reviewed without keyboard obstruction.
- User bubbles hug their text naturally.
- Wide markdown tables scroll horizontally without broken column text.
- Tool logs stay bounded and copyable in one tap.
- `ModelsRoute` and `GoalRoute` are directly accessible from any active session.
- Context inspection no longer risks accidental turn cancellation.
- Lengthy plan checklists no longer dislodge the chat view.
- Readers on compact screens can inspect complete session consumption stats.
- Multi-step tool runs collapse into a clean Cursor-style summary by default.
- Model reasoning displays execution duration.
