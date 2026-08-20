/// Backend registry controller — the UDF stream over the persisted
/// backend list plus the active-backend selection.
///
/// Guarded mutations (fail loud to the caller, never silently mutate):
/// the active backend cannot be removed (switch first), the list never
/// drops below one entry, ids are unique, and base URLs must parse with
/// an http(s) scheme and a host.
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

class BackendRegistryController {
  BackendRegistryController(this._store) {
    _load();
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
  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  int _idCounter = 0;

  Future<void> _load() async {
    try {
      final data = await _store.load();
      // A dangling active id (backend removed on another surface) falls
      // back to the first entry.
      final active = data.activeId;
      final activeId = data.backends.any((b) => b.id == active)
          ? active
          : data.backends.first.id;
      _state = BackendRegistryState(
        backends: data.backends,
        activeId: activeId,
      );
    } on BackendStoreException catch (error) {
      // A corrupt document never blocks the app: fall back to the seed.
      _errorMessage = error.toString();
      final seed = await _store.load();
      _state = BackendRegistryState(
        backends: seed.backends,
        activeId: seed.backends.first.id,
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
    if (!_state.backends.any((b) => b.id == backendId)) {
      _fail('Unknown backend: $backendId');
      return;
    }
    if (backendId == _state.activeId) return;
    _state = _state.withActiveId(backendId);
    _publish();
    _persist();
  }

  void _fail(String message) {
    _errorMessage = message;
    _publish();
  }

  void _publish() {
    _states.value = _state;
  }

  void _persist() {
    unawaited(
      _store
          .save(BackendStoreData(backends: _state.backends, activeId: _state.activeId))
          .then((_) {
            _errorMessage = null;
            _publish();
          })
          .catchError((Object error) {
            _errorMessage = error.toString();
            _publish();
          }),
    );
  }

  Future<void> dispose() async {
    await _states.close();
  }
}
