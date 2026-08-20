/// Assembly wiring — the ONLY app file allowed to import the harness
/// adapter (import-gate exemption, mirroring the legacy `app/di`).
///
/// Everything backend-dependent is a provider FAMILY keyed by the
/// backend id: each configured backend owns a live connection
/// (created when configured, stopped when removed) and one controller
/// set — switching the active backend rebinds the UI without dropping
/// the other backends' connections or state.
library;

import 'dart:io';

import 'package:flutter/widgets.dart' show AppLifecycleState, WidgetsBinding;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'package:domain/model/backend.dart';
import 'package:domain/repository/chat_repository.dart';
import 'package:harness_adapter/harness_adapter.dart';
import 'package:network/dsh_event_socket.dart' show DshEventSocket;
import 'package:network/dsh_rpc_client.dart' show DshRpcClient;
import 'package:network/http_dsh_rpc_client.dart';
import 'package:network/web_socket_dsh_event_socket.dart';

// Re-exported so tests can override the seams without importing the
// network package directly (import gate keeps that to this file).
export 'package:network/dsh_event_socket.dart';
export 'package:network/dsh_rpc_client.dart';
export 'package:network/rpc_envelope.dart';

// Re-exported so the UI surfaces the backend actions without importing
// the controller file directly.
export '../backends/backend_registry_controller.dart';
import '../backends/backend_registry_controller.dart';
import '../backends/backend_store.dart';
import '../config.dart';
import '../notifications/turn_complete_notifier.dart';
import '../ui/chat/chat_controller.dart';
import '../ui/chat/chat_ui_state.dart';
import '../ui/goal/goal_controller.dart';
import '../ui/models/models_controller.dart';
import '../ui/settings/settings_controller.dart';
import '../ui/subagents/subagent_controller.dart';
import '../ui/workspace/workspace_controller.dart';

/// Backend registry (device-local store + UDF stream).
final backendStoreProvider = FutureProvider<BackendStore>((ref) async {
  final documents = await getApplicationDocumentsDirectory();
  return BackendStore(
    File('${documents.path}/backends.json'),
    seedBaseUrl: kDshBaseUrl,
  );
});

final backendRegistryProvider = FutureProvider<BackendRegistryController>((
  ref,
) async {
  final controller = BackendRegistryController(await ref.watch(
    backendStoreProvider.future,
  ));
  ref.onDispose(controller.dispose);
  return controller;
});

/// The registry's state stream, mapped for widgets.
final backendRegistryStateProvider = StreamProvider<BackendRegistryState>((
  ref,
) async* {
  final controller = await ref.watch(backendRegistryProvider.future);
  yield controller.state;
  yield* controller.uiState;
});

/// The active backend's config; null until the store loads.
final activeBackendProvider = FutureProvider<BackendConfig?>((ref) async {
  final state = await ref.watch(backendRegistryStateProvider.future);
  return state.active;
});

/// The active backend id; empty string before the store loads (the UI
/// renders the loading state rather than a dead surface).
final activeBackendIdProvider = FutureProvider<String>((ref) async {
  final state = await ref.watch(backendRegistryStateProvider.future);
  return state.active?.id ?? '';
});

/// One backend's config by id; null once the backend is removed (the
/// dependent connection disposes with it through autoDispose).
final backendByIdProvider = StreamProvider.family.autoDispose<BackendConfig?,
    String>((ref, backendId) async* {
  final controller = await ref.watch(backendRegistryProvider.future);
  BackendConfig? current = controller.state.backends
      .where((backend) => backend.id == backendId)
      .firstOrNull;
  yield current;
  await for (final next in controller.uiState) {
    final updated = next.backends
        .where((backend) => backend.id == backendId)
        .firstOrNull;
    if (updated != current) {
      current = updated;
      yield updated;
    }
  }
});

/// Raw transport seams, overridable in tests (one per backend URL).
final dshRpcClientProvider = Provider.family.autoDispose<DshRpcClient, Uri>(
  (ref, uri) => HttpDshRpcClient(uri),
  name: 'dshRpcClient',
);

final dshEventSocketProvider = Provider.family.autoDispose<DshEventSocket,
    Uri>((ref, uri) => WebSocketDshEventSocket(uri), name: 'dshEventSocket');

