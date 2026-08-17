package com.deepseek.harness.android.domain.model

enum class MessageRole {
    USER,
    ASSISTANT,
}

/**
 * UI-facing chat message.
 *
 * Deliberately contains no dsh SessionEvent, ContentBlock, or MuxFrame type.
 */
data class ChatMessage(
    val id: String,
    val sessionId: String,
    val role: MessageRole,
    val text: String,
    val createdAtEpochMs: Long = 0L,
)
