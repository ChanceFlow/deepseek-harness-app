package com.deepseek.harness.android.domain.model

/**
 * Neutral timeline vocabulary rendered by Compose.
 *
 * Only :core:harness-adapter is allowed to create these from dsh events.
 */
enum class ToolRunStatus {
    RUNNING,
    COMPLETED,
    FAILED,
}

sealed interface TimelineItem {
    data class Message(val value: ChatMessage) : TimelineItem

    data class ToolCall(
        val id: String,
        val name: String,
        val arguments: String? = null,
        val result: String? = null,
        val isError: Boolean = false,
        val status: ToolRunStatus = ToolRunStatus.RUNNING,
    ) : TimelineItem

    data class ApprovalRequest(
        val requestId: String,
        val sessionId: String,
        val approvalId: String,
        val toolName: String,
        val callId: String? = null,
        val reason: String? = null,
    ) : TimelineItem

    data class QuestionRequest(
        val requestId: String,
        val questions: List<QuestionItem>,
    ) : TimelineItem

    data class Queue(
        val items: List<SessionQueueItem> = emptyList(),
    ) : TimelineItem

    data class Jobs(
        val jobs: List<JobView> = emptyList(),
    ) : TimelineItem

    data class Error(
        val id: String,
        val message: String,
        val code: String? = null,
    ) : TimelineItem
}

data class QuestionItem(
    val id: String,
    val question: String,
    val options: List<String> = emptyList(),
    val multiSelect: Boolean = false,
    val detail: String? = null,
    val header: String? = null,
    val optionDescriptions: Map<String, String> = emptyMap(),
)

data class ApprovalAnswer(
    val requestId: String,
    val sessionId: String,
    val approvalId: String,
    val allowed: Boolean,
)

data class QuestionAnswer(
    val questionId: String,
    val selectedOptions: List<String>,
    val customText: String? = null,
)

data class SessionQueueItem(
    val itemId: String,
    val placement: QueuePlacement,
    val text: String,
)
