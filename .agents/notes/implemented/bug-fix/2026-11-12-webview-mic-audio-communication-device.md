# Agent Note: Echo-cancelled microphone capture declares MODIFY_AUDIO_SETTINGS

Status: implemented

## Problem

The app is a WebView shell whose page is the host's own dsh web client, and the
host page's voice input calls `navigator.mediaDevices.getUserMedia` with audio
constraints `{ echoCancellation: true, noiseSuppression: true }`. The permission
seam already answers the WebView's ask:
[`host_web_view.dart`](../../../../flutter/app/lib/shell/host_web_view.dart)
wires `setOnPlatformPermissionRequest`, which ensures the Android runtime
permission before it calls `request.grant()`, and
[`webview_permissions.dart`](../../../../flutter/app/lib/shell/webview_permissions.dart)
maps the microphone and camera resources to `android.permission.RECORD_AUDIO`
and `android.permission.CAMERA`. Voice input still failed after the user
granted the microphone: `getUserMedia` rejected with `NotReadableError: Could
not start audio source`.

The requested constraints select the audio path, and the manifest did not cover
the selection. Chromium's Android WebView capture selects the communication
audio device for echo-cancelled microphone audio (`AudioManager`
`MODE_IN_COMMUNICATION`), and that selection requires
`android.permission.MODIFY_AUDIO_SETTINGS`. The app manifest
([`AndroidManifest.xml`](../../../../flutter/app/android/app/src/main/AndroidManifest.xml))
declared `RECORD_AUDIO` but not the audio-settings permission, so capture failed
after the grant. The missing-permission diagnosis and its fix appear in other
WebView embedders:
[NativePHP/mobile-air #144](https://github.com/NativePHP/mobile-air/issues/144)
and [its fix #145](https://github.com/NativePHP/mobile-air/pull/145); the same
`NotReadableError` symptom appears in
[react-native-webview #3658](https://github.com/react-native-webview/react-native-webview/issues/3658).

## Decision

- **Declare the permission in the app manifest.** `AndroidManifest.xml` carries
  `<uses-permission android:name="android.permission.MODIFY_AUDIO_SETTINGS"/>`
  next to `RECORD_AUDIO`, with a comment naming the echo-cancelled capture path
  that needs it.
- **Keep the existing permission path.** `RECORD_AUDIO` is still requested at
  `getUserMedia` time through the `dsh/webview` channel, and the WebView's ask
  is still granted only after the user agrees. The audio-settings entry is a
  normal, install-time permission: no request, no channel method, no Dart
  wiring.
- **Leave the page's constraints alone.** The shell injects nothing into the
  host page; the page owns `echoCancellation` and `noiseSuppression`, and the
  change only makes the device its capture selects usable.

## Alternatives considered

- **Disable echo cancellation in the host page.** Wrong layer: the page owns
  its constraints and the shell injects no script, and dropping the constraint
  degrades capture on speakerphone and speaker playback.
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

- In-app voice capture works on devices where it failed after the
  `RECORD_AUDIO` grant; the page starts its capture with the constraints it
  already asks for.
- No new user-facing prompt: normal permissions are granted at install, and the
  runtime microphone ask is unchanged.
- The merged manifest carries the permission. No Dart test covers a manifest
  declaration, so verification is the debug APK's merged
  `AndroidManifest.xml` containing the entry; the fix is behavior-level and is
  exercised on a device rather than pinned by a widget test.
- A plain-HTTP LAN host still cannot use `getUserMedia`: the WebView's
  secure-context rule, recorded in
  [the notification-tap and permission note](../feature/2026-11-07-notification-tap-and-webview-permissions.md).
- The shell still injects nothing into the page, and the page keeps ownership
  of its capture constraints; the app declares only what the platform asks of
  the embedded browser.
