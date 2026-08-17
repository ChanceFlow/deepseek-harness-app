package com.deepseek.harness.android.ui.subagents

import androidx.compose.runtime.Immutable
import com.deepseek.harness.android.domain.model.SessionSummary
import com.deepseek.harness.android.domain.model.SubagentCatalog
import com.deepseek.harness.android.domain.model.TimelineItem

@Immutable
data class SubagentUiState(
    val sessions: List<SessionSummary> = emptyList(),
    val selectedParentId: String? = null,
    val catalog: SubagentCatalog = SubagentCatalog(),
    val selectedChildId: String? = null,
    val childTimeline: List<TimelineItem> = emptyList(),
    val isSendingChild: Boolean = false,
    val isLoading: Boolean = false,
    val errorMessage: String? = null,
)

sealed interface SubagentAction {
    data class SelectParent(val sessionId: String) : SubagentAction
    data class OpenChild(val childSessionId: String) : SubagentAction
    data class SendPrompt(val text: String) : SubagentAction
    data class Interrupt(val childSessionId: String) : SubagentAction
    data object Refresh : SubagentAction
    data object DismissError : SubagentAction
}
