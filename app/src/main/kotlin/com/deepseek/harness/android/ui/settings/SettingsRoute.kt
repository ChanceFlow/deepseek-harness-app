package com.deepseek.harness.android.ui.settings

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.AssistChip
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
import com.deepseek.harness.android.domain.model.CredentialStatus
import com.deepseek.harness.android.domain.model.SettingsApplies
import com.deepseek.harness.android.domain.model.SettingsNamespace
import com.deepseek.harness.android.domain.model.SettingsSnapshot
import com.deepseek.harness.android.ui.theme.DeepSeekHarnessAndroidTheme

@Composable
fun SettingsRoute(
    modifier: Modifier = Modifier,
    viewModel: SettingsViewModel = hiltViewModel(),
) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    SettingsScreen(uiState = uiState, onAction = viewModel::onAction, modifier = modifier)
}

@Composable
fun SettingsScreen(
    uiState: SettingsUiState,
    onAction: (SettingsAction) -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(modifier = modifier.fillMaxSize().padding(16.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                text = "Settings",
                style = MaterialTheme.typography.titleLarge,
                modifier = Modifier.weight(1f),
            )
            OutlinedButton(onClick = { onAction(SettingsAction.Refresh) }) { Text("Refresh") }
        }
        uiState.errorMessage?.let {
            Text(
                text = it,
                color = MaterialTheme.colorScheme.error,
                style = MaterialTheme.typography.bodySmall,
            )
            Text(
                text = "settings/credentials are loopback-only on the host; connect via adb reverse",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        when (val described = uiState.snapshot) {
            null -> if (uiState.isLoading) {
                CircularProgressIndicator()
            }
            else -> SnapshotBody(
                snapshot = described,
                credentials = uiState.credentials,
                credentialError = uiState.credentialError,
                onAction = onAction,
            )
        }
    }
}

@Composable
private fun SnapshotBody(
    snapshot: SettingsSnapshot,
    credentials: List<CredentialStatus>,
    credentialError: String?,
    onAction: (SettingsAction) -> Unit,
) {
    Column(modifier = Modifier.fillMaxSize()) {
        Row {
            AssistChip(
                onClick = {},
                enabled = false,
                label = { Text(if (snapshot.writable) "host writable" else "host read-only") },
            )
            Spacer(modifier = Modifier.height(4.dp))
            AssistChip(
                onClick = {},
                enabled = false,
                label = {
                    Text(if (snapshot.hasDocument) "settings document" else "no settings document")
                },
            )
        }
        Spacer(modifier = Modifier.height(12.dp))
        LazyColumn(modifier = Modifier.weight(1f)) {
            items(snapshot.namespaces, key = { it.ns }) { namespace ->
                NamespaceRow(namespace)
            }
            if (credentials.isNotEmpty()) {
                item(key = "credentials-header") {
                    Text(
                        text = "Credentials",
                        style = MaterialTheme.typography.titleMedium,
                        modifier = Modifier.padding(top = 16.dp, bottom = 4.dp),
                    )
                }
                items(credentials, key = { it.ref }) { credential ->
                    CredentialRow(credential, onAction)
                }
            }
        }
        credentialError?.let {
            Text(
                text = "credentials: $it",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.error,
            )
        }
    }
}

@Composable
private fun NamespaceRow(namespace: SettingsNamespace) {
    Column(modifier = Modifier.fillMaxWidth().padding(vertical = 6.dp)) {
        Text(text = namespace.ns, style = MaterialTheme.typography.titleSmall)
        Text(
            text = listOfNotNull(
                "applies: ${namespace.applies.name.lowercase()}",
                "revision: ${namespace.revision}",
                if (namespace.hasUserLayer) "user layer" else null,
                if (namespace.secretCount > 0) "${namespace.secretCount} secrets set" else null,
            ).joinToString(" · "),
            style = MaterialTheme.typography.bodySmall,
        )
    }
}

@Composable
private fun CredentialRow(
    credential: CredentialStatus,
    onAction: (SettingsAction) -> Unit,
) {
    var editing by remember(credential.ref) { mutableStateOf(false) }
    var value by remember(credential.ref) { mutableStateOf("") }
    Column(modifier = Modifier.fillMaxWidth().padding(vertical = 6.dp)) {
        Text(text = credential.ref, style = MaterialTheme.typography.titleSmall)
        Text(
            text = listOfNotNull(
                if (credential.configured) "configured" else "not configured",
                credential.source?.let { "source: $it" },
                if (credential.writable) "writable" else "read-only",
            ).joinToString(" · "),
            style = MaterialTheme.typography.bodySmall,
        )
        if (credential.writable) {
            Row {
                OutlinedButton(onClick = { editing = true }) {
                    Text(if (credential.configured) "Replace" else "Set value")
                }
                if (credential.configured) {
                    OutlinedButton(
                        onClick = { onAction(SettingsAction.UnsetCredential(credential.ref)) },
                        modifier = Modifier.padding(start = 8.dp),
                    ) { Text("Unset") }
                }
            }
        }
    }
    if (editing) {
        AlertDialog(
            onDismissRequest = { editing = false },
            title = { Text("Store ${credential.ref}") },
            text = {
                OutlinedTextField(
                    value = value,
                    onValueChange = { value = it },
                    singleLine = true,
                    placeholder = { Text("secret value") },
                )
            },
            confirmButton = {
                Button(
                    onClick = {
                        if (value.isNotBlank()) {
                            onAction(SettingsAction.SetCredential(credential.ref, value.trim()))
                        }
                        editing = false
                        value = ""
                    },
                    enabled = value.isNotBlank(),
                ) { Text("Save") }
            },
            dismissButton = {
                OutlinedButton(onClick = { editing = false }) { Text("Cancel") }
            },
        )
    }
}

@Preview(showBackground = true)
@Composable
private fun SettingsScreenPreview() {
    DeepSeekHarnessAndroidTheme {
        SettingsScreen(
            uiState = SettingsUiState(
                snapshot = SettingsSnapshot(
                    writable = false,
                    hasDocument = true,
                    namespaces = listOf(
                        SettingsNamespace(
                            ns = "llm-deepseek",
                            applies = SettingsApplies.LIVE,
                            revision = 3L,
                            hasUserLayer = true,
                            secretCount = 1,
                        ),
                        SettingsNamespace(
                            ns = "shell",
                            applies = SettingsApplies.RESTART,
                            revision = 0L,
                            hasUserLayer = false,
                            secretCount = 0,
                        ),
                    ),
                    credentialRefs = listOf("DEEPSEEK_API_KEY"),
                ),
                credentials = listOf(
                    CredentialStatus(
                        ref = "DEEPSEEK_API_KEY",
                        configured = true,
                        source = "file",
                        writable = true,
                    ),
                ),
            ),
            onAction = {},
        )
    }
}
