package com.deepseek.harness.android.ui.chat

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.deepseek.harness.android.domain.model.ApprovalAnswer
import com.deepseek.harness.android.domain.model.ConnectionState
import com.deepseek.harness.android.domain.model.QueueUpdateKind
import com.deepseek.harness.android.domain.model.QueueUpdateRequest
import com.deepseek.harness.android.domain.model.CreateSessionRequest
import com.deepseek.harness.android.domain.model.SendMessageRequest
import com.deepseek.harness.android.domain.model.SessionSearchResult
import com.deepseek.harness.android.domain.model.SessionSummary
import com.deepseek.harness.android.domain.model.TimelineWindow
import com.deepseek.harness.android.domain.model.WorkspaceSummary
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
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

@HiltViewModel
class ChatViewModel @Inject constructor(
    private val chatRepository: ChatRepository,
) : ViewModel() {

    private val selectedSessionId = MutableStateFlow<String?>(null)
    private val timelineWindow = MutableStateFlow(TimelineWindow())
    private val isSending = MutableStateFlow(false)
    private val errorMessage = MutableStateFlow<String?>(null)
    private val searchResults = MutableStateFlow<List<SessionSearchResult>>(emptyList())

    private data class ChatUiCore(
        val connection: ConnectionState,
        val sessions: List<SessionSummary>,
        val workspaces: List<WorkspaceSummary>,
        val selectedSessionId: String?,
        val timelineWindow: TimelineWindow,
        val isSending: Boolean,
    ) {
        fun toUiState(
            error: String?,
            search: List<SessionSearchResult>,
        ): ChatUiState {
            // Matches the Web client grouping rule: store keeps every row,
            // while list surfaces hide blank placeholders unless selected.
            val visibleSessions = sessions.filter { session ->
                !session.blank || session.id == selectedSessionId
            }
            return ChatUiState(
                connection = connection,
                sessions = visibleSessions,
                workspaces = workspaces,
                selectedSessionId = selectedSessionId,
                timeline = timelineWindow.items,
                hasMoreOlder = timelineWindow.hasMoreOlder,
                isLoadingOlder = timelineWindow.isLoadingOlder,
                isSending = isSending,
                errorMessage = error,
                searchResults = search,
            )
        }
    }

    private data class ChatBaseline(
        val connection: ConnectionState,
        val sessions: List<SessionSummary>,
        val workspaces: List<WorkspaceSummary>,
    )

    @OptIn(ExperimentalCoroutinesApi::class)
    val uiState: StateFlow<ChatUiState> = combine(
        combine(
            combine(
                chatRepository.observeConnectionState(),
                chatRepository.observeSessions(),
                chatRepository.observeWorkspaces(),
            ) { connection, sessions, workspaces ->
                ChatBaseline(
                    connection = connection,
                    sessions = sessions,
                    workspaces = workspaces,
                )
            },
            selectedSessionId,
            timelineWindow,
            isSending,
        ) { baseline, selected, window, sending ->
            ChatUiCore(
                connection = baseline.connection,
                sessions = baseline.sessions,
                workspaces = baseline.workspaces,
                selectedSessionId = selected,
                timelineWindow = window,
                isSending = sending,
            )
        },
        errorMessage,
        searchResults,
    ) { core, error, search ->
        core.toUiState(error, search)
    }.stateIn(
        scope = viewModelScope,
        started = SharingStarted.WhileSubscribed(stopTimeoutMillis = 5_000),
        initialValue = ChatUiState(),
    )

    init {
        refresh()
        observeSelectedTimeline()
        observeSelectedSessionRemoval()
    }

    fun onAction(action: ChatAction) {
        when (action) {
            is ChatAction.SelectSession -> selectSession(action.sessionId)
            is ChatAction.SendPrompt -> sendPrompt(action)
            ChatAction.CancelTurn -> cancelTurn()
            ChatAction.CreateSession -> createSession(workspaceId = null)
            is ChatAction.CreateSessionInWorkspace -> createSession(action.workspaceId)
            ChatAction.DismissError -> errorMessage.value = null
            ChatAction.RetrySessions -> refresh()
            ChatAction.LoadOlderHistory -> loadOlderHistory()
            is ChatAction.RespondApproval -> respondApproval(action)
            is ChatAction.AnswerQuestion -> answerQuestion(action)
            is ChatAction.SearchSessions -> searchSessions(action.query)
            is ChatAction.ArchiveSession -> archiveSession(action.sessionId)
            is ChatAction.RenameSession -> renameSession(action.sessionId, action.title)
            is ChatAction.ForkSession -> forkSession(action.sessionId)
            is ChatAction.UpdateQueue -> updateQueue(action.itemId, action.kind)
        }
    }

    private fun selectSession(sessionId: String) {
        selectedSessionId.value = sessionId
        timelineWindow.value = TimelineWindow()
        viewModelScope.launch {
            runCatchingForUi { chatRepository.openSession(sessionId) }
        }
    }

    private fun loadOlderHistory() {
        val sessionId = selectedSessionId.value ?: return
        viewModelScope.launch {
            runCatchingForUi { chatRepository.loadOlderHistory(sessionId) }
        }
    }

    private fun refresh() {
        viewModelScope.launch {
            runCatchingForUi { chatRepository.refreshSessions() }
            runCatchingForUi { chatRepository.refreshWorkspaces() }
        }
    }

    private fun observeSelectedSessionRemoval() {
        viewModelScope.launch {
            chatRepository.observeSessions().collect { sessions ->
                val selected = selectedSessionId.value ?: return@collect
                if (sessions.none { it.id == selected }) {
                    selectedSessionId.value = null
                    timelineWindow.value = TimelineWindow()
                }
            }
        }
    }

    private fun archiveSession(sessionId: String) {
        viewModelScope.launch {
            runCatchingForUi { chatRepository.archiveSession(sessionId) }
        }
    }

    private fun sendPrompt(action: ChatAction.SendPrompt) {
        val sessionId = selectedSessionId.value ?: return
        if (action.text.isBlank()) return
        viewModelScope.launch {
            isSending.value = true
            try {
                runCatchingForUi {
                    chatRepository.sendMessage(
                        SendMessageRequest(
                            sessionId = sessionId,
                            text = action.text.trim(),
                            mode = action.mode,
                        ),
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

    private fun createSession(workspaceId: String?) {
        viewModelScope.launch {
            // Web parity: a workspace's blank session is the provisional New
            // Session row. Reuse it instead of minting another hidden row.
            val sessionId = workspaceId?.let { reusableBlankSessionId(it) }
                ?: runCatchingForUi {
                    chatRepository.createSession(
                        CreateSessionRequest(workspaceId = workspaceId),
                    )
                }?.id
                ?: return@launch
            selectedSessionId.value = sessionId
            runCatchingForUi { chatRepository.openSession(sessionId) }
        }
    }

    private suspend fun reusableBlankSessionId(workspaceId: String): String? {
        val workspace = chatRepository.observeWorkspaces()
            .first()
            .firstOrNull { it.workspaceId == workspaceId }
            ?: return null
        return chatRepository.observeSessions()
            .first()
            .firstOrNull { session ->
                session.blank &&
                    session.cwd == workspace.path &&
                    workspace.sessionIds.contains(session.id)
            }
            ?.id
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
                    if (sessionId == null) {
                        flowOf(TimelineWindow())
                    } else {
                        chatRepository.observeTimelineWindow(sessionId)
                    }
                }
                .collect { timelineWindow.value = it }
        }
    }

    private fun searchSessions(query: String) {
        if (query.isBlank()) {
            searchResults.value = emptyList()
            return
        }
        viewModelScope.launch {
            val results = runCatchingForUi { chatRepository.searchSessions(query) }
            searchResults.value = results.orEmpty()
        }
    }

    private fun renameSession(sessionId: String, title: String) {
        if (title.isBlank()) return
        viewModelScope.launch {
            runCatchingForUi { chatRepository.renameSession(sessionId, title) }
        }
    }

    private fun forkSession(sessionId: String) {
        viewModelScope.launch {
            val forked = runCatchingForUi { chatRepository.forkSession(sessionId) } ?: return@launch
            selectedSessionId.value = forked.id
            timelineWindow.value = TimelineWindow()
            runCatchingForUi { chatRepository.openSession(forked.id) }
        }
    }

    private fun updateQueue(itemId: String, kind: QueueUpdateKind) {
        val sessionId = selectedSessionId.value ?: return
        viewModelScope.launch {
            runCatchingForUi {
                chatRepository.updateQueue(
                    QueueUpdateRequest(
                        sessionId = sessionId,
                        itemId = itemId,
                        kind = kind,
                    ),
                )
            }
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
