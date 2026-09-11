# Agent Note: Battery-optimization exemption guidance

Status: implemented

## Problem

The keep-alive foreground service
([background keep-alive FGS](2026-09-11-background-keep-alive-foreground-service.md))
holds the mux WebSocket open while agent work is in flight, but a foreground
service does not survive Doze or an OEM battery optimizer: the aggressive
firmware behind the `dontkillmyapp.com` class of complaint suspends the app's
network and kills the process anyway, so the connection still dies with the
screen off. The system's answer is the user placing the app on the
battery-optimization exemption list. The client showed that standing nowhere
and offered no way to request it.

## Decision

Settings → Host & connection gains a battery-optimization row backed by a new
`dsh/battery_optimization` MethodChannel.

- Native [BatteryOptimizationBridge.kt](../../../../flutter/app/android/app/src/main/kotlin/com/deepseek/harness/app/BatteryOptimizationBridge.kt)
  answers `isIgnoringBatteryOptimizations` from
  `PowerManager.isIgnoringBatteryOptimizations(packageName)` and
  `requestIgnoreBatteryOptimizations` by resolving and starting
  `Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` for the app package
  with `FLAG_ACTIVITY_NEW_TASK`, answering whether an activity resolved.
- The Dart seam
  [battery_optimization.dart](../../../../flutter/app/lib/platform/battery_optimization.dart)
  is non-throwing: a missing channel or host error reads `unsupported`, and a
  request that could not resolve reads `false`.
- [battery_optimization_section.dart](../../../../flutter/app/lib/ui/settings/battery_optimization_section.dart)
  owns a UDF controller (`AppStateStream`) plus its Riverpod providers. It
  reads the standing on construction and re-reads on every
  `appLifecycleChangesProvider` event, so returning from the system dialog
  settles the row without polling.
- Three rendered states. Not exempted: `scheme.warning` glyph, the copy that
  names the risk, and an `OutlinedButton` opening the dialog. Exempt: the same
  line stated as settled on `scheme.success`, with no control — a permanent
  button that can only re-open a dialog the user already answered is chrome.
  Unsupported: the row renders nothing, because Android advice on a host with
  no battery concept would be false, and the honest degradation for an
  unregistered bridge is silence.
- Five ARB keys in both locales; the generated localizations are committed.

The manifest declares
`<uses-permission android:name="android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS"/>`
and `MainActivity.configureFlutterEngine` calls
`BatteryOptimizationBridge.register(this, flutterEngine.dartExecutor.binaryMessenger)`,
so the system emits the standing the row renders.

## Alternatives considered

- **Deep-link to the battery-optimization settings list**
  (`ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS`): needs no permission and no
  Play declaration, but drops the user into an unfiltered list to find the app
  themselves, and gives no answer about whether they succeeded. The direct
  dialog is one tap and returns a verifiable standing, so it carries the
  restricted permission instead.
- **A blocking onboarding gate**: refuse to continue until the exemption is
  granted. Rejected as user-hostile and wrong on the facts — the exemption
  only buys background survival, not correctness, and every host function
  works without it.
- **Do nothing (keep the FGS alone)**: rejected because the keep-alive promise
  then silently fails on exactly the OEMs that motivated it, with the failure
  surfacing as a dead connection the user cannot diagnose.
- **A warning banner at the top of Chat** instead of a settings row: rejected
  because it would spend transcript pixels every session, while the decision
  belongs where connections are already managed.

## Consequences

- An affected user can see the standing and open the system dialog in one tap;
  the row settles on return because lifecycle changes re-read the flag.
- New restricted permission `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`, declared in
  the manifest, plus the channel registration in `MainActivity`. Without the
  permission the dialog resolves no activity and the row states that it could
  not open.
- Play policy treats `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` as restricted;
  release review may ask for a declaration. The seam degrades to a hidden row
  wherever the bridge is absent.
- Evidence:
  [battery_optimization_test.dart](../../../../flutter/app/test/platform/battery_optimization_test.dart)
  drives the channel contract through the mock messenger (both answers, no
  channel, host error);
  [battery_optimization_section_test.dart](../../../../flutter/app/test/ui/settings/battery_optimization_section_test.dart)
  drives the controller (lifecycle re-read, refused request) and the real
  `SettingsScreen` with a fake bridge for all three states, asserting the
  warning and success roles under both `DshTheme` brightnesses.
