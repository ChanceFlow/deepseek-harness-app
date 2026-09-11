# Agent Note: Load older session history paging

Status: implemented

## Problem

When opening longer sessions in the Android Flutter app, the backend returns the latest tail page of events over the `session.history` RPC wire contract. If earlier history exists (`hasMoreOlder`), the adapter and controller expose `uiState.hasMoreOlder`, `uiState.isLoadingOlder`, and `LoadOlderHistoryAction`. However, `ChatScreen` had no UI element or action dispatch wired to trigger loading older messages. Users who scrolled up reached the head of the tail window and hit a boundary where no further messages could be scrolled or loaded.

## Decision

We align `ChatScreen` with the reference Web client (`ChatView.tsx`) by providing explicit on-demand paging for older session history:

- **Dedicated Sentinel Row**: `_OlderHistorySlot` defines a distinct sentinel object (`_olderHistorySlot`) rendered at the top of the timeline items list when `uiState.hasMoreOlder || uiState.isLoadingOlder` is true. `_opensBlock` recognizes this sentinel so standard block spacing (16dp) is preserved above the first conversation message.
- **`OlderHistoryRow` Component**: A centered Material 3 `OutlinedButton` (`chat-load-older-button`) with `kShapeCard` (14dp radius) styling and `scheme.outlineVariant` hairline border:
  - When idle: shows `Icons.history_rounded` with localized copy (`chatLoadOlder`: "Load earlier" / "加载更早"). Tapping dispatches `LoadOlderHistoryAction()`.
  - When loading: shows `CircularProgressIndicator` (stroke width 2) with localized progress copy (`chatLoadingOlder`: "Loading earlier…" / "正在加载更早记录…") and disables repeated taps.
  - When all history has been loaded (`hasMoreOlder == false` and `isLoadingOlder == false`), the sentinel slot drops from the list.
- **Bilingual Localization**: Added `chatLoadOlder` and `chatLoadingOlder` keys to `app_en.arb` and `app_zh.arb` with regenerated localization classes.
- **Scroll Stability**: Loading older history retains the reader's unpinned scroll offset so the newly prepended history flows into the viewport naturally without jumping to the tail.

## Alternatives considered

- **Infinite automatic scroll-up trigger (overscroll / reach offset 0)**: Automatically dispatching `LoadOlderHistoryAction` when scroll position hits top or overscrolls was rejected. During session open, the initial viewport mount starts at `pixels = 0` before the initial follow jump runs; auto-triggering on top would cause immediate unwanted fetches on cold opens. Furthermore, in long sessions with heavy tool call output, automatic continuous loading causes runaway network and rendering cascades. The explicit button matches the reference Web client and provides user-governed pagination.
- **Floating banner or snackbar**: Placing a floating pill at the top of the viewport competes with the app bar and overlaps message bubbles. An in-flow list item at index 0 ensures the button only appears when the reader has deliberately scrolled to the top of the transcript.

## Consequences

- Users scrolling to the top of any session with unretrieved earlier events see a clear Material 3 "Load earlier" button and can incrementally page through their complete conversation history.
- `LoadOlderHistoryAction` is covered end-to-end through `ChatScreen` widget tests verifying idle display, action dispatch, loading progress states, and removal on boundary settlement.
