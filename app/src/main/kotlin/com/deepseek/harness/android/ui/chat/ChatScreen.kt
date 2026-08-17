package com.deepseek.harness.android.ui.chat

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
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
import com.deepseek.harness.android.domain.model.ChatMessage
import com.deepseek.harness.android.domain.model.ConnectionPhase
import com.deepseek.harness.android.domain.model.ConnectionState
import com.deepseek.harness.android.domain.model.HostDescription
import com.deepseek.harness.android.domain.model.MessageRole
import com.deepseek.harness.android.domain.model.QuestionAnswer
import com.deepseek.harness.android.domain.model.QuestionItem
import com.deepseek.harness.android.domain.model.SessionSummary
import com.deepseek.harness.android.domain.model.TimelineItem
import com.deepseek.harness.android.domain.model.ToolRunStatus
import com.deepseek.harness.android.ui.theme.DeepSeekHarnessAndroidTheme

@Composable
fun ChatRoute(
    modifier: Modifier = Modifier,
    viewModel: ChatViewModel = hiltViewModel(),
) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    ChatScreen(
        uiState = uiState,
        onAction = viewModel::onAction,
        modifier = modifier,
    )
}

@Composable
fun ChatScreen(
    uiState: ChatUiState,
    onAction: (ChatAction) -> Unit,
    modifier: Modifier = Modifier,
) {
    BoxWithConstraints(modifier = modifier.fillMaxSize()) {
        val useTwoPanes = maxWidth >= 720.dp

        Scaffold { innerPadding ->
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(innerPadding),
            ) {
                ConnectionBanner(uiState = uiState)
                if (useTwoPanes) {
                    Row(modifier = Modifier.fillMaxSize()) {
                        SessionPanel(
                            sessions = uiState.sessions,
                            selectedSessionId = uiState.selectedSessionId,
                            onSelectSession = { onAction(ChatAction.SelectSession(it)) },
                            onCreateSession = { onAction(ChatAction.CreateSession) },
                            modifier = Modifier.width(320.dp),
                        )
                        ChatPanel(
                            uiState = uiState,
                            onAction = onAction,
                            modifier = Modifier.weight(1f),
                        )
                    }
                } else {
                    Column(modifier = Modifier.fillMaxSize()) {
                        SessionPanel(
                            sessions = uiState.sessions,
                            selectedSessionId = uiState.selectedSessionId,
                            onSelectSession = { onAction(ChatAction.SelectSession(it)) },
                            onCreateSession = { onAction(ChatAction.CreateSession) },
                            modifier = Modifier
                                .fillMaxWidth()
                                .height(160.dp),
                        )
                        ChatPanel(
                            uiState = uiState,
                            onAction = onAction,
                            modifier = Modifier.weight(1f),
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun ConnectionBanner(uiState: ChatUiState) {
    val connection = uiState.connection
    val text = when (connection.phase) {
        ConnectionPhase.CONNECTED -> "connected ${connection.hostDescription?.version.orEmpty()}"
        ConnectionPhase.CONNECTING -> "connecting"
        ConnectionPhase.RECONNECTING -> "reconnecting"
        ConnectionPhase.DISCONNECTED -> "disconnected"
    }
    Text(
        text = text,
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 12.dp, vertical = 4.dp),
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        style = MaterialTheme.typography.labelMedium,
    )
}

@Composable
private fun SessionPanel(
    sessions: List<SessionSummary>,
    selectedSessionId: String?,
    onSelectSession: (String) -> Unit,
    onCreateSession: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(modifier = modifier.padding(8.dp)) {
        OutlinedButton(
            onClick = onCreateSession,
            modifier = Modifier.fillMaxWidth(),
        ) {
            Text("New session")
        }
        Spacer(modifier = Modifier.height(8.dp))
        LazyColumn(
            modifier = Modifier.weight(1f),
            verticalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            items(sessions, key = { it.id }) { session ->
                val selected = session.id == selectedSessionId
                Button(
                    onClick = { onSelectSession(session.id) },
                    modifier = Modifier.fillMaxWidth(),
                    enabled = !selected,
                ) {
                    val status = if (session.running) " ●" else ""
                    Text(
                        text = (session.title ?: "Session ${session.id.take(8)}") + status,
                        maxLines = 1,
                    )
                }
            }
        }
    }
}

@Composable
private fun ChatPanel(
    uiState: ChatUiState,
    onAction: (ChatAction) -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(modifier = modifier.padding(12.dp)) {
        uiState.errorMessage?.let { error ->
            Text(text = error, color = MaterialTheme.colorScheme.error)
            Spacer(modifier = Modifier.height(8.dp))
        }

        LazyColumn(
            modifier = Modifier.weight(1f),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            items(uiState.timeline, key = { timelineKey(it) }) { item ->
                TimelineRow(item = item, onAction = onAction)
            }
        }

        Row(modifier = Modifier.fillMaxWidth()) {
            ComposerBar(
                enabled = uiState.selectedSessionId != null && !uiState.isSending,
                isSending = uiState.isSending,
                onSend = { onAction(ChatAction.SendPrompt(it)) },
                modifier = Modifier.weight(1f),
            )
            Button(
                onClick = { onAction(ChatAction.CancelTurn) },
                enabled = uiState.selectedSessionId != null,
                modifier = Modifier.padding(start = 8.dp),
            ) {
                Text("Stop")
            }
        }
    }
}

@Composable
private fun TimelineRow(
    item: TimelineItem,
    onAction: (ChatAction) -> Unit,
) {
    when (item) {
        is TimelineItem.Message -> MessageRow(item.value)
        is TimelineItem.ToolCall -> ToolCallRow(item)
        is TimelineItem.ApprovalRequest -> ApprovalRow(
            requestId = item.requestId,
            approvalId = item.approvalId,
            toolName = item.toolName,
            reason = item.reason,
            onAction = onAction,
        )
        is TimelineItem.QuestionRequest -> QuestionRow(
            request = item,
            onAction = onAction,
        )
        is TimelineItem.Error -> Text(
            text = item.message,
            color = MaterialTheme.colorScheme.error,
            modifier = Modifier.fillMaxWidth(),
        )
    }
}

@Composable
private fun MessageRow(message: ChatMessage) {
    Column(modifier = Modifier.fillMaxWidth()) {
        Text(
            text = if (message.role == MessageRole.USER) "You" else "Assistant",
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        message.reasoning?.takeIf { it.isNotEmpty() }?.let { reasoning ->
            Text(
                text = reasoning,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        Text(text = message.text)
        if (message.streaming) {
            CircularProgressIndicator(
                modifier = Modifier
                    .width(12.dp)
                    .height(12.dp),
            )
        }
    }
}

@Composable
private fun ToolCallRow(call: TimelineItem.ToolCall) {
    Column(modifier = Modifier.fillMaxWidth()) {
        Text(
            text = "${call.name} ${call.status.label()}",
            style = MaterialTheme.typography.labelLarge,
        )
        call.arguments?.let { Text(text = it, style = MaterialTheme.typography.bodySmall) }
        call.result?.let { Text(text = it, style = MaterialTheme.typography.bodySmall) }
    }
}

private fun ToolRunStatus.label(): String = when (this) {
    ToolRunStatus.RUNNING -> "running..."
    ToolRunStatus.COMPLETED -> "done"
    ToolRunStatus.FAILED -> "failed"
}

@Composable
private fun ApprovalRow(
    requestId: String,
    approvalId: String,
    toolName: String,
    reason: String?,
    onAction: (ChatAction) -> Unit,
) {
    Column(modifier = Modifier.fillMaxWidth()) {
        Text(
            text = "Approve tool: $toolName",
            style = MaterialTheme.typography.titleSmall,
        )
        reason?.let { Text(text = it, style = MaterialTheme.typography.bodySmall) }
        Row {
            Button(
                onClick = { onAction(ChatAction.RespondApproval(requestId, approvalId, true)) },
            ) {
                Text("Allow")
            }
            OutlinedButton(
                onClick = { onAction(ChatAction.RespondApproval(requestId, approvalId, false)) },
                modifier = Modifier.padding(start = 8.dp),
            ) {
                Text("Reject")
            }
        }
    }
}

@Composable
private fun QuestionRow(
    request: TimelineItem.QuestionRequest,
    onAction: (ChatAction) -> Unit,
) {
    var selections by remember(request.requestId) {
        mutableStateOf<Map<String, Set<String>>>(emptyMap())
    }
    Column(modifier = Modifier.fillMaxWidth()) {
        request.questions.forEach { question ->
            QuestionItemEditor(
                question = question,
                selected = selections[question.id].orEmpty(),
                onSelect = { selected ->
                    selections = selections + (question.id to selected)
                },
            )
        }
        Button(
            onClick = {
                val answers = request.questions.map { question ->
                    QuestionAnswer(
                        questionId = question.id,
                        selectedOptions = selections[question.id]?.toList().orEmpty(),
                    )
                }
                onAction(ChatAction.AnswerQuestion(request.requestId, answers))
            },
            enabled = request.questions.all { question ->
                question.options.isEmpty() || !selections[question.id].isNullOrEmpty()
            },
        ) {
            Text("Answer")
        }
    }
}

@Composable
private fun QuestionItemEditor(
    question: QuestionItem,
    selected: Set<String>,
    onSelect: (Set<String>) -> Unit,
) {
    Column {
        Text(text = question.question, style = MaterialTheme.typography.titleSmall)
        question.detail?.let { Text(text = it, style = MaterialTheme.typography.bodySmall) }
        question.options.forEach { option ->
            val isSelected = option in selected
            if (isSelected) {
                Button(
                    onClick = { onSelect(selectedWithout(selected, option, question.multiSelect)) },
                ) {
                    Text(option)
                }
            } else {
                OutlinedButton(
                    onClick = { onSelect(selectedWith(selected, option, question.multiSelect)) },
                ) {
                    Text(option)
                }
            }
        }
    }
}

private fun selectedWith(current: Set<String>, option: String, multi: Boolean): Set<String> =
    if (multi) current + option else setOf(option)

private fun selectedWithout(current: Set<String>, option: String, multi: Boolean): Set<String> =
    if (multi) current - option else emptySet()

@Composable
private fun ComposerBar(
    enabled: Boolean,
    isSending: Boolean,
    onSend: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    var draft by remember { mutableStateOf("") }
    Row(
        modifier = modifier,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        OutlinedTextField(
            value = draft,
            onValueChange = { draft = it },
            modifier = Modifier.weight(1f),
            enabled = enabled,
            placeholder = { Text("Message DeepSeek Harness") },
        )
        Button(
            onClick = {
                onSend(draft)
                draft = ""
            },
            modifier = Modifier.padding(start = 8.dp),
            enabled = enabled && !isSending && draft.isNotBlank(),
        ) {
            Text(if (isSending) "Sending" else "Send")
        }
    }
}

private fun timelineKey(item: TimelineItem): String = when (item) {
    is TimelineItem.Message -> "message:${item.value.id}:${item.value.streaming}"
    is TimelineItem.ToolCall -> "tool:${item.id}:${item.status}"
    is TimelineItem.ApprovalRequest -> "approval:${item.requestId}"
    is TimelineItem.QuestionRequest -> "question:${item.requestId}"
    is TimelineItem.Error -> "error:${item.id}"
}

@Preview(showBackground = true, widthDp = 840)
@Composable
private fun ChatScreenPreview() {
    DeepSeekHarnessAndroidTheme {
        ChatScreen(
            uiState = ChatUiState(
                connection = ConnectionState(
                    phase = ConnectionPhase.CONNECTED,
                    hostDescription = HostDescription(version = "preview", cwd = "/tmp"),
                ),
                sessions = listOf(SessionSummary(id = "s1", title = "Preview session")),
                selectedSessionId = "s1",
                timeline = listOf(
                    TimelineItem.Message(
                        ChatMessage(
                            id = "m1",
                            sessionId = "s1",
                            role = MessageRole.ASSISTANT,
                            text = "Kotlin best-practice skeleton.",
                        ),
                    ),
                    TimelineItem.ToolCall(
                        id = "call-1",
                        name = "bash",
                        arguments = "ls -la",
                        result = "README.md",
                        status = ToolRunStatus.COMPLETED,
                    ),
                    TimelineItem.ApprovalRequest(
                        requestId = "rpc-1",
                        sessionId = "s1",
                        approvalId = "approval-1",
                        toolName = "bash",
                        reason = "Would run a command",
                    ),
                    TimelineItem.QuestionRequest(
                        requestId = "rpc-2",
                        questions = listOf(
                            QuestionItem(
                                id = "q1",
                                question = "Continue?",
                                options = listOf("yes", "no"),
                            ),
                        ),
                    ),
                ),
            ),
            onAction = {},
        )
    }
}
