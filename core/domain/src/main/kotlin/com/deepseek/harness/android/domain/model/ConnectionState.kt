package com.deepseek.harness.android.domain.model

enum class ConnectionPhase {
    DISCONNECTED,
    CONNECTING,
    CONNECTED,
    RECONNECTING,
}

data class HostDescription(
    val version: String,
    val cwd: String,
    val provider: String? = null,
    val model: String? = null,
    val attachedSessions: Int = 0,
    val canOpenPath: Boolean = false,
)

data class ConnectionState(
    val phase: ConnectionPhase = ConnectionPhase.DISCONNECTED,
    val hostDescription: HostDescription? = null,
    val generation: Long = 0L,
) {
    val isConnected: Boolean get() = phase == ConnectionPhase.CONNECTED
}
