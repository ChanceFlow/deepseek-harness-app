package com.deepseek.harness.android.ui.goal

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.deepseek.harness.android.domain.model.GoalProjection
import com.deepseek.harness.android.domain.model.GoalRef
import com.deepseek.harness.android.domain.repository.ChatRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

@HiltViewModel
class GoalViewModel @Inject constructor(
    private val chatRepository: ChatRepository,
) : ViewModel() {

    private val selectedSessionId = MutableStateFlow<String?>(null)
    private val goal = MutableStateFlow<GoalProjection?>(null)
    private val isLoading = MutableStateFlow(false)
    private val errorMessage = MutableStateFlow<String?>(null)

    @OptIn(ExperimentalCoroutinesApi::class)
    val uiState: StateFlow<GoalUiState> = combine(
        combine(
            chatRepository.observeSessions(),
            selectedSessionId,
            goal,
            isLoading,
        ) { sessions, selected, projection, loading ->
            GoalUiState(
                sessions = sessions,
                selectedSessionId = selected,
                goal = projection,
                isLoading = loading,
            )
        },
        errorMessage,
    ) { base, error ->
        base.copy(errorMessage = error)
    }.stateIn(
        scope = viewModelScope,
        started = SharingStarted.WhileSubscribed(stopTimeoutMillis = 5_000),
        initialValue = GoalUiState(),
    )

    init {
        observeGoal()
    }

    fun onAction(action: GoalAction) {
        when (action) {
            is GoalAction.SelectSession -> selectSession(action.sessionId)
            is GoalAction.Create -> create(action.objective, action.maxRounds)
            GoalAction.Pause -> mutateGoal { current -> chatRepository.pauseGoal(actionSession(), current) }
            GoalAction.Resume -> mutateGoal { current -> chatRepository.resumeGoal(actionSession(), current) }
            GoalAction.Complete -> mutateGoal { current -> chatRepository.completeGoal(actionSession(), current) }
            GoalAction.Clear -> clear()
            GoalAction.DismissError -> errorMessage.value = null
            GoalAction.Refresh -> refresh()
        }
    }

    @OptIn(ExperimentalCoroutinesApi::class)
    private fun observeGoal() {
        viewModelScope.launch {
            selectedSessionId
                .flatMapLatest { sessionId ->
                    if (sessionId == null) flowOf(null) else chatRepository.observeGoal(sessionId)
                }
                .collect { goal.value = it }
        }
    }

    private fun selectSession(sessionId: String) {
        if (selectedSessionId.value == sessionId) return
        selectedSessionId.value = sessionId
        goal.value = null
    }

    private fun create(objective: String, maxRounds: Long?) {
        if (objective.isBlank()) return
        val sessionId = selectedSessionId.value ?: return
        viewModelScope.launch {
            isLoading.value = true
            try {
                runCatchingForUi { chatRepository.createGoal(sessionId, objective.trim(), maxRounds) }
            } finally {
                isLoading.value = false
            }
        }
    }

    private fun mutateGoal(block: suspend (GoalRef) -> GoalRef) {
        val sessionId = selectedSessionId.value ?: return
        val current = goal.value?.goal ?: return
        viewModelScope.launch {
            runCatchingForUi { block(GoalRef(id = current.id, revision = current.revision)) }
        }
    }

    private fun clear() {
        val sessionId = selectedSessionId.value ?: return
        val current = goal.value?.goal ?: return
        viewModelScope.launch {
            runCatchingForUi {
                chatRepository.clearGoal(
                    sessionId,
                    GoalRef(id = current.id, revision = current.revision),
                )
            }
        }
    }

    private fun refresh() {
        val sessionId = selectedSessionId.value ?: return
        viewModelScope.launch {
            runCatchingForUi { chatRepository.refreshSessions() }
            runCatchingForUi { chatRepository.openSession(sessionId) }
        }
    }

    private fun actionSession(): String = selectedSessionId.value.orEmpty()

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
