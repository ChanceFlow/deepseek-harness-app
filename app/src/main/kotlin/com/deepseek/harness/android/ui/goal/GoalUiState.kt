package com.deepseek.harness.android.ui.goal

import androidx.compose.runtime.Immutable
import com.deepseek.harness.android.domain.model.GoalProjection
import com.deepseek.harness.android.domain.model.SessionSummary

@Immutable
data class GoalUiState(
    val sessions: List<SessionSummary> = emptyList(),
    val selectedSessionId: String? = null,
    val goal: GoalProjection? = null,
    val isLoading: Boolean = false,
    val errorMessage: String? = null,
)

sealed interface GoalAction {
    data class SelectSession(val sessionId: String) : GoalAction
    data class Create(val objective: String, val maxRounds: Long?) : GoalAction
    data object Pause : GoalAction
    data object Resume : GoalAction
    data object Complete : GoalAction
    data object Clear : GoalAction
    data object DismissError : GoalAction
    data object Refresh : GoalAction
}
