# Agent Note: Permanent microphone denial recovers in the shell, and concurrent asks settle

Status: implemented

## Problem

The shell renders any number of host pages, and each page owns its own
`getUserMedia` asks. The activity answers those asks through the
`dsh/webview` channel by requesting Android runtime permissions. The
Android grant is app-wide — one process, one UID — but the channel answered a
bool, so Dart could not tell the user's "deny" from Android never asking
again. After the OS stops prompting (a "Don't allow" that records the choice,
or the second denial on Android 11 and later) every later ask returned `false`,
and the page could only show its generic capture error: the shell had no
`permanentlyDenied` state and no route to app settings. Native code also kept
one pending ask, so while one host's dialog was open a second host's ask was
answered `false` though the user never declined, and an activity teardown left
waiting Dart futures pending forever. A camera-only ask requested
`RECORD_AUDIO` as well, because the mapping routed every camera ask through
the microphone permission.

## Decision

- **A typed outcome replaces the bool.** `requestPermissions` answers
  `granted`, `denied`, `permanentlyDenied`, or `unavailable`, and
  [`webview_permissions.dart`](../../../../flutter/app/lib/shell/webview_permissions.dart)
  parses it; the WebView ask is granted only on `granted`.
- **Native asks settle one at a time, in FIFO order.** `MainActivity` holds a
  queue of pending `MethodChannel.Result`s instead of one slot, so a second
  host's concurrent ask waits for its own answer. On teardown every active and
  queued ask answers `unavailable`, so no Dart future hangs.
- **Permanent denial is detected, not guessed.** The activity persists, in
  `SharedPreferences`, the page permissions it has asked for before. When every
  still-missing permission was asked before and
  `shouldShowRequestPermissionRationale` is false, it answers
  `permanentlyDenied` without calling `requestPermissions`: the system would
  otherwise silently deny with no dialog.
- **The shell reaches app settings.** A new `openAppSettings` channel method
  starts `ACTION_APPLICATION_DETAILS_SETTINGS`, mirroring the existing
  notification-settings deep link in
  [`MainActivity.kt`](../../../../flutter/app/android/app/src/main/kotlin/com/deepseek/harness/app/MainActivity.kt).
- **The mapping is per resource.** Microphone requests `RECORD_AUDIO`, camera
  requests `CAMERA` only, and a page declaring both requests both.
- **One persistent banner owns the recovery.** The new
  `shell/mic_permission_recovery.dart` holds a Riverpod
  `Notifier<MicPermissionBlocked?>` with `reportBlocked(hostLabel)` and
  `clear()`; `shell/mic_permission_banner.dart` renders one top banner naming
  the host, with `Open settings` and `Dismiss`. A later granted ask clears it.
  The first denial stays the host page's own message: the shell acts only when
  Android will never prompt again.
- **Both locales carry the copy.** `micPermissionBlockedTitle`,
  `micPermissionBlockedBody` (placeholder `{host}`),
  `micPermissionOpenSettings`, and `micPermissionDismiss` are ARB keys in both
  locales.
- **Verification.** Focused tests cover the mapping and outcome parsing
  (`webview_permissions_test.dart`) and the banner
  (`mic_permission_banner_test.dart`); workspace analyze,
  `:app:compileDebugKotlin`, and `verify_android_manifest.py` complete the set.

## Alternatives considered

- **Keep the bool result and the single pending slot.** Denied and permanently
  denied stay one value, so the shell cannot tell a shrug from a door the OS
  has closed; the second host's concurrent ask still receives a false denial,
  and teardown still leaves a Dart future pending.
- **Expose an "Open settings" row only in shell settings.** The failure happens
  inside the host's page, where the user is; a settings row makes them leave
  the failed surface, discover a row that matters only in this exact state, and
  come back. The banner puts the one working action at the point of failure.
- **Pre-prompt the rationale from the shell before the Android dialog.**
  Rejected: the page owns its prompt and the shell injects nothing into the
  page, so a shell dialog would front-run an ask it does not own; permanent
  denial is the only state where the page's own message can no longer help.
- **Bridge audio capture through native code.** Rejected: an app recorder is an
  architecture change that moves capture and its audio graph out of the page;
  revisit only if voice becomes a core capability that must survive a hidden
  page.

## Consequences

- The permission states are distinguishable and the recovery is in-app: a
  permanent denial gets the banner, while a first denial stays the page's own
  message.
- The banner names the host whose page is blocked, so the user knows where the
  ask came from.
- Camera asks no longer request the microphone.
- Concurrent asks settle in order instead of being falsely denied, and a
  teardown answers `unavailable` instead of leaving futures pending.
- The OS dialog still names the app, not the host; per-host consent, host
  attribution in the OS prompt, hidden-page pausing, a microphone-in-use
  indicator, Bluetooth routing, and background capture remain open. The
  per-host consent proposal is a machine-local note under
  `.agents/notes/proposed/` (that tree is gitignored by policy), so it is not
  linked from this record.
- The debug APK's merged manifest and a device microphone retry are the
  remaining manual checks; the declarations themselves are pinned by
  [`verify_android_manifest.py`](../../../../scripts/verify_android_manifest.py).
