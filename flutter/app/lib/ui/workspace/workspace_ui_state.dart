/// Workspace screen UI state and intents — port of WorkspaceUiState.kt.
library;

import 'package:domain/model/directory.dart';
import 'package:domain/model/session.dart';
import 'package:domain/model/workspace.dart'
    show WorkspaceSummary, SessionSearchResult;

final class WorkspaceUiState {
  const WorkspaceUiState({
    this.workspaces = const <WorkspaceSummary>[],
    this.sessions = const <SessionSummary>[],
    this.pinnedSessionIds = const <String>[],
    this.searchResults = const <SessionSearchResult>[],
    this.isLoading = false,
    this.errorMessage,
    this.directoryListing,
    this.directoryBrowserOpen = false,
    this.directoryLoading = false,
  });

  final List<WorkspaceSummary> workspaces;

  /// Session summaries behind the workspace groups (web
  /// WorkspaceBrowser renders the session tree under each group).
  final List<SessionSummary> sessions;

  /// Registry-global pin set, most recently pinned first (the Host's own
  /// order); pinned rows lead their group on this surface too.
  final List<String> pinnedSessionIds;

  /// Content-search results replacing the tree while a query is active
  /// (web `session.search` flat result list).
  final List<SessionSearchResult> searchResults;
  final bool isLoading;
  final String? errorMessage;
  final DirectoryListing? directoryListing;
  final bool directoryBrowserOpen;
  final bool directoryLoading;
}

sealed class WorkspaceAction {
  const WorkspaceAction();
}

/// Content search over this backend's sessions (the browsing surface's
/// search capsule).
final class SearchSessionsAction extends WorkspaceAction {
  const SearchSessionsAction(this.query);

  final String query;

  @override
  bool operator ==(Object other) =>
      other is SearchSessionsAction && other.query == query;

  @override
  int get hashCode => query.hashCode;
}

final class CreateWorkspaceAction extends WorkspaceAction {
  const CreateWorkspaceAction(this.path);

  final String path;

  @override
  bool operator ==(Object other) =>
      other is CreateWorkspaceAction && other.path == path;

  @override
  int get hashCode => path.hashCode;
}

final class RenameWorkspaceAction extends WorkspaceAction {
  const RenameWorkspaceAction(this.workspaceId, this.title);

  final String workspaceId;
  final String title;

  @override
  bool operator ==(Object other) =>
      other is RenameWorkspaceAction &&
      other.workspaceId == workspaceId &&
      other.title == title;

  @override
  int get hashCode => Object.hash(workspaceId, title);
}

final class DeleteWorkspaceAction extends WorkspaceAction {
  const DeleteWorkspaceAction(this.workspaceId);

  final String workspaceId;

  @override
  bool operator ==(Object other) =>
      other is DeleteWorkspaceAction && other.workspaceId == workspaceId;

  @override
  int get hashCode => workspaceId.hashCode;
}

/// Archive one session (web SessionNodeItem "Archive session" — the
/// long-press session verb that also reaches ungrouped sessions).
final class ArchiveSessionAction extends WorkspaceAction {
  const ArchiveSessionAction(this.sessionId);

  final String sessionId;

  @override
  bool operator ==(Object other) =>
      other is ArchiveSessionAction && other.sessionId == sessionId;

  @override
  int get hashCode => Object.hash('archive-session', sessionId);
}

/// Restore an archived session (web SessionNodeItem "Unarchive session" —
/// the same row entry an archived row shows in place of archive).
final class UnarchiveSessionAction extends WorkspaceAction {
  const UnarchiveSessionAction(this.sessionId);

  final String sessionId;

  @override
  bool operator ==(Object other) =>
      other is UnarchiveSessionAction && other.sessionId == sessionId;

  @override
  int get hashCode => Object.hash('unarchive-session', sessionId);
}

final class PinSessionAction extends WorkspaceAction {
  const PinSessionAction(this.sessionId);

  final String sessionId;

  @override
  bool operator ==(Object other) =>
      other is PinSessionAction && other.sessionId == sessionId;

  @override
  int get hashCode => Object.hash('pin-session', sessionId);
}

