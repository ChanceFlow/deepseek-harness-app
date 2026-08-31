# Agent Note: Disabled hosts fully quiescent (teardown ongoing notifications and release providers)

Status: implemented

## Problem

When a host was disabled via [Backend enable/disable](../feature/2026-08-29-backend-enable-disable.md), ongoing notifications posted under [Ongoing working notifications](../feature/2026-08-29-ongoing-working-notifications.md) could linger as orphans in the Android notification shade:
1. `AppNotificationCenter.dispose()` tore down stream subscriptions but never issued `SystemNotifier.cancelWork` for its non-gone applied session rows.
2. In Riverpod, `foregroundNotificationEventsProvider` used an `async*` / `StreamProvider` loop whose previous dependency subscriptions lingered when the stream had no incoming events to push state changes across runs, and `chatUiStateProvider` was not marked `autoDispose`, keeping `ChatController` and `DshConnectionManager` alive.
3. If the app process was terminated or restarted while a session had an ongoing notification, a disabled or removed backend had no running `AppNotificationCenter` instantiated after boot to reconcile its stale OS notification rows away.

## Decision

### Center teardown clears active rows

In `AppNotificationCenter.dispose()`, the center iterates over all currently non-gone applied sessions in `_applied` and invokes `_notifier.cancelWork(backendId: _backendId, sessionId: sessionId)` before closing its channels. When Riverpod auto-disposes a disabled backend's center, all ongoing tray rows belonging to that backend are immediately cancelled.

### Auto-dispose cascade hardened against provider leaks

The merge provider `foregroundNotificationEventsProvider` is refactored from an `async*` generator to an imperative subscription coordinator:
- It listens to `backendRegistryStateProvider` via `ref.listen`.
- On registry changes, it opens explicit `ProviderSubscription<AppNotificationCenter>` listeners for newly enabled backends and immediately closes subscriptions for disabled or removed backends.
- `chatUiStateProvider` and `backendSessionSlicesProvider` are marked `autoDispose`.
When a backend is disabled, all watchers on its `AppNotificationCenter`, `ChatUiState`, `ChatController`, `ChatRepository`, and `DshConnectionManager` are synchronously dropped, triggering Riverpod's auto-dispose cascade and cleanly terminating WebSocket event subscriptions.

### Startup boot sweep via posted-rows ledger

To guarantee stale notification rows die across app process restarts:
- A posted-rows ledger (`NotificationLedger` / `StoreNotificationLedger`) persists `(backendId, sessionId)` entries into `LocalStateStore` under `notifications.posted_rows`.
- `SystemNotifier.showWork`, `updateWorkBody`, and `promoteWorkToDone` record entries into the ledger; `cancelWork` evicts them.
- At startup, `postedRowsSweepProvider` awaits the loaded `LocalStateStore` and `BackendRegistryController.loaded`, attaches the ledger to `SystemNotifier`, and calls `sweepStaleRows(enabledBackendIds: ...)`. Any ledger entry whose `backendId` is not in the enabled set has `cancelWork` called with its deterministic `(id, tag)` and is removed from storage. Enabled backends' rows remain in place until their center connects and performs its cold reconciliation.

## Alternatives considered

- **Cancel all ledger rows indiscriminately on boot**: Discarding all rows regardless of backend status clears stale rows but causes ongoing notifications for running sessions on enabled backends to flicker or disappear until the WebSocket reconnects and reconciles. Sweeping only disabled and removed backends leaves enabled backends' rows intact until cold reconciliation re-evaluates them in place.
- **In-memory-only tracking in AppNotificationCenter**: Fails across process death because no `AppNotificationCenter` is ever spawned for a disabled backend after startup, leaving orphaned notifications permanently in the OS notification shade.
- **Periodic background polling service**: Unnecessary battery and resource overhead; deterministic FNV-1a identifiers combined with a local ledger allow complete cleanup in a single synchronous-style pass during boot.

## Consequences

- Disabling any backend immediately clears its live WebSocket connection, drops all associated controllers/repositories from memory, and removes its ongoing notification rows from the Android notification shade.
- Leftover ongoing notifications from backends disabled or removed prior to a process restart are purged during startup boot sweep.
- Enabled backends retain their ongoing notifications across restarts until their respective centers reconcile current session states.
