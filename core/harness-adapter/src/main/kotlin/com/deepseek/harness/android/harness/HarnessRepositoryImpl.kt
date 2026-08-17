package com.deepseek.harness.android.harness

import com.deepseek.harness.android.domain.model.ApprovalAnswer
import com.deepseek.harness.android.domain.model.ConnectionPhase
import com.deepseek.harness.android.domain.model.ConnectionState
import com.deepseek.harness.android.domain.model.GoalPhase
import com.deepseek.harness.android.domain.model.GoalProjection
import com.deepseek.harness.android.domain.model.GoalRef
import com.deepseek.harness.android.domain.model.GoalSnapshot
import com.deepseek.harness.android.domain.model.CreateSessionRequest
import com.deepseek.harness.android.domain.model.ModelCatalogFailure
import com.deepseek.harness.android.domain.model.ModelCatalogModel
import com.deepseek.harness.android.domain.model.ModelProviderGroup
import com.deepseek.harness.android.domain.model.ModelReasoning
import com.deepseek.harness.android.domain.model.ModelReasoningEffort
import com.deepseek.harness.android.domain.model.ModelSelection
import com.deepseek.harness.android.domain.model.QueueUpdateKind
import com.deepseek.harness.android.domain.model.SessionModels
import com.deepseek.harness.android.domain.model.SessionSearchResult
import com.deepseek.harness.android.domain.model.WorkspaceSummary
import com.deepseek.harness.android.domain.model.PromptMode
import com.deepseek.harness.android.domain.model.QuestionAnswer
import com.deepseek.harness.android.domain.model.QueueUpdateRequest
import com.deepseek.harness.android.domain.model.SendMessageRequest
import com.deepseek.harness.android.domain.model.SessionSummary
import com.deepseek.harness.android.domain.model.SubagentCatalog
import com.deepseek.harness.android.domain.model.SubagentEntry
import com.deepseek.harness.android.domain.model.TimelineItem
import com.deepseek.harness.android.domain.repository.ChatRepository
import kotlinx.coroutines.CancellationException
import com.deepseek.harness.android.domain.repository.QuestionEvidence
import com.deepseek.harness.android.harness.dto.SessionCancelValue
import com.deepseek.harness.android.harness.dto.SessionCreateValue
import com.deepseek.harness.android.harness.dto.SessionHistoryValue
import com.deepseek.harness.android.harness.dto.GoalProjectionWire
import com.deepseek.harness.android.harness.dto.GoalSnapshotWire
import com.deepseek.harness.android.harness.dto.GoalBlockReasonWire
import com.deepseek.harness.android.harness.dto.GoalRefValue
import com.deepseek.harness.android.harness.dto.GoalRefWire
import com.deepseek.harness.android.harness.dto.ModelCatalogFailureWire
import com.deepseek.harness.android.harness.dto.ModelCatalogModelWire
import com.deepseek.harness.android.harness.dto.ModelProviderGroupWire
import com.deepseek.harness.android.harness.dto.ModelReasoningWire
import com.deepseek.harness.android.harness.dto.ModelSelectionWire
import com.deepseek.harness.android.harness.dto.SessionListValue
import com.deepseek.harness.android.harness.dto.SessionWire
import com.deepseek.harness.android.harness.dto.SessionModelsValue
import com.deepseek.harness.android.harness.dto.SessionSearchValue
import com.deepseek.harness.android.harness.dto.SessionSelectModelValue
import com.deepseek.harness.android.harness.dto.WorkspaceCreateValue
import com.deepseek.harness.android.harness.dto.WorkspaceListValue
import com.deepseek.harness.android.harness.dto.WorkspaceWire
import com.deepseek.harness.android.harness.dto.SessionPromptValue
import com.deepseek.harness.android.harness.dto.SessionQueueUpdateValue
import com.deepseek.harness.android.harness.dto.SubagentEntryWire
import com.deepseek.harness.android.harness.dto.SubagentInterruptValue
import com.deepseek.harness.android.harness.dto.SubagentListValue
import com.deepseek.harness.android.harness.dto.SubagentPromptValue
import com.deepseek.harness.android.harness.dto.SessionRenameValue
import com.deepseek.harness.android.harness.dto.SessionForkValue
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
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.decodeFromJsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put

