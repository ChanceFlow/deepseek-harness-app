# Agent Note: Backend registry error machine codes and surface localization

Status: implemented

## Problem

Backend store failures (corrupt JSON, malformed structure, invalid base URL,
read/write filesystem failures) and registry mutation validation errors
previously leaked developer English text (such as `BackendStoreException:
backends.json: malformed entry`) directly into `BackendRegistryState.errorMessage`.
When rendered on the Settings host management sheet, non-English users saw raw,
untranslated wire-level error strings rather than natural localized copy.

## Decision

### Machine error codes on exceptions and state

`BackendStoreException` and `BackendRegistryController` use a typed enum
`BackendErrorCode` (`invalidJson`, `malformedEntry`, `badBaseUrl`, `emptyList`,
`readFailed`, `writeFailed`, `emptyLabel`, `cannotRemoveLast`,
`removeActiveFirst`, `unknownBackend`, `backendDisabled`, `duplicateId`).

`BackendStoreException` carries `final BackendErrorCode code`, preserving the
developer-facing message, causal exception, and payload details on optional
fields for diagnostics. The controller encodes structured machine strings
(`code` or `code:detail`) onto `BackendRegistryState.errorMessage` instead of
raw English error strings.

### Localization helper and surface mapping

A pure helper `describeBackendError(AppLocalizations l10n, Object? error)` in
`flutter/app/lib/backends/describe_backend_error.dart` maps `BackendStoreException`,
`BackendErrorCode`, and encoded error strings to localized ARB keys in both
English and Simplified Chinese. The Settings host management sheet calls this
helper when rendering `_RegistryErrorLine`.

## Alternatives considered

- **Localize errors inside `BackendStoreException` or controller directly**:
  rejected — controllers and data stores are pure Dart logic detached from
  the widget tree and Flutter's `BuildContext` / `AppLocalizations`. The
  presentation layer owns localized string formatting.
- **Pass plain un-namespaced English text and try regex matching in UI**:
  rejected — fragile against developer message edits and violates the machine
  boundary contract. Stable machine enum codes guarantee exhaustive handling.

## Consequences

Registry errors and store failures surface in the user's active interface
language across English and Simplified Chinese without wire debug jargon.
Unit tests assert that every `BackendErrorCode` maps to distinct translated copy
in both supported locales, and widget tests verify that corrupt store files
render localized notices on the host management sheet.
