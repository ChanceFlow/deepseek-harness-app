/// Backend registry controller — the UDF stream over the persisted
/// backend list plus the active-backend selection.
///
/// Guarded mutations (fail loud to the caller, never silently mutate):
/// the active backend cannot be removed (switch first), the list never
/// drops below one entry, ids are unique, base URLs must parse with an
/// http(s) scheme and a host, and a disabled backend cannot be
/// activated. Disabling the active backend moves the active id to the
/// next enabled backend (null when none remain); enabling a backend while
/// none is active activates it.
library;

import 'dart:async';

import 'package:domain/model/backend.dart';

import '../ui/state_stream.dart';
import 'backend_store.dart';

sealed class BackendAction {
  const BackendAction();
}

final class AddBackend extends BackendAction {
  const AddBackend(this.label, this.baseUrl);

  final String label;
  final String baseUrl;
}

final class RenameBackend extends BackendAction {
  const RenameBackend(this.backendId, this.label);

  final String backendId;
  final String label;
}

final class UpdateBackendUrl extends BackendAction {
  const UpdateBackendUrl(this.backendId, this.baseUrl);

  final String backendId;
  final String baseUrl;
}

final class RemoveBackend extends BackendAction {
  const RemoveBackend(this.backendId);

  final String backendId;
}

/// Makes the backend the chat surface presents.
final class SelectBackend extends BackendAction {
  const SelectBackend(this.backendId);

  final String backendId;
}

/// Turns a backend's connection on or off. A disabled backend keeps its
/// config (and its Settings row) but owns no connection, controller,
/// sidebar slice, or switcher entry.
final class SetBackendEnabled extends BackendAction {
  const SetBackendEnabled(this.backendId, this.enabled);

  final String backendId;
  final bool enabled;
}

class BackendRegistryController {
  BackendRegistryController(this._store) {
    unawaited(_load());
  }

  final BackendStore _store;

  final AppStateStream<BackendRegistryState> _states =
      AppStateStream<BackendRegistryState>(const BackendRegistryState());

  /// Replay-seeded state stream: every subscriber first receives the
  /// current state, then live updates — a state published between two
  /// subscribers' attaches is never lost (the registry loads
  /// asynchronously, so consumers attach before the first load lands).
  Stream<BackendRegistryState> get uiState => _states.stream;
  BackendRegistryState get state => _state;

  BackendRegistryState _state = const BackendRegistryState();

  int _idCounter = 0;

  Future<void> _load() async {
    try {
      final data = await _store.load();
      // A dangling active id (backend removed on another surface) or one
      // pointing at a disabled backend falls back to the first enabled
      // entry; disabling every backend leaves no active backend.
      final active = data.activeId;
      final activeEnabled = data.backends
          .where((b) => b.id == active && b.enabled)
          .firstOrNull;
      final activeId =
          activeEnabled?.id ?? data.enabledBackends.firstOrNull?.id;
      _state = BackendRegistryState(
        backends: data.backends,
        activeId: activeId,
      );
    } on BackendStoreException catch (error) {
      // A corrupt document never blocks the app: fall back to the seed
      // (re-reading the same file would throw again), with the
      // corruption reported on the state.
      final seed = _store.seedDocument();
      _state = BackendRegistryState(
        backends: seed.backends,
        activeId: seed.backends.first.id,
        errorMessage: error.toString(),
      );
    }
    _publish();
  }

  void onAction(BackendAction action) {
    switch (action) {
      case AddBackend():
        _add(action.label, action.baseUrl);
      case RenameBackend():
        _rename(action.backendId, action.label);
      case UpdateBackendUrl():
        _updateUrl(action.backendId, action.baseUrl);
      case RemoveBackend():
        _remove(action.backendId);
      case SelectBackend():
        _select(action.backendId);
      case SetBackendEnabled():
        _setEnabled(action.backendId, action.enabled);
    }
  }

