/// Assembly wiring — the ONLY app file allowed to import the harness
/// adapter (import-gate exemption, mirroring the legacy `app/di`).
///
/// Everything backend-dependent is a provider FAMILY keyed by the
/// backend id: each enabled backend owns a live connection (created when
/// configured, stopped when removed or disabled) and one controller set —
/// switching the active backend rebinds the UI without dropping the other
/// backends' connections or state. Disabling a backend drops it from the
/// watch sets below; with no watcher left, Riverpod's default
/// auto-dispose releases its connection, repository, and controllers, and
/// re-enabling lazily rebuilds them.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart'
    show AppLifecycleState, WidgetsBinding, WidgetsBindingObserver;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'package:app/platform/disk_space.dart';

import 'dsh_reachability.dart';
import 'http_engine.dart';

import 'package:domain/model/backend.dart';
import 'package:domain/model/connection_state.dart';
import 'package:domain/model/session.dart' show SessionSummary;
import 'package:domain/model/workspace.dart' show WorkspaceSummary;
import 'package:domain/repository/chat_repository.dart';
import 'package:domain/repository/session_log_export_repository.dart';
import 'package:harness_adapter/harness_adapter.dart';
import 'package:network/dsh_download_client.dart';
import 'package:network/dsh_event_socket.dart' show DshEventSocket;
import 'package:network/dsh_rpc_client.dart' show DshRpcClient;
import 'package:network/http_dsh_rpc_client.dart';
import 'package:network/web_socket_dsh_event_socket.dart';

// Re-exported so tests can override the seams without importing the
// network package directly (import gate keeps that to this file).
export 'package:network/dsh_event_socket.dart';
export 'package:network/dsh_exceptions.dart';
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
import '../notifications/notification_ledger.dart';
import '../notifications/notification_localizations.dart';
import '../notifications/system_notifier.dart';
import '../notifications/watched_session.dart';
import '../local_state/local_state_providers.dart';
import '../platform/keep_alive_coordinator.dart';
import '../platform/keep_alive_service.dart';
import '../platform/network_reconnect.dart';
import '../platform/network_status.dart';
import '../ui/chat/chat_controller.dart';
import '../ui/chat/chat_local_state.dart';
import '../ui/chat/chat_ui_state.dart';
import '../ui/chat/session_panel.dart' show BackendSessionSlice;
import '../ui/goal/goal_controller.dart';
import '../ui/models/models_controller.dart';
import '../ui/root/app_destination.dart';
import '../ui/settings/llm_providers.dart';
import '../ui/settings/settings_controller.dart';
import '../ui/settings/asr/asr_models_controller.dart';
import '../ui/chat/voice_input/voice_input_controller.dart';
import '../ui/chat/voice_input/voice_input_ui_state.dart';
import '../ui/subagents/subagent_controller.dart';
import '../ui/trajectory/trajectory_controller.dart';
import '../ui/workspace/workspace_controller.dart';
import '../logging/error_log_collector.dart';
import '../logging/error_log_entry.dart';
import '../ui/settings/error_logs/error_logs_controller.dart';

import 'package:dev/dev.dart' show DebugTelemetry;

import '../ui/settings/error_logs/error_logs_ui_state.dart';

import 'package:asr/asr.dart';

export '../ui/settings/asr/asr_models_controller.dart';
export '../ui/settings/asr/asr_models_screen.dart';
export '../ui/chat/voice_input/voice_input_controller.dart';
export '../ui/chat/voice_input/voice_input_ui_state.dart';
export '../ui/chat/voice_input/voice_record_bubble.dart';
export '../ui/settings/error_logs/error_logs_controller.dart';
export '../ui/settings/error_logs/error_logs_screen.dart';
export '../ui/settings/error_logs/error_logs_ui_state.dart';
export '../logging/error_log_collector.dart';
export '../logging/error_log_entry.dart';

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
  final controller = BackendRegistryController(
    await ref.watch(backendStoreProvider.future),
  );
  ref.onDispose(controller.dispose);
  return controller;
});

