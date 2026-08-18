package com.deepseek.harness.android.ui.subagents

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.deepseek.harness.android.domain.model.SubagentCatalog
import com.deepseek.harness.android.domain.model.TimelineItem
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
class SubagentViewModel @Inject constructor(
    private val chatRepository: ChatRepository,
) : ViewModel() {

    private val selectedParentId = MutableStateFlow<String?>(null)
    private val catalog = MutableStateFlow(SubagentCatalog())
    private val selectedChildId = MutableStateFlow<String?>(null)
    private val childTimeline = MutableStateFlow<List<TimelineItem>>(emptyList())
    private val isSendingChild = MutableStateFlow(false)
    private val isLoading = MutableStateFlow(false)
    private val errorMessage = MutableStateFlow<String?>(null)

    val uiState: StateFlow<SubagentUiState> = combine(
        chatRepository.observeSessions(),
        selectedParentId,
        catalog,
        isLoading,
    ) { sessions, parent, entries, loading ->
        SubagentCore(
            sessions = sessions,
            selectedParentId = parent,
            catalog = entries,
            isLoading = loading,
        )
    }.let { core ->
        combine(
            core,
            selectedChildId,
            childTimeline,
            isSendingChild,
            errorMessage,
        ) { base, child, timeline, sending, error ->
            base.toUi(
                selectedChildId = child,
                childTimeline = timeline,
                isSendingChild = sending,
                errorMessage = error,
            )
        }.stateIn(
            scope = viewModelScope,
            started = SharingStarted.WhileSubscribed(stopTimeoutMillis = 5_000),
            initialValue = SubagentUiState(),
        )
    }

    private data class SubagentCore(
        val sessions: List<com.deepseek.harness.android.domain.model.SessionSummary>,
        val selectedParentId: String?,
        val catalog: SubagentCatalog,
        val isLoading: Boolean,
    ) {
        fun toUi(
            selectedChildId: String?,
            childTimeline: List<TimelineItem>,
            isSendingChild: Boolean,
            errorMessage: String?,
        ): SubagentUiState = SubagentUiState(
            sessions = sessions.filter { session ->
                !session.blank || session.id == selectedParentId
            },
            selectedParentId = selectedParentId,
            catalog = catalog,
            selectedChildId = selectedChildId,
            childTimeline = childTimeline,
            isSendingChild = isSendingChild,
            isLoading = isLoading,
            errorMessage = errorMessage,
        )
    }

    fun onAction(action: SubagentAction) {
        when (action) {
            is SubagentAction.SelectParent -> selectParent(action.sessionId)
            is SubagentAction.OpenChild -> openChild(action.childSessionId)
            is SubagentAction.SendPrompt -> sendPrompt(action.text)
            is SubagentAction.Interrupt -> interrupt(action.childSessionId)
            SubagentAction.Refresh -> refresh()
            SubagentAction.DismissError -> errorMessage.value = null
        }
    }

    private fun selectParent(sessionId: String) {
        if (selectedParentId.value == sessionId) return
        selectedParentId.value = sessionId
        selectedChildId.value = null
        childTimeline.value = emptyList()
        viewModelScope.launch { loadCatalog(sessionId) }
    }

    private fun openChild(childSessionId: String) {
        val parentId = selectedParentId.value ?: return
        selectedChildId.value = childSessionId
        childTimeline.value = emptyList()
        viewModelScope.launch {
            val result = runCatchingForUi {
                chatRepository.loadSubagentHistory(parentId, childSessionId)
            }
            childTimeline.value = result.orEmpty()
        }
    }

    private fun sendPrompt(text: String) {
        val parentId = selectedParentId.value ?: return
        val childId = selectedChildId.value ?: return
        if (text.isBlank()) return
        viewModelScope.launch {
            isSendingChild.value = true
            try {
                runCatchingForUi {
                    chatRepository.sendSubagentPrompt(parentId, childId, text.trim())
                }
                runCatchingForUi {
                    childTimeline.value = chatRepository.loadSubagentHistory(parentId, childId)
                }
            } finally {
                isSendingChild.value = false
            }
        }
    }

    private fun interrupt(childSessionId: String) {
        val parentId = selectedParentId.value ?: return
        viewModelScope.launch {
            runCatchingForUi {
                chatRepository.interruptSubagent(parentId, childSessionId)
            }
            runCatchingForUi { loadCatalog(parentId) }
        }
    }

    private fun refresh() {
        val parentId = selectedParentId.value ?: return
        viewModelScope.launch { loadCatalog(parentId) }
    }

    private suspend fun loadCatalog(parentId: String) {
        isLoading.value = true
        try {
            val loaded = runCatchingForUi { chatRepository.loadSubagents(parentId) }
            if (loaded != null) catalog.value = loaded
        } finally {
            isLoading.value = false
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
