package com.deepseek.harness.android.harness

import com.deepseek.harness.android.domain.model.JobStatus
import com.deepseek.harness.android.domain.model.MessageRole
import com.deepseek.harness.android.domain.model.QuestionIntent
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
    fun `tool result block isError marks the paired call failed`() {
        val history = listOf(
            event(
                seq = 1L,
                type = "tool/call",
                data = buildJsonObject {
                    put("turn", 1)
                    put("step", 1)
                    put("callId", "call-failed")
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
                                            put("toolCallId", "call-failed")
                                            put(
                                                "content",
                                                buildJsonArray { add(textBlock("boom")) },
                                            )
                                            put("isError", true)
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
        assertEquals(ToolRunStatus.FAILED, tool.status)
        assertEquals(true, tool.isError)
        assertEquals("boom", tool.result)
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

    @Test
    fun `question intent parses for plan review presentation`() {
        val reducer = TimelineReducer("s1")
        reducer.ingestFrame(
            ServerRequest(
                type = "server-request",
                rpcId = "rpc-plan",
                method = "question/requested",
                payload = buildJsonObject {
                    put("type", "question/requested")
                    put("sessionId", "s1")
                    put(
                        "questions",
                        buildJsonArray {
                            add(
                                buildJsonObject {
                                    put("id", "plan-review")
                                    put("header", "Plan review")
                                    put("question", "Approve this plan and leave plan mode?")
                                    put("detail", "# The plan")
                                    put(
                                        "options",
                                        buildJsonArray {
                                            add(buildJsonObject { put("label", "Approve plan") })
                                            add(buildJsonObject { put("label", "Keep planning") })
                                        },
                                    )
                                    put(
                                        "intent",
                                        buildJsonObject {
                                            put("kind", "plan-review")
                                            put("approve", "Approve plan")
                                        },
                                    )
                                },
                            )
                        },
                    )
                },
            ),
        )

        val question = (reducer.snapshot().single() as TimelineItem.QuestionRequest).questions.single()
        assertEquals(QuestionIntent(kind = "plan-review", approve = "Approve plan"), question.intent)
        assertEquals("# The plan", question.detail)
    }

    @Test
    fun `question frame keeps header and option descriptions and resolution removes it`() {
        val reducer = TimelineReducer("s1")
        val requested = ServerRequest(
            type = "server-request",
            rpcId = "rpc-question",
            method = "question/requested",
            payload = buildJsonObject {
                put("type", "question/requested")
                put("sessionId", "s1")
                put(
                    "questions",
                    buildJsonArray {
                        add(
                            buildJsonObject {
                                put("id", "q1")
                                put("header", "Before continuing")
                                put("question", "Proceed?")
                                put("detail", "This command writes files")
                                put("multiSelect", true)
                                put(
                                    "options",
                                    buildJsonArray {
                                        add(
                                            buildJsonObject {
                                                put("label", "yes")
                                                put("description", "Continue now")
                                            },
                                        )
                                        add(buildJsonObject { put("label", "no") })
                                    },
                                )
                            },
                        )
                    },
                )
            },
        )

        reducer.ingestFrame(requested)

        val question = reducer.snapshot().single() as TimelineItem.QuestionRequest
        val item = question.questions.single()
        assertEquals("q1", item.id)
        assertEquals("Before continuing", item.header)
        assertTrue(item.multiSelect)
        assertEquals("Continue now", item.optionDescriptions["yes"])
        assertEquals(listOf("yes", "no"), item.options)

        reducer.ingestFrame(
            ServerRequest(
                type = "server-request",
                rpcId = "rpc-resolved",
                method = "question/resolved",
                payload = buildJsonObject {
                    put("type", "question/resolved")
                    put("sessionId", "s1")
                    put("questionRpcId", "rpc-question")
                    put("outcome", "answered")
                },
            ),
        )
        assertTrue(reducer.snapshot().isEmpty())
    }

    @Test
    fun `session jobs frame becomes job snapshot`() {
        val reducer = TimelineReducer("s1")
        val frame = ServerRequest(
            type = "server-request",
            rpcId = "rpc-jobs",
            method = "session/jobs",
            payload = buildJsonObject {
                put("type", "session/jobs")
                put("sessionId", "s1")
                put(
                    "jobs",
                    buildJsonArray {
                        add(
                            buildJsonObject {
                                put("id", "bash-1")
                                put("kind", "bash")
                                put("label", "sleep 10")
                                put("status", "running")
                                put("startedAt", 10L)
                            },
                        )
                    },
                )
            },
        )

        reducer.ingestFrame(frame)

        val jobs = reducer.snapshot().single() as TimelineItem.Jobs
        assertEquals(1, jobs.jobs.size)
        assertEquals("bash-1", jobs.jobs.single().id)
        assertEquals(JobStatus.RUNNING, jobs.jobs.single().status)
    }

    @Test
    fun `user message image blocks fold into attachment refs`() {
        val history = listOf(
            event(
                seq = 1L,
                type = "user/message",
                data = buildJsonObject {
                    put("id", "user-1")
                    put(
                        "content",
                        buildJsonArray {
                            add(textBlock("look at this"))
                            add(
                                buildJsonObject {
                                    put("type", "image")
                                    put(
                                        "attachment",
                                        buildJsonObject {
                                            put("attachmentId", "sha256:abc")
                                            put("mediaType", "image/png")
                                            put("bytes", 2048)
                                            put("width", 640)
                                            put("height", 480)
                                            put("name", "shot.png")
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

        val message = (reducer.snapshot().single() as TimelineItem.Message).value
        assertEquals("look at this", message.text)
        val image = message.images.single()
        assertEquals("sha256:abc", image.attachmentId)
        assertEquals("image/png", image.mediaType)
        assertEquals(2048L, image.bytes)
        assertEquals(640, image.width)
        assertEquals(480, image.height)
        assertEquals("shot.png", image.name)
    }

    @Test
    fun `turn start events become boundaries and dedupe per turn`() {
        val history = listOf(
            event(
                seq = 1L,
                type = "turn/start",
                data = buildJsonObject { put("turn", 1) },
            ),
            event(
                seq = 2L,
                type = "user/message",
                data = buildJsonObject { put("id", "user-1"); put("content", buildJsonArray { add(textBlock("hi")) }) },
            ),
            event(
                seq = 3L,
                type = "turn/start",
                data = buildJsonObject { put("turn", 1) },
            ),
            event(
                seq = 4L,
                type = "turn/start",
                data = buildJsonObject { put("turn", 2) },
            ),
            event(
                seq = 5L,
                type = "user/message",
                data = buildJsonObject { put("id", "user-2"); put("content", buildJsonArray { add(textBlock("again")) }) },
            ),
        )

        val reducer = TimelineReducer("s1")
        reducer.reset(history)

        val snapshot = reducer.snapshot()
        val turns = snapshot.filterIsInstance<TimelineItem.TurnBoundary>()
        assertEquals(listOf(1L, 2L), turns.map { it.turn })
        assertEquals(0, snapshot.indexOfFirst { it is TimelineItem.TurnBoundary && it.turn == 1L })
        assertEquals(2, snapshot.indexOfFirst { it is TimelineItem.TurnBoundary && it.turn == 2L })
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
