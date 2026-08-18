/// Workspace screen UI state and intents — port of WorkspaceUiState.kt.
library;

import 'package:domain/model/directory.dart';
import 'package:domain/model/workspace.dart';

final class WorkspaceUiState {
  const WorkspaceUiState({
    this.workspaces = const <WorkspaceSummary>[],
    this.isLoading = false,
    this.errorMessage,
    this.directoryListing,
    this.directoryBrowserOpen = false,
    this.directoryLoading = false,
  });

  final List<WorkspaceSummary> workspaces;
  final bool isLoading;
  final String? errorMessage;
  final DirectoryListing? directoryListing;
  final bool directoryBrowserOpen;
  final bool directoryLoading;
}

sealed class WorkspaceAction {
  const WorkspaceAction();
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
