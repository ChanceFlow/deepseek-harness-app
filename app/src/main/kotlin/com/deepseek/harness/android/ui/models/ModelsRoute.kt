package com.deepseek.harness.android.ui.models

import androidx.compose.foundation.layout.Column
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
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.compose.ui.tooling.preview.Preview
import com.deepseek.harness.android.domain.model.ModelCatalogModel
import com.deepseek.harness.android.domain.model.ModelProviderGroup
import com.deepseek.harness.android.domain.model.ModelSelection
import com.deepseek.harness.android.domain.model.SessionModels
import com.deepseek.harness.android.domain.model.SessionSummary
import com.deepseek.harness.android.ui.theme.DeepSeekHarnessAndroidTheme

@Composable
fun ModelsRoute(
    modifier: Modifier = Modifier,
    viewModel: ModelsViewModel = hiltViewModel(),
) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    ModelsScreen(uiState = uiState, onAction = viewModel::onAction, modifier = modifier)
}

@Composable
fun ModelsScreen(
    uiState: ModelsUiState,
    onAction: (ModelsAction) -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(modifier = modifier.fillMaxSize().padding(16.dp)) {
        Text(text = "Models", style = MaterialTheme.typography.titleLarge)
        uiState.errorMessage?.let {
            Text(text = it, color = MaterialTheme.colorScheme.error)
        }
        Text("Session", style = MaterialTheme.typography.labelLarge)
        LazyColumn(modifier = Modifier.weight(0.35f)) {
            items(uiState.sessions, key = { it.id }) { session ->
                val selected = session.id == uiState.selectedSessionId
                OutlinedButton(
                    onClick = { onAction(ModelsAction.SelectSession(session.id)) },
                    modifier = Modifier.fillMaxWidth(),
                    enabled = !selected,
                ) {
                    Text(session.displayTitle)
                }
            }
        }
        Spacer(modifier = Modifier.height(12.dp))
        Text("Providers", style = MaterialTheme.typography.labelLarge)
        LazyColumn(modifier = Modifier.weight(0.65f)) {
            uiState.models?.groups.orEmpty().forEach { group ->
                item(key = "group-${group.id}") {
                    Text(text = group.name, style = MaterialTheme.typography.titleSmall)
                }
                items(group.models, key = { "${group.id}:${it.id}" }) { model ->
                    val isCurrent = uiState.selected?.provider == group.id && uiState.selected?.model == model.id
                    val defaultEffort = model.reasoning?.defaultEffort
                    val selectedEffort = when {
                        isCurrent -> uiState.selected?.reasoningEffort ?: defaultEffort
                        else -> defaultEffort
                    }
                    if (isCurrent) {
                        Button(
                            onClick = {
                                onAction(
                                    ModelsAction.SelectModel(group.id, model.id, selectedEffort),
                                )
                            },
                        ) {
                            Text("${model.name} (current)")
                        }
                    } else {
                        OutlinedButton(
                            onClick = {
                                onAction(ModelsAction.SelectModel(group.id, model.id, selectedEffort))
                            },
                        ) {
                            Text(model.name)
                        }
                    }
                    model.description?.let { description ->
                        Text(
                            text = description,
                            style = MaterialTheme.typography.bodySmall,
                            modifier = Modifier.padding(start = 8.dp, top = 2.dp),
                        )
                    }
                    if (isCurrent && !model.reasoning?.efforts.isNullOrEmpty()) {
                        Column(modifier = Modifier.padding(start = 8.dp, top = 4.dp)) {
                            Text(
                                text = "Reasoning effort",
                                style = MaterialTheme.typography.labelMedium,
                            )
                            model.reasoning?.efforts?.forEach { effort ->
                                val effortSelected =
                                    uiState.selected?.reasoningEffort == effort.id ||
                                        (uiState.selected?.reasoningEffort == null && defaultEffort == effort.id)
                                if (effortSelected) {
                                    Button(
                                        onClick = {
                                            onAction(
                                                ModelsAction.SelectModel(
                                                    provider = group.id,
                                                    model = model.id,
                                                    reasoningEffort = effort.id,
                                                ),
                                            )
                                        },
                                    ) { Text(effort.name) }
                                } else {
                                    OutlinedButton(
                                        onClick = {
                                            onAction(
                                                ModelsAction.SelectModel(
                                                    provider = group.id,
                                                    model = model.id,
                                                    reasoningEffort = effort.id,
                                                ),
                                            )
                                        },
                                    ) { Text(effort.name) }
                                }
                            }
                        }
                    }
                }
            }
            uiState.models?.failures.orEmpty().forEach { failure ->
                item(key = "failure-${failure.id}") {
                    Text(text = "${failure.name}: ${failure.message}", color = MaterialTheme.colorScheme.error)
                }
            }
        }
    }
}


@Preview(showBackground = true)
@Composable
private fun ModelsScreenPreview() {
    DeepSeekHarnessAndroidTheme {
        ModelsScreen(
            uiState = ModelsUiState(
                sessions = listOf(
                    SessionSummary(id = "session-1", title = "Models preview session", blank = false),
                ),
                selectedSessionId = "session-1",
                models = SessionModels(
                    current = ModelSelection(
                        provider = "preview",
                        model = "preview-model",
                        reasoningEffort = "high",
                    ),
                    routable = true,
                    groups = listOf(
                        ModelProviderGroup(
                            id = "preview",
                            name = "Preview provider",
                            models = listOf(
                                ModelCatalogModel(
                                    id = "preview-model",
                                    name = "Preview model",
                                    description = "Static preview data",
                                ),
                            ),
                        ),
                    ),
                ),
                selected = ModelSelection(
                    provider = "preview",
                    model = "preview-model",
                    reasoningEffort = "high",
                ),
            ),
            onAction = {},
        )
    }
}
