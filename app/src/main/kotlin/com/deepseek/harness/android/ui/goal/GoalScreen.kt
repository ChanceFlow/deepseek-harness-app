package com.deepseek.harness.android.ui.goal

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
import com.deepseek.harness.android.domain.model.GoalPhase
import com.deepseek.harness.android.domain.model.SessionSummary

@Composable
fun GoalRoute(
    modifier: Modifier = Modifier,
    viewModel: GoalViewModel = hiltViewModel(),
) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    GoalScreen(uiState = uiState, onAction = viewModel::onAction, modifier = modifier)
}

@Composable
fun GoalScreen(
    uiState: GoalUiState,
    onAction: (GoalAction) -> Unit,
    modifier: Modifier = Modifier,
) {
    var objective by remember { mutableStateOf("") }
    var maxRoundsText by remember { mutableStateOf("") }
    Column(modifier = modifier.fillMaxSize().padding(16.dp)) {
        Text("Goal", style = MaterialTheme.typography.titleLarge)
        uiState.errorMessage?.let {
            Text(it, color = MaterialTheme.colorScheme.error)
        }

        Row(modifier = Modifier.fillMaxWidth()) {
            Text(
                text = "Session",
                style = MaterialTheme.typography.labelLarge,
                modifier = Modifier.weight(1f),
            )
            OutlinedButton(
                onClick = { onAction(GoalAction.Refresh) },
                enabled = uiState.selectedSessionId != null,
            ) { Text("Refresh") }
        }
        LazyColumn(modifier = Modifier.height(150.dp)) {
            items(uiState.sessions, key = { it.id }) { session ->
                OutlinedButton(
                    onClick = { onAction(GoalAction.SelectSession(session.id)) },
                    modifier = Modifier.fillMaxWidth(),
                    enabled = session.id != uiState.selectedSessionId,
                ) {
                    Text(session.displayTitle)
                }
            }
        }

        Spacer(modifier = Modifier.height(12.dp))

        val goal = uiState.goal
        if (goal == null) {
            Text("No current goal", style = MaterialTheme.typography.titleSmall)
            OutlinedTextField(
                value = objective,
                onValueChange = { objective = it },
                modifier = Modifier.fillMaxWidth(),
                placeholder = { Text("Goal objective") },
            )
            Row(modifier = Modifier.fillMaxWidth()) {
                OutlinedTextField(
                    value = maxRoundsText,
                    onValueChange = { text -> maxRoundsText = text.filter { it.isDigit() } },
                    modifier = Modifier.weight(1f),
                    placeholder = { Text("Max goal rounds (optional)") },
                    singleLine = true,
                )
                Button(
                    onClick = {
                        onAction(
                            GoalAction.Create(
                                objective = objective,
                                maxRounds = maxRoundsText.toLongOrNull(),
                            ),
                        )
                    },
                    modifier = Modifier.padding(start = 8.dp),
                    enabled = objective.isNotBlank() && uiState.selectedSessionId != null,
                ) {
                    Text("Create")
                }
            }
        } else {
            val snapshot = goal.goal
            Text(snapshot.objective, style = MaterialTheme.typography.titleMedium)
            Text(
                text = "${snapshot.phase} · revision ${snapshot.revision} · rounds ${goal.roundsStarted}/${snapshot.maxGoalRounds}",
                style = MaterialTheme.typography.bodySmall,
            )
            Row(modifier = Modifier.fillMaxWidth()) {
                when (snapshot.phase) {
                    GoalPhase.ACTIVE -> {
                        Button(onClick = { onAction(GoalAction.Pause) }) { Text("Pause") }
                        OutlinedButton(
                            onClick = { onAction(GoalAction.Complete) },
                            modifier = Modifier.padding(start = 8.dp),
                        ) { Text("Complete") }
                    }
                    GoalPhase.PAUSED, GoalPhase.BLOCKED -> {
                        Button(onClick = { onAction(GoalAction.Resume) }) { Text("Resume") }
                        OutlinedButton(
                            onClick = { onAction(GoalAction.Complete) },
                            modifier = Modifier.padding(start = 8.dp),
                        ) { Text("Complete") }
                    }
                    GoalPhase.COMPLETE -> {
                        Button(onClick = { onAction(GoalAction.Clear) }) { Text("Clear") }
                    }
                }
            }
        }
    }
}
