package com.deepseek.harness.android.harness

import com.deepseek.harness.android.domain.model.ChatMessage
import com.deepseek.harness.android.domain.model.CreateSessionRequest
import com.deepseek.harness.android.domain.model.MessageRole
import com.deepseek.harness.android.domain.model.PromptMode
import com.deepseek.harness.android.domain.model.SendMessageRequest
import com.deepseek.harness.android.domain.model.SessionSummary
import com.deepseek.harness.android.domain.model.TimelineItem
import com.deepseek.harness.android.domain.repository.ChatRepository
import com.deepseek.harness.android.harness.dto.SessionCancelValue
import com.deepseek.harness.android.harness.dto.SessionCreateValue
import com.deepseek.harness.android.harness.dto.SessionListValue
import com.deepseek.harness.android.harness.dto.SessionPromptValue
import com.deepseek.harness.android.network.DshBusinessException
import com.deepseek.harness.android.network.DshEventSocket
import com.deepseek.harness.android.network.DshRpcClient
import com.deepseek.harness.android.network.RpcResult
import com.deepseek.harness.android.network.ServerRequest
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.filter
import kotlinx.coroutines.flow.mapNotNull
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put

private const val SESSION_LIST = "session.list"
private const val SESSION_CREATE = "session.create"
private const val SESSION_PROMPT = "session.prompt"
private const val SESSION_CANCEL = "session.cancel"
private const val MUX_STREAM_PATH = "/api/events.mux"

/**
 * The anti-corruption layer implementation.
 *
 * It is the only production code allowed to understand dsh endpoints and
 * frame shapes. Everything leaving this class is a neutral domain model.
 */
@Singleton
class HarnessRepositoryImpl @Inject constructor(
    private val rpcClient: DshRpcClient,
    private val eventSocket: DshEventSocket,
    private val json: Json,
) : ChatRepository {

    private val sessions = MutableStateFlow<List<SessionSummary>>(emptyList())

    override fun observeSessions(): Flow<List<SessionSummary>> =
        sessions.asStateFlow()

    override suspend fun refreshSessions() {
        sessions.value = loadSessions()
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
        return SessionSummary(id = created.sessionId, blank = true)
    }

    override suspend fun cancelTurn(sessionId: String) {
        val payload = buildJsonObject {
            put("sessionId", sessionId)
        }
        val value = rpcClient.call(SESSION_CANCEL, SESSION_CANCEL, payload).valueOrThrow()
        json.decodeFromJsonElement<SessionCancelValue>(value)
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

    override fun observeTimeline(sessionId: String): Flow<TimelineItem> =
        eventSocket.connect(MUX_STREAM_PATH)
            .filter { envelope -> envelope.frameSessionId() == sessionId }
            .mapNotNull { envelope -> envelope.translate(sessionId) }

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

    private fun ServerRequest.frameSessionId(): String? =
        payload["sessionId"]?.jsonPrimitive?.contentOrNull

    private fun ServerRequest.translate(sessionId: String): TimelineItem? {
        val frameType = payload["type"]?.jsonPrimitive?.contentOrNull ?: return null
        return when (frameType) {
            "session/event" -> TimelineItem.Message(
                value = payload.toChatMessage(sessionId) ?: return null,
            )
            "approval/requested" -> TimelineItem.ApprovalRequest(
                id = payload["approvalId"]?.jsonPrimitive?.contentOrNull ?: rpcId,
                toolName = payload["toolName"]?.jsonPrimitive?.contentOrNull ?: "unknown",
                reason = payload["reason"]?.jsonPrimitive?.contentOrNull,
            )
            else -> null
        }
    }

    private fun JsonObject.toChatMessage(sessionId: String): ChatMessage? {
        val event = get("event")?.jsonObject ?: return null
        val eventType = event["type"]?.jsonPrimitive?.contentOrNull ?: return null
        val role = when (eventType) {
            "user/message" -> MessageRole.USER
            "assistant/message" -> MessageRole.ASSISTANT
            else -> return null
        }
        val message = event["data"]?.jsonObject?.get("message")?.jsonObject ?: return null
        val id = message["id"]?.jsonPrimitive?.contentOrNull
            ?: event["seq"]?.jsonPrimitive?.contentOrNull
            ?: return null
        val time = event["time"]?.jsonPrimitive?.contentOrNull?.toLongOrNull() ?: 0L
        return ChatMessage(
            id = id,
            sessionId = sessionId,
            role = role,
            text = message.extractText(),
            createdAtEpochMs = time,
        )
    }

    private fun JsonObject.extractText(): String {
        val content = get("content")?.jsonArray ?: return ""
        return content.mapNotNull { block ->
            val obj = block.jsonObject
            if (obj["type"]?.jsonPrimitive?.contentOrNull == "text") {
                obj["text"]?.jsonPrimitive?.contentOrNull
            } else {
                null
            }
        }.joinToString(separator = "")
    }

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
