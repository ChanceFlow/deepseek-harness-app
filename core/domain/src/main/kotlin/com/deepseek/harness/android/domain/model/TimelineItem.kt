package com.deepseek.harness.android.domain.model

/**
 * The neutral timeline vocabulary Compose renders.
 * Harness-aware modules translate dsh events into these items.
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
