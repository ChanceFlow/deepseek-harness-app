package com.deepseek.harness.android.domain.repository

import com.deepseek.harness.android.domain.model.CreateSessionRequest
import com.deepseek.harness.android.domain.model.SendMessageRequest
import com.deepseek.harness.android.domain.model.SessionSummary
import com.deepseek.harness.android.domain.model.TimelineItem
import kotlinx.coroutines.flow.Flow

/**
 * Domain-owned repository contract.
 *
 * Implementations live behind :core:harness-adapter. UI and ViewModel code
 * must never import a dsh-specific implementation or type.
 */
interface ChatRepository {
    fun observeSessions(): Flow<List<SessionSummary>>

    suspend fun refreshSessions()

    suspend fun createSession(request: CreateSessionRequest): SessionSummary

    suspend fun sendMessage(request: SendMessageRequest)

    suspend fun cancelTurn(sessionId: String)

    fun observeTimeline(sessionId: String): Flow<TimelineItem>
}
