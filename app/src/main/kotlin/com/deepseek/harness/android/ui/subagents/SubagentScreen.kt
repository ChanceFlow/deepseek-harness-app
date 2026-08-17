package com.deepseek.harness.android.ui.subagents

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
import com.deepseek.harness.android.domain.model.SessionSummary
import com.deepseek.harness.android.domain.model.SubagentEntry
import com.deepseek.harness.android.domain.model.TimelineItem

@Composable
fun SubagentRoute(
    modifier: Modifier = Modifier,
    viewModel: SubagentViewModel = hiltViewModel(),
) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    SubagentScreen(uiState = uiState, onAction = viewModel::onAction, modifier = modifier)
}

@Composable
fun SubagentScreen(
    uiState: SubagentUiState,
    onAction: (SubagentAction) -> Unit,
    modifier: Modifier = Modifier,
) {
    var draft by remember { mutableStateOf("") }
    Column(modifier = modifier.fillMaxSize().padding(16.dp)) {
        Text("Subagents", style = MaterialTheme.typography.titleLarge)
        uiState.errorMessage?.let {
            Text(it, color = MaterialTheme.colorScheme.error)
        }

        Text("Parent session", style = MaterialTheme.typography.labelLarge)
        ParentPicker(
            sessions = uiState.sessions,
            selectedParentId = uiState.selectedParentId,
            onSelect = { onAction(SubagentAction.SelectParent(it)) },
        )

        Spacer(modifier = Modifier.height(12.dp))
        Text("Children", style = MaterialTheme.typography.labelLarge)
        if (!uiState.catalog.parentAvailable) {
            Text("Parent is not available for continuation.", style = MaterialTheme.typography.bodySmall)
        }
        LazyColumn(modifier = Modifier.weight(0.7f)) {
            items(uiState.catalog.entries, key = { it.id }) { entry ->
                SubagentEntryRow(
                    entry = entry,
                    selected = entry.id == uiState.selectedChildId,
                    onOpen = { onAction(SubagentAction.OpenChild(entry.id)) },
                    onInterrupt = { onAction(SubagentAction.Interrupt(entry.id)) },
                )
            }
        }

        if (uiState.selectedChildId != null) {
            Spacer(modifier = Modifier.height(12.dp))
            Text("Child timeline", style = MaterialTheme.typography.labelLarge)
            ChildTimeline(
                timeline = uiState.childTimeline,
                modifier = Modifier.weight(0.35f),
            )
            Row(modifier = Modifier.fillMaxWidth()) {
                OutlinedTextField(
                    value = draft,
                    onValueChange = { draft = it },
                    modifier = Modifier.weight(1f),
                    placeholder = { Text("Message selected subagent") },
                    enabled = !uiState.isSendingChild,
                )
                Button(
                    onClick = {
                        onAction(SubagentAction.SendPrompt(draft))
                        draft = ""
                    },
                    modifier = Modifier.padding(start = 8.dp),
                    enabled = draft.isNotBlank() && !uiState.isSendingChild,
                ) {
                    Text(if (uiState.isSendingChild) "Sending" else "Send")
                }
            }
        }
    }
}

@Composable
private fun ParentPicker(
    sessions: List<SessionSummary>,
    selectedParentId: String?,
    onSelect: (String) -> Unit,
) {
    LazyColumn(modifier = Modifier.height(150.dp)) {
        items(sessions, key = { it.id }) { session ->
            OutlinedButton(
                onClick = { onSelect(session.id) },
                modifier = Modifier.fillMaxWidth(),
                enabled = session.id != selectedParentId,
            ) {
                Text(session.title ?: "Session ${session.id.take(8)}")
            }
        }
    }
}

@Composable
private fun SubagentEntryRow(
    entry: SubagentEntry,
    selected: Boolean,
    onOpen: () -> Unit,
    onInterrupt: () -> Unit,
) {
    Column(modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp)) {
        Row(modifier = Modifier.fillMaxWidth()) {
            Text(
                text = "child ${entry.id.take(8)}",
                style = MaterialTheme.typography.titleSmall,
                modifier = Modifier.weight(1f),
            )
            if (entry.kind == "child" && entry.mode == "continuable") {
                Button(onClick = onOpen, enabled = !selected) { Text("Open") }
                if (entry.activity == "running") {
                    Button(
                        onClick = onInterrupt,
                        modifier = Modifier.padding(start = 4.dp),
                    ) { Text("Stop") }
                }
            }
        }
        Text("kind=${entry.kind} mode=${entry.mode.orEmpty()} activity=${entry.activity.orEmpty()}", style = MaterialTheme.typography.bodySmall)
        entry.label?.let { Text("label=$it", style = MaterialTheme.typography.bodySmall) }
        entry.reason?.let { Text(it, style = MaterialTheme.typography.bodySmall) }
    }
}

@Composable
private fun ChildTimeline(
    timeline: List<TimelineItem>,
    modifier: Modifier = Modifier,
) {
    LazyColumn(modifier = modifier.fillMaxSize()) {
        items(timeline, key = { timelineKey(it) }) { item ->
            when (item) {
                is TimelineItem.Message -> Text(
                    text = "${item.value.role}: ${item.value.text}",
                    modifier = Modifier.fillMaxWidth(),
                )
                is TimelineItem.ToolCall -> Text(
                    text = "Tool ${item.name}: ${item.result ?: item.arguments.orEmpty()}",
                    modifier = Modifier.fillMaxWidth(),
                )
                is TimelineItem.ApprovalRequest -> Text(
                    text = "Approval: ${item.toolName}",
                    modifier = Modifier.fillMaxWidth(),
                )
                is TimelineItem.QuestionRequest -> Text(
                    text = "Question: ${item.questions.firstOrNull()?.question.orEmpty()}",
                    modifier = Modifier.fillMaxWidth(),
                )
                is TimelineItem.Queue -> Text(
                    text = "Queue: ${item.items.size}",
                    modifier = Modifier.fillMaxWidth(),
                )
                is TimelineItem.Jobs -> Text(
                    text = "Jobs: ${item.jobs.size}",
                    modifier = Modifier.fillMaxWidth(),
                )
                is TimelineItem.Error -> Text(
                    text = item.message,
                    color = MaterialTheme.colorScheme.error,
                    modifier = Modifier.fillMaxWidth(),
                )
            }
        }
    }
}

private fun timelineKey(item: TimelineItem): String = when (item) {
    is TimelineItem.Message -> "m:${item.value.id}:${item.value.streaming}"
    is TimelineItem.ToolCall -> "t:${item.id}:${item.status}"
    is TimelineItem.ApprovalRequest -> "a:${item.requestId}"
    is TimelineItem.QuestionRequest -> "q:${item.requestId}"
    is TimelineItem.Queue -> "queue"
    is TimelineItem.Jobs -> "jobs"
    is TimelineItem.Error -> "e:${item.id}"
}
