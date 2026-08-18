/// Assembly wiring — the ONLY app file allowed to import the harness
/// adapter (import-gate exemption, mirroring the legacy `app/di`).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:domain/repository/chat_repository.dart';
import 'package:harness_adapter/harness_adapter.dart';
import 'package:network/dsh_event_socket.dart';
import 'package:network/dsh_rpc_client.dart';
import 'package:network/http_dsh_rpc_client.dart';
import 'package:network/web_socket_dsh_event_socket.dart';

// Re-exported so tests can override the seams without importing the
// network package directly (import gate keeps that to this file).
export 'package:network/dsh_event_socket.dart';
export 'package:network/dsh_rpc_client.dart';
export 'package:network/rpc_envelope.dart';

import '../config.dart';
import '../ui/chat/chat_controller.dart';
import '../ui/chat/chat_ui_state.dart';
import '../ui/goal/goal_controller.dart';
import '../ui/models/models_controller.dart';
import '../ui/settings/settings_controller.dart';
import '../ui/subagents/subagent_controller.dart';
import '../ui/workspace/workspace_controller.dart';

/// Raw transport seams, overridable in tests.
final dshRpcClientProvider = Provider<DshRpcClient>(
  (ref) => HttpDshRpcClient(Uri.parse(kDshBaseUrl)),
  name: 'dshRpcClient',
);

final dshEventSocketProvider = Provider<DshEventSocket>(
  (ref) => WebSocketDshEventSocket(Uri.parse(kDshBaseUrl)),
  name: 'dshEventSocket',
);

final dshConnectionManagerProvider = Provider<DshConnectionManager>((ref) {
  final manager = DshConnectionManager(
    ref.watch(dshRpcClientProvider),
    ref.watch(dshEventSocketProvider),
    exponentialDshBackoffDelay,
  );
  ref.onDispose(manager.stop);
  return manager;
});

/// The domain-facing repository the whole UI consumes.
final chatRepositoryProvider = Provider<ChatRepository>((ref) {
  return HarnessRepositoryImpl(
    ref.watch(dshRpcClientProvider),
    ref.watch(dshConnectionManagerProvider),
  );
});

/// Chat screen controller (UDF).
final chatControllerProvider = Provider<ChatController>((ref) {
  final controller = ChatController(ref.watch(chatRepositoryProvider));
  ref.onDispose(controller.dispose);
  return controller;
});

/// Chat UI state stream for widgets.
final chatUiStateProvider = StreamProvider<ChatUiState>(
  (ref) => ref.watch(chatControllerProvider).uiState,
);

/// Models screen controller (UDF).
final modelsControllerProvider = Provider<ModelsController>((ref) {
  final controller = ModelsController(ref.watch(chatRepositoryProvider));
  ref.onDispose(controller.dispose);
  return controller;
});

/// Subagents screen controller (UDF).
final subagentControllerProvider = Provider<SubagentController>((ref) {
  final controller = SubagentController(ref.watch(chatRepositoryProvider));
  ref.onDispose(controller.dispose);
  return controller;
});

/// Goal screen controller (UDF).
final goalControllerProvider = Provider<GoalController>((ref) {
  final controller = GoalController(ref.watch(chatRepositoryProvider));
  ref.onDispose(controller.dispose);
  return controller;
});

/// Settings screen controller (UDF).
final settingsControllerProvider = Provider<SettingsController>((ref) {
  final controller = SettingsController(ref.watch(chatRepositoryProvider));
  ref.onDispose(controller.dispose);
  return controller;
});

/// Workspace screen controller (UDF).
final workspaceControllerProvider = Provider<WorkspaceController>((ref) {
  final controller = WorkspaceController(ref.watch(chatRepositoryProvider));
  ref.onDispose(controller.dispose);
  return controller;
});
