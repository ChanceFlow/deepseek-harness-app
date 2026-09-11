/// Platform bridge for the Android battery-optimization exemption.
///
/// A foreground service keeps the process out of Android's cached state, but
/// it does not survive Doze or an OEM kill-list: with the screen off, the
/// system can still suspend the app's network and drop the mux WebSocket. The
/// fix is the system's own exemption list, read with
/// `PowerManager.isIgnoringBatteryOptimizations` and requested through the
/// `ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` dialog — both owned by
/// `BatteryOptimizationBridge.kt`, registered as `dsh/battery_optimization`
/// in `MainActivity`.
///
/// Every call is non-throwing. Where no host implements the channel (widget
/// tests, desktop, a build the parent has not wired yet) the status reads
/// [BatteryOptimizationStatus.unsupported] and a request reports that nothing
/// opened; the settings row is then hidden rather than claiming an exemption
/// state the host cannot report.
library;

import 'package:flutter/services.dart';

/// Method channel name; must match `BatteryOptimizationBridge.kt`.
const String kBatteryOptimizationChannel = 'dsh/battery_optimization';

/// The app's battery-optimization standing on this host.
enum BatteryOptimizationStatus {
  /// The host exposes no battery-optimization concept (desktop, widget
  /// tests, or an Android build without the bridge registered). The settings
  /// row stays hidden: there is nothing to exempt.
  unsupported,

  /// The system may still suspend the app's network and close the connection
  /// once the screen has been off for a while (Doze, OEM kill-lists).
  notExempt,

  /// The app is on the system's battery-optimization exemption list.
  exempt,
}

/// The platform seam. Overridden in tests; the real one talks to
/// [kBatteryOptimizationChannel].
class BatteryOptimizationBridge {
  const BatteryOptimizationBridge();

  /// Reads the current standing.
  ///
  /// A missing channel or a host error answers
  /// [BatteryOptimizationStatus.unsupported]; it never throws, because a
  /// settings surface must render on a host that has no battery concept.
  Future<BatteryOptimizationStatus> status() async {
    try {
      final bool? ignoring = await const MethodChannel(
        kBatteryOptimizationChannel,
      ).invokeMethod<bool>('isIgnoringBatteryOptimizations');
      if (ignoring == null) return BatteryOptimizationStatus.unsupported;
      return ignoring
          ? BatteryOptimizationStatus.exempt
          : BatteryOptimizationStatus.notExempt;
    } on MissingPluginException {
      return BatteryOptimizationStatus.unsupported;
    } on PlatformException {
      return BatteryOptimizationStatus.unsupported;
    }
  }

  /// Opens the system's exemption dialog for this app.
  ///
  /// Answers `true` only when an activity resolved and was started; `false`
  /// when none did (typically the manifest lacks
  /// `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`) or no channel exists. It never
  /// throws.
  Future<bool> requestExemption() async {
    try {
      final bool? started = await const MethodChannel(
        kBatteryOptimizationChannel,
      ).invokeMethod<bool>('requestIgnoreBatteryOptimizations');
      return started ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}