/// Startup boot sweep for posted notification rows: once the local state
/// store and backend registry are loaded, attaches the ledger to the
/// [SystemNotifier] and cancels any leftover ongoing rows for disabled or
/// removed backends.
final postedRowsSweepProvider = FutureProvider<void>((ref) async {
  final localStore = await ref.watch(localStateStoreProvider.future);
  final notifier = ref.watch(systemNotifierProvider);
  notifier.attachLedger(StoreNotificationLedger(localStore));
  final controller = await ref.watch(backendRegistryProvider.future);
  await controller.loaded;
  final enabledIds = controller.state.enabledBackends.map((b) => b.id).toSet();
  await notifier.sweepStaleRows(enabledBackendIds: enabledIds);
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
final backendByIdProvider = Provider.family.autoDispose<BackendConfig?, String>(
  (ref, backendId) {
    final state = ref.watch(backendRegistryStateProvider).value;
    return state?.backends
        .where((backend) => backend.id == backendId)
        .firstOrNull;
  },
);

/// Raw transport seams, overridable in tests (one per backend URL).
///
/// Android rides the embedded-Cronet engine (opportunistic HTTP/3, see
/// `http_engine.dart`); non-Android hosts and engine-construction failure
/// fall back to `HttpDshRpcClient`'s default `IOClient` path unchanged.
/// The engine lives for the application lifetime; client wrappers are closed
/// on autoDispose with disposal errors swallowed so they never escape into
/// Riverpod's unhandled zone.
///
/// A backend the user marked *trust this host's certificate* instead rides
/// `trustedHostRpcClient` — a dart:io client that accepts a failing
/// certificate for that exact host only. Cronet has no certificate-verify
/// override (`cronet_http` 1.9.0), so the opt-in costs that backend the
/// HTTP/3 upgrade; every untrusted backend keeps Cronet.
final dshRpcClientProvider = Provider.family.autoDispose<DshRpcClient, Uri>(
  _buildRpcClient,
  name: 'dshRpcClient',
);

/// Whether the user opted this exact backend in to trusting its certificate.
///
/// Selects the flag alone (not the whole registry) so a rename or an
/// enable/disable never rebuilds the transport and reconnects; only flipping
/// the opt-in does. A URL edit changes the provider family key by itself.
/// Non-`https` backends never carry an override: there is no certificate to
/// validate.
bool _trustsHostCertificate(Ref ref, Uri uri) {
  if (uri.scheme != 'https') return false;
  return ref.watch(
    backendRegistryStateProvider.select((registry) {
      final backend = registry.value?.backends
          .where((candidate) => candidate.baseUri == uri)
          .firstOrNull;
      return backend?.trustHostCertificate ?? false;
    }),
  );
}

DshRpcClient _buildRpcClient(Ref ref, Uri uri) {
  if (_trustsHostCertificate(ref, uri)) {
    final trusted = trustedHostRpcClient(
      uri.host,
      connectionTimeout: kDshRpcConnectTimeout,
    );
    ref.onDispose(() {
      try {
        trusted.close();
      } catch (_) {
        // Swallowed: client teardown must never crash the app.
      }
    });
    return HttpDshRpcClient(uri, httpClient: trusted);
  }
  final engine = dshHttp3Engine();
  if (engine == null) {
    return HttpDshRpcClient(uri);
  }
  ref.onDispose(() {
    try {
      engine.close();
    } catch (_) {
      // Swallowed: client teardown must never crash the app.
    }
  });
  return HttpDshRpcClient(uri, httpClient: engine);
}

/// One reachability probe, shared by the Settings host sheet.
///
/// A plain value with no lifecycle: each `probe` call builds its own
/// transport for the (URL, trust) pair it is given and closes it. The
/// registry-keyed [dshRpcClientProvider] family cannot serve this — the
/// sheet probes addresses the registry does not contain yet, and it selects
/// certificate trust out of the registry rather than the sheet's toggle.
/// The probe lives in `lib/di/dsh_reachability.dart`, next to the transport
/// seams it reuses.
final dshReachabilityProbeProvider = Provider<DshReachabilityProbe>(
  (ref) => const DshReachabilityProbe(),
);

/// The binary download leg, one per backend URL.
///
/// The session-log archive is a plain HTTP GET, not a JSON-RPC envelope, so
/// it gets its own client rather than a call through [DshRpcClient]. The
/// transport policy is the RPC leg's, unchanged: a backend the user opted
/// into trusting rides the dart:io certificate override, every other
/// backend rides the shared Cronet engine.
final dshDownloadClientProvider = Provider.family
    .autoDispose<DshDownloadClient, Uri>(
      _buildDownloadClient,
      name: 'dshDownloadClient',
    );

DshDownloadClient _buildDownloadClient(Ref ref, Uri uri) {
  if (_trustsHostCertificate(ref, uri)) {
    final trusted = trustedHostRpcClient(
      uri.host,
      connectionTimeout: kDshRpcConnectTimeout,
    );
    ref.onDispose(() {
      try {
        trusted.close();
      } catch (_) {
        // Swallowed: client teardown must never crash the app.
      }
    });
    return HttpDshDownloadClient(uri, httpClient: trusted);
  }
  final engine = dshHttp3Engine();
  if (engine == null) {
    return HttpDshDownloadClient(uri);
  }
  ref.onDispose(() {
    try {
      engine.close();
    } catch (_) {
      // Swallowed: client teardown must never crash the app.
    }
  });
  return HttpDshDownloadClient(uri, httpClient: engine);
}

/// The session-log archive seam per backend. It holds no lifecycle of its
/// own: the download client above owns the HTTP connection.
final sessionLogExportProvider = Provider.family
    .autoDispose<SessionLogExportRepository, String>((ref, backendId) {
      final backend = ref.watch(backendByIdProvider(backendId));
      final uri = backend?.baseUri ?? Uri.parse(kDshBaseUrl);
      return DshSessionLogExportRepository(
        ref.watch(dshDownloadClientProvider(uri)),
      );
    });

/// The event socket, one per backend URL. The WS leg is always dart:io/// (`WebSocket.connect`); a trusted backend hands it a `customClient` whose
/// certificate policy accepts a failing certificate for that exact host so
/// the `wss` handshake succeeds. Untrusted backends pass null and keep the
/// platform default.
final dshEventSocketProvider = Provider.family.autoDispose<DshEventSocket, Uri>(
  (ref, uri) {
    if (!_trustsHostCertificate(ref, uri)) {
      return WebSocketDshEventSocket(uri);
    }
    final trusted = trustedCertificateHttpClient(uri.host);
    ref.onDispose(trusted.close);
    return WebSocketDshEventSocket(uri, customClient: trusted);
  },
  name: 'dshEventSocket',
);

/// One live connection per backend, keyed by (id, url): a URL edit
/// reconnects cleanly (the old member stops), a removal stops the member
/// once nothing keeps it alive. Created running — every read of a
/// configured backend starts its connection.
final backendConnectionProvider = Provider.family
    .autoDispose<DshConnectionManager, (String, Uri)>((ref, key) {
      final manager = DshConnectionManager(
        ref.watch(dshEventSocketProvider(key.$2)),
        exponentialDshBackoffDelay,
        onDiagnostic: (diagnostic) {
          final levelStr = diagnostic.level.name.toUpperCase();
          ErrorLogCollector.instance.addBreadcrumb(
            '[Connection $levelStr] ${diagnostic.context ?? ""}: ${diagnostic.message}',
            level: diagnostic.level.name,
          );
          if (diagnostic.level == AdapterDiagnosticLevel.error) {
            ErrorLogCollector.instance.captureError(
              diagnostic.error ?? diagnostic.message,
              stackTrace: diagnostic.stackTrace,
              level: ErrorLogLevel.error,
              context: <String, Object?>{
                'backendId': key.$1,
                'uri': key.$2.toString(),
                'diagnostic_context': diagnostic.context,
                ...diagnostic.metadata,
              },
            );
          } else if (diagnostic.level == AdapterDiagnosticLevel.warning &&
              diagnostic.error != null) {
            ErrorLogCollector.instance.captureError(
              diagnostic.error!,
              stackTrace: diagnostic.stackTrace,
              level: ErrorLogLevel.warning,
              context: <String, Object?>{
                'backendId': key.$1,
                'uri': key.$2.toString(),
                'diagnostic_context': diagnostic.context,
                'diagnostic_message': diagnostic.message,
                ...diagnostic.metadata,
              },
            );
          }
          DebugTelemetry.instance?.log(
            '${diagnostic.context ?? "connection"}: ${diagnostic.message}',
            level: diagnostic.level == AdapterDiagnosticLevel.error
                ? 'error'
                : 'warn',
          );
        },
      );
      manager.start();
      ref.onDispose(manager.stop);
      return manager;
    });

/// Keep-alive for every enabled backend's connection: watches each one
/// so all connected backends stay connected simultaneously (the
/// requirement); a removed or disabled backend drops out of the watch
/// set and its connection stops. Read by the connection-status surfaces.
final allBackendConnectionsProvider =
    Provider<Map<String, DshConnectionManager>>((ref) {
      final state =
          ref.watch(backendRegistryStateProvider).value ??
          const BackendRegistryState();
      return <String, DshConnectionManager>{
        for (final backend in state.enabledBackends)
          backend.id: ref.watch(
            backendConnectionProvider((backend.id, backend.baseUri)),
          ),
      };
    });

/// One backend's live connection state — the manager's phase and host
/// description (version, cwd) as a watchable stream. The Settings
/// Backends rows read it to show the connected host's version; the
/// keep-alive map above guarantees the member exists for every enabled
/// backend (a disabled backend's rows show their disabled state without
/// reading this).
final backendConnectionStateProvider = StreamProvider.family
    .autoDispose<ConnectionState, String>((ref, backendId) async* {
      final manager = ref.watch(allBackendConnectionsProvider)[backendId];
      if (manager == null) return;
      yield* manager.state.stream;
    });

/// Android default-network availability hints. One instance for the app; the
/// [NetworkStatus] seam registers the host's connectivity callback on its
/// first listener and releases it on the last cancellation.
final networkStatusProvider = Provider<NetworkStatus>((ref) {
  final status = NetworkStatus();
  ref.onDispose(() => unawaited(status.dispose()));
  return status;
});

/// Wakes every enabled backend's connection the moment the device's network
/// comes back.
///
/// A generation lost to a network drop has already started its backoff, and
/// that delay was chosen for a network that no longer exists. Each
/// availability hint asks every live manager for a fresh generation at once,
/// so unlocking the phone or rejoining Wi-Fi recovers in a loop turn instead
/// of after up to the 10 s cap. Read by [AppRoot] to keep the binder — and
/// with it the host callback — alive for the app's lifetime.
final networkReconnectProvider = Provider<NetworkReconnectBinder>((ref) {
  final binder = NetworkReconnectBinder(
    available: ref.watch(networkStatusProvider).available,
    reconnectAll: () {
      for (final manager in ref.read(allBackendConnectionsProvider).values) {
        manager.reconnectNow();
      }
    },
  )..start();
  ref.onDispose(binder.dispose);
  return binder;
});

/// The domain-facing repository per backend.
final chatRepositoryProvider = Provider.family.autoDispose<ChatRepository, String>((
  ref,
  backendId,
) {
  final backend = ref.watch(backendByIdProvider(backendId));
  // The seed fallback covers only the pre-load window; a removed backend
  // takes its dependents down with it before this can matter.
  final uri = backend?.baseUri ?? Uri.parse(kDshBaseUrl);
  final repo = HarnessRepositoryImpl(
    ref.watch(dshRpcClientProvider(uri)),
    ref.watch(backendConnectionProvider((backendId, uri))),
    onDiagnostic: (diagnostic) {
      final levelStr = diagnostic.level.name.toUpperCase();
      ErrorLogCollector.instance.addBreadcrumb(
        '[Adapter $levelStr] ${diagnostic.context ?? ""}: ${diagnostic.message}',
        level: diagnostic.level.name,
      );
      if (diagnostic.level == AdapterDiagnosticLevel.error) {
        ErrorLogCollector.instance.captureError(
          diagnostic.error ?? diagnostic.message,
          stackTrace: diagnostic.stackTrace,
          level: ErrorLogLevel.error,
          context: <String, Object?>{
            'backendId': backendId,
            'diagnostic_context': diagnostic.context,
            ...diagnostic.metadata,
          },
        );
      } else if (diagnostic.level == AdapterDiagnosticLevel.warning &&
          diagnostic.error != null) {
        ErrorLogCollector.instance.captureError(
          diagnostic.error!,
          stackTrace: diagnostic.stackTrace,
          level: ErrorLogLevel.warning,
          context: <String, Object?>{
            'backendId': backendId,
            'diagnostic_context': diagnostic.context,
            'diagnostic_message': diagnostic.message,
            ...diagnostic.metadata,
          },
        );
      }
      DebugTelemetry.instance?.log(
        '${diagnostic.context ?? "adapter"}: ${diagnostic.message}',
        level: diagnostic.level == AdapterDiagnosticLevel.error
            ? 'error'
            : 'warn',
      );
    },
  );
  ref.onDispose(repo.dispose);
  return repo;
});

/// System (OS-level) notifications, single instance shared by every
/// backend's notification center.
final systemNotifierProvider = Provider<SystemNotifier>((ref) {
  return SystemNotifier();
});

/// Per-backend notification center: folds the session list into
/// notification events and routes them to the foreground toast channel or
/// the background system channel, and reconciles each session's ongoing
/// work notification. The app-root toast host keeps every enabled
/// backend's center alive so backgrounded turns still notify.
///
/// The center watches the backend's chat controller (its uiState feeds the
/// watched-session fact below), so the controller stays alive with its
/// center — per backend that is for the app's lifetime, matching the
/// connection keep-alive requirement.
final appNotificationCenterProvider = Provider.family
    .autoDispose<AppNotificationCenter, String>((ref, backendId) {
      final systemNotifier = ref.watch(systemNotifierProvider);
      // Keep the controller alive with its center (doc above); its uiState
      // feeds the watched-session fact the center polls and listens to.
      ref.watch(chatControllerProvider(backendId));
      // The watched-session fact (selection only while Chat covers the
      // screen) drives both the selected-turn silence rule and the ongoing
      // suppression; its changes — selection AND destination switches —
      // invalidate the reconcile.
      final watchedChanges = StreamController<void>.broadcast();
      ref.onDispose(watchedChanges.close);
      ref.listen<String?>(watchedSessionIdProvider(backendId), (_, _) {
        if (!watchedChanges.isClosed) watchedChanges.add(null);
      });
      final center = AppNotificationCenter(
        repository: ref.watch(chatRepositoryProvider(backendId)),
        backendId: backendId,
        isForegrounded: () =>
            WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed,
        selectedSessionIdOf: () =>
            ref.read(watchedSessionIdProvider(backendId)),
        onBackground: systemNotifier.show,
        notifier: systemNotifier,
        selectionChanges: watchedChanges.stream,
        foregroundChanges: ref.watch(appLifecycleChangesProvider),
      );
      ref.onDispose(center.dispose);
      return center;
    });

/// The session the user is actually watching on this backend: the chat
/// controller's selection only while the Chat destination is the active
/// one ([watchedSessionId]). A turn finishing in the selected session
/// while the user reads Workspaces or Settings is NOT watched — the web's
/// "selected stays silent" carve-out assumes the conversation pane is
/// always on screen, and the phone's full-screen destinations are not.
///
/// Selection changes republish the controller's uiState (watched for
/// invalidation); the value itself polls the controller's live state, so
/// a fold can never see a stale or pre-first-emission cache.
final watchedSessionIdProvider = Provider.family.autoDispose<String?, String>((
  ref,
  backendId,
) {
  final chatDestinationActive =
      ref.watch(appDestinationProvider) == AppDestination.chat;
  ref.watch(chatUiStateProvider(backendId));
  return watchedSessionId(
    chatDestinationActive: chatDestinationActive,
    selectedSessionId: ref
        .watch(chatControllerProvider(backendId))
        .state
        .selectedSessionId,
  );
});

/// Broadcast invalidation signal fired on every app lifecycle transition.
/// The ongoing work notifications re-reconcile on it; the signal carries no
/// value because the `lifecycleState == resumed` poll is the source of
/// truth (the binding updates it before notifying observers).
final appLifecycleChangesProvider = Provider<Stream<void>>((ref) {
  final controller = StreamController<void>.broadcast();
  final observer = _LifecycleSignal(controller);
  WidgetsBinding.instance.addObserver(observer);
  ref.onDispose(() {
    WidgetsBinding.instance.removeObserver(observer);
    unawaited(controller.close());
  });
  return controller.stream;
});

class _LifecycleSignal with WidgetsBindingObserver {
  _LifecycleSignal(this._controller);

  final StreamController<void> _controller;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_controller.isClosed) _controller.add(null);
  }
}

