/// Workspace screen — Flutter port of the legacy WorkspaceRoute.kt.
library;

import 'package:domain/model/directory.dart';
import 'package:domain/model/workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../di/providers.dart';
import 'workspace_ui_state.dart';

class WorkspaceRoute extends ConsumerWidget {
  const WorkspaceRoute({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(workspaceControllerProvider);
    return StreamBuilder<WorkspaceUiState>(
      stream: controller.uiState,
      initialData: controller.state,
      builder: (context, snapshot) {
        final uiState = snapshot.data ?? const WorkspaceUiState();
        return WorkspaceScreen(uiState: uiState, onAction: controller.onAction);
      },
    );
  }
}

class WorkspaceScreen extends StatefulWidget {
  const WorkspaceScreen({
    super.key,
    required this.uiState,
    required this.onAction,
  });

  final WorkspaceUiState uiState;
  final void Function(WorkspaceAction) onAction;

  @override
  State<WorkspaceScreen> createState() => _WorkspaceScreenState();
}

class _WorkspaceScreenState extends State<WorkspaceScreen> {
  final TextEditingController _pathController = TextEditingController();
  final TextEditingController _renameController = TextEditingController();

  @override
  void dispose() {
    _pathController.dispose();
    _renameController.dispose();
    super.dispose();
  }

  void _openRename(WorkspaceSummary workspace) {
    _renameController.text = workspace.title;
    _showRenameDialog(workspace.workspaceId);
  }

