/// Live connection dot for one configured backend — the connection-state
/// phases mapped onto the StateDot vocabulary (shared by the Workspaces
/// aggregate headers and the Settings Backends rows).
library;

import 'package:domain/model/connection_state.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../di/providers.dart';
import '../subagents/subagent_screen.dart'
    show SubagentDotState, SubagentStateDot;

class BackendConnectionDot extends ConsumerWidget {
  const BackendConnectionDot({required this.backendId, super.key});

  final String backendId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The keep-alive map guarantees the member exists for every
    // configured backend.
    final connections = ref.watch(allBackendConnectionsProvider);
    final phase = connections[backendId]?.state.value.phase;
    final dotState = switch (phase) {
      ConnectionPhase.connected => SubagentDotState.done,
      ConnectionPhase.connecting ||
      ConnectionPhase.reconnecting => SubagentDotState.ongoing,
      ConnectionPhase.disconnected => SubagentDotState.error,
      null => SubagentDotState.error,
    };
    return SubagentStateDot(state: dotState);
  }
}
