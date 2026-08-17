package com.deepseek.harness.android.harness.dto

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonObject

/**
 * A small subset of the dsh wire vocabulary. These types exist only in this
 * module; they must never leak into :core:domain or :app.
 */
@Serializable
data class MuxFrame(
    val type: String,
    val sessionId: String? = null,
    val event: JsonObject? = null,
)

@Serializable
data class HostFrame(
    val type: String,
    val sessionId: String? = null,
    val running: Boolean? = null,
)
