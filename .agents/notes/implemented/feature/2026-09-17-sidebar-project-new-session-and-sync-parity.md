# Agent Note: Sidebar project creation, workspace modal docking, and live model/session sync parity

Status: implemented

## Problem

Three user experience and synchronization defects affected session and workspace management across devices:

1. **No session creation per project in sidebar**: The Workspaces tab provides a `+` button on every workspace row (`_WorkspaceRow`), but the compact left sidebar session panel (`SessionPanel`) lacked an affordance to start a session directly under a project without opening the global new session dialog and selecting a workspace.
2. **Obscured directory browser in Workspaces tab**: In the aggregate Workspaces screen (`WorkspaceAggregateScreen`), each section mounted `WorkspaceScreen(embedded: true)`. The directory browser overlay (`DirectoryBrowserOverlay`) was placed in a section-local `Stack`, which sized to the section's contents rather than the full viewport. As a result, the bottom-docked sheet was clipped against section boundaries, obscuring the title, breadcrumbs, and footer controls. Additionally, on 360dp mobile viewports, the footer action row overflowed horizontally.
3. **Session model and state drift from Web client**: In upstream reference (`reference/deepseek-harness/`), session models are tracked via the host's durable `modelSelection` projection (`{ lastUsed, next }`) pushed over `session.control`, while the host model catalog invalidates on remote events (`llm/adapters-updated`, `settings/document-updated`, `credentials/reference-updated`). In the Flutter client, `HarnessRepositoryImpl` dropped `modelSelection` projection frames and ignored host configuration events. Furthermore, `loadModels` always decoded `current` from the host deployment default, causing `ChatController.refreshModels` to clobber active session selections back to the default model. Finally, when returning from background (`AppLifecycleState.resumed`), stale sockets were not verified and sessions were never revalidated against changes made in the Web frontend.

## Decision

**Sidebar project long-press.** Group headers in `SessionPanel` (`_GroupSection`) are wrapped in a `GestureDetector(onLongPress: ...)` when backed by a registered workspace. Long-pressing a project header dispatches `CreateSessionInWorkspace(workspaceId)` directly on the owning backend's controller, switching the active backend first if the group belongs to a standby host. Ungrouped sessions keep no long-press action (matching the reference rule where ungrouped buckets carry no workspace management verbs).

**Page-level directory browser docking.** `DirectoryBrowserOverlay` is hoisted from the section-local `WorkspaceScreen` to `WorkspaceAggregateScreen` at the page level. In embedded mode, `WorkspaceScreen` renders only its browsing region; the top-level aggregate Scaffold renders the modal pair (full-screen scrim and bottom-docked card) over a screen-sized `Stack`. `DirectoryBrowserDialog._buildFooter` uses `Wrap` instead of a rigid `Row` so that the "New folder" action and the "Show hidden files" toggle neatly wrap on narrow devices without overflowing. `_DsModalCard` wraps its content in `SingleChildScrollView` to prevent keyboard obstruction on compact screens.

**Reference-parity model selection and catalog sync.**
- `HarnessRepositoryImpl` decodes the durable `modelSelection` projection (`next ?? lastUsed`) in both `_handleProjection` (`session.control`) and `_applySessionProjectionValues` (`session.list` / `session.follow`).
- `HarnessRepositoryImpl` exposes `observeSessionModels(sessionId)` which combines the host model catalog with the session's active `modelSelection`. `loadModels` resolves against the session's current selection, eliminating the bug where opening the model picker clobbered the session model with the host default.
- Remote events `llm/adapters-updated`, `settings/document-updated`, and `credentials/reference-updated` on `$events` invalidate the cached model catalog and notify live session model observers.
- `ChatController` and `ModelsController` subscribe to `observeSessionModels(sessionId)` to reflect external model updates in real time.

**Foreground lifecycle revalidation.** `appResumeSyncProvider` is introduced in `flutter/app/lib/di/providers.dart` and watched by `AppRoot`. When the application returns from the background (`AppLifecycleState.resumed`), it checks connection states across all enabled backends: if disconnected or reconnecting, it immediately triggers `reconnectNow()`; if connected, it invokes `refreshSessions()` to reconcile any sessions or projections modified from the Web client while the app was suspended.

## Alternatives considered

- **Adding a visible `+` icon button inside the sidebar group header.** Rejected: the sidebar column is compact, and adding an extra button beside the count and chevron crowds the title. Long-press matches the sidebar's interaction idiom for row actions.
- **Polling `session.list` on a timer.** Rejected: upstream reference explicitly avoids periodic polling in favor of push WebSocket streams (`session.control`, `workspace.follow`, `$events`) and reconnect re-baselining (`connection/reset`). Adding `Timer.periodic` polling in mobile would drain battery without architectural justification.
- **Route-based `showModalBottomSheet` for the directory browser.** Rejected: the directory browser state and breadcrumb navigation are owned by the Riverpod `WorkspaceController` stream. An inline overlay preserves UDF state bindings and live error feedback without route synchronization complexity.

## Consequences

- Long-pressing a project header in the left sidebar creates and opens a session in that workspace instantly.
- The directory browser dialog in the Workspaces tab docks reliably at the bottom of the screen with a full-page scrim; footer buttons wrap cleanly without overflowing.
- Session models stay in sync between Web and mobile in real time; selecting a model in Web immediately updates the mobile header and model selector.
- New tests: `workspace_browser_docking_test.dart` verifies full-screen docking of the directory browser in the aggregate screen; new tests in `session_panel_test.dart` assert project header long-press dispatch; new tests in `harness_repository_integration_test.dart` verify `modelSelection` projection and catalog cache invalidation; new test in `chat_controller_test.dart` verifies live UI model updates.