private const val SESSION_LIST = "session.list"
private const val SESSION_CREATE = "session.create"
private const val SESSION_HISTORY = "session.history"
private const val SESSION_PROMPT = "session.prompt"
private const val SESSION_CANCEL = "session.cancel"
private const val SESSION_MODELS = "session.models"
private const val SESSION_SELECT_MODEL = "session.selectModel"
private const val SESSION_SEARCH = "session.search"
private const val SESSION_RENAME = "session.rename"
private const val SESSION_FORK = "session.fork"
private const val SESSION_UPDATE_QUEUE = "session.updateQueue"
private const val WORKSPACE_LIST = "workspace.list"
private const val WORKSPACE_CREATE = "workspace.create"
private const val WORKSPACE_DELETE = "workspace.delete"
private const val SUBAGENT_LIST = "subagent.list"
private const val SUBAGENT_INTERRUPT = "subagent.interrupt"
private const val SUBAGENT_HISTORY = "subagent.history"
private const val SUBAGENT_PROMPT = "subagent.prompt"
private const val GOAL_CREATE = "goal.create"
private const val GOAL_PAUSE = "goal.pause"
private const val GOAL_RESUME = "goal.resume"
private const val GOAL_COMPLETE = "goal.complete"
private const val GOAL_CLEAR = "goal.clear"

