/// Assembly wiring — the ONLY app file allowed to import the harness
/// adapter (import-gate exemption, mirroring the legacy `app/di`).
///
/// Everything backend-dependent is a provider FAMILY keyed by the
/// backend id: each configured backend owns a live connection
/// (created when configured, stopped when removed) and one controller
/// set — switching the active backend rebinds the UI without dropping
/// the other backends' connections or state.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart' show AppLifecycleState, WidgetsBinding;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'package:domain/model/backend.dart';
import 'package:domain/model/connection_state.dart';
import 'package:domain/model/session.dart' show SessionSummary;
import 'package:domain/model/workspace.dart' show WorkspaceSummary;
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
import '../notifications/app_notification_center.dart';
import '../notifications/notification_events.dart' show AppNotificationEvent;
import '../notifications/system_notifier.dart';
import '../local_state/local_state_providers.dart';
import '../ui/chat/chat_controller.dart';
import '../ui/chat/chat_local_state.dart';
import '../ui/chat/chat_ui_state.dart';
import '../ui/chat/session_panel.dart' show BackendSessionSlice;
import '../ui/goal/goal_controller.dart';
import '../ui/models/models_controller.dart';
import '../ui/settings/settings_controller.dart';
import '../ui/settings/asr/asr_models_controller.dart';
import '../ui/subagents/subagent_controller.dart';
import '../ui/workspace/workspace_controller.dart';
import 'package:asr/asr.dart';

