# Agent Note: Failure surfaces are localized, retryable and dismissible

Status: implemented

## Problem

Three failure surfaces leaked developer detail and offered no way out:

- `ChatRoute`'s `chatUiStateProvider` error branch and `WorkspaceRoute`'s
  registry error branch rendered `Scaffold(body: Center(child:
  Text(error.toString())))` — a raw Dart exception, full screen, English
  only, with no retry.
- The chat transcript's failure strip rendered `uiState.errorMessage` as
  plain red text. The controller publishes `SESSION_ALREADY_OWNED` for the
  one class it names and the raw host message otherwise, so a reader could
  be shown `ClientException with SocketException`. `DismissError` and
  `RetrySessions` existed on `ChatAction` and were dispatched nowhere: the
  strip was sticky and unretryable.

## Decision

- `ChatErrorBanner` (`flutter/app/lib/ui/chat/chat_error_banner.dart`)
  replaces the strip: an `errorContainer` surface carrying a localized
  headline, the raw host detail as a secondary monospace line, a Retry
  action that dispatches the existing `RetrySessions`, and a Dismiss action
  that dispatches `DismissError`. `describeChatError` maps
  `SESSION_ALREADY_OWNED` to `sessionAlreadyOwnedError`; every other message
  becomes the localized `chatActionFailed` headline with the message kept as
  detail. A host command that returned an error outcome (`commandFailed`)
  reuses the banner with dismiss only — retrying that means re-running the
  command, which only the reader can do.
- `LocalizedErrorView` (`flutter/app/lib/ui/shared/error_view.dart`) is the
  full-screen counterpart: localized sentence, error glyph, optional Retry.
  `ChatRoute` uses it for a failed state stream (`chatLoadFailed`) with a
  retry that invalidates the controller and state providers; `WorkspaceRoute`
  uses it for a failed registry future with a retry that invalidates the
  registry providers.
- The workspace message goes through `describeBackendFailure`
  (`flutter/app/lib/ui/shared/backend_error_text.dart`): a classified
  `BackendStoreException`, `BackendErrorCode`, or encoded string keeps
  `describeBackendError`'s specific copy; anything else falls back to the
  localized `backendErrorLoadFailed` instead of `toString()`.

## Alternatives considered

- **Keep the raw message as the headline and only add buttons**: rejected —
  the defect is that a reader is shown a wire string, not that buttons are
  missing; the detail survives as a secondary line instead.
- **Add a typed error channel to `ChatUiState`**: rejected — the controller
  already classifies what it can (`SESSION_ALREADY_OWNED`); the remaining
  failures are opaque transport and host messages, so a channel would need a
  domain error taxonomy the wire does not publish.
- **Route the retry through a new action**: rejected — `RetrySessions`
  already re-pulls the roster and `DismissError` already clears the message,
  command failure, and image rejections; the strip dispatches them.
- **A dismiss-only strip for every failure**: rejected — state-stream and
  roster failures genuinely recover on retry, and a dead end is the defect.

## Consequences

- A reader sees their own language and can clear or retry a failure.
- `RetrySessions` and `DismissError` gain production call sites; no new state
  channel is introduced.
- New ARB keys in both locales: `chatActionFailed`, `chatLoadFailed`,
  `backendErrorLoadFailed`. `sessionAlreadyOwnedError` is used for the first
  time.
- `chat_error_banner_test.dart` covers the localized headline, retry and
  dismiss dispatch, the session-owned copy, and command-failure dismiss-only;
  `workspace_error_test.dart` covers classified copy with retry and the
  generic fallback that never prints the raw type.
