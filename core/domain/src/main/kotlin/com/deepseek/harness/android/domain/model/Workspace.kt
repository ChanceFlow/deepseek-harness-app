package com.deepseek.harness.android.domain.model

data class WorkspaceSummary(
    val workspaceId: String,
    val path: String,
    val title: String,
    val sessionIds: List<String> = emptyList(),
    val createdAt: String = "",
    val updatedAt: String = "",
)

data class SessionSearchResult(
    val sessionId: String,
    val snippet: String,
)
