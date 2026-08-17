package com.deepseek.harness.android.ui.models

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.deepseek.harness.android.domain.model.ModelSelection
import com.deepseek.harness.android.domain.model.SessionModels
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
class ModelsViewModel @Inject constructor(
    private val chatRepository: ChatRepository,
) : ViewModel() {

    private val selectedSessionId = MutableStateFlow<String?>(null)
    private val models = MutableStateFlow<SessionModels?>(null)
    private val selected = MutableStateFlow<ModelSelection?>(null)
    private val isLoading = MutableStateFlow(false)
    private val errorMessage = MutableStateFlow<String?>(null)

    val uiState: StateFlow<ModelsUiState> = combine(
        chatRepository.observeSessions(),
        selectedSessionId,
        models,
        selected,
        isLoading,
    ) { sessions, sessionId, catalog, chosen, loading ->
        ModelsUiState(
            sessions = sessions,
            selectedSessionId = sessionId,
            models = catalog,
            selected = chosen,
            isLoading = loading,
        )
    }.let { flow ->
        combine(flow, errorMessage) { base, error ->
            base.copy(errorMessage = error)
        }.stateIn(
            scope = viewModelScope,
            started = SharingStarted.WhileSubscribed(stopTimeoutMillis = 5_000),
            initialValue = ModelsUiState(),
        )
    }

    init {
        refresh()
    }

    fun onAction(action: ModelsAction) {
        when (action) {
            is ModelsAction.SelectSession -> selectSession(action.sessionId)
            is ModelsAction.SelectModel -> selectModel(action.provider, action.model)
            ModelsAction.Refresh -> refresh()
            ModelsAction.DismissError -> errorMessage.value = null
        }
    }

    private fun refresh() {
        viewModelScope.launch {
            val sessionId = selectedSessionId.value ?: return@launch
            loadModels(sessionId)
        }
    }

    private fun selectSession(sessionId: String) {
        selectedSessionId.value = sessionId
        viewModelScope.launch { loadModels(sessionId) }
    }

    private fun selectModel(provider: String, model: String) {
        val sessionId = selectedSessionId.value ?: return
        viewModelScope.launch {
            runCatchingForUi {
                chatRepository.selectModel(sessionId, ModelSelection(provider = provider, model = model))
            }?.let { selected.value = it }
        }
    }

    private suspend fun loadModels(sessionId: String) {
        isLoading.value = true
        try {
            runCatchingForUi { chatRepository.loadModels(sessionId) }?.let { loaded ->
                models.value = loaded
                selected.value = loaded.current
            }
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
