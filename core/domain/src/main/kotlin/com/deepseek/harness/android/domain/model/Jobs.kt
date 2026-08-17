package com.deepseek.harness.android.domain.model

enum class JobStatus {
    RUNNING,
    STOPPING,
    COMPLETED,
    KILLED,
    FAILED,
}

data class JobView(
    val id: String,
    val kind: String,
    val label: String,
    val status: JobStatus,
    val detail: String? = null,
    val startedAt: Long = 0L,
    val finishedAt: Long? = null,
)
