package com.deepseek.harness.android.harness.dto

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject

@Serializable
internal data class SessionListValue(
    val items: List<SessionWire> = emptyList(),
)

@Serializable
internal data class SessionProjectionsValue(
    val values: JsonObject? = null,
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
    val agentPreset: String? = null,
    val projections: SessionProjectionsValue? = null,
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
    val projections: SessionProjectionsValue? = null,
)

@Serializable
internal data class HistoryEntryWire(
    val event: JsonObject,
)


// Workspace and model catalog shapes decoded by the adapter only.

@Serializable
internal data class WorkspaceListValue(
    val items: List<WorkspaceWire> = emptyList(),
    val archivedSessionIds: List<String> = emptyList(),
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
internal data class WorkspaceRenameValue(
    val workspace: WorkspaceWire,
)

@Serializable
internal data class WorkspaceArchiveValue(
    val archivedSessionIds: List<String> = emptyList(),
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

@Serializable
internal data class SubagentListValue(
    val entries: List<SubagentEntryWire> = emptyList(),
    val parentAvailable: Boolean = false,
)

@Serializable
internal data class SubagentEntryWire(
    val kind: String = "child",
    val id: String,
    val mode: String? = null,
    val activity: String? = null,
    val hasChildren: Boolean = false,
    val label: String? = null,
    val reason: String? = null,
)

@Serializable
internal data class SubagentInterruptValue(
    val accepted: Boolean = true,
)

@Serializable
internal data class SubagentPromptValue(
    val messageId: String,
)


// Goal domain shapes. Values are decoded only inside the adapter.

@Serializable
internal data class GoalRefWire(
    val id: String,
    val revision: Long,
)

@Serializable
internal data class GoalSnapshotWire(
    val id: String,
    val revision: Long,
    val objective: String,
    val phase: String,
    val blockedReason: GoalBlockReasonWire? = null,
    val maxGoalRounds: Long,
)

@Serializable
internal data class GoalBlockReasonWire(
    val code: String,
    val message: String,
)

@Serializable
internal data class GoalProjectionWire(
    val goal: GoalSnapshotWire,
    val roundsStarted: Long = 0L,
    val createdAt: Long = 0L,
    val updatedAt: Long = 0L,
)

@Serializable
internal data class GoalRefValue(
    val ref: GoalRefWire,
)


// Host in-app directory browser shapes.

@Serializable
internal data class DirectoryEntryWire(
    val name: String,
    val path: String,
    val hidden: Boolean,
)

@Serializable
internal data class DirectoryListingValue(
    val path: String,
    val home: String,
    val crumbs: List<DirectoryEntryWire> = emptyList(),
    val entries: List<DirectoryEntryWire> = emptyList(),
    val truncated: Boolean,
)

@Serializable
internal data class DirectoryCreateValue(
    val path: String,
)

// Read-only settings/credentials describe shapes. The `schema` field of a
// namespace view stays undecoded: the Android client renders only summary
// columns, and `ignoreUnknownKeys` tolerates its presence.

@Serializable
internal data class SettingsSecretWire(
    val path: List<String> = emptyList(),
    val set: Boolean = false,
)

@Serializable
internal data class SettingsNamespaceWire(
    val ns: String,
    val value: JsonElement? = null,
    val base: JsonElement? = null,
    val user: JsonElement? = null,
    val applies: String = "live",
    val secrets: List<SettingsSecretWire> = emptyList(),
    val revision: Long = 0L,
)

@Serializable
internal data class SettingsDescribeValue(
    val writable: Boolean,
    val hasDocument: Boolean = false,
    val namespaces: List<SettingsNamespaceWire> = emptyList(),
)

@Serializable
internal data class CredentialViewWire(
    val configured: Boolean,
    val source: String? = null,
    val writable: Boolean = false,
)

@Serializable
internal data class CredentialsDescribeValue(
    val credentials: Map<String, CredentialViewWire> = emptyMap(),
)

// Image attachment shapes: inline prompt parts plus the durable
// `session.attachment` download view and the `imageLimits` projection.

@Serializable
internal data class AttachmentRefWire(
    val attachmentId: String,
    val mediaType: String,
    val bytes: Long = 0L,
    val width: Int = 0,
    val height: Int = 0,
    val name: String? = null,
)

@Serializable
internal data class SessionAttachmentValue(
    val attachment: AttachmentRefWire,
    /** Base64-encoded image bytes. */
    val data: String,
)

@Serializable
internal data class ImageLimitsWire(
    val maxImageBytes: Long,
    val maxImagesPerMessage: Int,
    val maxMessageImageBytes: Long,
    val maxImagePixels: Long,
    val mediaTypes: List<String> = emptyList(),
)

/** `plan` session projection: the logged plan-mode collaboration state. */
@Serializable
internal data class PlanProjectionWire(
    val active: Boolean,
    val pending: Boolean,
)
