# Agent Note: The previous process's exit and the error log stay on the device

Status: implemented

## Problem

An Android WebView renderer death can take the app process with it before a
Dart error hook runs, and Android's own reporting does not surface every such
kill. The app already kept an on-device error log, but nothing recorded why
the previous process ended and nothing exposed the log: diagnosis needed a
debug build and a PC. A user on the phone has neither.

The renderer-death fix keeps the process alive and recreates the page
([bug-fix note](../bug-fix/2026-11-11-webview-renderer-death.md)); this note
owns the diagnostics capability around it.

## Decision

- **Native exit history.** [DiagnosticsBridge.kt](../../../../flutter/app/android/app/src/main/kotlin/com/deepseek/harness/app/DiagnosticsBridge.kt)
  registers the `dsh/diagnostics` channel. On API 30+
  `lastExitReasons` maps
  `ActivityManager.getHistoricalProcessExitReasons(packageName, 0, 10)` to
  timestamp, reason, description, importance, status and process name, newest
  first; below API 30, or when the system service refuses the query, it
  answers with an empty list. The call needs no permission, and the trace
  streams stay unread: they are large and a record can point at another
  process's data.
- **Dart mapping and filter.** [exit_reasons.dart](../../../../flutter/app/lib/logging/exit_reasons.dart)
  decodes each record tolerantly, so one malformed field never discards the
  records beside it. `processExitReasonName` names every
  `ApplicationExitInfo` constant Android 16 defines and keeps an unknown
  number as `reason-<n>`. `isAbnormalExit` treats exit-self, user-requested,
  user-stopped, package-state-change and package-updated as deliberate; every
  other reason is abnormal. `exitReasonLevel` maps low-memory, signaled and
  other to warning; crash-native, ANR and initialization-failure to fatal; the
  rest to error.
- **At most one entry per launch.** [main.dart](../../../../flutter/app/lib/main.dart)
  calls `recordProcessExitReasons` after the collector restores
  `error_logs.json`. `newestUnreportedExit` takes the newest abnormal exit
  strictly after the newest recorded `process-exit:` entry, so an exit
  attributed by an earlier launch is not recorded again. A recorded entry's
  timestamp is the time this app wrote it — always later than the exit it
  describes — which makes the cutoff stable across launches. The entry carries
  the platform's own description, reason, importance, status and process
  name, plus a breadcrumb.
- **Renderer-death warning.** [shell_root.dart](../../../../flutter/app/lib/shell/shell_root.dart)'s
  `_onRendererDeath` writes one `webview-renderer-gone` entry per coalesced
  death with `didCrash`, `priority`, `livePages`, `consecutiveDeaths` and
  `epoch`, and a breadcrumb; the duplicate reports of the same burst leave
  none. The linked note owns the rebuild; this entry records the death.
- **On-device viewer.** The settings page's About card has
  `settingsErrorLogsRow`, which opens
  [ErrorLogViewerScreen](../../../../flutter/app/lib/logging/error_log_viewer.dart)
  over [ErrorLogCollector](../../../../flutter/app/lib/logging/error_log_collector.dart):
  the entry stream over its snapshot, a level filter, copy-all and
  copy-entry, a Markdown export, clear, and the build footer. The row and
  screen reuse the existing `errorLogs*` strings. The collector caps 100
  entries and 30 breadcrumbs and persists synchronously to `error_logs.json`,
  so a kill preserves what was captured.
- **Release builds keep it.** The collector and viewer are part of every
  build, stable release included. The OTel debug telemetry stays
  debug/prerelease-only and is tree-shaken out of a stable release.

## Alternatives considered

- **Diagnose over adb only.** The person who hits a renderer death is on the
  phone without a PC, a cable or adb; a log only a developer can pull leaves
  the report empty.
- **Read Play Console.** Play Console does not report an unhandled renderer
  kill, so it cannot answer the question this capability exists for.
- **Record every exit.** Exit-self, user stop and package update would bury
  the real deaths; the abnormal filter plus the newest-only dedupe keeps the
  log actionable.
- **Adopt Sentry or Crashlytics.** That adds a dependency and a remote
  pipeline for data the existing collector already stores on device.
- **Read the exit trace streams.** The traces are large and a historical
  record may point at another process's data; the reason constant and the
  system description attribute the death.

## Consequences

- A launch records at most one previous-exit entry, and a deliberate stop
  records nothing. API below 30 has no history.
- A renderer death writes exactly one warning entry per coalesced burst, so
  the log and the rebuild count agree.
- Attribution failure never breaks startup: a missing channel, a platform
  error or a malformed field leaves the log untouched.
- The captured log lives in the app's own storage, so the reason vocabulary
  and the build facts travel with the device rather than a debug session.
