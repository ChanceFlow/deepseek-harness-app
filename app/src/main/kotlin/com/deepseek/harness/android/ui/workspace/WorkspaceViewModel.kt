package com.deepseek.harness.android.ui.workspace

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
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

    val uiState: StateFlow<WorkspaceUiState> = combine(
        chatRepository.observeWorkspaces(),
        isLoading,
        errorMessage,
    ) { workspaces, loading, error ->
        WorkspaceUiState(
            workspaces = workspaces,
            isLoading = loading,
            errorMessage = error,
        )
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
            is WorkspaceAction.Delete -> delete(action.workspaceId)
            WorkspaceAction.Refresh -> refresh()
            WorkspaceAction.DismissError -> errorMessage.value = null
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
