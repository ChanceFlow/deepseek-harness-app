/// Workspace screen controller — port of the legacy WorkspaceViewModel.
library;

import 'dart:async';

import 'package:domain/model/directory.dart';
import 'package:domain/model/workspace.dart';
import 'package:domain/repository/chat_repository.dart';

import '../state_stream.dart';
import 'workspace_ui_state.dart';

class WorkspaceController {
  WorkspaceController(this._repository) {
    _refresh();
    _subs.add(_repository.observeWorkspaces().listen((workspaces) {
      _workspaces = workspaces;
      _publish();
    }));
  }

  final ChatRepository _repository;
  final AppStateStream<WorkspaceUiState> _state =
      AppStateStream<WorkspaceUiState>(const WorkspaceUiState());
  final List<StreamSubscription<void>> _subs = <StreamSubscription<void>>[];

  List<WorkspaceSummary> _workspaces = const <WorkspaceSummary>[];
  bool _isLoading = false;
  String? _errorMessage;
  DirectoryListing? _directoryListing;
  bool _directoryBrowserOpen = false;
  bool _directoryLoading = false;

  WorkspaceUiState get state => _state.value;
  Stream<WorkspaceUiState> get uiState => _state.stream;

  void dispose() {
    for (final sub in _subs) {
      unawaited(sub.cancel());
    }
    _subs.clear();
  }

  void _publish() {
    _state.value = WorkspaceUiState(
      workspaces: _workspaces,
      isLoading: _isLoading,
      errorMessage: _errorMessage,
      directoryListing: _directoryListing,
      directoryBrowserOpen: _directoryBrowserOpen,
      directoryLoading: _directoryLoading,
    );
  }

  void onAction(WorkspaceAction action) {
    switch (action) {
      case CreateWorkspaceAction():
        _create(action.path);
      case RenameWorkspaceAction():
        _rename(action.workspaceId, action.title);
      case DeleteWorkspaceAction():
        unawaited(_runCatchingForUi(
            () => _repository.deleteWorkspace(action.workspaceId)));
      case MoveWorkspaceUpAction():
        _move(action.workspaceId, up: true);
      case MoveWorkspaceDownAction():
        _move(action.workspaceId, up: false);
      case RefreshWorkspacesAction():
        _refresh();
      case DismissWorkspaceError():
        _errorMessage = null;
        _publish();
      case OpenDirectoryBrowser():
        _openDirectoryBrowser();
      case CloseDirectoryBrowser():
        _closeDirectoryBrowser();
      case NavigateDirectory():
        _navigateDirectory(action.path);
      case CreateDirectoryAction():
        _createDirectory(action.parentPath, action.name);
    }
  }

  /// Reorder through `workspace.insertBefore`: moving up anchors on the
  /// row above, moving down anchors on the row two below (append when
  /// that is past the end). The host response re-orders the local list.
  void _move(String workspaceId, {required bool up}) {
    final current = _workspaces;
    var index = -1;
    for (var i = 0; i < current.length; i++) {
      if (current[i].workspaceId == workspaceId) {
        index = i;
        break;
      }
    }
    if (index < 0) return;
    final String? anchor;
    if (up) {
      if (index == 0) return;
      anchor = current[index - 1].workspaceId;
    } else {
      final target = index + 2;
      anchor = target <= current.length - 1 ? current[target].workspaceId : null;
    }
    unawaited(
        _runCatchingForUi(() => _repository.moveWorkspace(workspaceId, anchor)));
  }

  void _openDirectoryBrowser() {
    _directoryListing = null;
    _directoryBrowserOpen = true;
    _publish();
    _loadDirectory(null);
  }

  void _closeDirectoryBrowser() {
    _directoryBrowserOpen = false;
    _directoryListing = null;
    _publish();
  }

  void _navigateDirectory(String? path) {
    if (path == null || path.trim().isEmpty) return;
    _loadDirectory(path);
  }

  void _createDirectory(String parentPath, String name) {
    if (name.trim().isEmpty) return;
    unawaited(() async {
      await _runCatchingForUi(
          () => _repository.createDirectory(parentPath, name.trim()));
      await _loadDirectory(parentPath);
    }());
  }

  Future<void> _loadDirectory(String? path) async {
    _directoryLoading = true;
    _publish();
    try {
      final listing = await _runCatchingForUi(
        () => _repository.listDirectory(path),
      );
      if (listing != null) {
        _directoryListing = listing;
      }
    } finally {
      _directoryLoading = false;
      _publish();
    }
  }

  void _refresh() {
    unawaited(_runCatchingForUi(_repository.refreshWorkspaces));
  }

  void _create(String path) {
    if (path.trim().isEmpty) return;
    unawaited(() async {
      _isLoading = true;
      _publish();
      try {
        await _runCatchingForUi(
            () => _repository.createWorkspace(path.trim()));
      } finally {
        _isLoading = false;
        _publish();
      }
    }());
  }

  void _rename(String workspaceId, String title) {
    if (title.trim().isEmpty) return;
    unawaited(() async {
      _isLoading = true;
      _publish();
      try {
        await _runCatchingForUi(
            () => _repository.renameWorkspace(workspaceId, title.trim()));
      } finally {
        _isLoading = false;
        _publish();
      }
    }());
  }

  Future<T?> _runCatchingForUi<T>(Future<T> Function() block) async {
    try {
      _errorMessage = null;
      _publish();
      return await block();
    } catch (error) {
      _errorMessage = error.toString();
      _publish();
      return null;
    }
  }
}
