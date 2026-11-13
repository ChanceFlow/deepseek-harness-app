# Agent Note: A notification tap opens its host, and the page gets the permissions it asks for

Status: implemented

## Problem

Two defects, both found by using the app.

**The tap went nowhere.** Every system notification carried a
`NotificationTarget` payload (backend, session), and
`systemNotificationTargetsProvider` existed — but nothing consumed it. A tap
brought the app forward on whatever host it was already showing, and a cold
start forgot the launch target after `initialize()` returned it. The same bug
existed in a peer native client: session and agent ids written into one key
with no reader anywhere, so a tap only raised the app. A payload without a
consumer is worse than none: it looks like routing.

**The shell's permission surface was smaller than the page it hosts.** The
manifest declared the microphone for the old on-device ASR, not for the page;
there was no camera declaration; the WebView had no
`onPermissionRequest`, so a `getUserMedia` ask could never be granted even
with the manifest entry; and a download from the page did nothing at all
because `webview_flutter` exposes no download hook.

## Decision

**Consume the payload, and let the page's own asks reach Android.**

- **Warm and cold taps share one seam.** `ShellLifecycle` subscribes to
  `systemNotificationTargetsProvider` and reads
  `coldStartNotificationTargetProvider` once in `initState`; both call
  `notificationTargetDispatchProvider`, which selects the payload's host in the
  registry. The banner's tap goes through the same seam, so a tap on the
  in-app banner and a tap in the shade do the same thing.
- **An outside selection wins over a local one.** `ShellRoot` remembers the
  registry's active host when the user picks a host locally; if the registry's
  active host has moved elsewhere since (a notification tap), the local
  selection is dropped and the strip seats on the registry's host.
- **The page's permission ask is answered, not assumed.**
  `AndroidWebViewController.setOnPlatformPermissionRequest` maps the WebView's
  resource ask (microphone, camera) to Android runtime permissions, requests
  them through a `dsh/webview` channel in `MainActivity`, and grants only when
  the user did. Unknown resources are denied. The manifest declares
  `CAMERA` (with `uses-feature … required="false"`) next to `RECORD_AUDIO`.
- **Downloads are a native listener.** `webview_flutter` has no download API,
  so the activity walks its view tree for the plugin's WebViews once the page
  exists (idempotent `attachDownloads`) and hands `DownloadManager` the URL,
  cookies and guessed file name. `WRITE_EXTERNAL_STORAGE` is declared with
  `maxSdkVersion="28"`: API 29+ writes to Downloads through MediaStore.
- **The shade stays private.** Every chat notification is
  `NotificationVisibility.private`, uses `BigTextStyleInformation`, carries a
  `host:<id>` group key and a category (reminder for pending interactions,
  message for replies). A locked phone shows the app name, not the session.

## Alternatives considered

- **Deep-link into the session.** The hosts' web client owns routing and there
  is no bridge, so the only navigable fact we can honour is the host; a
  hard-coded web route would rot with the host's version.
- **Ask for permissions up front.** A cold microphone/camera prompt without a
  page asking is exactly the pattern users deny; the ask belongs at
  `getUserMedia` time, which is where the WebView hands it to us.
- **A download plugin.** `flutter_inappwebview` would replace the whole engine
  for one missing callback; the listener rides the WebView the shell already
  has.
- **Request storage on old APIs at launch.** It is only needed when a download
  starts on API ≤28, and a launch-time prompt for it is noise on every modern
  device.

## Consequences

- A tap now lands on the right host; the session inside that page still opens
  where the host's own UI left it, because the shell has no session route.
- `getUserMedia` still cannot work on a plain-HTTP LAN host: the WebView's
  secure-context rule, not the permission. Voice input needs HTTPS or a
  loopback-served page.
- WebView microphone capture also needs `MODIFY_AUDIO_SETTINGS`: Chromium
  routes every audio capture on a phone through the communication audio
  device. The manifest entry and its rationale are
  [the microphone capture note](../bug-fix/2026-11-12-webview-mic-audio-communication-device.md).
- The download listener finds a WebView only after the platform view exists;
  the call is repeated on `onPageFinished`, and a page that never finishes
  simply has no listener.
- Old-API downloads can still fail without the runtime storage grant; the
  manifest entry alone is not permission on API ≤28.
