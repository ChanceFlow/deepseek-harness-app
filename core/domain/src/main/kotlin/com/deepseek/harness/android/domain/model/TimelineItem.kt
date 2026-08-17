package com.deepseek.harness.android.domain.model

/**
 * Neutral timeline vocabulary rendered by Compose.
 *
 * Only :core:harness-adapter is allowed to create these from dsh events.
 */
sealed interface TimelineItem {
    data class Message(val value: ChatMessage) : TimelineItem

    data class ToolCall(
        val id: String,
        val name: String,
        val input: String? = null,
        val output: String? = null,
        val success: Boolean? = null,
    ) : TimelineItem

    data class ApprovalRequest(
        val id: String,
        val toolName: String,
        val reason: String? = null,
    ) : TimelineItem
}
