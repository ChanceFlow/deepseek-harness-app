package com.deepseek.harness.android.domain.model

/**
 * Read-only projection of one host settings namespace, mirrored from the
 * `settings.describe` wire view. Values stay on the host; the client only
 * renders the summary columns.
 */
data class SettingsNamespace(
    val ns: String,
    val applies: SettingsApplies,
    val revision: Long,
    val hasUserLayer: Boolean,
    val secretCount: Int,
)

/** When a namespace edit takes effect, as the host reports it. */
enum class SettingsApplies {
    LIVE,
    RESTART,
    UNKNOWN,
}

/**
 * Read-only settings snapshot: whether the host accepts writes, whether a
 * settings document exists, and one row per namespace. `credentialRefs`
 * collects every credential reference the namespace values name, so the UI
 * can follow up with one batched `credentials.describe`.
 */
data class SettingsSnapshot(
    val writable: Boolean,
    val hasDocument: Boolean,
    val namespaces: List<SettingsNamespace>,
    val credentialRefs: List<String>,
)

/**
 * Read-only state of one credential reference: whether the host holds a
 * value, where it comes from, and whether this client could store one.
 */
data class CredentialStatus(
    val ref: String,
    val configured: Boolean,
    val source: String?,
    val writable: Boolean,
)
