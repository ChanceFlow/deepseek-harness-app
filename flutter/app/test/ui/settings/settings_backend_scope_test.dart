/// SettingsBackendScope notifier behavior: follows the chat-active
/// backend until pinned, holds a pinned scope across chat-active
/// switches, unpins on follow-active, and resets to follow-active when
/// the pinned backend leaves the registry. The registry runs its real
/// controller over a temp-file store, so the scope rides the real
/// provider chain (store → controller → state providers → notifier).
library;

import 'dart:io';

import 'package:app/backends/backend_store.dart';
import 'package:app/config.dart';
import 'package:app/di/providers.dart';
import 'package:app/ui/settings/settings_backend_scope.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Two configured backends, Laptop active.
const _twoBackendsDoc =
    '{"backends": ['
    '{"id": "default", "label": "Laptop", "baseUrl": "http://10.0.2.2:3080"},'
    '{"id": "b1", "label": "Build box", "baseUrl": "http://10.0.2.2:3081"}'
    '], "activeId": "default"}';

class _Harness {
  _Harness(this.registry, this.container);

  final BackendRegistryController registry;
  final ProviderContainer container;
}

/// A registry over a temp-file store seeded with [_twoBackendsDoc], the
/// container wired to the real controller. The scope rides stream
/// providers, which only flow while a persistent listener holds them
/// open (a bare read is a transient subscription), so the harness keeps
/// one listener on the scope for the whole test and settles the chain
/// past the load.
Future<_Harness> _pump() async {
  final dir = Directory.systemTemp.createTempSync('settings_scope_test');
  // The registry persists unawaited; the atomic write's temp+rename can
  // race a plain recursive delete (errno 39) — retry until it lands.
  addTearDown(() async {
    for (var i = 0; i < 50; i++) {
      try {
        dir.deleteSync(recursive: true);
        return;
      } on FileSystemException {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    }
  });
  final file = File('${dir.path}/backends.json');
  file.writeAsStringSync(_twoBackendsDoc);
  final registry = BackendRegistryController(
    BackendStore(file, seedBaseUrl: kDshBaseUrl),
  );
  addTearDown(registry.dispose);
  final container = ProviderContainer(
    overrides: [
      backendRegistryProvider.overrideWithValue(AsyncValue.data(registry)),
    ],
  );
  // Teardown runs last-registered first: the scope listener closes
  // before the container, which disposes before the registry.
  addTearDown(container.dispose);
  final scopeSub = container.listen(settingsBackendScopeProvider, (_, __) {});
  addTearDown(scopeSub.close);
  await _waitLoaded(registry);
  await _flush();
  return _Harness(registry, container);
}

/// The controller's own state lands synchronously inside its async
/// load; poll it until the document decoded.
Future<void> _waitLoaded(BackendRegistryController registry) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (registry.state.backends.isEmpty) {
    if (DateTime.now().isAfter(deadline)) {
      fail('registry never loaded its document');
    }
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}

/// Lets the broadcast-stream delivery and the dependent provider
/// recomputations settle: each zero-delay await turns the event loop
/// once, and each hop (registry publish → stream provider yield →
/// notifier rebuild) is one such turn.
Future<void> _flush() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// Mutates the registry and settles the scope chain.
Future<void> _act(_Harness h, BackendAction action) async {
  h.registry.onAction(action);
  await _flush();
}

void main() {
  test('scope follows the chat-active backend until pinned', () async {
    final h = await _pump();

    expect(h.container.read(settingsBackendScopeProvider), 'default');
    expect(
      h.container.read(settingsBackendScopeProvider.notifier).isPinned,
      isFalse,
    );

    await _act(h, const SelectBackend('b1'));
    expect(h.container.read(settingsBackendScopeProvider), 'b1');
  });

  test('pinned scope survives chat-active switches', () async {
    final h = await _pump();
    h.container.read(settingsBackendScopeProvider.notifier).select('b1');
    expect(h.container.read(settingsBackendScopeProvider), 'b1');

    // The chat-active backend moves away and back; the pin holds both
    // ways — the settings scope is independent of chat.
    await _act(h, const SelectBackend('b1'));
    expect(h.container.read(settingsBackendScopeProvider), 'b1');
    await _act(h, const SelectBackend('default'));
    expect(h.container.read(settingsBackendScopeProvider), 'b1');
    expect(
      h.container.read(settingsBackendScopeProvider.notifier).isPinned,
      isTrue,
    );
  });

  test('followActive unpins to the chat-active backend', () async {
    final h = await _pump();
    final notifier = h.container.read(settingsBackendScopeProvider.notifier);

    notifier.select('b1');
    await _act(h, const SelectBackend('b1'));

    notifier.followActive();
    expect(h.container.read(settingsBackendScopeProvider), 'b1');
    expect(notifier.isPinned, isFalse);

    // Following again: the scope tracks the chat-active backend.
    await _act(h, const SelectBackend('default'));
    expect(h.container.read(settingsBackendScopeProvider), 'default');
  });

  test(
    'removing the pinned backend resets the scope to follow-active',
    () async {
      final h = await _pump();
      final notifier = h.container.read(settingsBackendScopeProvider.notifier);

      notifier.select('b1');
      expect(h.container.read(settingsBackendScopeProvider), 'b1');

      await _act(h, const RemoveBackend('b1'));
      expect(h.container.read(settingsBackendScopeProvider), 'default');
      expect(notifier.isPinned, isFalse);
    },
  );

  test(
    'disabling the pinned backend resets the scope to follow-active',
    () async {
      final h = await _pump();
      final notifier = h.container.read(settingsBackendScopeProvider.notifier);

      notifier.select('b1');
      expect(h.container.read(settingsBackendScopeProvider), 'b1');

      // A disabled backend has no live connection for the host pages to
      // describe; the scope falls back to following the (enabled)
      // active one.
      await _act(h, const SetBackendEnabled('b1', false));
      expect(h.container.read(settingsBackendScopeProvider), 'default');
      expect(notifier.isPinned, isFalse);

      // Re-enabling does not pull the scope back to the old pin.
      await _act(h, const SetBackendEnabled('b1', true));
      expect(h.container.read(settingsBackendScopeProvider), 'default');
    },
  );

  test('disabling every backend empties the scope', () async {
    final h = await _pump();

    await _act(h, const SetBackendEnabled('default', false));
    // The active id relocated to b1; the scope follows.
    expect(h.container.read(settingsBackendScopeProvider), 'b1');

    await _act(h, const SetBackendEnabled('b1', false));
    expect(h.container.read(settingsBackendScopeProvider), '');
  });
}
