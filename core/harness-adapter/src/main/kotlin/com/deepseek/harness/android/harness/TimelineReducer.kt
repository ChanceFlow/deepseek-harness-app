package com.deepseek.harness.android.harness

import com.deepseek.harness.android.domain.model.ChatMessage
import com.deepseek.harness.android.domain.model.JobStatus
import com.deepseek.harness.android.domain.model.JobView
import com.deepseek.harness.android.domain.model.MessageRole
import com.deepseek.harness.android.domain.model.QuestionItem
import com.deepseek.harness.android.domain.model.QueuePlacement
import com.deepseek.harness.android.domain.model.SessionQueueItem
import com.deepseek.harness.android.domain.model.TimelineItem
import com.deepseek.harness.android.domain.model.ToolRunStatus
import com.deepseek.harness.android.network.ServerRequest
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

/**
 * Incremental, seq-ordered reducer:
 * raw dsh session events -> immutable [TimelineItem] snapshot.
 *
 * History replay and live frames meet at the same `lastSeq` boundary, so an
 * event already folded by a history page is never applied twice.
 */
internal class TimelineReducer(
    private val sessionId: String,
) {
    private val items = mutableListOf<TimelineItem>()
    private var lastSeq = -1L
    private var partialKey: String? = null
    private var partialIndex: Int = -1

    fun reset(history: List<JsonObject>) {
        items.clear()
        lastSeq = -1L
        partialKey = null
        partialIndex = -1
        history.sortedBy { it.eventSeq() }.forEach(::ingestEvent)
    }

    fun snapshot(): List<TimelineItem> = items.toList()

    fun ingestFrame(envelope: ServerRequest) {
        val frame = envelope.payload
        when (frame.type()) {
            "session/event" -> frame["event"]?.jsonObject?.let(::ingestEvent)
            "approval/requested" -> {
                val approvalId = frame.string("approvalId") ?: envelope.rpcId
                upsertByKey(
                    key = "approval:$approvalId",
                    item = TimelineItem.ApprovalRequest(
                        requestId = envelope.rpcId,
                        sessionId = frame.string("sessionId") ?: sessionId,
                        approvalId = approvalId,
                        toolName = frame.string("toolName") ?: "unknown",
                        callId = frame.string("callId"),
                        reason = frame.string("reason"),
                    ),
                )
            }
            "approval/resolved" -> removeByKey("approval:${frame.string("approvalId")}")
            "question/requested" -> {
                val questions = frame["questions"]?.jsonArray
                    ?.mapNotNull { it.jsonObject.toQuestionItem() }
                    .orEmpty()
                upsertByKey(
                    key = "question:${envelope.rpcId}",
                    item = TimelineItem.QuestionRequest(
                        requestId = envelope.rpcId,
                        questions = questions,
                    ),
                )
            }
            "question/resolved" -> removeByKey("question:${frame.string("questionRpcId")}")
            "session/queue" -> {
                val items = frame["items"]?.jsonArray
                    ?.mapNotNull { it.jsonObject.toQueueItem() }
                    .orEmpty()
                upsertByKey(
                    key = "queue",
                    item = TimelineItem.Queue(items = items),
                )
            }
            "session/jobs" -> {
                val jobs = frame["jobs"]?.jsonArray
                    ?.mapNotNull { it.jsonObject.toJobView() }
                    .orEmpty()
                upsertByKey(
                    key = "jobs",
                    item = TimelineItem.Jobs(jobs = jobs),
                )
            }
        }
    }

    private fun ingestEvent(event: JsonObject) {
        val seq = event.eventSeq()
        if (seq <= lastSeq) return
        lastSeq = seq

        when (event.type()) {
            "user/message" -> appendUserMessage(event)
            "assistant/message" -> appendAssistantFinal(event)
            "assistant/chunk" -> appendAssistantDelta(event)
            "tool/call" -> appendToolCall(event)
            "tool/result" -> appendToolResult(event)
            "turn/end" -> appendTurnEnd(event)
        }
    }

    private fun appendUserMessage(event: JsonObject) {
        finalizePartial()
        val data = event.eventData()
        val text = data.extractText()
        val messageId = data.string("id") ?: "user:$lastSeq"
        items += TimelineItem.Message(
            ChatMessage(
                id = messageId,
                sessionId = sessionId,
                role = MessageRole.USER,
                text = text,
                createdAtEpochMs = event.eventTime(),
            ),
        )
    }

    private fun appendAssistantFinal(event: JsonObject) {
        val data = event.eventData()
        val turn = data.long("turn")
        val step = data.long("step")
        val message = data["message"]?.jsonObject ?: return
        val finalItem = TimelineItem.Message(
            ChatMessage(
                id = message.string("id") ?: "assistant:$lastSeq",
                sessionId = sessionId,
                role = MessageRole.ASSISTANT,
                text = message.extractText(),
                reasoning = message.extractReasoning(),
                createdAtEpochMs = event.eventTime(),
            ),
        )

        if (partialKey == turnStepKey(turn, step)) {
            items[partialIndex] = finalItem
            clearPartial()
        } else {
            finalizePartial()
            items += finalItem
        }
    }

    private fun appendAssistantDelta(event: JsonObject) {
        val data = event.eventData()
        val turn = data.long("turn")
        val step = data.long("step")
        val chunk = data["chunk"]?.jsonObject ?: return
        ensurePartial(turn, step, event)

        val current = items[partialIndex] as TimelineItem.Message
        val value = current.value
        val chunkType = chunk.type()

        var text = value.text
        var reasoning = value.reasoning
        when (chunkType) {
            "text-delta" -> text += chunk.string("text").orEmpty()
            "reasoning-delta" -> reasoning = (reasoning.orEmpty()) + chunk.string("text").orEmpty()
            "block-end" -> {
                val block = chunk["block"]?.jsonObject
                if (block != null) {
                    if (block.type() == "text") text = block.extractText()
                    val blockReasoning = block.extractReasoning()
                    if (blockReasoning != null) reasoning = blockReasoning
                }
            }
            "finish", "usage" -> Unit
        }

        items[partialIndex] = TimelineItem.Message(
            value.copy(text = text, reasoning = reasoning, streaming = true),
        )
    }

    private fun ensurePartial(turn: Long, step: Long, event: JsonObject) {
        val key = turnStepKey(turn, step)
        if (partialKey == key) return
        finalizePartial()
        partialKey = key
        partialIndex = items.size
        items += TimelineItem.Message(
            ChatMessage(
                id = "partial-$sessionId-$turn-$step",
                sessionId = sessionId,
                role = MessageRole.ASSISTANT,
                text = "",
                streaming = true,
                createdAtEpochMs = event.eventTime(),
            ),
        )
    }

    private fun finalizePartial() {
        if (partialIndex >= 0 && partialIndex < items.size) {
            val current = items[partialIndex]
            if (current is TimelineItem.Message && current.value.streaming) {
                items[partialIndex] = TimelineItem.Message(
                    current.value.copy(streaming = false),
                )
            }
        }
        clearPartial()
    }

    private fun clearPartial() {
        partialKey = null
        partialIndex = -1
    }

    private fun appendToolCall(event: JsonObject) {
        val data = event.eventData()
        val callId = data.string("callId") ?: "tool:$lastSeq"
        items += TimelineItem.ToolCall(
            id = callId,
            name = data.string("name") ?: "unknown",
            arguments = data.string("arguments"),
            status = ToolRunStatus.RUNNING,
        )
    }

    private fun appendToolResult(event: JsonObject) {
        val data = event.eventData()
        val toolMessage = data["message"]?.jsonObject ?: return
        val resultBlock = toolMessage["content"]?.jsonArray?.firstOrNull()?.jsonObject
        val callId = resultBlock?.string("toolCallId")
            ?: data.string("callId")
            ?: "tool-result:$lastSeq"
        val resultText = toolMessage.extractText()
        // dsh writes tool failures in either the `tool/result` event's
        // optional `error` field or the ToolResultBlock's `isError` flag.
        val isError = toolMessage.boolean("isError") ||
            resultBlock?.boolean("isError") == true ||
            data["error"] != null

        val index = items.indexOfFirst { item ->
            item is TimelineItem.ToolCall && item.id == callId
        }
        val previous = items.getOrNull(index) as? TimelineItem.ToolCall
        val newItem = TimelineItem.ToolCall(
            id = callId,
            name = previous?.name ?: "unknown",
            arguments = previous?.arguments,
            result = resultText,
            isError = isError,
            status = if (isError) ToolRunStatus.FAILED else ToolRunStatus.COMPLETED,
        )
        if (index >= 0) items[index] = newItem else items += newItem
    }

    private fun appendTurnEnd(event: JsonObject) {
        finalizePartial()
        val reason = event.eventData()["reason"]?.jsonObject
        val kind = reason?.string("kind")
        val message = when (kind) {
            "error" -> {
                val failure = reason["error"]?.jsonObject
                "Turn failed: ${failure?.string("message") ?: "unknown model failure"}"
            }
            "aborted" -> "Turn stopped"
            "interrupted" -> "Turn interrupted"
            "max-tokens" -> "Maximum output tokens reached"
            "blocked" -> "Turn blocked"
            else -> null
        }
        if (message != null) {
            items += TimelineItem.Error(
                id = "turn-end:$lastSeq",
                message = message,
                code = kind,
            )
        }
    }

    private fun upsertByKey(key: String, item: TimelineItem) {
        val index = items.indexOfFirst { itemKey(it) == key }
        if (index >= 0) items[index] = item else items += item
    }

    private fun removeByKey(key: String?) {
        if (key == null) return
        items.removeAll { itemKey(it) == key }
    }

    private fun itemKey(item: TimelineItem): String = when (item) {
        is TimelineItem.ApprovalRequest -> "approval:${item.approvalId}"
        is TimelineItem.QuestionRequest -> "question:${item.requestId}"
        is TimelineItem.Queue -> "queue"
        is TimelineItem.Jobs -> "jobs"
        else -> ""
    }

    private fun JsonObject.toQueueItem(): SessionQueueItem? {
        val itemId = string("id") ?: return null
        val message = get("message")?.jsonObject ?: return null
        val placement = when (string("placement")) {
            "steering" -> QueuePlacement.STEERING
            "context" -> QueuePlacement.CONTEXT
            else -> QueuePlacement.QUEUED
        }
        return SessionQueueItem(
            itemId = itemId,
            placement = placement,
            text = message.extractText(),
        )
    }

    private fun JsonObject.toJobView(): JobView? {
        val id = string("id") ?: return null
        return JobView(
            id = id,
            kind = string("kind") ?: "unknown",
            label = string("label") ?: "",
            status = when (string("status")) {
                "stopping" -> JobStatus.STOPPING
                "completed" -> JobStatus.COMPLETED
                "killed" -> JobStatus.KILLED
                "failed" -> JobStatus.FAILED
                else -> JobStatus.RUNNING
            },
            detail = string("detail"),
            startedAt = long("startedAt"),
            finishedAt = get("finishedAt")?.jsonPrimitive?.contentOrNull?.toLongOrNull(),
        )
    }

    private fun JsonObject.toQuestionItem(): QuestionItem? {
        val id = string("id") ?: return null
        val optionArray = get("options")?.jsonArray
        val options = optionArray
            ?.mapNotNull { it.jsonObject.string("label") }
            .orEmpty()
        val optionDescriptions = optionArray
            ?.mapNotNull { option ->
                val obj = option.jsonObject
                obj.string("label")?.let { label ->
                    obj.string("description")?.let { description -> label to description }
                }
            }
            .orEmpty()
            .toMap()
        return QuestionItem(
            id = id,
            question = string("question") ?: "",
            detail = string("detail"),
            options = options,
            multiSelect = boolean("multiSelect"),
            header = string("header"),
            optionDescriptions = optionDescriptions,
        )
    }

    private fun JsonObject.type(): String? =
        get("type")?.jsonPrimitive?.contentOrNull

    private fun JsonObject.string(key: String): String? =
        get(key)?.jsonPrimitive?.contentOrNull

    private fun JsonObject.long(key: String): Long =
        get(key)?.jsonPrimitive?.contentOrNull?.toLongOrNull() ?: 0L

    private fun JsonObject.boolean(key: String): Boolean =
        get(key)?.jsonPrimitive?.contentOrNull?.toBooleanStrictOrNull() ?: false

    private fun JsonObject.eventSeq(): Long = long("seq")

    private fun JsonObject.eventTime(): Long = long("time")

    private fun JsonObject.eventData(): JsonObject =
        get("data")?.jsonObject ?: JsonObject(emptyMap())

    private fun JsonObject.extractText(): String =
        collectText(this)

    private fun collectText(container: JsonObject): String {
        val content = container.get("content")?.jsonArray ?: return ""
        return content.mapNotNull { block ->
            val obj = block.jsonObject
            when (obj.type()) {
                "text" -> obj.string("text")
                "tool-result" -> collectText(obj)
                else -> null
            }
        }.joinToString(separator = "")
    }

    private fun JsonObject.extractReasoning(): String? {
        val content = get("content")?.jsonArray ?: return null
        val value = content.mapNotNull { block ->
            val obj = block.jsonObject
            if (obj.type() == "reasoning") obj.string("text") else null
        }.joinToString(separator = "")
        return value.ifEmpty { null }
    }

    private fun turnStepKey(turn: Long, step: Long): String = "$turn:$step"
}
