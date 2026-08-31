/// Disabling a backend releases its connection through the existing
/// keep-alive mechanism: the (id, url) family member loses its last
/// watcher when the registry republishes without that backend in the
/// enabled set, Riverpod disposes the member, and `manager.stop` cancels
/// the event-socket subscriptions. Re-enabling rebuilds the family
/// member lazily. Real store, real controller, real provider chain; only
/// the raw transports are faked (per URL, as elsewhere).
library;

import 'dart:async';
import 'dart:io';

import 'package:app/backends/backend_store.dart';
import 'package:app/config.dart';
import 'package:app/di/providers.dart';
import 'package:app/local_state/local_state_providers.dart';
import 'package:app/local_state/local_state_store.dart';
import 'package:app/notifications/notification_key.dart';
import 'package:app/notifications/notification_ledger.dart';
import 'package:app/notifications/system_notifier.dart';
import 'package:domain/model/connection_state.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _twoBackendsDoc =
    '{"backends": ['
    '{"id": "default", "label": "Laptop", "baseUrl": "http://10.0.2.2:3080", "enabled": true},'
    '{"id": "b1", "label": "Build box", "baseUrl": "http://10.0.2.2:3081", "enabled": true}'
    '], "activeId": "default"}';

const _disabledBackendDoc =
    '{"backends": ['
    '{"id": "default", "label": "Laptop", "baseUrl": "http://10.0.2.2:3080", "enabled": true},'
    '{"id": "b1", "label": "Build box", "baseUrl": "http://10.0.2.2:3081", "enabled": false}'
    '], "activeId": "default"}';

final _laptopUri = Uri.parse('http://10.0.2.2:3080');
final _buildBoxUri = Uri.parse('http://10.0.2.2:3081');

class _FakeRpc implements DshRpcClient {
  @override
  Future<RpcResult> call(
    String endpoint,
    String method,
    Map<String, Object?> payload,
  ) async {
    if (endpoint == 'host.describe') {
      return RpcResult(
        ok: true,
        value: <String, Object?>{
          'version': 'test',
          'cwd': '/tmp',
          'provider': 'deepseek',
          'model': 'test-model',
          'attachedSessions': 0,
          'canOpenPath': true,
        },
      );
    }
    if (endpoint == 'session.list') {
      return RpcResult(
        ok: true,
        value: <String, Object?>{'sessions': <Object?>[]},
      );
    }
    return RpcResult(ok: true, value: <String, Object?>{});
  }

  @override
  Future<void> respond(String rpcId, RpcResult result) async {}
}

/// An event socket that counts opens and reports whether any delivered
/// stream still has a listener — the observable face of
/// `DshConnectionManager.stop` cancelling its subscriptions.
class _TrackingSocket implements DshEventSocket {
  final List<StreamController<ServerRequest>> _delivered =
      <StreamController<ServerRequest>>[];

  int get connects => _delivered.length;

  bool get hasLiveStreams => _delivered.any(
    (StreamController<ServerRequest> controller) => controller.hasListener,
  );

  @override
  Stream<ServerRequest> connect(String path, {void Function()? onOpen}) {
    final controller = StreamController<ServerRequest>.broadcast();
    _delivered.add(controller);
    onOpen?.call();
    return controller.stream;
  }
}

class _RecordingPlugin implements FlutterLocalNotificationsPlugin {
  final cancelled = <({int id, String? tag})>[];

  @override
  Future<void> cancel(int id, {String? tag}) async {
    cancelled.add((id: id, tag: tag));
  }

  @override
  T? resolvePlatformSpecificImplementation<
    T extends FlutterLocalNotificationsPlatform
  >() => null;

  @override
  Future<bool?> initialize(
    InitializationSettings initializationSettings, {
    DidReceiveNotificationResponseCallback? onDidReceiveNotificationResponse,
    DidReceiveBackgroundNotificationResponseCallback?
    onDidReceiveBackgroundNotificationResponse,
  }) async => true;