/// The keep-alive foreground-service seam. Overridden where the platform
/// channel does not exist (widget tests, desktop hosts).
final keepAliveServiceProvider = Provider<KeepAliveService>(
  (ref) => const KeepAliveService(),
);

/// The keep-alive notification's copy, resolved at request time from the
/// platform locale — the same launch-locale rule [SystemNotifier] follows
/// for every other notification.
final keepAliveNotificationCopyProvider = Provider<KeepAliveCopyResolver>((
  ref,
) {
  return () {
    final l10n = resolveAppLocalizations(
      WidgetsBinding.instance.platformDispatcher.locale,
    );
    return KeepAliveNotificationCopy(
      title: l10n.keepAliveNotificationTitle,
      text: l10n.keepAliveNotificationBody,
      channelName: l10n.keepAliveChannelName,
      channelDescription: l10n.keepAliveChannelDescription,
    );
  };
});

/// The Android foreground service that holds the mux open while agent work
/// is in flight.
///
/// Android freezes a cached process — screen lock included — which stops the
/// Dart isolate and kills the socket; the service keeps the process out of
/// that state and holds a partial wake lock, so a turn started before the
/// phone was pocketed still finishes and notifies. It is scoped to work in
/// flight: the first running (or user-waiting) session starts it, the last
/// one settling stops it after [kKeepAliveLinger].
///
/// The merged fact comes from each enabled backend's notification center —
/// the one owner of the session stream — and is re-read on lifecycle changes
/// so a start Android refused in the background is retried on resume. On a
/// host without the channel this provider is inert.
final keepAliveCoordinatorProvider = Provider<KeepAliveCoordinator>((ref) {
  final coordinator = KeepAliveCoordinator(
    service: ref.watch(keepAliveServiceProvider),
    copy: ref.watch(keepAliveNotificationCopyProvider),
    onFailure: (error, stackTrace) {
      ErrorLogCollector.instance.captureError(
        error,
        stackTrace: stackTrace,
        level: ErrorLogLevel.warning,
        context: const <String, Object?>{'component': 'keepAliveCoordinator'},
      );
      DebugTelemetry.instance?.log(
        'keepAliveCoordinator: $error',
        level: 'warn',
      );
    },
  );

  final centers = <String, AppNotificationCenter>{};
  final centerSubs = <String, ProviderSubscription<AppNotificationCenter>>{};
  final streamSubs = <String, StreamSubscription<bool>>{};

  void recompute() {
    coordinator.update(
      workInFlight: centers.values.any((center) => center.hasWorkInFlight),
    );
  }

  void reconcile() {
    final state =
        ref.read(backendRegistryStateProvider).value ??
        const BackendRegistryState();
    final enabled = <String>{
      for (final backend in state.enabledBackends) backend.id,
    };
    for (final id in centerSubs.keys.toList()) {
      if (enabled.contains(id)) continue;
      unawaited(streamSubs.remove(id)?.cancel());
      centerSubs.remove(id)?.close();
      centers.remove(id);
    }
    for (final backend in state.enabledBackends) {
      if (centerSubs.containsKey(backend.id)) continue;
      centerSubs[backend.id] = ref.listen<AppNotificationCenter>(
        appNotificationCenterProvider(backend.id),
        (previous, next) {
          unawaited(streamSubs[backend.id]?.cancel());
          streamSubs[backend.id] = next.workInFlightChanges.listen(
            (_) => recompute(),
          );
          centers[backend.id] = next;
          recompute();
        },
        fireImmediately: true,
      );
    }
    recompute();
  }

  final registrySub = ref.listen<AsyncValue<BackendRegistryState>>(
    backendRegistryStateProvider,
    (previous, next) => reconcile(),
    fireImmediately: true,
  );
  // The lifecycle signal is the retry point for a start Android refused
  // while the app was in the background.
  final lifecycleSub = ref
      .watch(appLifecycleChangesProvider)
      .listen((_) => recompute());

  ref.onDispose(() {
    registrySub.close();
    unawaited(lifecycleSub.cancel());
    for (final sub in streamSubs.values) {
      unawaited(sub.cancel());
    }
    streamSubs.clear();
    for (final sub in centerSubs.values) {
      sub.close();
    }
    centerSubs.clear();
    centers.clear();
    unawaited(coordinator.dispose());
  });

  return coordinator;
});

