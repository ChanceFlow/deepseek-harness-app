package com.deepseek.harness.android.ui.workspace

import androidx.compose.runtime.Immutable
import com.deepseek.harness.android.domain.model.DirectoryListing
import com.deepseek.harness.android.domain.model.WorkspaceSummary

@Immutable
data class WorkspaceUiState(
    val workspaces: List<WorkspaceSummary> = emptyList(),
    val isLoading: Boolean = false,
    val errorMessage: String? = null,
    val directoryListing: DirectoryListing? = null,
    val directoryBrowserOpen: Boolean = false,
    val directoryLoading: Boolean = false,
)

sealed interface WorkspaceAction {
    data class Create(val path: String) : WorkspaceAction
    data class Rename(val workspaceId: String, val title: String) : WorkspaceAction
    data class Delete(val workspaceId: String) : WorkspaceAction
    data object Refresh : WorkspaceAction
    data object DismissError : WorkspaceAction
    data object OpenDirectoryBrowser : WorkspaceAction
    data object CloseDirectoryBrowser : WorkspaceAction
    data class NavigateDirectory(val path: String?) : WorkspaceAction
    data class CreateDirectory(val parentPath: String, val name: String) : WorkspaceAction
}
