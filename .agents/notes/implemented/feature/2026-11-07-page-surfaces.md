# Agent Note: The page gets a browser's affordances, and external links leave

Status: implemented

## Problem

The WebView was a viewer, not a browser. A file input did nothing (the
plugin's file-selector callback was unset), a download did nothing (the
plugin exposes no download hook), the page could not win the microphone or
camera (no `onPermissionRequest`, and no camera declaration), and any link —
including one to another site — navigated the host's page away inside the
same WebView, with no way back to the host's origin except reloading.

## Decision

- **File inputs open the system picker.** `setOnShowFileSelector` maps the
  page's ask (mime types, accepted extensions, multiple, capture) to
  `file_picker`; the chosen absolute paths go back to the WebView and an
  empty list is the cancel the page expects. The mapping lives in
  `webview_file_chooser.dart` as an injectable seam so it is unit-tested
  without a platform channel.
- **External links leave the app.** `onNavigationRequest` keeps the host's
  own origin (scheme, host and port equal to `BackendConfig.baseUri`) and the
  in-page-only schemes (`about:`, `data:`, `blob:`) in the WebView;
  everything else — another site, another port, `https` on an `http` host,
  `mailto:`, `tel:`, `intent:` — is prevented and handed to
  `url_launcher` in `LaunchMode.externalApplication`. An unlaunchable URL is
  swallowed: a page must not break because a link has no handler.
- **Permissions are asked at the moment the page needs them.**
  `setOnPlatformPermissionRequest` maps WebView resources (microphone,
  camera) to Android runtime permissions through the activity's
  `dsh/webview` channel; unknown resources are denied. The manifest declares
  `CAMERA` and keeps `RECORD_AUDIO`, both with `uses-feature
  required="false"` so a device without them still installs.
- **Downloads are a native listener.** The activity walks its view tree for
  the plugin's WebViews after the page exists and attaches a
  `DownloadListener` that enqueues into `DownloadManager` with the page's
  cookies and user agent. API 29+ needs no storage permission; the legacy
  grant is declared with `maxSdkVersion="28"`.

## Alternatives considered

- **Switch to `flutter_inappwebview`.** It has the callbacks, but replacing
  the engine for three missing hooks would rewrite the page lifecycle, the
  pool and every shell test; the plugin's own Android extension points cover
  the same ground.
- **Inject JavaScript to intercept links and downloads.** The shell's whole
  contract is "nothing is injected"; a page that does not need it must not
  get a script.
- **Keep external navigation inside the WebView with a back button.** There
  is no back affordance in the chrome, and an off-origin document in the
  host's page is exactly the state the shell cannot recover from.
- **Ask for the microphone and camera at launch.** A permission prompt with
  no page asking is the pattern users deny; the ask belongs at `getUserMedia`
  time.
- **Capture on `<input capture>` with the camera intent.** `file_picker` has
  no capture dialog; the picker is opened instead and the page still receives
  a file. A camera-intent path is a later addition, not a blocker.

## Consequences

- The app now depends on `file_picker` and `url_launcher`; both are leaf
  plugins with no native setup beyond what the manifest already declares.
- `getUserMedia` still cannot work on a plain-HTTP LAN host: the WebView
  requires a secure context, so voice input needs HTTPS (or a
  loopback-served page). The permission path is correct; the platform rule
  remains. WebView microphone capture also needs `MODIFY_AUDIO_SETTINGS`:
  Chromium routes every audio capture on a phone through the communication
  audio device. The manifest entry and its rationale are
  [the microphone capture note](../bug-fix/2026-11-12-webview-mic-audio-communication-device.md).
- The download listener finds a WebView only once the platform view exists;
  the attach call is repeated on `onPageFinished`. API ≤28 downloads can
  still fail without the runtime storage grant the manifest declares.
- Off-origin links no longer have an in-app path back; the user returns with
  the system back gesture, which is the platform's own contract for leaving
  an app.
