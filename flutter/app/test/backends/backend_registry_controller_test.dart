/// BackendRegistryController behavior: the guarded mutations (fail
/// loud on the state, never a silent no-op), persistence through the
/// real store, the replay-seeded stream, and the corrupt-document
/// fallback.
library;

import 'dart:io';

import 'package:app/backends/backend_registry_controller.dart';
import 'package:app/backends/backend_store.dart';
import 'package:domain/model/backend.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('backend_registry_test');
  });

  tearDown(() async {
    // The registry persists unawaited; the atomic write's temp+rename
    // can race the recursive delete (errno 39, directory not empty) —
    // retry until the write lands.
    for (var i = 0; i < 50; i++) {
      try {
        await tempDir.delete(recursive: true);
        return;
      } on FileSystemException {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    }
  });

  File fileFor(String name) => File('${tempDir.path}/$name.json');

  BackendStore storeFor(String name, {String? document}) {
    final file = fileFor(name);
    if (document != null) file.writeAsStringSync(document);
    return BackendStore(file, seedBaseUrl: 'http://10.0.2.2:3080');
  }

  /// Waits for the async load to land: the replay stream's first event
  /// is the pre-load empty state, so the load shows up as the first
  /// state with a backend list (the corrupt-document fallback's seed
  /// included).
  Future<BackendRegistryState> loadedState(
    BackendRegistryController controller,
  ) async {
    await for (final state in controller.uiState) {
      if (state.backends.isNotEmpty) return state;
    }
    throw StateError('registry stream closed before load');
  }

  /// The registry persists unawaited (exists-check → create → write →
  /// rename is several real IO turns); a round-trip read polls the
  /// document until the mutation's bytes are on disk.
  Future<void> letPersistLand(File file, String untilContains) async {
    for (var i = 0; i < 200; i++) {
      if (file.existsSync() &&
          file.readAsStringSync().contains(untilContains)) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    fail('persist never landed: ${file.path}');
  }

  test('loads the persisted document and latches a valid active id', () async {
    final controller = BackendRegistryController(
      storeFor(
        'load',
        document:
            '{"backends": ['
            '{"id": "default", "label": "Laptop", "baseUrl": "http://10.0.2.2:3080"},'
            '{"id": "b1", "label": "Build box", "baseUrl": "http://10.0.2.2:3081"}'
            '], "activeId": "b1"}',
      ),
    );
    addTearDown(controller.dispose);

    final state = await loadedState(controller);
    expect(state.backends, hasLength(2));
    expect(state.activeId, 'b1');
    expect(state.errorMessage, isNull);
    // A document predating the `enabled` key decodes every entry as
    // enabled.
    expect(state.backends.every((b) => b.enabled), isTrue);
  });

  test('a dangling active id falls back to the first backend', () async {
    final controller = BackendRegistryController(
      storeFor(
        'dangling',
        document:
            '{"backends": ['
            '{"id": "default", "label": "Laptop", "baseUrl": "http://10.0.2.2:3080"}'
            '], "activeId": "gone"}',
      ),
    );
    addTearDown(controller.dispose);

    final state = await loadedState(controller);
    expect(state.activeId, 'default');
  });

  test(
    'a corrupt document falls back to the seed with the error on state',
    () async {
      final controller = BackendRegistryController(
        storeFor('corrupt', document: '{"backends": ['),
      );
      addTearDown(controller.dispose);

      final state = await loadedState(controller);
      expect(state.backends.single.id, 'default');
      expect(state.errorMessage, equals(BackendErrorCode.invalidJson.name));
    },
  );

  test('add appends, persists, and selects nothing', () async {
    final store = storeFor('add');
    final controller = BackendRegistryController(store);
    addTearDown(controller.dispose);
    await loadedState(controller);

    controller.onAction(const AddBackend('Build box', 'http://10.0.2.2:3081'));
    await letPersistLand(fileFor('add'), 'Build box');

    final state = controller.state;
    expect(state.backends, hasLength(2));
    expect(state.backends.last.label, 'Build box');
    expect(state.activeId, 'default');
    expect(state.errorMessage, isNull);

    final reloaded = BackendRegistryController(store);
    addTearDown(reloaded.dispose);
    final roundTrip = await loadedState(reloaded);
    expect(roundTrip.backends, hasLength(2));
    expect(roundTrip.backends.last.label, 'Build box');
  });

  test(
    'add guards: bad URL and empty label refuse with the error on state',
    () async {
      final controller = BackendRegistryController(storeFor('guards'));
      addTearDown(controller.dispose);
      await loadedState(controller);
      final before = controller.state;

      controller.onAction(const AddBackend('Bad', 'ftp://nope'));
      expect(
        controller.state.errorMessage,
        equals('${BackendErrorCode.badBaseUrl.name}:ftp://nope'),
      );
      expect(controller.state.backends, before.backends);

      controller.onAction(const AddBackend('  ', 'http://10.0.2.2:3081'));
      expect(
        controller.state.errorMessage,
        equals(BackendErrorCode.emptyLabel.name),
      );

      // The next successful mutation clears the refusal.
      controller.onAction(const AddBackend('OK', 'http://10.0.2.2:3081'));
      expect(controller.state.errorMessage, isNull);
      expect(controller.state.backends, hasLength(2));
    },
  );

  test('rename and URL repoint update the entry and persist', () async {
    final store = storeFor('rename');
    final controller = BackendRegistryController(store);
    addTearDown(controller.dispose);
    await loadedState(controller);

    controller.onAction(const RenameBackend('default', 'Laptop host'));
    controller.onAction(
      const UpdateBackendUrl('default', 'http://10.0.2.2:3082'),
    );
    await letPersistLand(fileFor('rename'), 'Laptop host');

    final entry = controller.state.backends.single;
    expect(entry.label, 'Laptop host');
    expect(entry.baseUri, Uri.parse('http://10.0.2.2:3082'));

    final reloaded = BackendRegistryController(store);
    addTearDown(reloaded.dispose);
    expect((await loadedState(reloaded)).backends.single.label, 'Laptop host');
  });

  test(
    'remove guards: the last backend and the active one are refused',
    () async {
      final controller = BackendRegistryController(
        storeFor(
          'remove',
          document:
              '{"backends": ['
              '{"id": "default", "label": "Laptop", "baseUrl": "http://10.0.2.2:3080"},'
              '{"id": "b1", "label": "Build box", "baseUrl": "http://10.0.2.2:3081"}'
              '], "activeId": "default"}',
        ),
      );
      addTearDown(controller.dispose);
      await loadedState(controller);

      controller.onAction(const RemoveBackend('default'));
      expect(
        controller.state.errorMessage,
        equals(BackendErrorCode.removeActiveFirst.name),
      );
      expect(controller.state.backends, hasLength(2));

      controller.onAction(const RemoveBackend('unknown-id'));
      expect(controller.state.backends, hasLength(2));

      controller.onAction(const RemoveBackend('b1'));
      expect(controller.state.errorMessage, isNull);
      expect(controller.state.backends, hasLength(1));

      controller.onAction(const RemoveBackend('default'));
      expect(
        controller.state.errorMessage,
        equals(BackendErrorCode.cannotRemoveLast.name),
      );
      expect(controller.state.backends, hasLength(1));
    },
  );

  test('select switches the active id and persists it', () async {
    final store = storeFor(
      'select',
      document:
          '{"backends": ['
          '{"id": "default", "label": "Laptop", "baseUrl": "http://10.0.2.2:3080"},'
          '{"id": "b1", "label": "Build box", "baseUrl": "http://10.0.2.2:3081"}'
          '], "activeId": "default"}',
    );
    final controller = BackendRegistryController(store);
    addTearDown(controller.dispose);
    await loadedState(controller);

    controller.onAction(const SelectBackend('b1'));
    expect(controller.state.activeId, 'b1');
    // Selecting the already-active backend is a no-op, not an error.
    controller.onAction(const SelectBackend('b1'));
    expect(controller.state.activeId, 'b1');
    expect(controller.state.errorMessage, isNull);

    controller.onAction(const SelectBackend('unknown'));
    expect(
      controller.state.errorMessage,
      equals('${BackendErrorCode.unknownBackend.name}:unknown'),
    );
    expect(controller.state.activeId, 'b1');

    await letPersistLand(fileFor('select'), '"activeId":"b1"');
    final reloaded = BackendRegistryController(store);
    addTearDown(reloaded.dispose);
    expect((await loadedState(reloaded)).activeId, 'b1');
  });

  test(
    'disabling the active backend moves active to the next enabled one',
    () async {
      final store = storeFor(
        'disable-relocate',
        document:
            '{"backends": ['
            '{"id": "default", "label": "Laptop", "baseUrl": "http://10.0.2.2:3080", "enabled": true},'
            '{"id": "b1", "label": "Build box", "baseUrl": "http://10.0.2.2:3081", "enabled": true}'
            '], "activeId": "default"}',
      );
      final controller = BackendRegistryController(store);
      addTearDown(controller.dispose);
      await loadedState(controller);

      controller.onAction(const SetBackendEnabled('default', false));
      final state = controller.state;
      expect(state.backends, hasLength(2));
      expect(state.backends.first.enabled, isFalse);
      expect(state.activeId, 'b1');
      expect(state.errorMessage, isNull);

      // Disabling the now-active backend leaves no enabled backend: the
      // active id becomes null.
      controller.onAction(const SetBackendEnabled('b1', false));
      expect(controller.state.enabledBackends, isEmpty);
      expect(controller.state.activeId, isNull);

      // Re-enabling a backend while none is active activates it.
      controller.onAction(const SetBackendEnabled('b1', true));
      expect(controller.state.activeId, 'b1');

      // Toggling a backend's current state is a silent no-op, not an
      // error.
      controller.onAction(const SetBackendEnabled('b1', true));
      expect(controller.state.errorMessage, isNull);
    },
  );

  test('disabling a non-active backend keeps the active id', () async {
    final controller = BackendRegistryController(
      storeFor(
        'disable-standby',
        document:
            '{"backends": ['
            '{"id": "default", "label": "Laptop", "baseUrl": "http://10.0.2.2:3080"},'
            '{"id": "b1", "label": "Build box", "baseUrl": "http://10.0.2.2:3081"}'
            '], "activeId": "default"}',
      ),
    );
    addTearDown(controller.dispose);
    await loadedState(controller);

    controller.onAction(const SetBackendEnabled('b1', false));
    expect(controller.state.activeId, 'default');
    expect(controller.state.backends.last.enabled, isFalse);
  });

  test('select refuses a disabled backend and an unknown id', () async {
    final controller = BackendRegistryController(
      storeFor(
        'select-disabled',
        document:
            '{"backends": ['
            '{"id": "default", "label": "Laptop", "baseUrl": "http://10.0.2.2:3080"},'
            '{"id": "b1", "label": "Build box", "baseUrl": "http://10.0.2.2:3081", "enabled": false}'
            '], "activeId": "default"}',
      ),
    );
    addTearDown(controller.dispose);
    await loadedState(controller);

    controller.onAction(const SelectBackend('b1'));
    expect(controller.state.activeId, 'default');
    expect(
      controller.state.errorMessage,
      equals(BackendErrorCode.backendDisabled.name),
    );

    controller.onAction(const SetBackendEnabled('unknown', false));
    expect(
      controller.state.errorMessage,
      equals('${BackendErrorCode.unknownBackend.name}:unknown'),
    );
    expect(controller.state.backends, hasLength(2));
  });

  test(
    'setEnabled persists: the flag and the relocated active survive reload',
    () async {
      final store = storeFor(
        'disable-persist',
        document:
            '{"backends": ['
            '{"id": "default", "label": "Laptop", "baseUrl": "http://10.0.2.2:3080", "enabled": true},'
            '{"id": "b1", "label": "Build box", "baseUrl": "http://10.0.2.2:3081", "enabled": true}'
            '], "activeId": "default"}',
      );
      final controller = BackendRegistryController(store);
      addTearDown(controller.dispose);
      await loadedState(controller);

      controller.onAction(const SetBackendEnabled('default', false));
      await letPersistLand(fileFor('disable-persist'), '"enabled":false');

      final reloaded = BackendRegistryController(store);
      addTearDown(reloaded.dispose);
      final state = await loadedState(reloaded);
      expect(state.backends.first.enabled, isFalse);
      // The relocated active id persisted alongside the flag.
      expect(state.activeId, 'b1');
    },
  );

  test(
    'a load whose active id points at a disabled backend relocates it',
    () async {
      final controller = BackendRegistryController(
        storeFor(
          'load-reconcile',
          document:
              '{"backends": ['
              '{"id": "default", "label": "Laptop", "baseUrl": "http://10.0.2.2:3080", "enabled": false},'
              '{"id": "b1", "label": "Build box", "baseUrl": "http://10.0.2.2:3081", "enabled": true}'
              '], "activeId": "default"}',
        ),
      );
      addTearDown(controller.dispose);

      final state = await loadedState(controller);
      expect(state.activeId, 'b1');
    },
  );

  test('a load with every backend disabled yields no active backend', () async {
    final controller = BackendRegistryController(
      storeFor(
        'all-disabled',
        document:
            '{"backends": ['
            '{"id": "default", "label": "Laptop", "baseUrl": "http://10.0.2.2:3080", "enabled": false},'
            '{"id": "b1", "label": "Build box", "baseUrl": "http://10.0.2.2:3081", "enabled": false}'
            '], "activeId": "default"}',
      ),
    );
    addTearDown(controller.dispose);

    final state = await loadedState(controller);
    expect(state.activeId, isNull);
    expect(state.enabledBackends, isEmpty);
  });

  test(
    'a new backend is added enabled and does not steal the active id',
    () async {
      final controller = BackendRegistryController(storeFor('add-enabled'));
      addTearDown(controller.dispose);
      await loadedState(controller);

      controller.onAction(
        const AddBackend('Build box', 'http://10.0.2.2:3081'),
      );
      expect(controller.state.activeId, 'default');
      expect(controller.state.backends.last.enabled, isTrue);
    },
  );

  test(
    'the state stream replays the current state to late subscribers',
    () async {
      final controller = BackendRegistryController(storeFor('replay'));
      addTearDown(controller.dispose);
      await loadedState(controller);

      // A subscriber attaching after the async load still receives the
      // loaded state first (the registry load predates most watchers).
      final first = await controller.uiState.first;
      expect(first.backends.single.id, 'default');
    },
  );
}
