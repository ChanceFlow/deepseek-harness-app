/// Settings → Host & connection: the battery-optimization exemption row.
///
/// A foreground service keeps the mux WebSocket alive while agent work is in
/// flight, but with the screen off Android still suspends the app's network
/// unless the app sits on the system's battery-optimization exemption list
/// (`dontkillmyapp.com` is the same problem named per OEM). This row is the
/// only place the app shows that standing and the only way to request it.
///
/// The state is device-global and host-independent, so it lives outside the
/// host settings document: the controller reads the platform seam on
/// construction and re-reads on every app-lifecycle change, which is how the
/// row settles after the user returns from the system dialog.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../di/providers.dart';
import '../../l10n/app_localizations.dart';
import '../../platform/battery_optimization.dart';
import '../state_stream.dart';
import '../theme/theme.dart';

export '../../platform/battery_optimization.dart'
    show BatteryOptimizationBridge, BatteryOptimizationStatus;

/// One resolved battery-optimization state.
final class BatteryOptimizationState {
  const BatteryOptimizationState({
    this.status = BatteryOptimizationStatus.unsupported,
    this.requestFailed = false,
  });

  /// The system's standing for this app.
  final BatteryOptimizationStatus status;

  /// The last exemption request resolved no activity, so nothing opened.
  final bool requestFailed;

  BatteryOptimizationState copyWith({
    BatteryOptimizationStatus? status,
    bool? requestFailed,
  }) {
    return BatteryOptimizationState(
      status: status ?? this.status,
      requestFailed: requestFailed ?? this.requestFailed,
    );
  }
}

/// UDF controller over the platform seam: reads the standing on construction,
/// re-reads on every app-lifecycle change, and publishes every result.
class BatteryOptimizationController {
  BatteryOptimizationController({
    required this._bridge,
    Stream<void>? lifecycleChanges,
  }) {
    _lifecycleSubscription = lifecycleChanges?.listen(
      (void _) => unawaited(refresh()),
    );
    unawaited(refresh());
  }

  final BatteryOptimizationBridge _bridge;
  final AppStateStream<BatteryOptimizationState> _state =
      AppStateStream<BatteryOptimizationState>(
        const BatteryOptimizationState(),
      );
  StreamSubscription<void>? _lifecycleSubscription;
  bool _requesting = false;

  BatteryOptimizationState get state => _state.value;
  Stream<BatteryOptimizationState> get uiState => _state.stream;

  void dispose() {
    unawaited(_lifecycleSubscription?.cancel());
    unawaited(_state.close());
  }

  /// Re-reads the system flag. Overlapping reads are harmless — the flag is
  /// the truth either way — so no in-flight guard is needed.
  Future<void> refresh() async {
    final BatteryOptimizationStatus status = await _bridge.status();
    _state.value = _state.value.copyWith(status: status, requestFailed: false);
  }

  /// Opens the system exemption dialog.
  ///
  /// On a resolved open the row re-reads immediately, so a host whose dialog
  /// applies the exemption without leaving the app still settles; the
  /// lifecycle subscription covers the round trip. A refused open is stated
  /// on the row rather than silently swallowed.
  Future<bool> requestExemption() async {
    if (_requesting) return false;
    _requesting = true;
    try {
      final bool started = await _bridge.requestExemption();
      if (started) {
        await refresh();
      } else {
        _state.value = _state.value.copyWith(requestFailed: true);
      }
      return started;
    } finally {
      _requesting = false;
    }
  }
}

/// The platform seam. Tests override this with a fake to drive both states.
final batteryOptimizationBridgeProvider = Provider<BatteryOptimizationBridge>(
  (Ref ref) => const BatteryOptimizationBridge(),
);

/// The one controller for the app: the standing is device-global, not per
/// backend or per settings scope.
final batteryOptimizationControllerProvider =
    Provider<BatteryOptimizationController>((Ref ref) {
      final controller = BatteryOptimizationController(
        bridge: ref.watch(batteryOptimizationBridgeProvider),
        lifecycleChanges: ref.watch(appLifecycleChangesProvider),
      );
      ref.onDispose(controller.dispose);
      return controller;
    });

/// The exemption row for the Host & connection section card.
///
/// Not exempted: a warning-toned line and the button that opens the system
/// dialog. Exempt: the same line stated as settled, with no control. On a
/// host with no battery concept the row renders nothing — the guidance is
/// Android-specific and a hidden row is the only honest state when the
/// platform answers nothing.
class SettingsBatteryOptimizationRow extends ConsumerWidget {
  const SettingsBatteryOptimizationRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final BatteryOptimizationController controller = ref.watch(
      batteryOptimizationControllerProvider,
    );
    return StreamBuilder<BatteryOptimizationState>(
      stream: controller.uiState,
      initialData: controller.state,
      builder:
          (
            BuildContext context,
            AsyncSnapshot<BatteryOptimizationState> snapshot,
          ) {
            final BatteryOptimizationState state =
                snapshot.data ?? controller.state;
            if (state.status == BatteryOptimizationStatus.unsupported) {
              return const SizedBox.shrink();
            }
            return _row(context, l10n, controller, state);
          },
    );
  }

  Widget _row(
    BuildContext context,
    AppLocalizations l10n,
    BatteryOptimizationController controller,
    BatteryOptimizationState state,
  ) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final bool exempt = state.status == BatteryOptimizationStatus.exempt;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                exempt
                    ? Icons.check_circle_outline
                    : Icons.warning_amber_rounded,
                size: 18,
                color: exempt ? scheme.success : scheme.warning,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.batteryOptimizationTitle,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            exempt
                ? l10n.batteryOptimizationExemptBody
                : l10n.batteryOptimizationNotExemptBody,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          if (!exempt) ...<Widget>[
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: () => unawaited(controller.requestExemption()),
              child: Text(l10n.batteryOptimizationAllowAction),
            ),
            if (state.requestFailed) ...<Widget>[
              const SizedBox(height: 6),
              Text(
                l10n.batteryOptimizationRequestFailed,
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.error),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
