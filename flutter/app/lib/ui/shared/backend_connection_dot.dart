/// Live connection dot for one configured backend — the connection-state
/// phases mapped onto the StateDot vocabulary (shared by the Workspaces
/// aggregate headers and the Settings host rows). A disabled backend
/// wears the neutral grey: the host is off by choice, not unreachable.
library;

import 'package:domain/model/connection_state.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../di/providers.dart';
import 'state_dot.dart';

class BackendConnectionDot extends ConsumerWidget {
  const BackendConnectionDot({
    required this.backendId,
    this.enabled = true,
    super.key,
  });

  final String backendId;

  /// Whether the backend is enabled; a disabled backend draws the
  /// neutral dot without touching the (released) connection.
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!enabled) {
      return const StateDot(state: StateDotState.disabled, size: 8);
    }
    // The keep-alive map guarantees the member exists for every enabled
    // backend.
    final connections = ref.watch(allBackendConnectionsProvider);
    final phase = connections[backendId]?.state.value.phase;
    final dotState = switch (phase) {
      ConnectionPhase.connected => StateDotState.done,
      ConnectionPhase.connecting ||
      ConnectionPhase.reconnecting => StateDotState.ongoing,
      ConnectionPhase.disconnected => StateDotState.error,
      null => StateDotState.error,
    };
    return StateDot(state: dotState, size: 8);
  }
}
