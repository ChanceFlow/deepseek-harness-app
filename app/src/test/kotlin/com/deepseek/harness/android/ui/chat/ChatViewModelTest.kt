package com.deepseek.harness.android.ui.chat

import com.deepseek.harness.android.domain.model.CreateSessionRequest
import com.deepseek.harness.android.domain.model.SendMessageRequest
import com.deepseek.harness.android.domain.model.SessionSummary
import com.deepseek.harness.android.domain.model.TimelineItem
import com.deepseek.harness.android.domain.repository.ChatRepository
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.emptyFlow
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

    private class FakeChatRepository : ChatRepository {
        val sessions = MutableStateFlow(listOf(initialSession))
        val sentMessages = mutableListOf<SendMessageRequest>()

        override fun observeSessions(): Flow<List<SessionSummary>> =
            sessions.asStateFlow()

        override suspend fun refreshSessions() {
            sessions.value = listOf(initialSession)
        }

        override suspend fun createSession(request: CreateSessionRequest): SessionSummary =
            initialSession

        override suspend fun sendMessage(request: SendMessageRequest) {
            sentMessages += request
        }

        override suspend fun cancelTurn(sessionId: String) {
            lastCancelledSession = sessionId
        }

        var lastCancelledSession: String? = null

        override fun observeTimeline(sessionId: String): Flow<TimelineItem> =
            emptyFlow()

        companion object {
            val initialSession = SessionSummary(
                id = "session-1",
                title = "Test session",
                blank = false,
            )
        }
    }
}
