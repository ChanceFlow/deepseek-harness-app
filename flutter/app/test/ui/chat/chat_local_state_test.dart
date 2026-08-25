/// Model-seat preference persistence: roundtrips through the shared
/// [LocalStateStore], survives a fresh store over the same document, and
/// scopes keys per backend so hosts with different catalogs never read
/// each other's remembered routes.
library;

import 'dart:io';

import 'package:app/local_state/local_state_store.dart';
import 'package:app/ui/chat/chat_local_state.dart';
import 'package:domain/model/model_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('model_prefs_test');
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  test(
    'write roundtrips and a fresh store over the file reads it back',
    () async {
      final file = File('${tempDir.path}/local_state.json');
      final store = LocalStateStore(file);
      await store.load();
      final persistence = StoreModelPreferencePersistence(store, 'backend.b1');

      await persistence.write(
        const ModelSeatPreferences(
          lastSelection: ModelSelection(
            provider: 'deepseek-official',
            model: 'deepseek-reasoner',
            reasoningEffort: 'high',
          ),
          effortByRoute: <String, String>{
            'deepseek-official/deepseek-reasoner': 'high',
            'deepseek-official/deepseek-chat': 'off',
          },
        ),
      );
      await store.flush();

      final reopened = LocalStateStore(file);
      await reopened.load();
      final read = await StoreModelPreferencePersistence(
        reopened,
        'backend.b1',
      ).read();
      expect(
        read.lastSelection,
        const ModelSelection(
          provider: 'deepseek-official',
          model: 'deepseek-reasoner',
          reasoningEffort: 'high',
        ),
      );
      expect(read.effortFor('deepseek-official', 'deepseek-reasoner'), 'high');
      expect(read.effortFor('deepseek-official', 'deepseek-chat'), 'off');
      expect(read.effortFor('other', 'model'), isNull);
    },
  );

  test('scopes never see each other keys', () async {
    final file = File('${tempDir.path}/local_state.json');
    final store = LocalStateStore(file);
    await store.load();
    final mine = StoreModelPreferencePersistence(store, 'backend.b1');
    final other = StoreModelPreferencePersistence(store, 'backend.b2');

    await mine.write(
      const ModelSeatPreferences(
        lastSelection: ModelSelection(provider: 'p', model: 'm'),
      ),
    );
    expect(await other.read(), const ModelSeatPreferences());
    expect(await mine.read(), isNot(const ModelSeatPreferences()));
  });

  test('remembering folds one selection into the preferences', () {
    const prefs = ModelSeatPreferences();
    const first = ModelSelection(
      provider: 'p',
      model: 'm1',
      reasoningEffort: 'high',
    );
    const second = ModelSelection(provider: 'p', model: 'm2');
    final remembered = prefs.remembering(first).remembering(second);
    expect(remembered.lastSelection, second);
    // m1 keeps its own remembered effort; m2 chose none (provider
    // default), so it has no entry and the model default applies.
    expect(remembered.effortFor('p', 'm1'), 'high');
    expect(remembered.effortFor('p', 'm2'), isNull);
  });

  test('selected-session persistence roundtrips per backend scope', () async {
    final file = File('${tempDir.path}/local_state.json');
    final store = LocalStateStore(file);
    await store.load();

    final b1 = StoreSessionSelectionPersistence(store, 'backend.b1');
    final b2 = StoreSessionSelectionPersistence(store, 'backend.b2');
    await b1.writeSelectedSession('session-1');
    expect(await b1.readSelectedSession(), 'session-1');
    // The other backend's seat restores its own session, not b1's.
    expect(await b2.readSelectedSession(), isNull);

    await store.flush();
    final reopened = LocalStateStore(file);
    await reopened.load();
    expect(
      await StoreSessionSelectionPersistence(
        reopened,
        'backend.b1',
      ).readSelectedSession(),
      'session-1',
    );

    // Clearing (session removed) deletes rather than storing empty.
    await b1.writeSelectedSession(null);
    expect(await b1.readSelectedSession(), isNull);
  });
}
