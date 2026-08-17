package com.deepseek.harness.android.ui.models

import androidx.compose.runtime.Immutable
import com.deepseek.harness.android.domain.model.ModelSelection
import com.deepseek.harness.android.domain.model.SessionModels
import com.deepseek.harness.android.domain.model.SessionSummary

@Immutable
data class ModelsUiState(
    val sessions: List<SessionSummary> = emptyList(),
    val selectedSessionId: String? = null,
    val models: SessionModels? = null,
    val selected: ModelSelection? = null,
    val isLoading: Boolean = false,
    val errorMessage: String? = null,
)

sealed interface ModelsAction {
    data class SelectSession(val sessionId: String) : ModelsAction
    data class SelectModel(val provider: String, val model: String) : ModelsAction
    data object Refresh : ModelsAction
    data object DismissError : ModelsAction
}
