# Agent Note: Load older session history paging

Status: implemented

## Problem

When opening longer sessions in the Android Flutter app, the backend returns the latest tail page of events over the `session.history` RPC wire contract. If earlier history exists (`hasMoreOlder`), the adapter and controller expose `uiState.hasMoreOlder`, `uiState.isLoadingOlder`, and `LoadOlderHistoryAction`. However, `ChatScreen` had no UI element or action dispatch wired to trigger loading older messages. Users who scrolled up reached the head of the tail window and hit a boundary where no further messages could be scrolled or loaded.

## Decision

We implement a mobile-first, commercial-grade older session history paging system in `ChatScreen`:

- **Threshold-Based Auto-Paging**: As the user scrolls up, approaching the head within `kAutoLoadOlderThreshold` (160dp) automatically dispatches `LoadOlderHistoryAction()` in the background. A single-flight guard (`_autoLoadDispatched`) prevents duplicate dispatches during fast scroll flings, and auto-load is disabled during initial session landings and reading-position restores.
- **Precision Viewport Anchoring**: Prepending earlier history to a top-down list normally causes the viewport to jump to the newly inserted items. Before older history is requested, the controller captures `_anchorDistanceFromBottom = maxScrollExtent - pixels`. Upon arrival of prepended items, a post-frame callback restores `newMax - _anchorDistanceFromBottom`, perfectly pinning the message currently in view with zero visual jumping while the newly loaded history expands above.
- **Mobile-Native Paging Indicator**:
  - When loading: `OlderHistoryRow` renders a centered Material 3 loading spinner (`CircularProgressIndicator`) with localized copy (`chatLoadingOlder`: "Loading earlier…" / "正在加载更早记录…").
  - When idle: provides a lightweight, unobtrusive `TextButton.icon` (`chat-load-older-button`) with `Icons.history_rounded` and `chatLoadOlder` for manual tapping or network retry.
- **Conversation Origin Boundary Badge**: When all history has been loaded (`hasMoreOlder == false` and `isLoadingOlder == false`), `_conversationStartSlot` renders a subtle `ConversationStartRow` featuring `Icons.flag_outlined` and localized badge copy (`chatBeginningOfHistory`: "Beginning of conversation" / "已到达会话起点"), giving users clear spatial closure.
- **Bilingual Localization**: Added `chatLoadOlder`, `chatLoadingOlder`, `chatBeginningOfHistory`, and `chatLoadOlderRetry` keys across English and Chinese ARB bundles.

## Alternatives considered

- **Desktop-only static button**: Forcing mobile users to stop scrolling and tap an outlined button to load each page breaks touch reading flow. Commercial mobile chat apps (WeChat, Telegram, Slack, ChatGPT) use seamless scroll-triggered paging. We support automatic scroll-triggered loading while retaining the button as an unobtrusive manual/retry fallback.
- **Unguarded offset-0 triggers**: Naively triggering on `pixels <= 0` fires immediately on session open because Flutter's viewport initializes at 0 before the post-frame bottom jump completes. Adding `kAutoLoadOlderThreshold` guarded by `_restoreDecided`, `!_needsInitialJump`, and `_autoLoadDispatched` avoids spurious cold-start loads and runaway cascades.
- **Unanchored prepends**: Leaving scroll offset at 0 after older messages arrive shifts the user's viewport to the earliest message of the new page, disorienting the reader. Invariant bottom-distance compensation (`maxScrollExtent - pixels`) ensures zero-jump reading stability.

## Consequences

- Users scrolling to the top of any session with unretrieved earlier events see a clear Material 3 "Load earlier" button and can incrementally page through their complete conversation history.
- `LoadOlderHistoryAction` is covered end-to-end through `ChatScreen` widget tests verifying idle display, action dispatch, loading progress states, and removal on boundary settlement.
