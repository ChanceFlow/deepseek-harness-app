/// Riverpod wiring for the device-local UI-state cache.
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'local_state_store.dart';

/// The app-wide UI-state cache, loaded from
/// `<documents>/local_state.json`. Consumers await (or watch
/// `.valueOrNull` on) this provider and then read synchronously; until it
/// resolves every [LocalStateStore.read] is null, which is the correct
/// pre-cache default.
final localStateStoreProvider = FutureProvider<LocalStateStore>((ref) async {
  final documents = await getApplicationDocumentsDirectory();
  final store = LocalStateStore(File('${documents.path}/local_state.json'));
  await store.load();
  return store;
});
