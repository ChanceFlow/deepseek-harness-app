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


// Workspace and model catalog shapes decoded by the adapter only.

@Serializable
internal data class WorkspaceListValue(
    val items: List<WorkspaceWire> = emptyList(),
)

@Serializable
internal data class WorkspaceWire(
    val workspaceId: String,
    val path: String,
    val title: String,
    val sessionIds: List<String> = emptyList(),
    val createdAt: String = "",
    val updatedAt: String = "",
)

@Serializable
internal data class WorkspaceCreateValue(
    val workspace: WorkspaceWire,
    val created: Boolean = false,
)

@Serializable
internal data class ModelSelectionWire(
    val provider: String,
    val model: String,
    val reasoningEffort: String? = null,
)

@Serializable
internal data class ModelCatalogModelWire(
    val id: String,
    val name: String,
    val description: String? = null,
    val reasoning: ModelReasoningWire? = null,
)

@Serializable
internal data class ModelReasoningWire(
    val efforts: List<ModelReasoningEffortWire> = emptyList(),
    val defaultEffort: String? = null,
)

@Serializable
internal data class ModelReasoningEffortWire(
    val id: String,
    val name: String,
    val description: String? = null,
)

@Serializable
internal data class ModelProviderGroupWire(
    val id: String,
    val name: String,
    val models: List<ModelCatalogModelWire> = emptyList(),
)

@Serializable
internal data class ModelCatalogFailureWire(
    val id: String,
    val name: String,
    val message: String,
)

@Serializable
internal data class SessionModelsValue(
    val current: ModelSelectionWire,
    val routable: Boolean = false,
    val groups: List<ModelProviderGroupWire> = emptyList(),
    val failures: List<ModelCatalogFailureWire> = emptyList(),
)

@Serializable
internal data class SessionSelectModelValue(
    val selected: ModelSelectionWire,
)

@Serializable
internal data class SessionSearchValue(
    val items: List<SessionSearchItemWire> = emptyList(),
)

@Serializable
internal data class SessionSearchItemWire(
    val sessionId: String,
    val snippet: String,
)

@Serializable
internal data class SessionRenameValue(
    val title: String,
)

@Serializable
internal data class SessionForkValue(
    val sessionId: String,
)

@Serializable
internal data class SessionQueueUpdateValue(
    val accepted: Boolean = true,
)
