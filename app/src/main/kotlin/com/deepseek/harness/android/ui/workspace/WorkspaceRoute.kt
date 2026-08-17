package com.deepseek.harness.android.ui.workspace

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle

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
                    OutlinedButton(onClick = { onAction(WorkspaceAction.Delete(workspace.workspaceId)) }) {
                        Text("Delete workspace")
                    }
                }
            }
        }
    }
}