export '../ui/settings/asr/asr_models_controller.dart';
export '../ui/settings/asr/asr_models_screen.dart';

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
/// renders the loading state rather than a dead surface). Stream-based:
/// the registry's first snapshot can predate its async load, so latching
/// a single future would freeze the empty id forever.
final activeBackendIdProvider = StreamProvider<String>((ref) async* {
  final controller = await ref.watch(backendRegistryProvider.future);
  await for (final state in controller.uiState) {
    yield state.active?.id ?? '';
  }
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

/// One backend's live connection state — the manager's phase and host
/// description (version, cwd) as a watchable stream. The Settings
/// Backends rows read it to show the connected host's version; the
/// keep-alive map above guarantees the member exists for every
/// configured backend.
final backendConnectionStateProvider =
    StreamProvider.family.autoDispose<ConnectionState, String>((ref,
        backendId) async* {
  final manager = ref.watch(allBackendConnectionsProvider)[backendId];
  if (manager == null) return;
  yield* manager.state.stream;
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

/// System (OS-level) notifications, single instance shared by every
/// backend's notification center.
final systemNotifierProvider = Provider<SystemNotifier>((ref) {
  return SystemNotifier();
});

/// Per-backend notification center: folds the session list into
/// notification events and routes them to the foreground toast channel or
/// the background system channel. The app-root toast host keeps every
/// configured backend's center alive so backgrounded turns still notify.
final appNotificationCenterProvider =
    Provider.family.autoDispose<AppNotificationCenter, String>((ref,
        backendId) {
  final systemNotifier = ref.watch(systemNotifierProvider);
  final center = AppNotificationCenter(
    repository: ref.watch(chatRepositoryProvider(backendId)),
    backendId: backendId,
    isForegrounded: () =>
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed,
    selectedSessionIdOf: () =>
        ref.read(chatControllerProvider(backendId)).state.selectedSessionId,
    onBackground: systemNotifier.show,
  );
  ref.onDispose(center.dispose);
  return center;
});

/// Merged foreground channel across every configured backend: the app-root
/// toast host listens here and watches the family, which keeps every
/// backend's center (and its session fold) alive for the app's lifetime.
final foregroundNotificationEventsProvider = StreamProvider<AppNotificationEvent>(
  (ref) async* {
    final registry =
        ref.watch(backendRegistryStateProvider).value ??
        const BackendRegistryState();
    final controller = StreamController<AppNotificationEvent>.broadcast();
    final subscriptions = <StreamSubscription<AppNotificationEvent>>[];
    for (final backend in registry.backends) {
      subscriptions.add(
        ref
            .watch(appNotificationCenterProvider(backend.id))
            .foregroundEvents
            .listen(controller.add),
      );
    }
    ref.onDispose(() {
      for (final subscription in subscriptions) {
        unawaited(subscription.cancel());
      }
      unawaited(controller.close());
    });
    yield* controller.stream;
  },
);

/// System-notification tap destinations (running-app taps plus cold-start
/// launches), merged so the app root can navigate on either.
final systemNotificationTargetsProvider = StreamProvider<NotificationTarget>(
  (ref) => ref.watch(systemNotifierProvider).targets,
);

/// Chat screen controller (UDF), one per backend.
final chatControllerProvider = Provider.family.autoDispose<ChatController,
    String>((ref, backendId) {
  final controller = ChatController(
    ref.watch(chatRepositoryProvider(backendId)),
    // Model-seat preferences are scoped per backend: hosts own different
    // catalogs, so a route remembered on one must not land on another's
    // seat. The store resolves asynchronously; the controller arms the
    // remembered values once it settles.
    modelPreferences: ref.watch(
      modelPreferencePersistenceProvider(backendId).future,
    ),
    // The last-opened session restores per backend after the session
    // list loads (web `dsh.sessions.current` parity).
    sessionSelection: ref.watch(
      sessionSelectionPersistenceProvider(backendId).future,
    ),
  );
  ref.onDispose(controller.dispose);
  return controller;
});

/// Composer model-seat preference persistence over the shared
/// [LocalStateStore], one scope per backend.
final modelPreferencePersistenceProvider =
    FutureProvider.family.autoDispose<ModelPreferencePersistence?, String>((
      ref,
      backendId,
    ) async {
      final store = await ref.watch(localStateStoreProvider.future);
      return StoreModelPreferencePersistence(store, 'backend.$backendId');
    });

/// Selected-session persistence over the shared [LocalStateStore], one
/// scope per backend.
final sessionSelectionPersistenceProvider =
    FutureProvider.family.autoDispose<SessionSelectionPersistence?, String>((
      ref,
      backendId,
    ) async {
      final store = await ref.watch(localStateStoreProvider.future);
      return StoreSessionSelectionPersistence(store, 'backend.$backendId');
    });

/// Chat UI state stream for widgets.
final chatUiStateProvider = StreamProvider.family<ChatUiState, String>((
  ref,
  backendId,
) => ref.watch(chatControllerProvider(backendId)).uiState);

/// Every configured backend's sidebar slice, keyed by the backend the
/// chat surface presents (the slice's active flag follows it). Each
/// slice is SELECTED out of its host's chat state — only the roster
/// facts, never the timeline — so a slice whose sessions and workspaces
/// did not change compares equal and a streaming publish on ANY backend
/// (each backend's restored session now streams while the app is open)
/// recomputes nothing and rebuilds no surface (the reference web client
/// renders the sidebar from per-node subscriptions, not a whole-tree
/// rebuild). Watching here also keeps every backend's chat controller
/// alive for the app's lifetime.
final backendSessionSlicesProvider =
    Provider.family<List<BackendSessionSlice>, String>((ref, activeBackendId) {
      final registry =
          ref.watch(backendRegistryStateProvider).value ??
          const BackendRegistryState();
      return <BackendSessionSlice>[
        for (final backend in registry.backends)
          ref.watch(
            chatUiStateProvider(backend.id).select(
              (uiState) => BackendSessionSlice(
                backend: backend,
                active: backend.id == activeBackendId,
                sessions:
                    uiState.value?.sessions ??
                    const <SessionSummary>[],
                workspaces:
                    uiState.value?.workspaces ??
                    const <WorkspaceSummary>[],
              ),
            ),
          ),
      ];
    });

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

/// ASR models base storage directory.
final asrModelsDirectoryProvider = FutureProvider<Directory>((ref) async {
  final supportDir = await getApplicationSupportDirectory();
  final modelsDir = Directory('${supportDir.path}/models');
  if (!await modelsDir.exists()) {
    await modelsDir.create(recursive: true);
  }
  return modelsDir;
});

/// ASR models registry provider.
final asrModelsRegistryProvider = FutureProvider<ModelsRegistry>((ref) async {
  final modelsDir = await ref.watch(asrModelsDirectoryProvider.future);
  final registry = ModelsRegistry(
    registryFile: File('${modelsDir.path}/models_registry.json'),
  );
  await registry.load();
  ref.onDispose(registry.dispose);
  return registry;
});

/// ASR model manager provider.
final asrModelManagerProvider = FutureProvider<AsrModelManager>((ref) async {
  final modelsDir = await ref.watch(asrModelsDirectoryProvider.future);
  final registry = await ref.watch(asrModelsRegistryProvider.future);
  return AsrModelManager(
    baseModelsDir: modelsDir,
    registry: registry,
  );
});

/// ASR models controller (UDF).
final asrModelsControllerProvider =
    Provider.autoDispose<AsrModelsController>((ref) {
  final managerAsync = ref.watch(asrModelManagerProvider);
  final controller = AsrModelsController(manager: managerAsync.value);
  ref.onDispose(controller.dispose);
  return controller;
});

/// ASR models UI state stream.
final asrModelsUiStateProvider =
    StreamProvider.autoDispose<AsrModelsUiState>((ref) {
  final controller = ref.watch(asrModelsControllerProvider);
  return controller.uiState;
});

