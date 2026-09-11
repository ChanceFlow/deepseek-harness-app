/// Self-contained mount for the trajectory ledger.
///
/// The chat surface owns `ui/chat/**`, so the entry point lives here as one
/// widget the chat header drops into its `actions` list:
///
/// ```dart
/// actions: [
///   if (widget.backendId case final backendId?)
///     if (widget.uiState.selectedSessionId case final sessionId?)
///       TrajectoryEntryButton(backendId: backendId, sessionId: sessionId),
///   // …existing actions
/// ]
/// ```
///
/// The button carries its own `ProviderScope` and route, so it needs no
/// other wiring and no screen-level state from the chat surface.
library;

import 'package:app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../di/providers.dart';
import 'trajectory_screen.dart';
import 'trajectory_ui_state.dart';

/// App-bar action opening the trajectory ledger for one session.
class TrajectoryEntryButton extends StatelessWidget {
  const TrajectoryEntryButton({
    required this.backendId,
    required this.sessionId,
    super.key,
  });

  final String backendId;
  final String sessionId;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return IconButton(
      icon: const Icon(Icons.route_outlined),
      tooltip: l10n.trajectoryEntryTooltip,
      onPressed: () => openTrajectoryLedger(
        context,
        backendId: backendId,
        sessionId: sessionId,
      ),
    );
  }
}

/// Pushes the trajectory ledger route for one session.
void openTrajectoryLedger(
  BuildContext context, {
  required String backendId,
  required String sessionId,
}) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (routeContext) =>
          TrajectorySessionRoute(backendId: backendId, sessionId: sessionId),
    ),
  );
}

/// Route host binding the trajectory controller's UDF stream to the screen.
class TrajectorySessionRoute extends ConsumerWidget {
  const TrajectorySessionRoute({
    required this.backendId,
    required this.sessionId,
    super.key,
  });

  final String backendId;
  final String sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(
      trajectoryControllerProvider((
        backendId: backendId,
        sessionId: sessionId,
      )),
    );
    return StreamBuilder<TrajectoryUiState>(
      stream: controller.uiState,
      initialData: controller.state,
      builder: (context, snapshot) {
        return TrajectoryScreen(
          uiState: snapshot.data ?? const TrajectoryUiState(),
          onAction: controller.onAction,
        );
      },
    );
  }
}
