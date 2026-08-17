package com.deepseek.harness.android.harness

import com.deepseek.harness.android.domain.model.ApprovalAnswer
import com.deepseek.harness.android.domain.model.ConnectionPhase
import com.deepseek.harness.android.domain.model.ConnectionState
import com.deepseek.harness.android.domain.model.CreateSessionRequest
import com.deepseek.harness.android.domain.model.PromptMode
import com.deepseek.harness.android.domain.model.QuestionAnswer
import com.deepseek.harness.android.domain.model.SendMessageRequest
import com.deepseek.harness.android.domain.model.SessionSummary
import com.deepseek.harness.android.domain.model.TimelineItem
import com.deepseek.harness.android.domain.repository.ChatRepository
import com.deepseek.harness.android.domain.repository.QuestionEvidence
import com.deepseek.harness.android.harness.dto.SessionCancelValue
import com.deepseek.harness.android.harness.dto.SessionCreateValue
import com.deepseek.harness.android.harness.dto.SessionHistoryValue
import com.deepseek.harness.android.harness.dto.SessionListValue
import com.deepseek.harness.android.harness.dto.SessionPromptValue
import com.deepseek.harness.android.network.DshBusinessException
import com.deepseek.harness.android.network.DshRpcClient
import com.deepseek.harness.android.network.RpcResult
import com.deepseek.harness.android.network.ServerRequest
import java.util.concurrent.ConcurrentHashMap
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.decodeFromJsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put

private const val SESSION_LIST = "session.list"
private const val SESSION_CREATE = "session.create"
private const val SESSION_HISTORY = "session.history"
private const val SESSION_PROMPT = "session.prompt"
private const val SESSION_CANCEL = "session.cancel"

