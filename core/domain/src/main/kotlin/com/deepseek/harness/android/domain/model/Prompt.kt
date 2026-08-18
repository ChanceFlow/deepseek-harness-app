package com.deepseek.harness.android.domain.model

enum class PromptMode {
    QUEUE,
    STEER,
}

data class SendMessageRequest(
    val sessionId: String,
    val text: String,
    val mode: PromptMode = PromptMode.QUEUE,
    /** Inline image parts appended after the text part, web-composer parity. */
    val images: List<PendingImage> = emptyList(),
)