/// Merged foreground channel across every enabled backend: the app-root
/// toast host listens here and watches the family, which keeps every
/// connected backend's center (and its session fold) alive for the
/// app's lifetime.
final foregroundNotificationEventsProvider =
    StreamProvider<AppNotificationEvent>((ref) {
      // Trigger the startup boot sweep for posted notification rows.
      ref.watch(postedRowsSweepProvider);
      final controller = StreamController<AppNotificationEvent>.broadcast();
      final centerSubs =
          <String, ProviderSubscription<AppNotificationCenter>>{};
      final eventSubs = <String, StreamSubscription<AppNotificationEvent>>{};

      void reconcile(BackendRegistryState registry) {
        final enabledIds = registry.enabledBackends.map((b) => b.id).toSet();
        // Teardown disabled/removed backends
        for (final id in centerSubs.keys.toList()) {
          if (!enabledIds.contains(id)) {
            unawaited(eventSubs.remove(id)?.cancel());
            centerSubs.remove(id)?.close();
          }
        }
        // Setup newly enabled backends
        for (final backend in registry.enabledBackends) {
          if (!centerSubs.containsKey(backend.id)) {
            final sub = ref.listen<AppNotificationCenter>(
              appNotificationCenterProvider(backend.id),
              (previous, next) {
                unawaited(eventSubs[backend.id]?.cancel());
                eventSubs[backend.id] = next.foregroundEvents.listen((event) {
                  if (!controller.isClosed) controller.add(event);
                });
              },
              fireImmediately: true,
            );
            centerSubs[backend.id] = sub;
          }
        }
      }

      final registrySub = ref.listen<AsyncValue<BackendRegistryState>>(
        backendRegistryStateProvider,
        (previous, next) {
          final state = next.value;
          if (state != null) {
            reconcile(state);
          }
        },
        fireImmediately: true,
      );

      ref.onDispose(() {
        registrySub.close();
        for (final sub in eventSubs.values) {
          unawaited(sub.cancel());
        }
        eventSubs.clear();
        for (final sub in centerSubs.values) {
          sub.close();
        }
        centerSubs.clear();
        unawaited(controller.close());
      });

      return controller.stream;
    });

