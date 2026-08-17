package com.deepseek.harness.android.ui.workspace

import androidx.compose.runtime.Immutable
import com.deepseek.harness.android.domain.model.WorkspaceSummary

@Immutable
data class WorkspaceUiState(
    val workspaces: List<WorkspaceSummary> = emptyList(),
    val isLoading: Boolean = false,
    val errorMessage: String? = null,
)

sealed interface WorkspaceAction {
    data class Create(val path: String) : WorkspaceAction
    data class Delete(val workspaceId: String) : WorkspaceAction
    data object Refresh : WorkspaceAction
    data object DismissError : WorkspaceAction
}
