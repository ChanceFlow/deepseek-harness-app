package com.deepseek.harness.android.domain.model

data class SubagentEntry(
    val id: String,
    val kind: String,
    val mode: String? = null,
    val activity: String? = null,
    val hasChildren: Boolean = false,
    val label: String? = null,
    val reason: String? = null,
) {
    val isInterruptible: Boolean
        get() = kind == "child" && mode == "continuable" && activity == "running"
}

data class SubagentCatalog(
    val parentSessionId: String = "",
    val entries: List<SubagentEntry> = emptyList(),
    val parentAvailable: Boolean = false,
)
