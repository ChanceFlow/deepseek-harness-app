package com.deepseek.harness.android.ui.chat

import com.deepseek.harness.android.domain.model.ApprovalAnswer
import com.deepseek.harness.android.domain.model.ConnectionPhase
import com.deepseek.harness.android.domain.model.GoalProjection
import com.deepseek.harness.android.domain.model.GoalRef
import com.deepseek.harness.android.domain.model.GoalSnapshot
import com.deepseek.harness.android.domain.model.ConnectionState
import com.deepseek.harness.android.domain.model.CreateSessionRequest
import com.deepseek.harness.android.domain.model.ModelSelection
import com.deepseek.harness.android.domain.model.PromptMode
import com.deepseek.harness.android.domain.model.QuestionAnswer
import com.deepseek.harness.android.domain.model.QueueUpdateKind
import com.deepseek.harness.android.domain.model.QueueUpdateRequest
import com.deepseek.harness.android.domain.model.SessionModels
import com.deepseek.harness.android.domain.model.SessionSearchResult
import com.deepseek.harness.android.domain.model.WorkspaceSummary
import com.deepseek.harness.android.domain.model.HostDescription
import com.deepseek.harness.android.domain.model.SendMessageRequest
import com.deepseek.harness.android.domain.model.SessionSummary
import com.deepseek.harness.android.domain.model.SubagentEntry
import com.deepseek.harness.android.domain.model.SubagentCatalog
import com.deepseek.harness.android.domain.model.TimelineItem
import com.deepseek.harness.android.domain.repository.ChatRepository
import com.deepseek.harness.android.domain.repository.QuestionEvidence
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class ChatViewModelTest {

    private val dispatcher = StandardTestDispatcher()

    @Before
    fun setUp() {
        Dispatchers.setMain(dispatcher)
    }

    @After
    fun tearDown() {
        Dispatchers.resetMain()
    }

    @Test
    fun `init refreshes sessions`() = runTest(dispatcher) {
        val repository = FakeChatRepository()
        ChatViewModel(repository)
        advanceUntilIdle()

        assertEquals(listOf(FakeChatRepository.initialSession), repository.observeSessions().first())
    }

    @Test
    fun `select session loads timeline`() = runTest(dispatcher) {
        val repository = FakeChatRepository(
            timeline = MutableStateFlow(
                listOf(
                    TimelineItem.Error(id = "e1", message = "offline fixture"),
                ),
            ),
        )
        val viewModel = ChatViewModel(repository)
        backgroundScope.launch { viewModel.uiState.collect {} }
        advanceUntilIdle()

        viewModel.onAction(ChatAction.SelectSession(FakeChatRepository.initialSession.id))
        advanceUntilIdle()

        assertEquals(FakeChatRepository.initialSession.id, repository.openedSessionIds.single())
        assertEquals(1, viewModel.uiState.value.timeline.size)
    }

    @Test
    fun `send prompt delegates to repository`() = runTest(dispatcher) {
        val repository = FakeChatRepository()
        val viewModel = ChatViewModel(repository)
        advanceUntilIdle()

        viewModel.onAction(ChatAction.SelectSession(FakeChatRepository.initialSession.id))
        viewModel.onAction(ChatAction.SendPrompt("hello"))
        advanceUntilIdle()

        assertEquals(
            listOf(
                SendMessageRequest(
                    sessionId = FakeChatRepository.initialSession.id,
                    text = "hello",
                ),
            ),
            repository.sentMessages,
        )
    }

    @Test
    fun `send prompt honours steer delivery mode`() = runTest(dispatcher) {
        val repository = FakeChatRepository()
        val viewModel = ChatViewModel(repository)
        advanceUntilIdle()

        viewModel.onAction(ChatAction.SelectSession(FakeChatRepository.initialSession.id))
        viewModel.onAction(ChatAction.SendPrompt("take over", PromptMode.STEER))
        advanceUntilIdle()

        assertEquals(
            SendMessageRequest(
                sessionId = FakeChatRepository.initialSession.id,
                text = "take over",
                mode = PromptMode.STEER,
            ),
            repository.sentMessages.single(),
        )
    }

    @Test
    fun `workspace scoped new session passes workspace request through`() = runTest(dispatcher) {
        val repository = FakeChatRepository()
        val viewModel = ChatViewModel(repository)
        advanceUntilIdle()

        viewModel.onAction(ChatAction.CreateSessionInWorkspace("workspace-1"))
        advanceUntilIdle()

        assertEquals(listOf(CreateSessionRequest(workspaceId = "workspace-1")), repository.createRequests)
        assertEquals(FakeChatRepository.initialSession.id, repository.openedSessionIds.single())
    }

    @Test
    fun `load older history delegates to repository`() = runTest(dispatcher) {
        val repository = FakeChatRepository()
        val viewModel = ChatViewModel(repository)
        advanceUntilIdle()

        viewModel.onAction(ChatAction.SelectSession(FakeChatRepository.initialSession.id))
        viewModel.onAction(ChatAction.LoadOlderHistory)
        advanceUntilIdle()

        assertEquals(listOf(FakeChatRepository.initialSession.id), repository.olderHistorySessionIds)
    }

    @Test
    fun `archive session delegates to repository`() = runTest(dispatcher) {
        val repository = FakeChatRepository()
        val viewModel = ChatViewModel(repository)
        advanceUntilIdle()

        viewModel.onAction(ChatAction.SelectSession(FakeChatRepository.initialSession.id))
        viewModel.onAction(ChatAction.ArchiveSession(FakeChatRepository.initialSession.id))
        advanceUntilIdle()

        assertEquals(listOf(FakeChatRepository.initialSession.id), repository.archivedSessionIds)
    }

    @Test
    fun `approval action delegates`() = runTest(dispatcher) {
        val repository = FakeChatRepository()
        val viewModel = ChatViewModel(repository)
        advanceUntilIdle()

        viewModel.onAction(ChatAction.SelectSession(FakeChatRepository.initialSession.id))
        viewModel.onAction(
            ChatAction.RespondApproval(
                requestId = "rpc-1",
                approvalId = "approval-1",
                allowed = true,
            ),
        )
        advanceUntilIdle()

        assertEquals(
            ApprovalAnswer(
                requestId = "rpc-1",
                sessionId = FakeChatRepository.initialSession.id,
                approvalId = "approval-1",
                allowed = true,
            ),
            repository.approvalAnswers.single(),
        )
    }

    @Test
    fun `blank session rows are hidden unless selected`() = runTest(dispatcher) {
        val blankSession = SessionSummary(
            id = "provisional",
            blank = true,
            cwd = "/tmp/provisional",
        )
        val repository = FakeChatRepository(
            initialSessions = listOf(FakeChatRepository.initialSession, blankSession),
        )
        val viewModel = ChatViewModel(repository)
        backgroundScope.launch { viewModel.uiState.collect {} }
        advanceUntilIdle()

        assertEquals(
            listOf(FakeChatRepository.initialSession.id),
            viewModel.uiState.value.sessions.map { it.id },
        )

        viewModel.onAction(ChatAction.SelectSession(blankSession.id))
        advanceUntilIdle()

        assertEquals(
            listOf(FakeChatRepository.initialSession.id, blankSession.id),
            viewModel.uiState.value.sessions.map { it.id },
        )
    }

    @Test
    fun `workspace create reuses the workspace blank session`() = runTest(dispatcher) {
        val blankSession = SessionSummary(
            id = "blank-workspace-session",
            blank = true,
            cwd = "/tmp/reusable-workspace",
        )
        val workspace = WorkspaceSummary(
            workspaceId = "workspace-1",
            path = "/tmp/reusable-workspace",
            title = "Workspace",
            sessionIds = listOf(blankSession.id),
        )
        val repository = FakeChatRepository(
            initialSessions = listOf(blankSession),
            initialWorkspaces = listOf(workspace),
        )
        val viewModel = ChatViewModel(repository)
        backgroundScope.launch { viewModel.uiState.collect {} }
        advanceUntilIdle()

        viewModel.onAction(ChatAction.CreateSessionInWorkspace(workspace.workspaceId))
        advanceUntilIdle()

        assertEquals(emptyList<CreateSessionRequest>(), repository.createRequests)
        assertEquals(listOf(blankSession.id), repository.openedSessionIds)
        assertEquals(blankSession.id, viewModel.uiState.value.selectedSessionId)
    }

    @Test
    fun `queue edit action delegates edited text`() = runTest(dispatcher) {
        val repository = FakeChatRepository()
        val viewModel = ChatViewModel(repository)
        advanceUntilIdle()

        viewModel.onAction(ChatAction.SelectSession(FakeChatRepository.initialSession.id))
        viewModel.onAction(
            ChatAction.UpdateQueue(
                itemId = "queued-1",
                kind = QueueUpdateKind.EDIT,
                text = "revised prompt",
            ),
        )
        advanceUntilIdle()

        assertEquals(
            QueueUpdateRequest(
                sessionId = FakeChatRepository.initialSession.id,
                itemId = "queued-1",
                kind = QueueUpdateKind.EDIT,
                text = "revised prompt",
            ),
            repository.queueUpdates.single(),
        )
    }

    @Test
    fun `blank queue edit is ignored`() = runTest(dispatcher) {
        val repository = FakeChatRepository()
        val viewModel = ChatViewModel(repository)
        advanceUntilIdle()

        viewModel.onAction(ChatAction.SelectSession(FakeChatRepository.initialSession.id))
        viewModel.onAction(
            ChatAction.UpdateQueue(
                itemId = "queued-1",
                kind = QueueUpdateKind.EDIT,
                text = "   ",
            ),
        )
        advanceUntilIdle()

        assertTrue(repository.queueUpdates.isEmpty())
    }

    @Test
    fun `skipped question answer delegates empty selections`() = runTest(dispatcher) {
        val repository = FakeChatRepository()
        val viewModel = ChatViewModel(repository)
        advanceUntilIdle()

        viewModel.onAction(ChatAction.SelectSession(FakeChatRepository.initialSession.id))
        viewModel.onAction(
            ChatAction.AnswerQuestion(
                requestId = "rpc-question",
                answers = listOf(
                    QuestionAnswer(
                        questionId = "question-1",
                        selectedOptions = emptyList(),
                    ),
                ),
            ),
        )
        advanceUntilIdle()

        val (requestId, evidence) = repository.questionAnswers.single()
        assertEquals("rpc-question", requestId)
        assertEquals("question-1", evidence.answers.single().questionId)
        assertTrue(evidence.answers.single().selectedOptions.isEmpty())
    }

    private class FakeChatRepository(
        private val timeline: MutableStateFlow<List<TimelineItem>> =
            MutableStateFlow(emptyList()),
        initialSessions: List<SessionSummary> = listOf(initialSession),
        initialWorkspaces: List<WorkspaceSummary> = emptyList(),
    ) : ChatRepository {
        private val baselineSessions = initialSessions
        private val baselineWorkspaces = initialWorkspaces
        val sessions = MutableStateFlow(baselineSessions)
        val workspaces = MutableStateFlow(baselineWorkspaces)
        val sentMessages = mutableListOf<SendMessageRequest>()
        val openedSessionIds = mutableListOf<String>()
        val approvalAnswers = mutableListOf<ApprovalAnswer>()
        val createRequests = mutableListOf<CreateSessionRequest>()
        val olderHistorySessionIds = mutableListOf<String>()
        val archivedSessionIds = mutableListOf<String>()
        val renamedWorkspaces = mutableListOf<Pair<String, String>>()
        val queueUpdates = mutableListOf<QueueUpdateRequest>()
        val questionAnswers = mutableListOf<Pair<String, QuestionEvidence>>()

        override fun observeConnectionState(): Flow<ConnectionState> =
            MutableStateFlow(
                ConnectionState(
                    phase = ConnectionPhase.CONNECTED,
                    hostDescription = HostDescription(version = "test", cwd = "/tmp"),
                ),
            )

        override fun observeSessions(): Flow<List<SessionSummary>> =
            sessions.asStateFlow()

        override suspend fun refreshSessions() {
            sessions.value = baselineSessions
        }

        override suspend fun createSession(request: CreateSessionRequest): SessionSummary {
            createRequests += request
            return initialSession
        }

        override suspend fun openSession(sessionId: String) {
            openedSessionIds += sessionId
            timeline.value = listOf(
                TimelineItem.Error(id = "e1", message = "offline fixture"),
            )
        }

        override fun observeTimeline(sessionId: String): Flow<List<TimelineItem>> =
            timeline

        override suspend fun loadOlderHistory(sessionId: String): Boolean {
            olderHistorySessionIds += sessionId
            return true
        }

        override suspend fun archiveSession(sessionId: String) {
            archivedSessionIds += sessionId
        }

        override suspend fun sendMessage(request: SendMessageRequest) {
            sentMessages += request
        }

        override suspend fun cancelTurn(sessionId: String) = Unit

        override suspend fun respondToApproval(answer: ApprovalAnswer) {
            approvalAnswers += answer
        }

        override suspend fun answerQuestions(
            requestId: String,
            evidence: QuestionEvidence,
        ) {
            questionAnswers += requestId to evidence
        }

        private val searchResults = mutableListOf<SessionSearchResult>()

        override fun observeWorkspaces(): Flow<List<WorkspaceSummary>> =
            workspaces

        override suspend fun refreshWorkspaces() {
            workspaces.value = baselineWorkspaces
        }

        override suspend fun createWorkspace(path: String): WorkspaceSummary {
            return WorkspaceSummary(workspaceId = "workspace-1", path = path, title = path)
        }

        override suspend fun renameWorkspace(workspaceId: String, title: String): WorkspaceSummary = WorkspaceSummary(
            workspaceId = workspaceId,
            path = title,
            title = title,
        ).also { renamedWorkspaces += workspaceId to title }

        override suspend fun deleteWorkspace(workspaceId: String) = Unit

        override suspend fun loadModels(sessionId: String): SessionModels {
            return SessionModels(
                current = ModelSelection(provider = "test", model = "test"),
                routable = true,
            )
        }

        override suspend fun selectModel(sessionId: String, selection: ModelSelection): ModelSelection =
            selection

        override suspend fun searchSessions(query: String): List<SessionSearchResult> =
            searchResults.toList()

        override suspend fun renameSession(sessionId: String, title: String): String = title

        override suspend fun forkSession(sessionId: String, atSeq: Long?): SessionSummary =
            initialSession

        override suspend fun updateQueue(request: QueueUpdateRequest) {
            queueUpdates += request
        }

        override suspend fun loadSubagents(parentSessionId: String): SubagentCatalog =
            SubagentCatalog()

        override suspend fun interruptSubagent(parentSessionId: String, childSessionId: String) = Unit

        override suspend fun loadSubagentHistory(parentSessionId: String, childSessionId: String): List<TimelineItem> = emptyList()

        override suspend fun sendSubagentPrompt(parentSessionId: String, childSessionId: String, text: String): String = "msg-1"

        override fun observeGoal(sessionId: String): Flow<GoalProjection?> = MutableStateFlow(null)

        override suspend fun createGoal(sessionId: String, objective: String, maxGoalRounds: Long?): GoalRef =
            GoalRef(id = "g1", revision = 1)

        override suspend fun pauseGoal(sessionId: String, ref: GoalRef): GoalRef = ref
        override suspend fun resumeGoal(sessionId: String, ref: GoalRef): GoalRef = ref
        override suspend fun completeGoal(sessionId: String, ref: GoalRef): GoalRef = ref
        override suspend fun clearGoal(sessionId: String, ref: GoalRef) = Unit

        companion object {
            val initialSession = SessionSummary(
                id = "session-1",
                title = "Test session",
                blank = false,
            )
        }
    }
}
