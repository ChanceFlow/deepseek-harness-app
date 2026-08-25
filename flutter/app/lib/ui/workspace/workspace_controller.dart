/// Workspace screen controller — port of the legacy WorkspaceViewModel.
library;

import 'dart:async';

import 'package:domain/model/directory.dart';
import 'package:domain/model/session.dart';
import 'package:domain/model/workspace.dart';
import 'package:domain/repository/chat_repository.dart';

import '../state_stream.dart';
import 'workspace_ui_state.dart';

class WorkspaceController {
  WorkspaceController(this._repository) {
    _refresh();
    _subs.add(
      _repository.observeWorkspaces().listen((workspaces) {
        _workspaces = workspaces;
        _publish();
      }),
    );
    // Session summaries feed the blank-session reuse rule behind
    // StartSessionInWorkspace and the browsing tree's session rows (web
    // WorkspaceBrowser renders the session tree under each group).
    _subs.add(
      _repository.observeSessions().listen((sessions) {
        _sessions = sessions;
        _publish();
      }),
    );
  }

  final ChatRepository _repository;
  final AppStateStream<WorkspaceUiState> _state =
      AppStateStream<WorkspaceUiState>(const WorkspaceUiState());
  final List<StreamSubscription<void>> _subs = <StreamSubscription<void>>[];

  List<WorkspaceSummary> _workspaces = const <WorkspaceSummary>[];
  List<SessionSearchResult> _searchResults = const <SessionSearchResult>[];
  List<SessionSummary> _sessions = const <SessionSummary>[];
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
      sessions: _sessions,
      searchResults: _searchResults,
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
        unawaited(
          _runCatchingForUi(
            () => _repository.deleteWorkspace(action.workspaceId),
          ),
        );
      case ArchiveSessionAction():
        unawaited(
          _runCatchingForUi(() => _repository.archiveSession(action.sessionId)),
        );
      case RenameSessionAction():
        if (action.title.trim().isNotEmpty) {
          unawaited(
            _runCatchingForUi(
              () => _repository.renameSession(
                action.sessionId,
                action.title.trim(),
              ),
            ),
          );
        }
      case ForkSessionAction():
        unawaited(
          _runCatchingForUi(() => _repository.forkSession(action.sessionId)),
        );
      case MoveWorkspaceUpAction():
        _move(action.workspaceId, up: true);
      case MoveWorkspaceDownAction():
        _move(action.workspaceId, up: false);
      case StartSessionInWorkspace():
        unawaited(startSessionInWorkspace(action.workspaceId));
      case SearchSessionsAction():
        _searchSessions(action.query);
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

  /// Web WorkspaceBrowser search: an empty query clears the results
  /// (the tree returns); otherwise `session.search` answers the flat
  /// result list.
  void _searchSessions(String query) {
    if (query.trim().isEmpty) {
      _searchResults = const <SessionSearchResult>[];
      _publish();
      return;
    }
    unawaited(() async {
      final results = await _runCatchingForUi(
        () => _repository.searchSessions(query),
      );
      _searchResults = results ?? const <SessionSearchResult>[];
      _publish();
    }());
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
      anchor = target <= current.length - 1
          ? current[target].workspaceId
          : null;
    }
    unawaited(
      _runCatchingForUi(() => _repository.moveWorkspace(workspaceId, anchor)),
    );
  }

  /// Web WorkspaceBrowser `startSession(workspaceId)`: a workspace's blank
  /// session is its provisional New Session row, so reuse it before
  /// minting another; the resolved session is then opened (subscribed).
  /// Returns the resolved session id (null on failure) so the
  /// dispatching surface can navigate to the conversation — the web's
  /// `startSession` ends in `sessions.open`.
  Future<String?> startSessionInWorkspace(String workspaceId) async {
    final workspace = _workspaceById(workspaceId);
    String? sessionId;
    if (workspace != null) {
      for (final session in _sessions) {
        if (session.blank &&
            session.cwd == workspace.path &&
            workspace.sessionIds.contains(session.id)) {
          sessionId = session.id;
          break;
        }
      }
    }
    if (sessionId == null) {
      final created = await _runCatchingForUi(
        () => _repository.createSession(
          CreateSessionRequest(workspaceId: workspaceId),
        ),
      );
      sessionId = created?.id;
    }
    final resolved = sessionId;
    if (resolved != null) {
      await _runCatchingForUi(() => _repository.openSession(resolved));
    }
    return resolved;
  }

  WorkspaceSummary? _workspaceById(String workspaceId) {
    for (final workspace in _workspaces) {
      if (workspace.workspaceId == workspaceId) return workspace;
    }
    return null;
  }

  void _openDirectoryBrowser() {
    _directoryListing = null;
    _directoryBrowserOpen = true;
    _publish();
    unawaited(_loadDirectory(null));
  }

  void _closeDirectoryBrowser() {
    _directoryBrowserOpen = false;
    _directoryListing = null;
    _publish();
  }

  void _navigateDirectory(String? path) {
    if (path == null || path.trim().isEmpty) return;
    unawaited(_loadDirectory(path));
  }

  void _createDirectory(String parentPath, String name) {
    if (name.trim().isEmpty) return;
    unawaited(() async {
      await _runCatchingForUi(
        () => _repository.createDirectory(parentPath, name.trim()),
      );
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
        await _runCatchingForUi(() => _repository.createWorkspace(path.trim()));
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
          () => _repository.renameWorkspace(workspaceId, title.trim()),
        );
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
