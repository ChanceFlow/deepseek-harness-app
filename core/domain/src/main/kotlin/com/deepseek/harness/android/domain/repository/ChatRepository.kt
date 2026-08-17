package com.deepseek.harness.android.domain.repository

import com.deepseek.harness.android.domain.model.ApprovalAnswer
import com.deepseek.harness.android.domain.model.ConnectionState
import com.deepseek.harness.android.domain.model.ModelSelection
import com.deepseek.harness.android.domain.model.QueueUpdateKind
import com.deepseek.harness.android.domain.model.QueueUpdateRequest
import com.deepseek.harness.android.domain.model.SendMessageRequest
import com.deepseek.harness.android.domain.model.SessionModels
import com.deepseek.harness.android.domain.model.SessionSearchResult
import com.deepseek.harness.android.domain.model.SessionSummary
import com.deepseek.harness.android.domain.model.TimelineItem
import com.deepseek.harness.android.domain.model.WorkspaceSummary
import com.deepseek.harness.android.domain.model.QuestionAnswer
import kotlinx.coroutines.flow.Flow

/**
 * Domain-owned repository contract.
 *
 * Implementations live behind :core:harness-adapter. UI and ViewModel code
 * must never import a dsh-specific implementation or type.
 */
interface ChatRepository {
    fun observeConnectionState(): Flow<ConnectionState>

    fun observeSessions(): Flow<List<SessionSummary>>

    suspend fun refreshSessions()

    suspend fun createSession(request: com.deepseek.harness.android.domain.model.CreateSessionRequest): SessionSummary

    suspend fun openSession(sessionId: String)

    fun observeTimeline(sessionId: String): Flow<List<TimelineItem>>

    suspend fun sendMessage(request: SendMessageRequest)

    suspend fun cancelTurn(sessionId: String)

    suspend fun respondToApproval(answer: ApprovalAnswer)

    suspend fun answerQuestions(
        requestId: String,
        evidence: QuestionEvidence,
    )

    fun observeWorkspaces(): Flow<List<WorkspaceSummary>>

    suspend fun refreshWorkspaces()

    suspend fun createWorkspace(path: String): WorkspaceSummary

    suspend fun deleteWorkspace(workspaceId: String)

    suspend fun loadModels(sessionId: String): SessionModels

    suspend fun selectModel(sessionId: String, selection: ModelSelection): ModelSelection

    suspend fun searchSessions(query: String): List<SessionSearchResult>

    suspend fun renameSession(sessionId: String, title: String): String

    suspend fun forkSession(sessionId: String, atSeq: Long? = null): SessionSummary

    suspend fun updateQueue(request: QueueUpdateRequest)
}

data class QuestionEvidence(
    val sessionId: String,
    val answers: List<QuestionAnswer>,
)
