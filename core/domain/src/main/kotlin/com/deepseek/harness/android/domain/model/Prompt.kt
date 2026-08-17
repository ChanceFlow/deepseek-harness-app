package com.deepseek.harness.android.domain.model

enum class PromptMode {
    QUEUE,
    STEER,
}

data class SendMessageRequest(
    val sessionId: String,
    val text: String,
    val mode: PromptMode = PromptMode.QUEUE,
)