/// System-notification tap destinations (running-app taps plus cold-start
/// launches), merged so the app root can navigate on either.
final systemNotificationTargetsProvider = StreamProvider<NotificationTarget>(
  (ref) => ref.watch(systemNotifierProvider).targets,
);

/// Chat screen controller (UDF), one per backend.
final chatControllerProvider = Provider.family
    .autoDispose<ChatController, String>((ref, backendId) {
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
        // The session-log archive is a plain HTTP GET, so it rides its own
        // seam rather than the wire repository.
        sessionLogExport: ref.watch(sessionLogExportProvider(backendId)),
      );
      ref.onDispose(controller.dispose);
      return controller;
    });

/// Composer model-seat preference persistence over the shared
/// [LocalStateStore], one scope per backend.
final modelPreferencePersistenceProvider = FutureProvider.family
    .autoDispose<ModelPreferencePersistence?, String>((ref, backendId) async {
      final store = await ref.watch(localStateStoreProvider.future);
      return StoreModelPreferencePersistence(store, 'backend.$backendId');
    });

/// Selected-session persistence over the shared [LocalStateStore], one
/// scope per backend.
final sessionSelectionPersistenceProvider = FutureProvider.family
    .autoDispose<SessionSelectionPersistence?, String>((ref, backendId) async {
      final store = await ref.watch(localStateStoreProvider.future);
      return StoreSessionSelectionPersistence(store, 'backend.$backendId');
    });

