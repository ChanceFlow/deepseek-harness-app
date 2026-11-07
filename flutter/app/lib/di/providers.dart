/// Assembly wiring — the ONLY app file allowed to import the harness
/// adapter (import-gate exemption, mirroring the legacy `app/di`).
///
/// Everything backend-dependent is a provider FAMILY keyed by the
/// backend id: each enabled backend owns a live connection (created when
/// configured, stopped when removed or disabled), a repository, and a
/// notification center — the WebView shell only switches which host's page
/// is on screen, without dropping the other backends' connections or state.
/// Disabling a backend drops it from the watch sets below; with no watcher
/// left, Riverpod's default auto-dispose releases its connection, repository,
/// and center, and re-enabling lazily rebuilds them.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart'
    show AppLifecycleState, WidgetsBinding, WidgetsBindingObserver;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'package:app/config.dart';

import 'dsh_reachability.dart';
import 'http_engine.dart';

import 'package:domain/model/backend.dart';
import 'package:domain/model/connection_state.dart';
import 'package:domain/repository/chat_repository.dart';
import 'package:harness_adapter/harness_adapter.dart';
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

// Re-exported so the shell surfaces backend actions without importing the
// controller file directly.
export '../backends/backend_registry_controller.dart';
import '../backends/backend_registry_controller.dart';
import '../backends/backend_store.dart';
import '../notifications/app_notification_center.dart';
import '../notifications/notification_events.dart' show AppNotificationEvent;
import '../notifications/notification_ledger.dart';
import '../notifications/notification_localizations.dart';
import '../notifications/notification_preferences.dart';
import '../notifications/turn_outcome_probe.dart';
import '../notifications/system_notifier.dart';
import '../local_state/locale_preference.dart';
import '../local_state/local_state_providers.dart';
import '../logging/error_log_collector.dart';
import '../logging/error_log_entry.dart';
import '../platform/keep_alive_coordinator.dart';
import '../platform/keep_alive_service.dart';
import '../platform/network_reconnect.dart';
import '../platform/network_status.dart';

import 'package:dev/dev.dart' show DebugTelemetry;

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
/// store is loaded, attaches the ledger to the [SystemNotifier] and cancels
/// every row the previous process left behind. None of those rows is
/// confirmed by this process — the session may have finished, or the host
/// may be unreachable — and an ongoing row cannot be swiped away, so leaving
/// one is a permanent scar. The first real snapshot re-arms what is still
/// running.
final postedRowsSweepProvider = FutureProvider<void>((ref) async {
  final localStore = await ref.watch(localStateStoreProvider.future);
  final notifier = ref.watch(systemNotifierProvider);
  notifier.attachLedger(StoreNotificationLedger(localStore));
  await notifier.clearUnconfirmedRows();
});

/// The registry's state stream, mapped for widgets.
final backendRegistryStateProvider = StreamProvider<BackendRegistryState>((
  ref,
) async* {
  final controller = await ref.watch(backendRegistryProvider.future);
  yield controller.state;
  yield* controller.uiState;
});

/// The active backend id; empty string before the store loads (the shell
/// renders the empty state rather than a dead page). Stream-based:
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

/// One reachability probe for the shell's host editor.
///
/// A plain value with no lifecycle: each `probe` call builds its own
/// transport for the (URL, trust) pair it is given and closes it. The
/// registry-keyed [dshRpcClientProvider] family cannot serve this — the host
/// editor probes addresses the registry does not contain yet, and it selects
/// certificate trust from the editor rather than the registry.
/// The probe lives in `lib/di/dsh_reachability.dart`, next to the transport
/// seams it reuses.
final dshReachabilityProbeProvider = Provider<DshReachabilityProbe>(
  (ref) => const DshReachabilityProbe(),
);

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
/// description (version, cwd) as a watchable stream. The shell bar's status
/// dot reads it; the keep-alive map above guarantees the member exists for
/// every enabled backend, and a disabled backend's host is never on screen.
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
/// of after up to the 10 s cap. Read by `ShellLifecycle` to keep the binder
/// — and with it the host callback — alive for the app's lifetime.
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