/// One live connection per backend, keyed by (id, url): a URL edit
/// reconnects cleanly (the old member stops), a removal stops the member
/// once nothing keeps it alive. Created running — every read of a
/// configured backend starts its connection.
final backendConnectionProvider = Provider.family
    .autoDispose<DshConnectionManager, (String, Uri)>((ref, key) {
      final manager = DshConnectionManager(
        ref.watch(dshRpcClientProvider(key.$2)),
        ref.watch(dshEventSocketProvider(key.$2)),
        exponentialDshBackoffDelay,
      );
      manager.start();
      ref.onDispose(manager.stop);
      return manager;
    });

/// Keep-alive for every configured backend's connection: watches each
/// one so all backends stay connected simultaneously (the requirement);
/// a removed backend drops out of the watch set and its connection
/// stops. Read by the connection-status surfaces.
final allBackendConnectionsProvider =
    Provider<Map<String, DshConnectionManager>>((ref) {
      final state =
          ref.watch(backendRegistryStateProvider).value ??
          const BackendRegistryState();
      return <String, DshConnectionManager>{
        for (final backend in state.backends)
          backend.id: ref.watch(
            backendConnectionProvider((backend.id, backend.baseUri)),
          ),
      };
    });

/// The domain-facing repository per backend.
final chatRepositoryProvider = Provider.family.autoDispose<ChatRepository,
    String>((ref, backendId) {
  final backend = ref.watch(backendByIdProvider(backendId)).value;
  // The seed fallback covers only the pre-load window; a removed backend
  // takes its dependents down with it before this can matter.
  final uri = backend?.baseUri ?? Uri.parse(kDshBaseUrl);
  return HarnessRepositoryImpl(
    ref.watch(dshRpcClientProvider(uri)),
    ref.watch(backendConnectionProvider((backendId, uri))),
  );
});

/// Turn-complete system notifications (single instance, active backend
/// only — the hook is installed on that backend's chat controller).
final turnCompleteNotifierProvider = Provider<TurnCompleteNotifier>((ref) {
  return TurnCompleteNotifier();
});

/// Chat screen controller (UDF), one per backend.
final chatControllerProvider = Provider.family.autoDispose<ChatController,
    String>((ref, backendId) {
  final notifier = ref.watch(turnCompleteNotifierProvider);
  final controller = ChatController(
    ref.watch(chatRepositoryProvider(backendId)),
    onTurnComplete: (sessionTitle) {
      // Only when backgrounded: a foregrounded user is already watching.
      final lifecycle = WidgetsBinding.instance.lifecycleState;
      if (lifecycle != null && lifecycle != AppLifecycleState.resumed) {
        notifier.showTurnComplete(sessionTitle);
      }
    },
  );
  ref.onDispose(controller.dispose);
  return controller;
});

/// Chat UI state stream for widgets.
final chatUiStateProvider = StreamProvider.family<ChatUiState, String>((
  ref,
  backendId,
) => ref.watch(chatControllerProvider(backendId)).uiState);

/// Models screen controller (UDF), one per backend.
final modelsControllerProvider = Provider.family.autoDispose<ModelsController,
    String>((ref, backendId) {
  final controller = ModelsController(
    ref.watch(chatRepositoryProvider(backendId)),
  );
  ref.onDispose(controller.dispose);
  return controller;
});

/// Subagents screen controller (UDF), one per backend.
final subagentControllerProvider = Provider.family
    .autoDispose<SubagentController, String>((ref, backendId) {
  final controller = SubagentController(
    ref.watch(chatRepositoryProvider(backendId)),
  );
  ref.onDispose(controller.dispose);
  return controller;
});

/// Goal screen controller (UDF), one per backend.
final goalControllerProvider = Provider.family.autoDispose<GoalController,
    String>((ref, backendId) {
  final controller = GoalController(
    ref.watch(chatRepositoryProvider(backendId)),
  );
  ref.onDispose(controller.dispose);
  return controller;
});

/// Settings screen controller (UDF), one per backend.
final settingsControllerProvider = Provider.family.autoDispose<SettingsController,
    String>((ref, backendId) {
  final controller = SettingsController(
    ref.watch(chatRepositoryProvider(backendId)),
  );
  ref.onDispose(controller.dispose);
  return controller;
});

/// Workspace screen controller (UDF), one per backend.
final workspaceControllerProvider = Provider.family
    .autoDispose<WorkspaceController, String>((ref, backendId) {
  final controller = WorkspaceController(
    ref.watch(chatRepositoryProvider(backendId)),
  );
  ref.onDispose(controller.dispose);
  return controller;
});