  Uri? _parseBaseUrl(String raw) {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null) return null;
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;
    if (uri.host.isEmpty) return null;
    return uri;
  }

  String _mintId() {
    var id = 'b${_idCounter++}';
    final taken = _state.backends.map((b) => b.id).toSet();
    while (taken.contains(id)) {
      id = 'b${_idCounter++}';
    }
    return id;
  }

  void _add(String label, String baseUrl) {
    final uri = _parseBaseUrl(baseUrl);
    if (uri == null) {
      _fail('Invalid backend URL: $baseUrl');
      return;
    }
    final trimmed = label.trim();
    if (trimmed.isEmpty) {
      _fail('Backend label cannot be empty');
      return;
    }
    final backend = BackendConfig(id: _mintId(), label: trimmed, baseUri: uri);
    _state = _state.withBackends([..._state.backends, backend]);
    _publish();
    _persist();
  }

  void _rename(String backendId, String label) {
    final trimmed = label.trim();
    if (trimmed.isEmpty) {
      _fail('Backend label cannot be empty');
      return;
    }
    _state = _state.withBackends([
      for (final backend in _state.backends)
        backend.id == backendId ? backend.copyWith(label: trimmed) : backend,
    ]);
    _publish();
    _persist();
  }

  void _updateUrl(String backendId, String baseUrl) {
    final uri = _parseBaseUrl(baseUrl);
    if (uri == null) {
      _fail('Invalid backend URL: $baseUrl');
      return;
    }
    _state = _state.withBackends([
      for (final backend in _state.backends)
        backend.id == backendId ? backend.copyWith(baseUri: uri) : backend,
    ]);
    _publish();
    _persist();
  }

  void _remove(String backendId) {
    if (_state.backends.length <= 1) {
      _fail('The last backend cannot be removed');
      return;
    }
    if (backendId == _state.activeId) {
      _fail('Switch away before removing the active backend');
      return;
    }
    _state = _state.withBackends([
      for (final backend in _state.backends)
        if (backend.id != backendId) backend,
    ]);
    _publish();
    _persist();
  }

  void _select(String backendId) {
    final target = _state.backends.where((b) => b.id == backendId).firstOrNull;
    if (target == null) {
      _fail('Unknown backend: $backendId');
      return;
    }
    if (!target.enabled) {
      _fail('Enable the backend before activating it');
      return;
    }
    if (backendId == _state.activeId) return;
    _state = _state.withActiveId(backendId);
    _publish();
    _persist();
  }

  void _setEnabled(String backendId, bool enabled) {
    final index = _state.backends.indexWhere((b) => b.id == backendId);
    if (index < 0) {
      _fail('Unknown backend: $backendId');
      return;
    }
    if (_state.backends[index].enabled == enabled) return;
    final backends = [..._state.backends];
    backends[index] = backends[index].copyWith(enabled: enabled);
    _state = _state.withBackends(backends);
    if (!enabled) {
      // Disabling the active backend moves the chat surface to the next
      // enabled backend; disabling the last enabled one leaves no active
      // backend (surfaces show their loading/empty state).
      if (_state.activeId == backendId) {
        _state = _state.withActiveId(_state.enabledBackends.firstOrNull?.id);
      }
    } else if (_state.activeId == null) {
      // Enabling a backend while none is active activates it: a disabled
      // list has no chat surface to preserve.
      _state = _state.withActiveId(backendId);
    }
    _publish();
    _persist();
  }

  void _fail(String message) {
    _state = _state.withError(message);
    _publish();
  }

  void _publish() {
    _states.value = _state;
  }

  void _persist() {
    unawaited(
      _store
          .save(
            BackendStoreData(
              backends: _state.backends,
              activeId: _state.activeId,
            ),
          )
          .then((_) {
            _state = _state.withError(null);
            _publish();
          })
          .catchError((Object error) {
            _state = _state.withError(error.toString());
            _publish();
          }),
    );
  }

  Future<void> dispose() async {
    await _states.close();
  }
}
