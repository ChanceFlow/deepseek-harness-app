# Agent Note: Module-by-module error observability and diagnostic wiring

Status: implemented

## Problem

When network or protocol errors occurred (such as Caddy returning 502 Bad Gateway on port 3083, WebSocket disconnects, or failed prompt commands), the application showed no automated error popups, logged nothing to local developer consoles, and presented `(No error logs recorded)` in the settings error log viewer:
1. `DshConnectionManager` (Harness Adapter) completely lacked diagnostic reporting (`onDiagnostic`). In `_runGeneration`, connection handshake failures were caught with an empty `catch (_) {}`. In `_pump`, optional stream errors called `return` silently, and reconnection attempts looped without emitting breadcrumbs.
2. In `packages/dev`, `initDebugTelemetry` returned `null` whenever the remote SigNoz OTLP endpoint was offline (the default local development state). Because telemetry was null, `DebugToolBootstrap` never started, which prevented `FlutterError.onError` and `PlatformDispatcher.instance.onError` from being installed. Furthermore, all telemetry calls swallowed errors without falling back to `debugPrint` or local console output.
3. In `packages/domain`, models lacked complete barrel exports in `domain.dart` (`agent_preset.dart`, `context_pressure.dart`, `permission_select.dart`, `session_window_stats.dart`).
4. In `packages/app` `providers.dart`, `backendConnectionProvider` instantiated `DshConnectionManager` without an `onDiagnostic` callback. In `harnessRepositoryProvider`, `captureError` was strictly gated on `diagnostic.level == AdapterDiagnosticLevel.error`, so `warning` level anomalies (such as history load failures and disconnects) never created error records.
5. In `ChatController`, `_loadSkills`, `_loadAgentPresets`, `_loadSessionSelection`, and `_loadModelPreferences` swallowed exceptions with empty `catch (_)` blocks without breadcrumbs. In `ChatScreen`, the snackbar listener only responded to voice-specific string constants, silently ignoring general transport and RPC exceptions.

## Decision

1. Added `AdapterDiagnosticListener? onDiagnostic` to `DshConnectionManager` and wired it into `backendConnectionProvider`. Diagnostic warnings are now emitted for generation handshake failures, downlink stream drops, 404 fallbacks, and reconnect backoff intervals.
2. Wired `onError` callbacks on `_connectionManager.muxFrames.listen` and `_connectionManager.hostFrames.listen` in `HarnessRepositoryImpl`, wrapped `state.handleFrame` in error handlers, and replaced empty `refreshSessions().catchError((_) {})` blocks with diagnostic logging.
3. Added a `localFallback` constructor to `DebugTelemetry` in `packages/dev` and updated `initDebugTelemetry` to always return a working local telemetry instance and bootstrap global error hooks even when remote OTLP collection is unavailable. Mirrored logs, events, and crash dumps to `debugPrint` in `kDebugMode`.
4. Exported all models through `packages/domain/lib/domain.dart` and added deep value equality to domain entities while keeping `TimelineWindow` on instance identity to preserve frame-level snapshot streaming.
5. Updated `providers.dart` to capture any diagnostic with an attached exception (`diagnostic.error != null`) directly into `ErrorLogCollector.instance.captureError`.
6. Replaced silent catches in `ChatController` with `ErrorLogCollector.instance.addBreadcrumb` calls, and added a general error snackbar fallback in `ChatScreen` for immediate visual notification of RPC and transport failures.

## Alternatives considered

1. Throwing fatal uncaught exceptions for all connection drops: rejected because mobile networks drop routinely and should reconnect with exponential backoff rather than crashing the application.
2. Routing all adapter diagnostics directly to Riverpod UI state: rejected because UI widgets should only observe domain models, not transport diagnostics.
3. Value equality comparison on `TimelineWindow`: rejected because `StateStream<TimelineWindow>` suppresses consecutive emissions when `_value == next`, which breaks frame-level UI reactivity for timeline updates that add non-item structural events.

## Consequences

- Connection losses, 502 Bad Gateway responses, and stream disconnects are immediately recorded in `ErrorLogCollector` and displayed in the Settings Error Logs screen.
- Crash and async error hooks are guaranteed to be installed at launch regardless of remote OTel availability.
- Debug mode development displays clean, formatted diagnostic logs in `logcat` and terminal.
- Users receive immediate floating snackbars when prompt dispatches or network mutations fail.
- All workspace tests and quality gates pass cleanly without import boundary violations.
