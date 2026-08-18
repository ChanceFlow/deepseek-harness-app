package com.deepseek.harness.android.ui.workspace

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.deepseek.harness.android.domain.model.DirectoryEntry
import com.deepseek.harness.android.domain.model.DirectoryListing
import com.deepseek.harness.android.domain.model.WorkspaceSummary
import com.deepseek.harness.android.ui.theme.DeepSeekHarnessAndroidTheme

@Composable
fun WorkspaceRoute(
    modifier: Modifier = Modifier,
    viewModel: WorkspaceViewModel = hiltViewModel(),
) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    WorkspaceScreen(uiState = uiState, onAction = viewModel::onAction, modifier = modifier)
}

@Composable
fun WorkspaceScreen(
    uiState: WorkspaceUiState,
    onAction: (WorkspaceAction) -> Unit,
    modifier: Modifier = Modifier,
) {
    var path by remember { mutableStateOf("") }
    var renameTargetId by remember { mutableStateOf<String?>(null) }
    var renameTitle by remember { mutableStateOf("") }
    Column(modifier = modifier.fillMaxSize().padding(16.dp)) {
        Text(text = "Workspaces", style = MaterialTheme.typography.titleLarge)
        uiState.errorMessage?.let {
            Text(text = it, color = MaterialTheme.colorScheme.error)
        }
        Row(modifier = Modifier.fillMaxWidth()) {
            OutlinedTextField(
                value = path,
                onValueChange = { path = it },
                modifier = Modifier.weight(1f),
                label = { Text("Existing directory path") },
            )
            OutlinedButton(
                onClick = { onAction(WorkspaceAction.OpenDirectoryBrowser) },
                modifier = Modifier.padding(start = 8.dp),
            ) { Text("Browse") }
            Button(
                onClick = { onAction(WorkspaceAction.Create(path)); path = "" },
                modifier = Modifier.padding(start = 8.dp),
                enabled = uiState.isLoading.not() && path.isNotBlank(),
            ) {
                Text("Create")
            }
        }
        Spacer(modifier = Modifier.height(12.dp))
        LazyColumn(modifier = Modifier.weight(1f)) {
            items(uiState.workspaces, key = { it.workspaceId }) { workspace ->
                Column(modifier = Modifier.fillMaxWidth().padding(vertical = 6.dp)) {
                    Text(text = workspace.title, style = MaterialTheme.typography.titleSmall)
                    Text(text = workspace.path, style = MaterialTheme.typography.bodySmall)
                    Text(
                        text = "sessions: ${workspace.sessionIds.size}",
                        style = MaterialTheme.typography.bodySmall,
                    )
                    Row {
                        OutlinedButton(
                            onClick = {
                                renameTargetId = workspace.workspaceId
                                renameTitle = workspace.title
                            },
                        ) { Text("Rename") }
                        OutlinedButton(
                            onClick = { onAction(WorkspaceAction.Delete(workspace.workspaceId)) },
                            modifier = Modifier.padding(start = 8.dp),
                        ) { Text("Delete workspace") }
                    }
                }
            }
        }
    }

    if (uiState.directoryBrowserOpen) {
        DirectoryBrowserDialog(
            listing = uiState.directoryListing,
            loading = uiState.directoryLoading,
            onNavigate = { destination ->
                onAction(WorkspaceAction.NavigateDirectory(destination))
            },
            onCreateDirectory = { name ->
                uiState.directoryListing?.path?.let { parent ->
                    onAction(WorkspaceAction.CreateDirectory(parent, name))
                }
            },
            onSelect = { selected ->
                path = selected
                onAction(WorkspaceAction.CloseDirectoryBrowser)
            },
            onClose = { onAction(WorkspaceAction.CloseDirectoryBrowser) },
        )
    }

    renameTargetId?.let { workspaceId ->
        AlertDialog(
            onDismissRequest = { renameTargetId = null },
            title = { Text("Rename workspace") },
            text = {
                OutlinedTextField(
                    value = renameTitle,
                    onValueChange = { renameTitle = it },
                    singleLine = true,
                )
            },
            confirmButton = {
                Button(
                    onClick = {
                        onAction(WorkspaceAction.Rename(workspaceId, renameTitle))
                        renameTargetId = null
                        renameTitle = ""
                    },
                ) { Text("Save") }
            },
            dismissButton = {
                OutlinedButton(onClick = { renameTargetId = null }) { Text("Cancel") }
            },
        )
    }
}

@Composable
private fun DirectoryBrowserDialog(
    listing: DirectoryListing?,
    loading: Boolean,
    onNavigate: (String) -> Unit,
    onCreateDirectory: (String) -> Unit,
    onSelect: (String) -> Unit,
    onClose: () -> Unit,
) {
    var newFolderName by remember { mutableStateOf("") }
    var showHidden by remember { mutableStateOf(false) }
    AlertDialog(
        onDismissRequest = onClose,
        title = { Text("Choose directory") },
        text = {
            Column(modifier = Modifier.heightIn(max = 420.dp)) {
                if (listing == null) {
                    if (loading) {
                        CircularProgressIndicator()
                    } else {
                        Text("Unable to load directory")
                    }
                } else {
                    Text(listing.path, style = MaterialTheme.typography.bodySmall)
                    Spacer(modifier = Modifier.height(8.dp))
                    LazyColumn(modifier = Modifier.weight(1f)) {
                        items(
                            items = listing.entries.filter { entry ->
                                showHidden || !entry.hidden
                            },
                            key = { it.path },
                        ) { entry: DirectoryEntry ->
                            OutlinedButton(
                                onClick = { onNavigate(entry.path) },
                                modifier = Modifier.fillMaxWidth(),
                            ) {
                                Text("${if (entry.hidden) "." else ""}${entry.name}", maxLines = 1)
                            }
                        }
                    }
                    if (listing.truncated) {
                        Text("Directory listing truncated", style = MaterialTheme.typography.bodySmall)
                    }
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        OutlinedButton(onClick = { showHidden = !showHidden }) {
                            Text(if (showHidden) "Hide hidden" else "Show hidden")
                        }
                    }
                    OutlinedTextField(
                        value = newFolderName,
                        onValueChange = { newFolderName = it.filter { ch -> ch != '/' && ch != '\\' } },
                        modifier = Modifier.fillMaxWidth(),
                        placeholder = { Text("New folder name") },
                        singleLine = true,
                    )
                    Button(
                        onClick = {
                            onCreateDirectory(newFolderName.trim())
                            newFolderName = ""
                        },
                        enabled = newFolderName.isNotBlank() && !loading,
                    ) { Text("Create folder") }
                }
            }
        },
        confirmButton = {
            Button(
                onClick = { listing?.let { onSelect(it.path) } },
                enabled = listing != null && !loading,
            ) { Text("Use this folder") }
        },
        dismissButton = {
            OutlinedButton(onClick = onClose) { Text("Cancel") }
        },
    )
}

@Preview(showBackground = true)
@Composable
private fun WorkspaceScreenPreview() {
    DeepSeekHarnessAndroidTheme {
        WorkspaceScreen(
            uiState = WorkspaceUiState(
                workspaces = listOf(
                    WorkspaceSummary(
                        workspaceId = "workspace-preview",
                        path = "/home/user/workspace",
                        title = "workspace",
                        sessionIds = listOf("session-1", "session-2"),
                    ),
                ),
            ),
            onAction = {},
        )
    }
}
