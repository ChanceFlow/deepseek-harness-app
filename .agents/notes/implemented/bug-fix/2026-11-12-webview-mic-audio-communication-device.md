# Agent Note: WebView microphone capture declares MODIFY_AUDIO_SETTINGS

Status: implemented

## Problem

The app is a WebView shell whose page is the host's own dsh web client, and the
host page's voice input calls `navigator.mediaDevices.getUserMedia`. The
permission seam already answers the WebView's ask:
[`host_web_view.dart`](../../../../flutter/app/lib/shell/host_web_view.dart)
wires `setOnPlatformPermissionRequest`, which ensures the Android runtime
permission before it calls `request.grant()`, and
[`webview_permissions.dart`](../../../../flutter/app/lib/shell/webview_permissions.dart)
maps the microphone and camera resources to `android.permission.RECORD_AUDIO`
and `android.permission.CAMERA`. Capture still failed after the user granted
the microphone: `getUserMedia` rejected with `NotReadableError: Could not start
audio source`.

The manifest did not cover the device selection, and that selection runs for
every capture rather than for one audio constraint. Chromium's Android WebView
captures audio through `MakeLowLatencyInputStream()` in
`media/audio/android/audio_manager_android.cc`, which calls
`AudioManagerAndroid.setCommunicationDevice()` for every low-latency input
stream; the per-stream AAudio device-selection path is enabled on desktop
only. `AudioManagerAndroid` requires both `MODIFY_AUDIO_SETTINGS` and
`RECORD_AUDIO`; without them it logs "Unable to select communication device!"
and returns null, which the page sees as the `NotReadableError` above. Any
WebView audio capture on a phone needs the permission; echo cancellation is
not the trigger, and disabling it would not remove the requirement. The app
manifest
([`AndroidManifest.xml`](../../../../flutter/app/android/app/src/main/AndroidManifest.xml))
declared `RECORD_AUDIO` but not the audio-settings permission, so capture
failed after the grant. Chrome's own
`chrome/android/java/AndroidManifest.xml` declares the permission, and
Capacitor and Cordova request it beside `RECORD_AUDIO` on `AUDIO_CAPTURE`. The
missing-permission diagnosis and its fix appear in other WebView embedders:
[NativePHP/mobile-air #144](https://github.com/NativePHP/mobile-air/issues/144)
and [its fix #145](https://github.com/NativePHP/mobile-air/pull/145); the same
`NotReadableError` symptom appears in
[react-native-webview #3658](https://github.com/react-native-webview/react-native-webview/issues/3658).

## Decision

- **Declare the permission in the app manifest.** `AndroidManifest.xml` carries
  `<uses-permission android:name="android.permission.MODIFY_AUDIO_SETTINGS"/>`
  next to `RECORD_AUDIO`.
- **Keep the existing permission path.** `RECORD_AUDIO` is still requested at
  `getUserMedia` time through the `dsh/webview` channel, and the WebView's ask
  is still granted only after the user agrees. The audio-settings entry is a
  normal, install-time permission: no request, no channel method, no Dart
  wiring.
- **Leave the page's constraints alone.** The shell injects nothing into the
  host page; the page owns `echoCancellation` and `noiseSuppression`, and the
  change only makes the communication device its capture selects usable.

## Alternatives considered

- **Disable echo cancellation in the host page.** Wrong layer: the page owns
  its constraints and the shell injects no script, and the device selection
  runs for every low-latency capture, so dropping the constraint would not
  remove the permission requirement.
- **Request the permission at runtime.** `MODIFY_AUDIO_SETTINGS` is normal and
  install-time, so a runtime request changes nothing and adds a fake prompt
  path beside the real microphone ask.
- **Bridge audio capture through native code.** An app-side recorder replaces
  the page's `getUserMedia` and its audio graph, and violates the shell's rule
  that nothing is injected or substituted into the page.
- **Rely on the host to serve HTTPS.** Orthogonal: the secure-context rule
  gates whether `getUserMedia` exists at all on a plain-HTTP host, while this
  permission is what the capture uses once the page clears that gate.

## Consequences

- Any WebView audio capture on a phone works where it failed after the
  `RECORD_AUDIO` grant, not only the echo-cancelled path the host page happens
  to request.
- No new user-facing prompt: normal permissions are granted at install, and the
  runtime microphone ask is unchanged.
- The merged manifest carries the permission. The declaration is pinned by
  [`verify_android_manifest.py`](../../../../scripts/verify_android_manifest.py)
  and checked on a device; the fix is behavior-level and is exercised by a
  microphone retry rather than a widget test.
- Permission outcomes and their recovery in the shell are
  [the microphone-permission recovery note](2026-11-13-webview-microphone-permission-recovery.md).
- A plain-HTTP LAN host still cannot use `getUserMedia`: the WebView's
  secure-context rule, recorded in
  [the notification-tap and permission note](../feature/2026-11-07-notification-tap-and-webview-permissions.md).
- The shell still injects nothing into the page, and the page keeps ownership
  of its capture constraints; the app declares only what the platform asks of
  the embedded browser.
