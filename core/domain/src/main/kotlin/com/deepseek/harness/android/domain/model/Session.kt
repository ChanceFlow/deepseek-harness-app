package com.deepseek.harness.android.domain.model

data class SessionSummary(
    val id: String,
    val title: String? = null,
    val running: Boolean = false,
    val blank: Boolean = true,
    val workspaceId: String? = null,
    val updatedAtEpochMs: Long = 0L,
)
