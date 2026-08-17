package com.deepseek.harness.android.ui.chat

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.deepseek.harness.android.domain.model.ApprovalAnswer
import com.deepseek.harness.android.domain.model.ConnectionState
import com.deepseek.harness.android.domain.model.CreateSessionRequest
import com.deepseek.harness.android.domain.model.SendMessageRequest
import com.deepseek.harness.android.domain.model.TimelineItem
import com.deepseek.harness.android.domain.repository.ChatRepository
import com.deepseek.harness.android.domain.repository.QuestionEvidence
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
class ChatViewModel @Inject constructor(
    private val chatRepository: ChatRepository,
) : ViewModel() {

    private val selectedSessionId = MutableStateFlow<String?>(null)
    private val timeline = MutableStateFlow<List<TimelineItem>>(emptyList())
    private val isSending = MutableStateFlow(false)
    private val errorMessage = MutableStateFlow<String?>(null)

    @OptIn(ExperimentalCoroutinesApi::class)
    val uiState: StateFlow<ChatUiState> = combine(
        chatRepository.observeConnectionState(),
        chatRepository.observeSessions(),
        selectedSessionId,
        timeline,
        isSending,
        errorMessage,
    ) { connection, sessions, selected, items, sending, error ->
        ChatUiState(
            connection = connection,
            sessions = sessions,
            selectedSessionId = selected,
            timeline = items,
            isSending = sending,
            errorMessage = error,
        )
    }.stateIn(
        scope = viewModelScope,
        started = SharingStarted.WhileSubscribed(stopTimeoutMillis = 5_000),
        initialValue = ChatUiState(),
    )

    init {
        refreshSessions()
        observeSelectedTimeline()
    }

    fun onAction(action: ChatAction) {
        when (action) {
            is ChatAction.SelectSession -> selectSession(action.sessionId)
            is ChatAction.SendPrompt -> sendPrompt(action.text)
            ChatAction.CancelTurn -> cancelTurn()
            ChatAction.CreateSession -> createSession()
            ChatAction.DismissError -> errorMessage.value = null
            ChatAction.RetrySessions -> refreshSessions()
            is ChatAction.RespondApproval -> respondApproval(action)
            is ChatAction.AnswerQuestion -> answerQuestion(action)
        }
    }

    private fun selectSession(sessionId: String) {
        selectedSessionId.value = sessionId
        timeline.value = emptyList()
        viewModelScope.launch {
            runCatchingForUi { chatRepository.openSession(sessionId) }
        }
    }

    private fun refreshSessions() {
        viewModelScope.launch {
            runCatchingForUi { chatRepository.refreshSessions() }
        }
    }

    private fun sendPrompt(text: String) {
        val sessionId = selectedSessionId.value ?: return
        if (text.isBlank()) return
        viewModelScope.launch {
            isSending.value = true
            try {
                runCatchingForUi {
                    chatRepository.sendMessage(
                        SendMessageRequest(sessionId = sessionId, text = text.trim()),
                    )
                }
            } finally {
                isSending.value = false
            }
        }
    }

    private fun cancelTurn() {
        val sessionId = selectedSessionId.value ?: return
        viewModelScope.launch {
            runCatchingForUi { chatRepository.cancelTurn(sessionId) }
        }
    }

    private fun createSession() {
        viewModelScope.launch {
            val session = runCatchingForUi {
                chatRepository.createSession(CreateSessionRequest())
            } ?: return@launch
            selectedSessionId.value = session.id
            runCatchingForUi { chatRepository.openSession(session.id) }
        }
    }

    private fun respondApproval(action: ChatAction.RespondApproval) {
        val sessionId = selectedSessionId.value ?: return
        viewModelScope.launch {
            runCatchingForUi {
                chatRepository.respondToApproval(
                    ApprovalAnswer(
                        requestId = action.requestId,
                        sessionId = sessionId,
                        approvalId = action.approvalId,
                        allowed = action.allowed,
                    ),
                )
            }
        }
    }

    private fun answerQuestion(action: ChatAction.AnswerQuestion) {
        val sessionId = selectedSessionId.value ?: return
        viewModelScope.launch {
            runCatchingForUi {
                chatRepository.answerQuestions(
                    requestId = action.requestId,
                    evidence = QuestionEvidence(
                        sessionId = sessionId,
                        answers = action.answers,
                    ),
                )
            }
        }
    }

    @OptIn(ExperimentalCoroutinesApi::class)
    private fun observeSelectedTimeline() {
        viewModelScope.launch {
            selectedSessionId
                .flatMapLatest { sessionId ->
                    if (sessionId == null) flowOf(emptyList())
                    else chatRepository.observeTimeline(sessionId)
                }
                .collect { timeline.value = it }
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
