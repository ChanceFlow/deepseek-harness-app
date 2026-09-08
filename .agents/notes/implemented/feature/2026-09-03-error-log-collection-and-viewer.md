# Agent Note: In-app error log collection system and diagnostic viewer

Status: implemented

## Problem

When users encounter runtime errors, rendering issues, network timeouts,
or fatal crashes, mobile users previously had no way to inspect or report
what happened. The existing debug tooling (`packages/dev`) reported exclusively
to a remote SigNoz OpenTelemetry collector over OTLP/HTTP — an infrastructure
designed for development that is stripped out in production release builds
and inaccessible to end users. Furthermore, on-disk crash markers were
deleted on restart without exposing their contents to the user, leaving
testers and end users unable to view or copy error logs when reporting issues.

## Decision

### Central error log collection engine

`ErrorLogCollector` (`flutter/app/lib/logging/error_log_collector.dart`)
provides an in-app error collection service operating independently from
remote telemetry:
- **Automatic hook chaining**: Hooks `FlutterError.onError` and
  `PlatformDispatcher.instance.onError`, chaining to previous handlers
  to ensure debugging tools and tests remain unaffected.
- **In-memory ring buffer**: Holds the most recent 100 structured
  `ErrorLogEntry` items and a rolling buffer of 30 breadcrumb lines.
- **Local persistence**: Saves errors synchronously to `logs/error_logs.json`
  under the app documents directory upon capture, ensuring that crashes
  survive process termination and remain readable on the next launch.
- **Markdown diagnostic reporting**: Generates formatted diagnostic
  reports containing build info (version, commit, OS, active host) and
  chronological error details with stack traces and breadcrumbs.

### Dedicated error logs screen

`ErrorLogsScreen` (`flutter/app/lib/ui/settings/error_logs/error_logs_screen.dart`)
provides an on-device diagnostic viewer adhering to Stock Material 3:
- **System overview card**: Displays app version, git commit, OS, active
  host, and error count badges with a quick copy action.
- **Filtering and search**: Level filter chips (All, Fatal, Error, Warning)
  and real-time query filtering across message, error type, and stack trace.
- **Expandable error cards**: Cards display severity tags, timestamps,
  and error summaries, expanding to reveal monospace stack traces,
  recent breadcrumbs, and context attributes.
- **Copy and export**: "Copy All" exports the complete Markdown report
  to the clipboard; individual error cards provide one-tap copy buttons.
- **Safe deletion**: Clear button with confirmation dialog wipes both
  memory and persistent storage.

### Navigation integration

`SettingsScreen` includes an `_ErrorLogsEntryRow` under the App Preferences
section (`_AppPreferencesSection`), alongside Language and Speech Recognition.
The row displays a live badge with the current error count (tinted with
`errorContainer` when errors exist) and navigates to `ErrorLogsRoute`.

## Alternatives considered

- **Extend packages/dev OTel buffer**: rejected — `packages/dev` is
  compile-time gated and tree-shaken in release builds; end-user error
  reporting must function in all builds without requiring an external
  collector.
- **Store logs in SQLite**: rejected — lightweight JSON array in the
  app documents directory avoids native dependencies, keeping file operations
  direct and synchronously flushable during dying-process crashes.
- **Modal bottom sheet viewer**: rejected — error logs with long stack
  traces require full-screen scrolling, filtering, and copy affordances;
  a dedicated route matches the pattern established by speech model settings.

## Consequences

- Users can inspect and copy full error reports directly on device.
- All user-facing strings are fully localized in English and Chinese.
- Zero raw color literals; all elements strictly use `ColorScheme` roles
  and theme extensions.
- Comprehensive widget and unit tests verify persistence, error capture,
  filtering, and navigation.
