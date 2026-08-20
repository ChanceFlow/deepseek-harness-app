/// LocalStateStore behavior: roundtrips, null deletes, corrupt-file
/// recovery, and coalesced flushes.
library;

import 'dart:io';

import 'package:app/local_state/local_state_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('local_state_test');
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  test('reads are null before load and authoritative after', () async {
    final file = File('${tempDir.path}/local_state.json');
    await file.writeAsString('{"chat.draft.s1": "hello"}');
    final store = LocalStateStore(file);

    expect(store.read('chat.draft.s1'), isNull);
    await store.load();
    expect(store.read('chat.draft.s1'), 'hello');
    expect(store.isLoaded, isTrue);
  });

  test('write roundtrips through the document and null deletes', () async {
    final file = File('${tempDir.path}/local_state.json');
    final store = LocalStateStore(file);
    await store.load();

    store.write('chat.draft.s1', 'hello');
    store.write('chat.expandedTools.s1', <Object?>['tool-1', 'tool-2']);
    await store.flush();

    final reloaded = LocalStateStore(file);
    await reloaded.load();
    expect(reloaded.read('chat.draft.s1'), 'hello');
    expect(reloaded.read('chat.expandedTools.s1'), <Object?>['tool-1', 'tool-2']);

    reloaded.write('chat.draft.s1', null);
    await reloaded.flush();

    final afterDelete = LocalStateStore(file);
    await afterDelete.load();
    expect(afterDelete.read('chat.draft.s1'), isNull);
    expect(afterDelete.read('chat.expandedTools.s1'), <Object?>[
      'tool-1',
      'tool-2',
    ]);
  });

  test('a corrupt document is an empty cache, not an error', () async {
    final file = File('${tempDir.path}/local_state.json');
    await file.writeAsString('{"chat.draft.s1": "hel'); // truncated JSON
    final store = LocalStateStore(file);
    await store.load();
    expect(store.read('chat.draft.s1'), isNull);
    expect(store.isLoaded, isTrue);
  });

  test('rapid writes keep the last value through the flush', () async {
    final file = File('${tempDir.path}/local_state.json');
    final store = LocalStateStore(file);
    await store.load();

    for (var i = 0; i < 50; i++) {
      store.write('chat.readOffset.s1', i.toDouble());
    }
    await store.flush();

    expect(file.existsSync(), isTrue);
    final reloaded = LocalStateStore(file);
    await reloaded.load();
    expect(reloaded.read('chat.readOffset.s1'), 49.0);
  });
}
