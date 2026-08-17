package com.deepseek.harness.android.ui.chat

import com.deepseek.harness.android.domain.model.ApprovalAnswer
import com.deepseek.harness.android.domain.model.ConnectionPhase
import com.deepseek.harness.android.domain.model.ConnectionState
import com.deepseek.harness.android.domain.model.CreateSessionRequest
import com.deepseek.harness.android.domain.model.HostDescription
import com.deepseek.harness.android.domain.model.SendMessageRequest
import com.deepseek.harness.android.domain.model.SessionSummary
import com.deepseek.harness.android.domain.model.TimelineItem
import com.deepseek.harness.android.domain.repository.ChatRepository
import com.deepseek.harness.android.domain.repository.QuestionEvidence
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.assertEquals
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

    private class FakeChatRepository(
        private val timeline: MutableStateFlow<List<TimelineItem>> =
            MutableStateFlow(emptyList()),
    ) : ChatRepository {
        val sessions = MutableStateFlow(listOf(initialSession))
        val sentMessages = mutableListOf<SendMessageRequest>()
        val openedSessionIds = mutableListOf<String>()
        val approvalAnswers = mutableListOf<ApprovalAnswer>()

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
            sessions.value = listOf(initialSession)
        }

        override suspend fun createSession(request: CreateSessionRequest): SessionSummary =
            initialSession

        override suspend fun openSession(sessionId: String) {
            openedSessionIds += sessionId
            timeline.value = listOf(
                TimelineItem.Error(id = "e1", message = "offline fixture"),
            )
        }

        override fun observeTimeline(sessionId: String): Flow<List<TimelineItem>> =
            timeline

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
        ) = Unit

        companion object {
            val initialSession = SessionSummary(
                id = "session-1",
                title = "Test session",
                blank = false,
            )
        }
    }
}
