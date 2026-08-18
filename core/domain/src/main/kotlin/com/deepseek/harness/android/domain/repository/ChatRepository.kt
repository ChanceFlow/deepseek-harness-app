package com.deepseek.harness.android.domain.repository

import com.deepseek.harness.android.domain.model.ApprovalAnswer
import com.deepseek.harness.android.domain.model.AttachmentData
import com.deepseek.harness.android.domain.model.AttachmentRef
import com.deepseek.harness.android.domain.model.ConnectionState
import com.deepseek.harness.android.domain.model.CredentialStatus
import com.deepseek.harness.android.domain.model.DirectoryListing
import com.deepseek.harness.android.domain.model.GoalProjection
import com.deepseek.harness.android.domain.model.GoalRef
import com.deepseek.harness.android.domain.model.ImageLimits
import com.deepseek.harness.android.domain.model.PlanState
import com.deepseek.harness.android.domain.model.SettingsSnapshot
import com.deepseek.harness.android.domain.model.SkillEntry
import com.deepseek.harness.android.domain.model.ModelSelection
import com.deepseek.harness.android.domain.model.QueueUpdateKind
import com.deepseek.harness.android.domain.model.QueueUpdateRequest
import com.deepseek.harness.android.domain.model.SendMessageRequest
import com.deepseek.harness.android.domain.model.SessionModels
import com.deepseek.harness.android.domain.model.SessionSearchResult
import com.deepseek.harness.android.domain.model.SessionSummary
import com.deepseek.harness.android.domain.model.SubagentCatalog
import com.deepseek.harness.android.domain.model.SubagentEntry
import com.deepseek.harness.android.domain.model.TimelineItem
import com.deepseek.harness.android.domain.model.TimelineWindow
import com.deepseek.harness.android.domain.model.WorkspaceSummary
import com.deepseek.harness.android.domain.model.QuestionAnswer
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.map

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

    /** List one host-directory level; absent path lists the host home. */
    suspend fun listDirectory(path: String? = null): DirectoryListing =
        unsupported("listDirectory")

    /** Create one child directory inside [parentPath]. */
    suspend fun createDirectory(parentPath: String, name: String): String =
        unsupported("createDirectory")

    /**
     * Read-only settings overview. The host pins this verb to loopback
     * connections; other sources receive a transport error.
     */
    suspend fun describeSettings(): SettingsSnapshot =
        unsupported("describeSettings")

    /**
     * Read-only probe of credential references. Like settings describe, the
     * host only serves it to loopback-trusted callers.
     */
    suspend fun describeCredentials(refs: List<String>): List<CredentialStatus> =
        unsupported("describeCredentials")

    /** Store one credential value; loopback-trusted connections only. */
    suspend fun setCredential(ref: String, value: String) {
        unsupported("setCredential")
    }

    /** Clear one stored credential; loopback-trusted connections only. */
    suspend fun unsetCredential(ref: String) {
        unsupported("unsetCredential")
    }

    suspend fun openSession(sessionId: String)

    fun observeTimeline(sessionId: String): Flow<List<TimelineItem>>

    /**
     * Pagination-aware timeline window. The default derives from
     * [observeTimeline] so legacy fakes keep working untouched; the harness
     * adapter overrides this with a journal-backed state machine.
     */
    fun observeTimelineWindow(sessionId: String): Flow<TimelineWindow> =
        observeTimeline(sessionId).map { items -> TimelineWindow(items = items) }

    /**
     * Load the previous history page. Returns true when an older page was
     * accepted and folded, false when there is no more history or loading is
     * already in flight. The default no-op keeps old test doubles valid.
     */
    suspend fun loadOlderHistory(sessionId: String): Boolean = false

    suspend fun sendMessage(request: SendMessageRequest)

    /** Download one durable image; bytes are session-authorized. */
    suspend fun readAttachment(sessionId: String, attachmentId: String): AttachmentData =
        unsupported("readAttachment")

    /** Session-scoped user-invocable skill catalog for the `/` composer source. */
    suspend fun listSkills(sessionId: String): List<SkillEntry> =
        unsupported("listSkills")

    /** Host image admission limits from the `imageLimits` session projection. */
    fun observeImageLimits(): Flow<ImageLimits?> = flowOf(null)

    suspend fun cancelTurn(sessionId: String)

    suspend fun respondToApproval(answer: ApprovalAnswer)

    suspend fun answerQuestions(
        requestId: String,
        evidence: QuestionEvidence,
    )

    fun observeWorkspaces(): Flow<List<WorkspaceSummary>>

    /** Registry-global archive set mirrored from `workspace.list` and host frames. */
    fun observeArchivedSessionIds(): Flow<Set<String>> = flowOf(emptySet())

    suspend fun refreshWorkspaces()

    /** Archive a session without deleting its log or workspace accounting slot. */
    suspend fun archiveSession(sessionId: String) {
        unsupported("archiveSession")
    }

    suspend fun createWorkspace(path: String): WorkspaceSummary

    /**
     * Rename a registered workspace. Production adapters override this with
     * the dsh `workspace.rename` call. Test doubles may leave the default
     * implementation and only stub the operations their scenario exercises.
     */
    suspend fun renameWorkspace(workspaceId: String, title: String): WorkspaceSummary =
        unsupported("renameWorkspace")

    suspend fun deleteWorkspace(workspaceId: String)

    /**
     * Move one workspace in the durable display order; a null anchor appends
     * to the end. Returns the complete order after the move.
     */
    suspend fun moveWorkspace(workspaceId: String, beforeWorkspaceId: String?): List<String> =
        unsupported("moveWorkspace")

    suspend fun loadModels(sessionId: String): SessionModels

    suspend fun selectModel(sessionId: String, selection: ModelSelection): ModelSelection

    suspend fun searchSessions(query: String): List<SessionSearchResult>

    suspend fun renameSession(sessionId: String, title: String): String

    suspend fun forkSession(sessionId: String, atSeq: Long? = null): SessionSummary

    suspend fun updateQueue(request: QueueUpdateRequest)

    suspend fun loadSubagents(parentSessionId: String): SubagentCatalog

    suspend fun interruptSubagent(parentSessionId: String, childSessionId: String)

    suspend fun loadSubagentHistory(parentSessionId: String, childSessionId: String): List<TimelineItem>

    suspend fun sendSubagentPrompt(parentSessionId: String, childSessionId: String, text: String): String

    fun observeGoal(sessionId: String): Flow<GoalProjection?>

    /** Plan collaboration state; null while the host composes no plan mode. */
    fun observePlan(sessionId: String): Flow<PlanState?> = flowOf(null)

    suspend fun createGoal(sessionId: String, objective: String, maxGoalRounds: Long? = null): GoalRef

    /**
     * Replaces the current goal's objective without changing its phase.
     * Test doubles may use the default [unsupported] implementation unless
     * their scenario explicitly exercises the Web GoalBar edit verb.
     */
    suspend fun editGoal(sessionId: String, ref: GoalRef, objective: String): GoalRef =
        unsupported("editGoal")

    suspend fun pauseGoal(sessionId: String, ref: GoalRef): GoalRef

    suspend fun resumeGoal(sessionId: String, ref: GoalRef): GoalRef

    suspend fun completeGoal(sessionId: String, ref: GoalRef): GoalRef

    suspend fun clearGoal(sessionId: String, ref: GoalRef)
}

private fun unsupported(operation: String): Nothing =
    throw UnsupportedOperationException("$operation is not supported by this repository double")

data class QuestionEvidence(
    val sessionId: String,
    val answers: List<QuestionAnswer>,
)
