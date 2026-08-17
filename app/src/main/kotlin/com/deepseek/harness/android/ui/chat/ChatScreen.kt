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
import com.deepseek.harness.android.domain.model.MessageRole
import com.deepseek.harness.android.domain.model.SessionSummary
import com.deepseek.harness.android.domain.model.TimelineItem
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
            if (useTwoPanes) {
                Row(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(innerPadding),
                ) {
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
                Column(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(innerPadding),
                ) {
                    SessionPanel(
                        sessions = uiState.sessions,
                        selectedSessionId = uiState.selectedSessionId,
                        onSelectSession = { onAction(ChatAction.SelectSession(it)) },
                        onCreateSession = { onAction(ChatAction.CreateSession) },
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(180.dp),
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
                    Text(
                        text = session.title ?: "Session ${session.id.take(8)}",
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
            Text(
                text = error,
                color = MaterialTheme.colorScheme.error,
            )
            Spacer(modifier = Modifier.height(8.dp))
        }

        LazyColumn(
            modifier = Modifier.weight(1f),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            items(uiState.timeline, key = { timelineKey(it) }) { item ->
                when (item) {
                    is TimelineItem.Message -> Text(
                        text = if (item.value.role == MessageRole.USER) {
                            "You: ${item.value.text}"
                        } else {
                            item.value.text
                        },
                        modifier = Modifier.fillMaxWidth(),
                    )
                    is TimelineItem.ToolCall -> Text(
                        text = "Tool ${item.name}: ${item.output ?: item.input.orEmpty()}",
                        modifier = Modifier.fillMaxWidth(),
                    )
                    is TimelineItem.ApprovalRequest -> Text(
                        text = "Approval requested for ${item.toolName}",
                        modifier = Modifier.fillMaxWidth(),
                    )
                }
            }
        }

        ComposerBar(
            enabled = uiState.selectedSessionId != null && !uiState.isSending,
            onSend = { onAction(ChatAction.SendPrompt(it)) },
        )
    }
}

@Composable
private fun ComposerBar(
    enabled: Boolean,
    onSend: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    var draft by remember { mutableStateOf("") }
    Row(
        modifier = modifier.fillMaxWidth(),
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
            enabled = enabled && draft.isNotBlank(),
        ) {
            Text("Send")
        }
    }
}

private fun timelineKey(item: TimelineItem): String = when (item) {
    is TimelineItem.Message -> "message:${item.value.id}"
    is TimelineItem.ToolCall -> "tool:${item.id}"
    is TimelineItem.ApprovalRequest -> "approval:${item.id}"
}

@Preview(showBackground = true, widthDp = 840)
@Composable
private fun ChatScreenPreview() {
    DeepSeekHarnessAndroidTheme {
        ChatScreen(
            uiState = ChatUiState(
                sessions = listOf(
                    SessionSummary(id = "s1", title = "Preview session"),
                ),
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
                ),
            ),
            onAction = {},
        )
    }
}