  @override
  Future<NotificationAppLaunchDetails?>
  getNotificationAppLaunchDetails() async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _waitFor(bool Function() condition, String reason) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) fail('timeout waiting: $reason');
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await pumpEventQueue();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('backend_release_test');
  });

  tearDown(() async {
    // The registry persists unawaited; retry the delete past the
    // atomic-write race like the other backend suites.
    for (var i = 0; i < 50; i++) {
      try {
        await tempDir.delete(recursive: true);
        return;
      } on FileSystemException {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    }
  });

  test(
    'disabling releases the backend connection; re-enabling rebuilds it',
    () async {
      final file = File('${tempDir.path}/backends.json');
      file.writeAsStringSync(_twoBackendsDoc);
      final stateFile = File('${tempDir.path}/local_state.json');
      final localStore = LocalStateStore(stateFile);
      await localStore.load();
      final laptopSocket = _TrackingSocket();
      final buildBoxSocket = _TrackingSocket();
      final container = ProviderContainer(
        overrides: [
          backendStoreProvider.overrideWith(
            (Ref ref) async => BackendStore(file, seedBaseUrl: kDshBaseUrl),
          ),
          localStateStoreProvider.overrideWith((ref) async => localStore),
          dshRpcClientProvider(_laptopUri).overrideWithValue(_FakeRpc()),
          dshRpcClientProvider(_buildBoxUri).overrideWithValue(_FakeRpc()),
          dshEventSocketProvider(_laptopUri).overrideWithValue(laptopSocket),
          dshEventSocketProvider(_buildBoxUri)
              .overrideWithValue(buildBoxSocket),
        ],
      );
      addTearDown(container.dispose);

      // Streams need a persistent listener; the keep-alive map is what
      // the app surfaces watch.
      container.listen(allBackendConnectionsProvider, (_, _) {});

      final registry = await container.read(backendRegistryProvider.future);

      // Every enabled backend connects.
      await _waitFor(
        () =>
            container.read(allBackendConnectionsProvider).length == 2 &&
            laptopSocket.connects > 0 &&
            buildBoxSocket.connects > 0,
        'both backends connect',
      );
      await _waitFor(
        () =>
            container
                .read(allBackendConnectionsProvider)['b1']!
                .state
                .value
                .phase ==
            ConnectionPhase.connected,
        'the build box reaches connected',
      );

      final keptManager = container.read(
        allBackendConnectionsProvider,
      )['default']!;
      final releasedManager = container.read(
        allBackendConnectionsProvider,
      )['b1']!;

      registry.onAction(const SetBackendEnabled('b1', false));

      // The disabled backend drops out of the keep-alive map, its
      // subscriptions are cancelled, and the active backend's connection
      // is untouched.
      await _waitFor(
        () => !container.read(allBackendConnectionsProvider).containsKey('b1'),
        'the build box leaves the keep-alive map',
      );
      await _waitFor(
        () => !buildBoxSocket.hasLiveStreams,
        'the build box connection stops (no live streams)',
      );
      expect(
        identical(
          keptManager,
          container.read(allBackendConnectionsProvider)['default'],
        ),
        isTrue,
        reason: 'disabling one backend must not disturb the other',
      );
      expect(laptopSocket.hasLiveStreams, isTrue);

      // Re-enabling rebuilds the member lazily: a fresh manager connects.
      registry.onAction(const SetBackendEnabled('b1', true));
      await _waitFor(
        () => container.read(allBackendConnectionsProvider)['b1'] != null,
        'the build box returns to the keep-alive map',
      );
      final rebuilt = container.read(allBackendConnectionsProvider)['b1']!;
      expect(
        identical(rebuilt, releasedManager),
        isFalse,
        reason: 'the rebuilt member is a fresh connection',
      );
      await _waitFor(
        () => buildBoxSocket.hasLiveStreams,
        'the rebuilt member reconnects',
      );
    },
  );

  test('disabling the active backend moves the chat surface away', () async {
    final file = File('${tempDir.path}/backends2.json');
    file.writeAsStringSync(_twoBackendsDoc);
    final stateFile = File('${tempDir.path}/local_state2.json');
    final localStore = LocalStateStore(stateFile);
    await localStore.load();
    final laptopSocket = _TrackingSocket();
    final buildBoxSocket = _TrackingSocket();
    final container = ProviderContainer(
      overrides: [
        backendStoreProvider.overrideWith(
          (Ref ref) async => BackendStore(file, seedBaseUrl: kDshBaseUrl),
        ),
        localStateStoreProvider.overrideWith((ref) async => localStore),
        dshRpcClientProvider(_laptopUri).overrideWithValue(_FakeRpc()),
        dshRpcClientProvider(_buildBoxUri).overrideWithValue(_FakeRpc()),
        dshEventSocketProvider(_laptopUri).overrideWithValue(laptopSocket),
        dshEventSocketProvider(_buildBoxUri).overrideWithValue(buildBoxSocket),
      ],
    );
    addTearDown(container.dispose);
    container.listen(allBackendConnectionsProvider, (_, _) {});
    final activeIds = <String?>[];
    final activeSub = container.listen(
      activeBackendIdProvider,
      (_, next) => activeIds.add(next.value),
    );
    addTearDown(activeSub.close);

    final registry = await container.read(backendRegistryProvider.future);
    await _waitFor(
      () => registry.state.activeId == 'default' && laptopSocket.connects > 0,
      'the seed backend connects',
    );

    // The chat surface's backend is switched off: the active id
    // relocates and the disabled host's sockets fall silent.
    registry.onAction(const SetBackendEnabled('default', false));
    await _waitFor(
      () => activeIds.lastOrNull == 'b1',
      'the active backend stream reports the relocated id',
    );
    await _waitFor(
      () => !laptopSocket.hasLiveStreams,
      'the disabled active backend releases its connection',
    );
    expect(container.read(allBackendConnectionsProvider).keys.toList(), ['b1']);
    expect(buildBoxSocket.hasLiveStreams, isTrue);
    expect(registry.state.enabledBackends.map((b) => b.id), ['b1']);
  });

  test('cascade: disabling a backend drops its center, slices, controller, and connection without leaking', () async {
    final file = File('${tempDir.path}/backends_cascade.json');
    file.writeAsStringSync(_twoBackendsDoc);
    final stateFile = File('${tempDir.path}/local_state_cascade.json');
    final localStore = LocalStateStore(stateFile);
    await localStore.load();
    final laptopSocket = _TrackingSocket();
    final buildBoxSocket = _TrackingSocket();
    final plugin = _RecordingPlugin();
    final notifier = SystemNotifier(plugin: plugin);

    final container = ProviderContainer(
      overrides: [
        backendStoreProvider.overrideWith(
          (Ref ref) async => BackendStore(file, seedBaseUrl: kDshBaseUrl),
        ),
        localStateStoreProvider.overrideWith((ref) async => localStore),
        systemNotifierProvider.overrideWithValue(notifier),
        dshRpcClientProvider(_laptopUri).overrideWithValue(_FakeRpc()),
        dshRpcClientProvider(_buildBoxUri).overrideWithValue(_FakeRpc()),
        dshEventSocketProvider(_laptopUri).overrideWithValue(laptopSocket),
        dshEventSocketProvider(_buildBoxUri).overrideWithValue(buildBoxSocket),
      ],
    );
    addTearDown(container.dispose);

    // Keep all connections, notification centers, and sidebar slices alive.
    container.listen(allBackendConnectionsProvider, (_, _) {});
    container.listen(foregroundNotificationEventsProvider, (_, _) {});
    container.listen(backendSessionSlicesProvider('default'), (_, _) {});

    final registry = await container.read(backendRegistryProvider.future);

    // Both backends start connected.
    await _waitFor(
      () =>
          container.read(allBackendConnectionsProvider).length == 2 &&
          laptopSocket.connects > 0 &&
          buildBoxSocket.connects > 0,
      'both backends connect and have live sockets',
    );

    // Disabling backend B (build box) drops its center, sidebar slice, and connection.
    registry.onAction(const SetBackendEnabled('b1', false));

    await _waitFor(
      () => !container.read(allBackendConnectionsProvider).containsKey('b1'),
      'build box leaves allBackendConnectionsProvider',
    );
    await _waitFor(
      () => !buildBoxSocket.hasLiveStreams,
      'build box drops all live streams / connection closed',
    );

    // Backend A (default) remains live and connected.
    expect(laptopSocket.hasLiveStreams, isTrue);
    expect(
      container.read(allBackendConnectionsProvider).containsKey('default'),
      isTrue,
    );

    // Re-enabling backend B restores its connection cleanly.
    registry.onAction(const SetBackendEnabled('b1', true));
    await _waitFor(
      () => container.read(allBackendConnectionsProvider)['b1'] != null,
      'build box returns to allBackendConnectionsProvider',
    );
    await _waitFor(
      () => buildBoxSocket.hasLiveStreams,
      'build box reconnects event socket',
    );
  });

  test('startup boot sweep cancels leftover rows for disabled and removed backends', () async {
    final file = File('${tempDir.path}/backends_sweep.json');
    file.writeAsStringSync(_disabledBackendDoc);
    final stateFile = File('${tempDir.path}/local_state_sweep.json');
    final localStore = LocalStateStore(stateFile);
    await localStore.load();

    // Seed the ledger in localStore with entries for:
    // 1. 'default' (enabled in backends_sweep.json)
    // 2. 'b1' (disabled in backends_sweep.json)
    // 3. 'b_removed' (not in backends_sweep.json)
    final ledger = StoreNotificationLedger(localStore);
    ledger.record(backendId: 'default', sessionId: 's1');
    ledger.record(backendId: 'b1', sessionId: 's2');
    ledger.record(backendId: 'b_removed', sessionId: 's3');
    await localStore.flush();

    final plugin = _RecordingPlugin();
    final notifier = SystemNotifier(plugin: plugin);
    await notifier.initialize();
    final laptopSocket = _TrackingSocket();

    final container = ProviderContainer(
      overrides: [
        backendStoreProvider.overrideWith(
          (Ref ref) async => BackendStore(file, seedBaseUrl: kDshBaseUrl),
        ),
        localStateStoreProvider.overrideWith((ref) async => localStore),
        systemNotifierProvider.overrideWithValue(notifier),
        dshRpcClientProvider(_laptopUri).overrideWithValue(_FakeRpc()),
        dshEventSocketProvider(_laptopUri).overrideWithValue(laptopSocket),
      ],
    );
    addTearDown(container.dispose);

    // Await the startup boot sweep.
    await container.read(postedRowsSweepProvider.future);

    // Cancel must be issued for b1 and b_removed, but NOT for default.
    expect(plugin.cancelled, [
      (id: workingNotificationId('b1', 's2'), tag: 'b1/s2'),
      (id: workingNotificationId('b_removed', 's3'), tag: 'b_removed/s3'),
    ]);

    // In the ledger, only the enabled backend's row remains.
    expect(ledger.readEntries(), [
      const NotificationRowEntry(backendId: 'default', sessionId: 's1'),
    ]);
  });
}