/// Re-syncs every enabled backend when the app returns to the foreground.
///
/// Mobile sockets can stall or drop silently in the background without TCP
/// RST (OS network suspension, sleep, or cellular/Wi-Fi handover). Re-entering
/// foreground re-checks connection health (reconnecting if dead) and re-polls
/// the session and workspace rosters so changes made from Web or other clients
/// while the phone was backgrounded immediately converge.
final appResumeSyncProvider = Provider<void>((ref) {
  final lifecycleSub = ref.watch(appLifecycleChangesProvider).listen((_) {
    if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      return;
    }
    final connections = ref.read(allBackendConnectionsProvider);
    final registry = ref.read(backendRegistryStateProvider).value;
    if (registry == null) return;
    for (final backend in registry.enabledBackends) {
      final manager = connections[backend.id];
      if (manager == null) continue;
      final phase = manager.state.value.phase;
      if (phase == ConnectionPhase.disconnected ||
          phase == ConnectionPhase.reconnecting) {
        manager.reconnectNow();
      } else if (phase == ConnectionPhase.connected) {
        final repo = ref.read(chatRepositoryProvider(backend.id));
        unawaited(repo.refreshSessions());
      }
    }
  });
  ref.onDispose(() => unawaited(lifecycleSub.cancel()));
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

/// Host display labels used by notification copy (the body's host segment).
///
/// Empty by default: a headless test or tool must not build the registry
/// store just to render a notification. `main.dart` overrides it with the
/// registry-derived map, so production copy names the host while tests keep
/// their isolated containers.
final backendLabelsProvider = Provider<Map<String, String>>(
  (ref) => const <String, String>{},
);

/// System (OS-level) notifications, single instance shared by every
/// backend's notification center.
final systemNotifierProvider = Provider<SystemNotifier>((ref) {
  return SystemNotifier();
});

/// Per-backend notification center: folds the session list into
/// notification events and routes them to the foreground toast channel or
/// the background system channel, and reconciles each session's ongoing
/// work notification. The shell keeps every enabled backend's center alive
/// so backgrounded turns still notify.
///
/// The center depends on the repository and the watched-session seam alone:
/// no chat controller, destination, or widget tree takes part in its build,
/// so it runs with nothing native mounted (the WebView shell keeps it alive
/// for the connection keep-alive requirement).
final appNotificationCenterProvider = Provider.family
    .autoDispose<AppNotificationCenter, String>((ref, backendId) {
      final systemNotifier = ref.watch(systemNotifierProvider);
      // The watched-session seam (null in the WebView shell, overridable in
      // tests/future bridges) drives both the selected-turn silence rule and
      // the ongoing suppression; a change invalidates the reconcile.
      final watchedChanges = StreamController<void>.broadcast();
      ref.onDispose(watchedChanges.close);
      ref.listen<String?>(watchedSessionIdProvider(backendId), (_, _) {
        if (!watchedChanges.isClosed) watchedChanges.add(null);
      });
      final repository = ref.watch(chatRepositoryProvider(backendId));
      final center = AppNotificationCenter(
        repository: repository,
        backendId: backendId,
        isForegrounded: () =>
            WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed,
        selectedSessionIdOf: () =>
            ref.read(watchedSessionIdProvider(backendId)),
        onBackground: systemNotifier.show,
        notifier: systemNotifier,
        hostLabelOf: () => ref.read(backendLabelsProvider)[backendId],
        notificationsEnabled: () =>
            ref.read(notificationPreferencesProvider).enabled,
        allowsNotification: (kind) =>
            ref.read(notificationPreferencesProvider).allows(kind),
        turnProbe: RepositoryTurnOutcomeProbe(repository),
        selectionChanges: watchedChanges.stream,
        foregroundChanges: ref.watch(appLifecycleChangesProvider),
      );
      ref.onDispose(center.dispose);
      return center;
    });

/// Which session the user is actually watching on this backend: the input
/// to the selected-turn silence rule and the ongoing-notification
/// suppression.
///
/// The WebView shell owns the conversation and reports no selection or
/// destination fact to the app, so the default answer is always null — a
/// turn completing in any session surfaces, and nothing is ever "watched".
/// This is a seam, not a derived value: a test or a future bridge overrides
/// the per-backend family
/// (`watchedSessionIdProvider(id).overrideWith((ref) => sessionId)`) to
/// supply the fact. It stays a family because every consumer is per-backend
/// and an override must not leak across hosts.
final watchedSessionIdProvider = Provider.family.autoDispose<String?, String>(
  (ref, backendId) => null,
);

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
/// app's own language choice (else the device locale) — the same rule
/// [SystemNotifier] applies to every other notification.
///
/// The preference is read, not watched: the coordinator that consumes this
/// resolver must not gain a dependency on a value that changes, because a
/// rebuild would dispose and restart the foreground service mid-work.
final keepAliveNotificationCopyProvider = Provider<KeepAliveCopyResolver>((
  ref,
) {
  return () {
    final preference = ref.read(appLocalePreferenceProvider).value;
    final l10n = resolveAppLocalizations(effectiveContentLocale(preference));
    return KeepAliveNotificationCopy(
      title: l10n.keepAliveNotificationTitle,
      text: l10n.keepAliveNotificationBody,
      channelName: l10n.keepAliveChannelName,
      channelDescription: l10n.keepAliveChannelDescription,
    );
  };
});

/// Keeps [SystemNotifier]'s copy in step with the app's language choice.
///
/// The notifier composes notification copy outside the widget tree, so an
/// in-app language switch has to be pushed to it — `MaterialApp.locale` does
/// not reach it, and without this the app would show one language while its
/// notifications kept another until the process restarted.
final notificationLocaleSyncProvider = Provider<void>((ref) {
  final notifier = ref.watch(systemNotifierProvider);
  final preference = ref.watch(appLocalePreferenceProvider).value;
  notifier.applyLocale(effectiveContentLocale(preference));
});

/// Whether any enabled backend currently has agent work in flight, emitted
/// on transitions only. The notification-permission ask waits for the first
/// `true` so its prompt arrives with a reason the user can see.
final workInFlightChangesProvider = Provider<Stream<bool>>(
  (ref) => ref.watch(keepAliveCoordinatorProvider).workInFlightChanges,
);

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

/// Merged foreground channel across every enabled backend: `ShellLifecycle`
/// watches the family here, which keeps every connected backend's center (and
/// its session fold) alive for the app's lifetime.
///
/// A plain stream rather than a [StreamProvider]: two completions of the
/// same session are equal events, and a state provider would compare the
/// second one against the first and drop it — the user would never see it.
final foregroundNotificationEventsProvider =
    Provider<Stream<AppNotificationEvent>>((ref) {
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
/// launches). Exposed as a plain stream rather than a [StreamProvider]: a
/// tap is an event, and two taps on the same session — its ongoing row
/// and its completion notice carry the same payload — must both navigate,
/// while a state provider would compare equal and swallow the second.
final systemNotificationTargetsProvider = Provider<Stream<NotificationTarget>>(
  (ref) => ref.watch(systemNotifierProvider).targets,
);

/// Switches the app to the host a notification came from.
///
/// The shell has no per-session surface to deep-link into (there is no
/// bridge into the page), so the host is the navigable fact a payload can
/// carry. A single seam keeps the tap path out of the widget tree and lets
/// tests record the dispatch.
typedef NotificationTargetDispatch = Future<void> Function(
  NotificationTarget target,
);

final notificationTargetDispatchProvider = Provider<NotificationTargetDispatch>(
  (ref) {
    return (target) async {
      final registry = await ref.read(backendRegistryProvider.future);
      registry.onAction(SelectBackend(target.backendId));
    };
  },
);

/// The notification that launched a cold start, when one did.
///
/// `main.dart` overrides this with the notifier's launch target; a warm
/// launch reaches the same seam through [systemNotificationTargetsProvider].
final coldStartNotificationTargetProvider = Provider<NotificationTarget?>(
  (ref) => null,
);
