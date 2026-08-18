package com.deepseek.harness.android.ui.chat

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.deepseek.harness.android.domain.model.ApprovalAnswer
import com.deepseek.harness.android.domain.model.AttachmentRef
import com.deepseek.harness.android.domain.model.ConnectionState
import com.deepseek.harness.android.domain.model.ImageLimits
import com.deepseek.harness.android.domain.model.PendingImage
import com.deepseek.harness.android.domain.model.PlanState
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
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/** Bounded attachment byte cache; decoded images are bounded by the same count. */
private const val ATTACHMENT_CACHE_LIMIT = 24

@HiltViewModel
class ChatViewModel @Inject constructor(
    private val chatRepository: ChatRepository,
) : ViewModel() {

    private val selectedSessionId = MutableStateFlow<String?>(null)
    private val timelineWindow = MutableStateFlow(TimelineWindow())
    private val isSending = MutableStateFlow(false)
    private val errorMessage = MutableStateFlow<String?>(null)
    private val searchResults = MutableStateFlow<List<SessionSearchResult>>(emptyList())
    private val pendingImages = MutableStateFlow<List<PendingImage>>(emptyList())
    private val imageLimits = MutableStateFlow(ImageLimits())
    private val plan = MutableStateFlow<PlanState?>(null)

    /** Decoded attachment bytes cache; scroll re-entry must not re-download. */
    private val attachmentBytes = LinkedHashMap<String, ByteArray>()
    private val attachmentMutex = Mutex()

    private data class ChatUiCore(
        val connection: ConnectionState,
        val sessions: List<SessionSummary>,
        val workspaces: List<WorkspaceSummary>,
        val selectedSessionId: String?,
        val timelineWindow: TimelineWindow,
        val isSending: Boolean,
        val pendingImages: List<PendingImage>,
        val imageLimits: ImageLimits,
        val plan: PlanState?,
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
                pendingImages = pendingImages,
                imageLimits = imageLimits,
                plan = plan,
            )
        }
    }

    private data class ChatBaseline(
        val connection: ConnectionState,
        val sessions: List<SessionSummary>,
        val workspaces: List<WorkspaceSummary>,
        val imageLimits: ImageLimits,
    )

    @OptIn(ExperimentalCoroutinesApi::class)
    val uiState: StateFlow<ChatUiState> = combine(
        combine(
            combine(
                chatRepository.observeConnectionState(),
                chatRepository.observeSessions(),
                chatRepository.observeWorkspaces(),
                chatRepository.observeImageLimits(),
            ) { connection, sessions, workspaces, limits ->
                ChatBaseline(
                    connection = connection,
                    sessions = sessions,
                    workspaces = workspaces,
                    imageLimits = limits ?: ImageLimits(),
                )
            },
            selectedSessionId,
            timelineWindow,
            isSending,
            pendingImages,
        ) { baseline, selected, window, sending, images ->
            ChatUiCore(
                connection = baseline.connection,
                sessions = baseline.sessions,
                workspaces = baseline.workspaces,
                selectedSessionId = selected,
                timelineWindow = window,
                isSending = sending,
                pendingImages = images,
                imageLimits = baseline.imageLimits,
                plan = null,
            )
        },
        plan,
        errorMessage,
        searchResults,
    ) { core, planState, error, search ->
        core.copy(plan = planState).toUiState(error, search)
    }.stateIn(
        scope = viewModelScope,
        started = SharingStarted.WhileSubscribed(stopTimeoutMillis = 5_000),
        initialValue = ChatUiState(),
    )

    init {
        refresh()
        observeSelectedTimeline()
        observeSelectedSessionRemoval()
        observeSelectedPlan()
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
            is ChatAction.UpdateQueue -> updateQueue(action.itemId, action.kind, action.text)
            is ChatAction.ImagesLoaded -> admitPendingImages(action.images)
            is ChatAction.RemovePendingImage -> removePendingImage(action.id)
            is ChatAction.ImagePickError -> errorMessage.value = action.message
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
        val images = pendingImages.value
        if (action.text.isBlank() && images.isEmpty()) return
        viewModelScope.launch {
            isSending.value = true
            try {
                val sent = runCatchingForUi {
                    chatRepository.sendMessage(
                        SendMessageRequest(
                            sessionId = sessionId,
                            text = action.text.trim(),
                            mode = action.mode,
                            images = images,
                        ),
                    )
                }
                // Keep drafts only on failure, mirroring the text composer.
                if (sent != null) pendingImages.value = emptyList()
            } finally {
                isSending.value = false
            }
        }
    }

    /** Validate picked images against the host limits, then queue the rest. */
    private fun admitPendingImages(images: List<PendingImage>) {
        if (images.isEmpty()) return
        val limits = imageLimits.value
        val admitted = mutableListOf<PendingImage>()
        val rejected = mutableListOf<String>()
        images.forEach { image ->
            when {
                image.mediaType !in limits.mediaTypes ->
                    rejected += "${image.name ?: image.id}: unsupported type ${image.mediaType}"
                image.byteSize > limits.maxImageBytes ->
                    rejected += "${image.name ?: image.id}: exceeds ${limits.maxImageBytes} bytes"
                else -> admitted += image
            }
        }
        val room = (limits.maxImagesPerMessage - pendingImages.value.size).coerceAtLeast(0)
        val keep = admitted.take(room)
        val overflow = admitted.drop(room)
        if (keep.isNotEmpty()) {
            pendingImages.value = pendingImages.value + keep
        }
        if (overflow.isNotEmpty()) {
            rejected += "only $room more image(s) allowed per message"
        }
        if (rejected.isNotEmpty()) {
            errorMessage.value = rejected.joinToString("; ")
        }
    }

    private fun removePendingImage(id: String) {
        pendingImages.value = pendingImages.value.filterNot { it.id == id }
    }

    /**
     * Download one durable image through `session.attachment`, caching bytes
     * per attachment id. Returns null on failure; the UI shows a placeholder.
     */
    suspend fun loadAttachmentBytes(sessionId: String, ref: AttachmentRef): ByteArray? {
        attachmentMutex.withLock {
            attachmentBytes[ref.attachmentId]?.let { return it }
        }
        return try {
            val downloaded = chatRepository.readAttachment(sessionId, ref.attachmentId)
            attachmentMutex.withLock {
                if (attachmentBytes.size >= ATTACHMENT_CACHE_LIMIT) {
                    attachmentBytes.remove(attachmentBytes.keys.first())
                }
                attachmentBytes[ref.attachmentId] = downloaded.data
            }
            downloaded.data
        } catch (error: CancellationException) {
            throw error
        } catch (_: Throwable) {
            null
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

    @OptIn(ExperimentalCoroutinesApi::class)
    private fun observeSelectedPlan() {
        viewModelScope.launch {
            selectedSessionId
                .flatMapLatest { sessionId ->
                    if (sessionId == null) {
                        flowOf(null)
                    } else {
                        chatRepository.observePlan(sessionId)
                    }
                }
                .collect { plan.value = it }
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

    private fun updateQueue(itemId: String, kind: QueueUpdateKind, text: String?) {
        val sessionId = selectedSessionId.value ?: return
        if (kind == QueueUpdateKind.EDIT && text.isNullOrBlank()) return
        viewModelScope.launch {
            runCatchingForUi {
                chatRepository.updateQueue(
                    QueueUpdateRequest(
                        sessionId = sessionId,
                        itemId = itemId,
                        kind = kind,
                        text = text,
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
