package com.deepseek.harness.android.harness.dto

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonObject

@Serializable
internal data class SessionListValue(
    val items: List<SessionWire> = emptyList(),
)

@Serializable
internal data class SessionWire(
    val sessionId: String,
    val updatedAt: Long = 0L,
    val running: Boolean = false,
    val blank: Boolean = true,
    val parentSessionId: String? = null,
    val origin: String? = null,
    val cwd: String? = null,
)

@Serializable
internal data class SessionCreateValue(
    val sessionId: String,
)

@Serializable
internal data class SessionPromptValue(
    val accepted: Boolean = true,
)

@Serializable
internal data class SessionCancelValue(
    val accepted: Boolean = true,
)

@Serializable
internal data class SessionHistoryValue(
    val events: List<HistoryEntryWire> = emptyList(),
    val hasMore: Boolean = false,
)

@Serializable
internal data class HistoryEntryWire(
    val event: JsonObject,
)