@Singleton
class HarnessRepositoryImpl @Inject constructor(
    private val rpcClient: DshRpcClient,
    private val connectionManager: DshConnectionManager,
    private val json: Json,
) : ChatRepository {

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val connectionGeneration = MutableStateFlow(0L)
    private val sessions = MutableStateFlow<List<SessionSummary>>(emptyList())
    private val workspaces = MutableStateFlow<List<WorkspaceSummary>>(emptyList())
    private val sessionStates = ConcurrentHashMap<String, SessionState>()
    private val goalProjections = ConcurrentHashMap<String, MutableStateFlow<GoalProjection?>>()
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
                                                    add(JsonPrimitive(selected))
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

    override suspend fun renameSession(sessionId: String, title: String): String {
        val result = rpcClient.call(
            SESSION_RENAME,
            SESSION_RENAME,
            buildJsonObject {
                put("sessionId", sessionId)
                put("title", title)
            },
        ).valueOrThrow()
        val renamed = json.decodeFromJsonElement<SessionRenameValue>(result)
        sessions.value = loadSessions()
        return renamed.title
    }

    override suspend fun forkSession(sessionId: String, atSeq: Long?): SessionSummary {
        val result = rpcClient.call(
            SESSION_FORK,
            SESSION_FORK,
            buildJsonObject {
                put("sessionId", sessionId)
                atSeq?.let { put("atSeq", it) }
            },
        ).valueOrThrow()
        val forked = json.decodeFromJsonElement<SessionForkValue>(result)
        sessions.value = loadSessions()
        return SessionSummary(id = forked.sessionId, blank = false)
    }

    override suspend fun updateQueue(request: QueueUpdateRequest) {
        val action = buildJsonObject {
            put("kind", if (request.kind == QueueUpdateKind.REMOVE) "remove" else "steer")
        }
        val result = rpcClient.call(
            SESSION_UPDATE_QUEUE,
            SESSION_UPDATE_QUEUE,
            buildJsonObject {
                put("sessionId", request.sessionId)
                put("itemId", request.itemId)
                put("action", action)
            },
        ).valueOrThrow()
        json.decodeFromJsonElement<SessionQueueUpdateValue>(result)
    }

    override suspend fun loadSubagents(parentSessionId: String): SubagentCatalog {
        val value = rpcClient.call(
            SUBAGENT_LIST,
            SUBAGENT_LIST,
            buildJsonObject { put("parentSessionId", parentSessionId) },
        ).valueOrThrow()
        val wire = json.decodeFromJsonElement<SubagentListValue>(value)
        return SubagentCatalog(
            entries = wire.entries.map { entry ->
                SubagentEntry(
                    id = entry.id,
                    kind = entry.kind,
                    mode = entry.mode,
                    activity = entry.activity,
                    hasChildren = entry.hasChildren,
                    label = entry.label,
                    reason = entry.reason,
                )
            },
            parentAvailable = wire.parentAvailable,
        )
    }

    override suspend fun interruptSubagent(parentSessionId: String, childSessionId: String) {
        rpcClient.call(
            SUBAGENT_INTERRUPT,
            SUBAGENT_INTERRUPT,
            buildJsonObject {
                put("parentSessionId", parentSessionId)
                put("childSessionId", childSessionId)
                put("mode", "continuable")
            },
        ).valueOrThrow()
    }

    override suspend fun loadSubagentHistory(parentSessionId: String, childSessionId: String): List<TimelineItem> {
        val value = rpcClient.call(
            SUBAGENT_HISTORY,
            SUBAGENT_HISTORY,
            buildJsonObject {
                put("parentSessionId", parentSessionId)
                put("childSessionId", childSessionId)
                put("mode", "continuable")
            },
        ).valueOrThrow()
        val history = json.decodeFromJsonElement<SessionHistoryValue>(value)
        val reducer = TimelineReducer(childSessionId)
        reducer.reset(history.events.map { it.event })
        return reducer.snapshot()
    }

    override suspend fun sendSubagentPrompt(parentSessionId: String, childSessionId: String, text: String): String {
        val value = rpcClient.call(
            SUBAGENT_PROMPT,
            SUBAGENT_PROMPT,
            buildJsonObject {
                put("parentSessionId", parentSessionId)
                put("childSessionId", childSessionId)
                put("mode", "continuable")
                put(
                    "content",
                    buildJsonArray {
                        add(buildJsonObject { put("type", "text"); put("text", text) })
                    },
                )
            },
        ).valueOrThrow()
        return json.decodeFromJsonElement<SubagentPromptValue>(value).messageId
    }

    override fun observeGoal(sessionId: String): Flow<GoalProjection?> =
        goalProjections.getOrPut(sessionId) { MutableStateFlow(null) }

    override suspend fun createGoal(sessionId: String, objective: String, maxGoalRounds: Long?): GoalRef {
        val value = rpcClient.call(
            GOAL_CREATE,
            GOAL_CREATE,
            buildJsonObject {
                put("sessionId", sessionId)
                put("objective", objective)
                maxGoalRounds?.let { put("maxGoalRounds", it) }
            },
        ).valueOrThrow()
        return json.decodeFromJsonElement<GoalRefValue>(value).ref.toDomain()
    }

    override suspend fun pauseGoal(sessionId: String, ref: GoalRef): GoalRef =
        goalMutation(GOAL_PAUSE, sessionId, ref)

    override suspend fun resumeGoal(sessionId: String, ref: GoalRef): GoalRef =
        goalMutation(GOAL_RESUME, sessionId, ref)

    override suspend fun completeGoal(sessionId: String, ref: GoalRef): GoalRef =
        goalMutation(GOAL_COMPLETE, sessionId, ref)

    override suspend fun clearGoal(sessionId: String, ref: GoalRef) {
        rpcClient.call(
            GOAL_CLEAR,
            GOAL_CLEAR,
            goalPayload(sessionId, ref),
        ).valueOrThrow()
        goalProjections[sessionId]?.value = null
    }

    private suspend fun goalMutation(endpoint: String, sessionId: String, ref: GoalRef): GoalRef {
        val value = rpcClient.call(endpoint, endpoint, goalPayload(sessionId, ref)).valueOrThrow()
        return json.decodeFromJsonElement<GoalRefValue>(value).ref.toDomain()
    }

    private fun goalPayload(sessionId: String, ref: GoalRef): JsonObject = buildJsonObject {
        put("sessionId", sessionId)
        put(
            "ref",
            buildJsonObject {
                put("id", ref.id)
                put("revision", ref.revision)
            },
        )
    }

    override fun observeWorkspaces(): Flow<List<WorkspaceSummary>> =
        workspaces.asStateFlow()

    override suspend fun refreshWorkspaces() {
        val result = rpcClient.call(WORKSPACE_LIST, WORKSPACE_LIST, buildJsonObject {}).valueOrThrow()
        val listing = json.decodeFromJsonElement<WorkspaceListValue>(result)
        workspaces.value = listing.items.map { it.toDomain() }
    }

    override suspend fun createWorkspace(path: String): WorkspaceSummary {
        val result = rpcClient.call(
            WORKSPACE_CREATE,
            WORKSPACE_CREATE,
            buildJsonObject { put("path", path) },
        ).valueOrThrow()
        val created = json.decodeFromJsonElement<WorkspaceCreateValue>(result)
        workspaces.value = loadWorkspaces()
        return created.workspace.toDomain()
    }

    override suspend fun deleteWorkspace(workspaceId: String) {
        rpcClient.call(
            WORKSPACE_DELETE,
            WORKSPACE_DELETE,
            buildJsonObject { put("workspaceId", workspaceId) },
        ).valueOrThrow()
        workspaces.value = loadWorkspaces()
    }

    override suspend fun loadModels(sessionId: String): SessionModels {
        val result = rpcClient.call(
            SESSION_MODELS,
            SESSION_MODELS,
            buildJsonObject { put("sessionId", sessionId) },
        ).valueOrThrow()
        return json.decodeFromJsonElement<SessionModelsValue>(result).toDomain()
    }

    override suspend fun selectModel(sessionId: String, selection: ModelSelection): ModelSelection {
        val payload = buildJsonObject {
            put("sessionId", sessionId)
            put("provider", selection.provider)
            put("model", selection.model)
            selection.reasoningEffort?.let { put("reasoningEffort", it) }
        }
        val result = rpcClient.call(SESSION_SELECT_MODEL, SESSION_SELECT_MODEL, payload).valueOrThrow()
        return json.decodeFromJsonElement<SessionSelectModelValue>(result).selected.toDomain()
    }

    override suspend fun searchSessions(query: String): List<SessionSearchResult> {
        val result = rpcClient.call(SESSION_SEARCH, SESSION_SEARCH, buildJsonObject { put("query", query) }).valueOrThrow()
        return json.decodeFromJsonElement<SessionSearchValue>(result).items.map { item ->
            SessionSearchResult(sessionId = item.sessionId, snippet = item.snippet)
        }
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
                val type = frame.payload["type"]?.jsonPrimitive?.contentOrNull
                if (type == "session/projection") {
                    handleProjection(frame)
                    return@collect
                }
                val sessionId = frame.frameSessionId() ?: return@collect
                val state = sessionStates[sessionId] ?: return@collect
                state.handleFrame(frame)
            }
        }
    }

    private fun handleProjection(frame: ServerRequest) {
        val sessionId = frame.frameSessionId() ?: return
        when (frame.payload["key"]?.jsonPrimitive?.contentOrNull) {
            "title" -> {
                val title = frame.payload["value"]?.jsonPrimitive?.contentOrNull
                if (title != null && title != "null") {
                    sessions.update { current ->
                        current.map { if (it.id == sessionId) it.copy(title = title) else it }
                    }
                } else {
                    sessions.update { current ->
                        current.map { if (it.id == sessionId) it.copy(title = null) else it }
                    }
                }
            }
            "goal" -> {
                val value = frame.payload["value"]
                val projection = runCatching {
                    if (value == null || value.jsonPrimitive?.contentOrNull == "null") null
                    else json.decodeFromJsonElement<GoalProjectionWire>(value)
                }.getOrNull()
                if (projection == null) {
                    goalProjections.getOrPut(sessionId) { MutableStateFlow(null) }.value = null
                } else {
                    goalProjections.getOrPut(sessionId) { MutableStateFlow(projection.toDomain()) }.value = projection.toDomain()
                }
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
                    "host/workspace-changed", "host/workspace-removed", "host/workspace-order-changed" -> {
                        try {
                            refreshWorkspaces()
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
                refreshWorkspaces()
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
        return listing.items.map { it.toDomain() }
    }

    private fun SessionWire.toDomain(): SessionSummary = SessionSummary(
        id = sessionId,
        title = titleFromProjections(),
        running = running,
        blank = blank,
        updatedAtEpochMs = updatedAt,
    )

    private fun SessionWire.titleFromProjections(): String? {
        val value = projections?.values?.get("title") ?: return null
        return value.jsonPrimitive?.contentOrNull
    }

    private suspend fun loadHistory(sessionId: String): List<JsonObject> {
        val payload = buildJsonObject {
            put("sessionId", sessionId)
        }
        val value = rpcClient.call(SESSION_HISTORY, SESSION_HISTORY, payload).valueOrThrow()
        val history = json.decodeFromJsonElement<SessionHistoryValue>(value)
        history.projections?.values?.get("goal")?.let { goalValue ->
            goalProjections.getOrPut(sessionId) { MutableStateFlow(null) }.value =
                parseGoalProjection(goalValue)
        }
        return history.events.map { it.event }
    }

    private fun parseGoalProjection(value: JsonElement?): GoalProjection? {
        if (value == null || value.jsonPrimitive?.contentOrNull == "null") return null
        return runCatching { json.decodeFromJsonElement<GoalProjectionWire>(value).toDomain() }.getOrNull()
    }

    private fun GoalRefWire.toDomain(): GoalRef = GoalRef(
        id = id,
        revision = revision,
    )

    private fun GoalProjectionWire.toDomain(): GoalProjection = GoalProjection(
        goal = goal.toDomain(),
        roundsStarted = roundsStarted,
        createdAt = createdAt,
        updatedAt = updatedAt,
    )

    private fun GoalSnapshotWire.toDomain(): GoalSnapshot = GoalSnapshot(
        id = id,
        revision = revision,
        objective = objective,
        phase = when (phase) {
            "paused" -> GoalPhase.PAUSED
            "blocked" -> GoalPhase.BLOCKED
            "complete" -> GoalPhase.COMPLETE
            else -> GoalPhase.ACTIVE
        },
        blockedReason = blockedReason?.message,
        maxGoalRounds = maxGoalRounds,
    )

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

    private suspend fun loadWorkspaces(): List<WorkspaceSummary> {
        val result = rpcClient.call(WORKSPACE_LIST, WORKSPACE_LIST, buildJsonObject {}).valueOrThrow()
        return json.decodeFromJsonElement<WorkspaceListValue>(result).items.map { it.toDomain() }
    }

    private fun WorkspaceWire.toDomain(): WorkspaceSummary = WorkspaceSummary(
        workspaceId = workspaceId,
        path = path,
        title = title,
        sessionIds = sessionIds,
        createdAt = createdAt,
        updatedAt = updatedAt,
    )

    private fun SessionModelsValue.toDomain(): SessionModels = SessionModels(
        current = current.toDomain(),
        routable = routable,
        groups = groups.map { group ->
            ModelProviderGroup(
                id = group.id,
                name = group.name,
                models = group.models.map { it.toDomain() },
            )
        },
        failures = failures.map { failure ->
            ModelCatalogFailure(id = failure.id, name = failure.name, message = failure.message)
        },
    )

    private fun ModelSelectionWire.toDomain(): ModelSelection = ModelSelection(
        provider = provider,
        model = model,
        reasoningEffort = reasoningEffort,
    )

    private fun ModelCatalogModelWire.toDomain(): ModelCatalogModel = ModelCatalogModel(
        id = id,
        name = name,
        description = description,
        reasoning = reasoning?.toDomain(),
    )

    private fun ModelReasoningWire.toDomain(): ModelReasoning = ModelReasoning(
        efforts = efforts.map { effort ->
            ModelReasoningEffort(id = effort.id, name = effort.name, description = effort.description)
        },
        defaultEffort = defaultEffort,
    )

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
