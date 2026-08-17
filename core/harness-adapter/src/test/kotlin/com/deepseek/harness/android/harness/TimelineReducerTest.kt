package com.deepseek.harness.android.harness

import com.deepseek.harness.android.domain.model.MessageRole
import com.deepseek.harness.android.domain.model.TimelineItem
import com.deepseek.harness.android.domain.model.ToolRunStatus
import com.deepseek.harness.android.network.ServerRequest
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class TimelineReducerTest {

    @Test
    fun `history finalizes live assistant text from chunks`() {
        val history = listOf(
            event(
                seq = 1L,
                type = "assistant/chunk",
                data = buildJsonObject {
                    put("turn", 1)
                    put("step", 1)
                    put("chunk", buildJsonObject { put("type", "text-delta"); put("index", 0); put("text", "hello") })
                },
            ),
            event(
                seq = 2L,
                type = "assistant/message",
                data = buildJsonObject {
                    put("turn", 1)
                    put("step", 1)
                    put(
                        "message",
                        buildJsonObject {
                            put("id", "assistant-1")
                            put("role", "assistant")
                            put("content", buildJsonArray { add(textBlock("hello")) })
                        },
                    )
                },
            ),
        )

        val reducer = TimelineReducer("s1")
        reducer.reset(history)

        val snapshot = reducer.snapshot()
        assertEquals(1, snapshot.size)
        val message = snapshot.single() as TimelineItem.Message
        assertEquals("assistant-1", message.value.id)
        assertEquals(MessageRole.ASSISTANT, message.value.role)
        assertEquals("hello", message.value.text)
        assertEquals(false, message.value.streaming)
    }

    @Test
    fun `tool call pairs with result`() {
        val history = listOf(
            event(
                seq = 1L,
                type = "tool/call",
                data = buildJsonObject {
                    put("turn", 1)
                    put("step", 1)
                    put("callId", "call-1")
                    put("name", "bash")
                    put("arguments", "{}")
                },
            ),
            event(
                seq = 2L,
                type = "tool/result",
                data = buildJsonObject {
                    put("turn", 1)
                    put("step", 1)
                    put(
                        "message",
                        buildJsonObject {
                            put(
                                "content",
                                buildJsonArray {
                                    add(
                                        buildJsonObject {
                                            put("type", "tool-result")
                                            put("toolCallId", "call-1")
                                            put(
                                                "content",
                                                buildJsonArray { add(textBlock("ok")) },
                                            )
                                        },
                                    )
                                },
                            )
                        },
                    )
                },
            ),
        )

        val reducer = TimelineReducer("s1")
        reducer.reset(history)

        val tool = reducer.snapshot().single() as TimelineItem.ToolCall
        assertEquals("call-1", tool.id)
        assertEquals("bash", tool.name)
        assertEquals(ToolRunStatus.COMPLETED, tool.status)
        assertEquals("ok", tool.result)
    }

    @Test
    fun `approval frame becomes answerable card and resolved removes it`() {
        val reducer = TimelineReducer("s1")
        val requested = ServerRequest(
            type = "server-request",
            rpcId = "rpc-1",
            method = "approval/requested",
            payload = buildJsonObject {
                put("type", "approval/requested")
                put("sessionId", "s1")
                put("approvalId", "approval-1")
                put("toolName", "bash")
                put("reason", "run command")
            },
        )
        val resolved = ServerRequest(
            type = "server-request",
            rpcId = "rpc-2",
            method = "approval/resolved",
            payload = buildJsonObject {
                put("type", "approval/resolved")
                put("sessionId", "s1")
                put("approvalId", "approval-1")
                put("outcome", "allowed-once")
            },
        )

        reducer.ingestFrame(requested)
        val approval = reducer.snapshot().single() as TimelineItem.ApprovalRequest
        assertEquals("rpc-1", approval.requestId)
        assertEquals("bash", approval.toolName)

        reducer.ingestFrame(resolved)
        assertTrue(reducer.snapshot().isEmpty())
    }

    private fun event(seq: Long, type: String, data: JsonObject): JsonObject =
        buildJsonObject {
            put("type", type)
            put("seq", seq)
            put("time", 1L)
            put("data", data)
        }

    private fun textBlock(text: String): JsonObject =
        buildJsonObject {
            put("type", "text")
            put("text", text)
        }
}
