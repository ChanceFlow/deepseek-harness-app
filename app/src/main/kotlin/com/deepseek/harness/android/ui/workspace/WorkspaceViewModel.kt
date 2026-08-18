package com.deepseek.harness.android.ui.workspace

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.deepseek.harness.android.domain.model.DirectoryListing
import com.deepseek.harness.android.domain.repository.ChatRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

@HiltViewModel
class WorkspaceViewModel @Inject constructor(
    private val chatRepository: ChatRepository,
) : ViewModel() {

    private val isLoading = MutableStateFlow(false)
    private val errorMessage = MutableStateFlow<String?>(null)
    private val directoryListing = MutableStateFlow<DirectoryListing?>(null)
    private val directoryBrowserOpen = MutableStateFlow(false)
    private val directoryLoading = MutableStateFlow(false)

    val uiState: StateFlow<WorkspaceUiState> = combine(
        combine(
            chatRepository.observeWorkspaces(),
            isLoading,
            errorMessage,
            directoryListing,
            directoryBrowserOpen,
        ) { workspaces, loading, error, listing, open ->
            WorkspaceUiState(
                workspaces = workspaces,
                isLoading = loading,
                errorMessage = error,
                directoryListing = listing,
                directoryBrowserOpen = open,
            )
        },
        directoryLoading,
    ) { base, loading ->
        base.copy(directoryLoading = loading)
    }.stateIn(
        scope = viewModelScope,
        started = SharingStarted.WhileSubscribed(stopTimeoutMillis = 5_000),
        initialValue = WorkspaceUiState(),
    )

    init {
        refresh()
    }

    fun onAction(action: WorkspaceAction) {
        when (action) {
            is WorkspaceAction.Create -> create(action.path)
            is WorkspaceAction.Rename -> rename(action.workspaceId, action.title)
            is WorkspaceAction.Delete -> delete(action.workspaceId)
            is WorkspaceAction.MoveUp -> move(action.workspaceId, up = true)
            is WorkspaceAction.MoveDown -> move(action.workspaceId, up = false)
            WorkspaceAction.Refresh -> refresh()
            WorkspaceAction.DismissError -> errorMessage.value = null
            WorkspaceAction.OpenDirectoryBrowser -> openDirectoryBrowser()
            WorkspaceAction.CloseDirectoryBrowser -> closeDirectoryBrowser()
            is WorkspaceAction.NavigateDirectory -> navigateDirectory(action.path)
            is WorkspaceAction.CreateDirectory -> createDirectory(action.parentPath, action.name)
        }
    }

    /**
     * Reorder through `workspace.insertBefore`: moving up anchors on the row
     * above, moving down anchors on the row two below (append when that is
     * past the end). The host response re-orders the local list.
     */
    private fun move(workspaceId: String, up: Boolean) {
        val current = uiState.value.workspaces
        val index = current.indexOfFirst { it.workspaceId == workspaceId }
        if (index < 0) return
        val anchor: String? = if (up) {
            current.getOrNull(index - 1)?.workspaceId ?: return
        } else {
            current.getOrNull(index + 2)?.workspaceId
        }
        viewModelScope.launch {
            runCatchingForUi { chatRepository.moveWorkspace(workspaceId, anchor) }
        }
    }

    private fun openDirectoryBrowser() {
        directoryListing.value = null
        directoryBrowserOpen.value = true
        loadDirectory(null)
    }

    private fun closeDirectoryBrowser() {
        directoryBrowserOpen.value = false
        directoryListing.value = null
    }

    private fun navigateDirectory(path: String?) {
        if (path.isNullOrBlank()) return
        loadDirectory(path)
    }

    private fun createDirectory(parentPath: String, name: String) {
        if (name.isBlank()) return
        viewModelScope.launch {
            runCatchingForUi {
                chatRepository.createDirectory(parentPath, name.trim())
            }
            loadDirectory(parentPath)
        }
    }

    private fun loadDirectory(path: String?) {
        viewModelScope.launch {
            directoryLoading.value = true
            try {
                runCatchingForUi { chatRepository.listDirectory(path) }?.let {
                    directoryListing.value = it
                }
            } finally {
                directoryLoading.value = false
            }
        }
    }

    private fun refresh() {
        viewModelScope.launch {
            runCatchingForUi { chatRepository.refreshWorkspaces() }
        }
    }

    private fun create(path: String) {
        if (path.isBlank()) return
        viewModelScope.launch {
            isLoading.value = true
            try {
                runCatchingForUi { chatRepository.createWorkspace(path.trim()) }
            } finally {
                isLoading.value = false
            }
        }
    }

    private fun rename(workspaceId: String, title: String) {
        if (title.isBlank()) return
        viewModelScope.launch {
            isLoading.value = true
            try {
                runCatchingForUi { chatRepository.renameWorkspace(workspaceId, title.trim()) }
            } finally {
                isLoading.value = false
            }
        }
    }

    private fun delete(workspaceId: String) {
        viewModelScope.launch {
            runCatchingForUi { chatRepository.deleteWorkspace(workspaceId) }
        }
    }

    private suspend fun <T> runCatchingForUi(block: suspend () -> T): T? =
        try {
            errorMessage.value = null
            block()
        } catch (error: CancellationException) {
            throw error
        } catch (error: Throwable) {
            errorMessage.value = error.message ?: error.javaClass.simpleName
            null
        }
}