final class UnpinSessionAction extends WorkspaceAction {
  const UnpinSessionAction(this.sessionId);

  final String sessionId;

  @override
  bool operator ==(Object other) =>
      other is UnpinSessionAction && other.sessionId == sessionId;

  @override
  int get hashCode => Object.hash('unpin-session', sessionId);
}

/// Rename one session (web SessionNodeItem "Rename session" — the
/// long-press session verb).
final class RenameSessionAction extends WorkspaceAction {
  const RenameSessionAction(this.sessionId, this.title);

  final String sessionId;
  final String title;

  @override
  bool operator ==(Object other) =>
      other is RenameSessionAction &&
      other.sessionId == sessionId &&
      other.title == title;

  @override
  int get hashCode => Object.hash('rename-session', sessionId, title);
}

/// Fork one session (web SessionNodeItem "Fork session" — the long-press
/// session verb).
final class ForkSessionAction extends WorkspaceAction {
  const ForkSessionAction(this.sessionId);

  final String sessionId;

  @override
  bool operator ==(Object other) =>
      other is ForkSessionAction && other.sessionId == sessionId;

  @override
  int get hashCode => Object.hash('fork-session', sessionId);
}

final class MoveWorkspaceUpAction extends WorkspaceAction {
  const MoveWorkspaceUpAction(this.workspaceId);

  final String workspaceId;

  @override
  bool operator ==(Object other) =>
      other is MoveWorkspaceUpAction && other.workspaceId == workspaceId;

  @override
  int get hashCode => workspaceId.hashCode;
}

final class MoveWorkspaceDownAction extends WorkspaceAction {
  const MoveWorkspaceDownAction(this.workspaceId);

  final String workspaceId;

  @override
  bool operator ==(Object other) =>
      other is MoveWorkspaceDownAction && other.workspaceId == workspaceId;

  @override
  int get hashCode => workspaceId.hashCode;
}

/// Start (or reuse) the workspace's blank session and open it — the web
/// ProjectRowItem "+" action (`startSession(workspaceId)`).
final class StartSessionInWorkspace extends WorkspaceAction {
  const StartSessionInWorkspace(this.workspaceId);

  final String workspaceId;

  @override
  bool operator ==(Object other) =>
      other is StartSessionInWorkspace && other.workspaceId == workspaceId;

  @override
  int get hashCode => Object.hash('start-session-in-workspace', workspaceId);
}

final class RefreshWorkspacesAction extends WorkspaceAction {
  const RefreshWorkspacesAction();

  @override
  bool operator ==(Object other) => other is RefreshWorkspacesAction;

  @override
  int get hashCode => 'refresh-workspaces'.hashCode;
}

final class DismissWorkspaceError extends WorkspaceAction {
  const DismissWorkspaceError();

  @override
  bool operator ==(Object other) => other is DismissWorkspaceError;

  @override
  int get hashCode => 'dismiss-workspace-error'.hashCode;
}

final class OpenDirectoryBrowser extends WorkspaceAction {
  const OpenDirectoryBrowser();

  @override
  bool operator ==(Object other) => other is OpenDirectoryBrowser;

  @override
  int get hashCode => 'open-directory-browser'.hashCode;
}

final class CloseDirectoryBrowser extends WorkspaceAction {
  const CloseDirectoryBrowser();

  @override
  bool operator ==(Object other) => other is CloseDirectoryBrowser;

  @override
  int get hashCode => 'close-directory-browser'.hashCode;
}

final class NavigateDirectory extends WorkspaceAction {
  const NavigateDirectory(this.path);

  final String? path;

  @override
  bool operator ==(Object other) =>
      other is NavigateDirectory && other.path == path;

  @override
  int get hashCode => Object.hash('navigate-directory', path);
}

final class CreateDirectoryAction extends WorkspaceAction {
  const CreateDirectoryAction(this.parentPath, this.name);

  final String parentPath;
  final String name;

  @override
  bool operator ==(Object other) =>
      other is CreateDirectoryAction &&
      other.parentPath == parentPath &&
      other.name == name;

  @override
  int get hashCode => Object.hash(parentPath, name);
}