/// Chat UI state stream for widgets.
final chatUiStateProvider = StreamProvider.family
    .autoDispose<ChatUiState, String>(
      (ref, backendId) => ref.watch(chatControllerProvider(backendId)).uiState,
    );

/// Every enabled backend's sidebar slice, keyed by the backend the
/// chat surface presents (the slice's active flag follows it). Disabled
/// backends get no slice — dropping their watch releases the backend's
/// chat controller (and its connection) until re-enablement rebuilds it.
/// Each slice is SELECTED out of its host's chat state — only the roster
/// facts, never the timeline — so a slice whose sessions and workspaces
/// did not change compares equal and a streaming publish on ANY backend
/// (each backend's restored session now streams while the app is open)
/// recomputes nothing and rebuilds no surface (the reference web client
/// renders the sidebar from per-node subscriptions, not a whole-tree
/// rebuild). Watching here also keeps every enabled backend's chat
/// controller alive for the app's lifetime.
final backendSessionSlicesProvider = Provider.family
    .autoDispose<List<BackendSessionSlice>, String>((ref, activeBackendId) {
      final registry =
          ref.watch(backendRegistryStateProvider).value ??
          const BackendRegistryState();
      return <BackendSessionSlice>[
        for (final backend in registry.enabledBackends)
          ref.watch(
            chatUiStateProvider(backend.id).select(
              (uiState) => BackendSessionSlice(
                backend: backend,
                active: backend.id == activeBackendId,
                sessions: uiState.value?.sessions ?? const <SessionSummary>[],
                workspaces:
                    uiState.value?.workspaces ?? const <WorkspaceSummary>[],
              ),
            ),
          ),
      ];
    });

