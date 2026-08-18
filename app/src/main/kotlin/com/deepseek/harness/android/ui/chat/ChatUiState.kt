package com.deepseek.harness.android.ui.chat

import androidx.compose.runtime.Immutable
import com.deepseek.harness.android.domain.model.ConnectionState
import com.deepseek.harness.android.domain.model.PromptMode
import com.deepseek.harness.android.domain.model.QuestionAnswer
import com.deepseek.harness.android.domain.model.QueueUpdateKind
import com.deepseek.harness.android.domain.model.SessionSearchResult
import com.deepseek.harness.android.domain.model.SessionSummary
import com.deepseek.harness.android.domain.model.TimelineItem
import com.deepseek.harness.android.domain.model.WorkspaceSummary

@Immutable
data class ChatUiState(
    val connection: ConnectionState = ConnectionState(),
    val sessions: List<SessionSummary> = emptyList(),
    val workspaces: List<WorkspaceSummary> = emptyList(),
    val selectedSessionId: String? = null,
    val timeline: List<TimelineItem> = emptyList(),
    val hasMoreOlder: Boolean = false,
    val isLoadingOlder: Boolean = false,
    val searchResults: List<SessionSearchResult> = emptyList(),
    val isSending: Boolean = false,
    val errorMessage: String? = null,
)

sealed interface ChatAction {
    data class SelectSession(val sessionId: String) : ChatAction
    data class SendPrompt(
        val text: String,
        val mode: PromptMode = PromptMode.QUEUE,
    ) : ChatAction
    data object CancelTurn : ChatAction
    data object CreateSession : ChatAction
    data class CreateSessionInWorkspace(val workspaceId: String? = null) : ChatAction
    data object DismissError : ChatAction
    data object RetrySessions : ChatAction
    data object LoadOlderHistory : ChatAction

    data class RespondApproval(
        val requestId: String,
        val approvalId: String,
        val allowed: Boolean,
    ) : ChatAction

    data class AnswerQuestion(
        val requestId: String,
        val answers: List<QuestionAnswer>,
    ) : ChatAction

    data class SearchSessions(val query: String) : ChatAction
    data class RenameSession(val sessionId: String, val title: String) : ChatAction
    data class ArchiveSession(val sessionId: String) : ChatAction
    data class ForkSession(val sessionId: String) : ChatAction
    data class UpdateQueue(
        val itemId: String,
        val kind: QueueUpdateKind,
        val text: String? = null,
    ) : ChatAction
}
