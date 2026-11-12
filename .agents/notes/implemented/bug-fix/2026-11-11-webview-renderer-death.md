# Agent Note: A WebView renderer death keeps the app and recreates the page

Status: implemented

## Problem

Android renders each WebView in a separate process. Its
[termination contract](https://developer.android.com/develop/ui/views/layout/webapps/handle-termination)
is strict: `WebViewClient.onRenderProcessGone` must return `true` when the
renderer dies, and the default `false` tells the OS to kill the app with the
renderer. The shell never overrode that callback, so a page's
out-of-memory kill or renderer crash took the whole app down with it — the
notification sockets, the host registry and every other live page included.

`webview_flutter_android` 4.14.1 has no API for it: the plugin's
`WebViewClient` in the compiled classes overrides no `onRenderProcessGone`,
and the upstream fix
([flutter/packages PR #6508](https://github.com/flutter/packages/pull/6508))
is unmerged. The app also had no way to replace a page in place:
`HostWebView`'s key was `host-page:<id>` only, so a rebuild reused the dead
page's `State` and its dead controller.

## Decision

- **Native guard.** `RendererDeathGuard`
  ([RendererDeathGuard.kt](../../../../flutter/app/android/app/src/main/kotlin/com/deepseek/harness/app/RendererDeathGuard.kt))
  is a `WebViewClient` that delegates to the plugin's own client, forwards
  the 15 callbacks that client overrides, returns `true` from
  `onRenderProcessGone`, and reports the death. `installRendererGuards`, a new
  method on the existing `dsh/webview` channel, walks the activity's view
  tree and wraps each unguarded WebView. It is idempotent, and below API 26 it
  is a no-op because `WebView.getWebViewClient()` does not exist there.
- **Report to Dart.** The guard posts `rendererGone` with `didCrash` and
  `priority` on the same channel.
  [`webview_renderer.dart`](../../../../flutter/app/lib/shell/webview_renderer.dart)
  turns it into a `RendererWatch` stream; `ShellRoot` subscribes once and
  disposes the watch with the shell.
- **Coalesced rebuild.** Android reports one death per WebView attached to the
  dead renderer, so the first report marks the death pending and later
  reports of the same burst are dropped. The shell then clears the live page
  pool and bumps `_pageEpoch`; each `HostWebView` key carries the host id, the
  epoch and the base URI, so the replacement builds a new `State` and
  controller even when the URL is unchanged.
- **Backoff.** The first rebuild waits 600 ms and each consecutive death
  doubles the delay, capped at 5 s; 60 s without a death resets the streak.

## Alternatives considered

- **Rely on the OS restarting the app.** That is the default contract: the
  renderer death takes the process, and the user returns to a cold start with
  the notification sockets, the in-flight page state and every warm host
  gone. A background page often dies while the user is elsewhere, so the
  restart reads as a spontaneous app crash.
- **Switch the shell to `flutter_inappwebview`.** That plugin exposes
  `onRenderProcessGone`, but adopting it replaces the entire page host —
  controller, permission asks, download listener, file chooser, and the
  cookie and TLS seams — for one callback.
- **Inject a script that shrinks the page's memory.** The shell injects
  nothing into the host's page, and a memory hint would not satisfy the
  termination contract: the renderer can still die, and the app still dies
  with it.

## Consequences

- A renderer death keeps the process. Live pages are recreated after a 600 ms
  backoff that doubles per consecutive death and is capped at 5 s, and a
  burst of reports is coalesced into one rebuild.
- A page key carries the host id, `_pageEpoch` and the base URI, so a
  renderer-death rebuild builds a fresh page rather than updating the dead
  controller, and editing a host's URL reloads the page in place.
- Android API below 26 is unguarded and keeps the previous behavior; the
  platform callback does not exist there.
- `didCrash` and `priority` reach Dart but recovery does not branch on them;
  every death takes the same rebuild path.
- [`renderer_recovery_test.dart`](../../../../flutter/app/test/shell/renderer_recovery_test.dart)
  drives an injected watch to pin the backoff, the burst coalescing and a
  second death after the coalescing window.
- The page pool bounds memory as before: the renderer-death rebuild recreates
  only the pages that are live, not every enabled host.
