package com.deepseek.harness.android.harness.dto

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonObject

/** Session list value decoded from the dsh unary response. */
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

/** A decoded mux envelope. `event` stays wide until the event-type switch. */
@Serializable
internal data class MuxEnvelope(
    val type: String? = null,
    val sessionId: String? = null,
    val event: JsonObject? = null,
    val approvalId: String? = null,
    val toolName: String? = null,
    val reason: String? = null,
)