  Future<void> _showRenameDialog(String workspaceId) {
    return showDialog<void>(
      context: context,
      builder: (context) => _RenameWorkspaceDialog(
        controller: _renameController,
        onSave: (title) =>
            widget.onAction(RenameWorkspaceAction(workspaceId, title)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uiState = widget.uiState;
    final browserOpen = uiState.directoryBrowserOpen;
    final body = Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Workspaces', style: Theme.of(context).textTheme.titleLarge),
              if (uiState.errorMessage case final String error)
                Text(
                  error,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _pathController,
                      decoration: const InputDecoration(
                        labelText: 'Existing directory path',
                        isDense: true,
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: OutlinedButton(
                      onPressed: () =>
                          widget.onAction(const OpenDirectoryBrowser()),
                      child: const Text('Browse'),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: FilledButton(
                      onPressed:
                          !uiState.isLoading &&
                              _pathController.text.trim().isNotEmpty
                          ? () {
                              widget.onAction(
                                CreateWorkspaceAction(_pathController.text),
                              );
                              _pathController.clear();
                              setState(() {});
                            }
                          : null,
                      child: const Text('Create'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView.builder(
                  itemCount: uiState.workspaces.length,
                  itemBuilder: (context, index) {
                    final workspace = uiState.workspaces[index];
                    final position = uiState.workspaces.indexWhere(
                      (item) => item.workspaceId == workspace.workspaceId,
                    );
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            workspace.title,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          Text(
                            workspace.path,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          Text(
                            'sessions: ${workspace.sessionIds.length}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          Wrap(
                            children: [
                              OutlinedButton(
                                onPressed: () => _openRename(workspace),
                                child: const Text('Rename'),
                              ),
                              Padding(
                                padding: const EdgeInsets.only(left: 8),
                                child: OutlinedButton(
                                  onPressed: () => widget.onAction(
                                    DeleteWorkspaceAction(
                                      workspace.workspaceId,
                                    ),
                                  ),
                                  child: const Text('Delete workspace'),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.only(left: 8),
                                child: OutlinedButton(
                                  onPressed: position > 0
                                      ? () => widget.onAction(
                                          MoveWorkspaceUpAction(
                                            workspace.workspaceId,
                                          ),
                                        )
                                      : null,
                                  child: const Text('Up'),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.only(left: 8),
                                child: OutlinedButton(
                                  onPressed:
                                      position < uiState.workspaces.length - 1
                                      ? () => widget.onAction(
                                          MoveWorkspaceDownAction(
                                            workspace.workspaceId,
                                          ),
                                        )
                                      : null,
                                  child: const Text('Down'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return Stack(
      children: [
        body,
        if (browserOpen) ...[
          const Positioned.fill(child: ModalBarrier(dismissible: false)),
          Positioned.fill(
            child: Center(
              child: DirectoryBrowserDialog(
                listing: uiState.directoryListing,
                loading: uiState.directoryLoading,
                onNavigate: (destination) =>
                    widget.onAction(NavigateDirectory(destination)),
                onCreateDirectory: (name) {
                  final parent = uiState.directoryListing?.path;
                  if (parent != null) {
                    widget.onAction(CreateDirectoryAction(parent, name));
                  }
                },
                onSelect: (selected) {
                  _pathController.text = selected;
                  setState(() {});
                  widget.onAction(const CloseDirectoryBrowser());
                },
                onClose: () => widget.onAction(const CloseDirectoryBrowser()),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _RenameWorkspaceDialog extends StatelessWidget {
  const _RenameWorkspaceDialog({
    required this.controller,
    required this.onSave,
  });

  final TextEditingController controller;
  final void Function(String title) onSave;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Rename workspace'),
      content: TextField(controller: controller, autofocus: true),
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            onSave(controller.text);
            Navigator.of(context).pop();
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

/// Host-directory browser backing the "Browse" affordance.
class DirectoryBrowserDialog extends StatefulWidget {
  const DirectoryBrowserDialog({
    super.key,
    required this.listing,
    required this.loading,
    required this.onNavigate,
    required this.onCreateDirectory,
    required this.onSelect,
    required this.onClose,
  });

  final DirectoryListing? listing;
  final bool loading;
  final void Function(String path) onNavigate;
  final void Function(String name) onCreateDirectory;
  final void Function(String path) onSelect;
  final VoidCallback onClose;

  @override
  State<DirectoryBrowserDialog> createState() => _DirectoryBrowserDialogState();
}

class _DirectoryBrowserDialogState extends State<DirectoryBrowserDialog> {
  final TextEditingController _folderNameController = TextEditingController();
  bool _showHidden = false;

  @override
  void dispose() {
    _folderNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final listing = widget.listing;
    return AlertDialog(
      title: const Text('Choose directory'),
      content: SizedBox(
        width: double.maxFinite,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 420),
          child: listing == null
              ? widget.loading
                    ? const Center(child: CircularProgressIndicator())
                    : const Text('Unable to load directory')
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      listing.path,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    Flexible(
                      child: ListView(
                        shrinkWrap: true,
                        children: [
                          for (final entry in listing.entries.where(
                            (entry) => _showHidden || !entry.hidden,
                          ))
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton(
                                onPressed: () => widget.onNavigate(entry.path),
                                child: Text(
                                  '${entry.hidden ? '.' : ''}${entry.name}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (listing.truncated)
                      Text(
                        'Directory listing truncated',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    OutlinedButton(
                      onPressed: () =>
                          setState(() => _showHidden = !_showHidden),
                      child: Text(_showHidden ? 'Hide hidden' : 'Show hidden'),
                    ),
                    TextField(
                      controller: _folderNameController,
                      decoration: const InputDecoration(
                        hintText: 'New folder name',
                        isDense: true,
                      ),
                      onChanged: (text) => setState(() {
                        _folderNameController.text = text
                            .replaceAll('/', '')
                            .replaceAll('\\', '');
                        _folderNameController.selection =
                            TextSelection.collapsed(
                              offset: _folderNameController.text.length,
                            );
                      }),
                    ),
                    FilledButton(
                      onPressed:
                          _folderNameController.text.trim().isNotEmpty &&
                              !widget.loading
                          ? () {
                              widget.onCreateDirectory(
                                _folderNameController.text.trim(),
                              );
                              _folderNameController.clear();
                              setState(() {});
                            }
                          : null,
                      child: const Text('Create folder'),
                    ),
                  ],
                ),
        ),
      ),
      actions: [
        OutlinedButton(onPressed: widget.onClose, child: const Text('Cancel')),
        FilledButton(
          onPressed: listing != null && !widget.loading
              ? () => widget.onSelect(listing.path)
              : null,
          child: const Text('Use this folder'),
        ),
      ],
    );
  }
}
