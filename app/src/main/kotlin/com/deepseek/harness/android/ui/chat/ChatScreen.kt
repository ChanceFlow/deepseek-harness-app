package com.deepseek.harness.android.ui.chat

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.weight
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.deepseek.harness.android.domain.model.ChatMessage
import com.deepseek.harness.android.domain.model.MessageRole

data class ChatUiState(
    val sessionTitle: String = "New session",
    val messages: List<ChatMessage> = emptyList(),
)

/**
 * Chat page. All spatial layout choices live here, in Kotlin/Compose.
 * The rest of the app never participates in this screen's layout.
 */
@Composable
fun ChatRoute(modifier: Modifier = Modifier) {
    ChatScreen(
        uiState = ChatUiState(
            sessionTitle = "Preview",
            messages = listOf(
                ChatMessage(
                    id = "welcome-1",
                    sessionId = "local-preview",
                    role = MessageRole.ASSISTANT,
                    text = "DeepSeek Harness Android skeleton is ready.",
                ),
            ),
        ),
        modifier = modifier,
    )
}

@Composable
fun ChatScreen(
    uiState: ChatUiState,
    modifier: Modifier = Modifier,
) {
    Scaffold(modifier = modifier.fillMaxSize()) { innerPadding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding)
                .padding(16.dp),
        ) {
            Text(
                text = uiState.sessionTitle,
                style = MaterialTheme.typography.titleLarge,
            )

            Spacer(modifier = Modifier.height(8.dp))

            LazyColumn(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                items(uiState.messages, key = { it.id }) { message ->
                    Text(
                        text = if (message.role == MessageRole.USER) {
                            "You: ${message.text}"
                        } else {
                            message.text
                        },
                        modifier = Modifier.fillMaxWidth(),
                    )
                }
            }

            Row(modifier = Modifier.fillMaxWidth()) {
                var draft by remember { mutableStateOf("") }
                OutlinedTextField(
                    value = draft,
                    onValueChange = { draft = it },
                    modifier = Modifier.weight(1f),
                    placeholder = { Text("Message DeepSeek Harness") },
                )
                Button(
                    onClick = { draft = "" },
                    modifier = Modifier.padding(start = 8.dp),
                ) {
                    Text("Send")
                }
            }
        }
    }
}
