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
 * One credential-reference state: whether the host holds a
 * value, where it comes from, and whether this client could store one.
 */
data class CredentialStatus(
    val ref: String,
    val configured: Boolean,
    val source: String?,
    val writable: Boolean,
)

/** One path-addressed settings mutation; [op] is "set" or "unset". */
data class SettingPathOp(
    val op: String,
    val path: List<String>,
    val jsonValue: String? = null,
) {
    init {
        require(op == "set" || op == "unset") { "op must be set or unset" }
        require(path.isNotEmpty()) { "path must be non-empty" }
        require(op == "unset" || jsonValue != null) { "set op requires a value" }
    }
}