/// Models screen controller (UDF), one per backend.
final modelsControllerProvider = Provider.family
    .autoDispose<ModelsController, String>((ref, backendId) {
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

/// Trajectory ledger controller (UDF), one per backend + session.
///
/// The ledger reads the same session timeline window the chat surface does,
/// so the key carries the session id — opening the ledger for another
/// session binds its own controller rather than re-pointing a shared one.
final trajectoryControllerProvider = Provider.family
    .autoDispose<TrajectoryController, ({String backendId, String sessionId})>((
      ref,
      key,
    ) {
      final controller = TrajectoryController(
        ref.watch(chatRepositoryProvider(key.backendId)),
        sessionId: key.sessionId,
      );
      ref.onDispose(controller.dispose);
      return controller;
    });

/// Goal screen controller (UDF), one per backend.
final goalControllerProvider = Provider.family
    .autoDispose<GoalController, String>((ref, backendId) {
      final controller = GoalController(
        ref.watch(chatRepositoryProvider(backendId)),
      );
      ref.onDispose(controller.dispose);
      return controller;
    });

/// Settings screen controller (UDF), one per backend.
final settingsControllerProvider = Provider.family
    .autoDispose<SettingsController, String>((ref, backendId) {
      final controller = SettingsController(
        ref.watch(chatRepositoryProvider(backendId)),
      );
      ref.onDispose(controller.dispose);
      return controller;
    });

/// Provider/model administration controller (UDF), one per backend.
final llmProvidersControllerProvider = Provider.family
    .autoDispose<LlmProvidersController, String>((ref, backendId) {
      final controller = LlmProvidersController(
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

/// Voice-input mode/credentials store (online/offline input selection),
/// persisted next to the ASR model registry.
final onlineAsrSettingsStoreProvider = FutureProvider<OnlineAsrSettingsStore>((
  ref,
) async {
  final modelsDir = await ref.watch(asrModelsDirectoryProvider.future);
  final store = OnlineAsrSettingsStore(
    File('${modelsDir.path}/online_asr_settings.json'),
  );
  await store.load();
  ref.onDispose(store.dispose);
  return store;
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
    diskSpaceChecker: freeDiskSpaceBytes,
  );
});

/// ASR models controller (UDF).
final asrModelsControllerProvider = Provider.autoDispose<AsrModelsController>((
  ref,
) {
  final managerAsync = ref.watch(asrModelManagerProvider);
  final settingsAsync = ref.watch(onlineAsrSettingsStoreProvider);
  final controller = AsrModelsController(
    manager: managerAsync.value,
    cloudSettings: settingsAsync.value,
  );
  ref.onDispose(controller.dispose);
  return controller;
});

/// ASR models UI state stream.
final asrModelsUiStateProvider = StreamProvider.autoDispose<AsrModelsUiState>((
  ref,
) {
  final controller = ref.watch(asrModelsControllerProvider);
  return controller.uiState;
});

/// Voice input controller for speech recognition in the chat composer.
final voiceInputControllerProvider = Provider.autoDispose<VoiceInputController>(
  (ref) {
    final managerAsync = ref.watch(asrModelManagerProvider);
    final manager =
        managerAsync.value ??
        AsrModelManager(
          baseModelsDir: Directory.systemTemp,
          registry: ModelsRegistry(
            registryFile: File(
              '${Directory.systemTemp.path}/tmp_registry.json',
            ),
          ),
        );
    final controller = VoiceInputController(
      manager: manager,
      cloudSettings: ref.watch(onlineAsrSettingsStoreProvider).value,
    );
    ref.onDispose(controller.dispose);
    return controller;
  },
);

/// Voice input UI state stream.
final voiceInputUiStateProvider = StreamProvider.autoDispose<VoiceInputUiState>(
  (ref) {
    final controller = ref.watch(voiceInputControllerProvider);
    return controller.uiState;
  },
);

/// Central Error Log Collector singleton provider.
final errorLogCollectorProvider = Provider<ErrorLogCollector>((ref) {
  return ErrorLogCollector.instance;
});

/// Error logs controller provider (autoDispose).
final errorLogsControllerProvider = Provider.autoDispose<ErrorLogsController>((
  ref,
) {
  final collector = ref.watch(errorLogCollectorProvider);
  final registry = ref.watch(backendRegistryStateProvider).value;
  final activeBackend = registry?.backends
      .where((BackendConfig b) => b.id == registry.activeId)
      .firstOrNull;
  final activeBackendUrl = activeBackend?.baseUri.toString();

  final controller = ErrorLogsController(
    collector: collector,
    activeBackendUrl: activeBackendUrl,
  );
  ref.onDispose(controller.dispose);
  return controller;
});

/// Error logs UI state stream.
final errorLogsUiStateProvider = StreamProvider.autoDispose<ErrorLogsUiState>((
  ref,
) {
  final controller = ref.watch(errorLogsControllerProvider);
  return controller.uiState;
});
