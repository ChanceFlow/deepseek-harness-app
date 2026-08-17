package com.deepseek.harness.android.domain.model

data class SessionSummary(
    val id: String,
    val title: String? = null,
    val running: Boolean = false,
    val blank: Boolean = true,
    val workspaceId: String? = null,
    val updatedAtEpochMs: Long = 0L,
    val cwd: String? = null,
    val agentPreset: String? = null,
) {
    /**
     * Same label rule as the Web client: durable title first, then the
     * canonical workspace path basename, then the raw session id.
     */
    val displayTitle: String
        get() = title?.takeIf { it.isNotBlank() }
            ?: cwd
                ?.split('/', '\\')
                ?.lastOrNull { it.isNotBlank() }
                ?.takeIf { it.isNotBlank() }
            ?: id
}

data class CreateSessionRequest(
    val sessionId: String? = null,
    val workspaceId: String? = null,
    val cwd: String? = null,
    val agentPreset: String? = null,
)

enum class QueuePlacement {
    QUEUED,
    STEERING,
    CONTEXT,
}

enum class QueueUpdateKind {
    REMOVE,
    STEER,
}

data class QueueUpdateRequest(
    val sessionId: String,
    val itemId: String,
    val kind: QueueUpdateKind,
)