@Singleton
class HarnessRepositoryImpl @Inject constructor(
    private val rpcClient: DshRpcClient,
    private val connectionManager: DshConnectionManager,
    private val json: Json,
) : ChatRepository {

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val connectionGeneration = MutableStateFlow(0L)
    private val sessions = MutableStateFlow<List<SessionSummary>>(emptyList())
    private val sessionStates = ConcurrentHashMap<String, SessionState>()
    private val resyncMutex = Mutex()

    init {
        connectionManager.start()
        collectConnection()
        collectMuxFrames()
        collectHostFrames()
    }

    override fun observeConnectionState(): Flow<ConnectionState> =
        connectionManager.state

    override fun observeSessions(): Flow<List<SessionSummary>> =
        sessions.asStateFlow()

    override suspend fun refreshSessions() {
        val current = loadSessions()
        sessions.value = current
    }

    override suspend fun createSession(request: CreateSessionRequest): SessionSummary {
        val payload = buildJsonObject {
            request.sessionId?.let { put("sessionId", it) }
            request.workspaceId?.let { put("workspaceId", it) }
            request.cwd?.let { put("cwd", it) }
            request.agentPreset?.let { put("agentPreset", it) }
        }
        val value = rpcClient.call(SESSION_CREATE, SESSION_CREATE, payload).valueOrThrow()
        val created = json.decodeFromJsonElement<SessionCreateValue>(value)
        sessions.value = loadSessions()
        return SessionSummary(id = created.sessionId, blank = true)
    }

    override suspend fun openSession(sessionId: String) {
        val state = sessionStates.getOrPut(sessionId) { SessionState(sessionId) }
        try {
            state.ensureLoaded { loadHistory(sessionId) }
        } catch (error: CancellationException) {
            throw error
        } catch (_: Throwable) {
            // A failed first load stays pending; the next generation retries it.
        }
    }

    override fun observeTimeline(sessionId: String): Flow<List<TimelineItem>> {
        val state = sessionStates.getOrPut(sessionId) { SessionState(sessionId) }
        return state.timeline
    }

    override suspend fun sendMessage(request: SendMessageRequest) {
        val payload = buildJsonObject {
            put("sessionId", request.sessionId)
            put("mode", if (request.mode == PromptMode.QUEUE) "queue" else "steer")
            put(
                "content",
                buildJsonArray {
                    add(
                        buildJsonObject {
                            put("type", "text")
                            put("text", request.text)
                        },
                    )
                },
            )
        }
        val value = rpcClient.call(SESSION_PROMPT, SESSION_PROMPT, payload).valueOrThrow()
        json.decodeFromJsonElement<SessionPromptValue>(value)
    }

    override suspend fun cancelTurn(sessionId: String) {
        val payload = buildJsonObject {
            put("sessionId", sessionId)
        }
        val value = rpcClient.call(SESSION_CANCEL, SESSION_CANCEL, payload).valueOrThrow()
        json.decodeFromJsonElement<SessionCancelValue>(value)
    }

    override suspend fun respondToApproval(answer: ApprovalAnswer) {
        val value = buildJsonObject {
            put("sessionId", answer.sessionId)
            put("approvalId", answer.approvalId)
            put("outcome", if (answer.allowed) "allowed-once" else "rejected")
        }
        rpcClient.respond(
            rpcId = answer.requestId,
            result = RpcResult(ok = true, value = value),
        )
    }

    override suspend fun answerQuestions(
        requestId: String,
        evidence: QuestionEvidence,
    ) {
        val value = buildJsonObject {
            put("sessionId", evidence.sessionId)
            put(
                "answer",
                buildJsonObject {
                    put(
                        "answers",
                        buildJsonArray {
                            evidence.answers.forEach { answer ->
                                add(
                                    buildJsonObject {
                                        put("id", answer.questionId)
                                        put(
                                            "selected",
                                            buildJsonArray {
                                                answer.selectedOptions.forEach { selected ->
                                                    this.add(selected)
                                                }
                                            },
                                        )
                                        answer.customText?.let { put("custom", it) }
                                    },
                                )
                            }
                        },
                    )
                },
            )
        }
        rpcClient.respond(
            rpcId = requestId,
            result = RpcResult(ok = true, value = value),
        )
    }

    private fun collectConnection() {
        scope.launch {
            connectionManager.state.collect { connection ->
                if (connection.phase == ConnectionPhase.CONNECTED
                    && connection.generation != connectionGeneration.value
                ) {
                    connectionGeneration.value = connection.generation
                    resync(connection)
                }
            }
        }
    }

    private fun collectMuxFrames() {
        scope.launch {
            connectionManager.muxFrames.collect { frame ->
                val sessionId = frame.frameSessionId() ?: return@collect
                val state = sessionStates[sessionId] ?: return@collect
                state.handleFrame(frame)
            }
        }
    }

    private fun collectHostFrames() {
        scope.launch {
            connectionManager.hostFrames.collect { frame ->
                val type = frame.payload["type"]?.jsonPrimitive?.contentOrNull ?: return@collect
                val sessionId = frame.payload["sessionId"]?.jsonPrimitive?.contentOrNull
                when (type) {
                    "host/session-status" -> {
                        if (sessionId == null) return@collect
                        val running = frame.payload["running"]?.jsonPrimitive?.content == "true"
                        sessions.update { current ->
                            current.map { item ->
                                if (item.id == sessionId) item.copy(running = running) else item
                            }
                        }
                    }
                    "host/session-added", "host/session-removed" -> {
                        try {
                            refreshSessions()
                        } catch (_: Throwable) {
                            // Retried on next generation.
                        }
                    }
                }
            }
        }
    }

    private suspend fun resync(connection: ConnectionState) {
        resyncMutex.withLock {
            sessionStates.values.forEach { state -> state.prepareResync() }
            try {
                refreshSessions()
            } catch (_: Throwable) {
                // List failure does not block timeline recovery.
            }
            sessionStates.values.forEach { state ->
                try {
                    state.ensureLoaded { loadHistory(state.sessionId) }
                } catch (_: Throwable) {
                    // Pending state retries on the next generation.
                }
            }
        }
    }

    private suspend fun loadSessions(): List<SessionSummary> {
        val value = rpcClient.call(SESSION_LIST, SESSION_LIST, buildJsonObject {}).valueOrThrow()
        val listing = json.decodeFromJsonElement<SessionListValue>(value)
        return listing.items.map { session ->
            SessionSummary(
                id = session.sessionId,
                running = session.running,
                blank = session.blank,
                updatedAtEpochMs = session.updatedAt,
            )
        }
    }

    private suspend fun loadHistory(sessionId: String): List<JsonObject> {
        val payload = buildJsonObject {
            put("sessionId", sessionId)
        }
        val value = rpcClient.call(SESSION_HISTORY, SESSION_HISTORY, payload).valueOrThrow()
        val history = json.decodeFromJsonElement<SessionHistoryValue>(value)
        return history.events.map { it.event }
    }

    private inner class SessionState(
        val sessionId: String,
    ) {
        val timeline = MutableStateFlow<List<TimelineItem>>(emptyList())
        private val mutex = Mutex()
        private var reducer = TimelineReducer(sessionId)
        private var ready = false
        private val pending = mutableListOf<ServerRequest>()

        suspend fun ensureLoaded(loader: suspend () -> List<JsonObject>) {
            mutex.withLock {
                if (ready) return
                val events = loader()
                reducer = TimelineReducer(sessionId)
                reducer.reset(events)
                pending.forEach(reducer::ingestFrame)
                pending.clear()
                ready = true
                timeline.value = reducer.snapshot()
            }
        }

        suspend fun prepareResync() {
            mutex.withLock {
                ready = false
            }
        }

        suspend fun handleFrame(frame: ServerRequest) {
            mutex.withLock {
                if (!ready) {
                    pending += frame
                    return
                }
                reducer.ingestFrame(frame)
                timeline.value = reducer.snapshot()
            }
        }
    }

    private fun ServerRequest.frameSessionId(): String? =
        payload["sessionId"]?.jsonPrimitive?.contentOrNull

    private fun RpcResult.valueOrThrow(): JsonObject {
        if (ok) {
            return value ?: throw DshBusinessException(
                code = "bad-response",
                message = "missing result value",
            )
        }
        val failure = error
        throw DshBusinessException(
            code = failure?.code ?: "internal",
            message = failure?.message ?: "unknown dsh error",
        )
    }
}
