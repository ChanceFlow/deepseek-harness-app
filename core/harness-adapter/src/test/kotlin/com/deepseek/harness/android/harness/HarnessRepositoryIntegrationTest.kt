package com.deepseek.harness.android.harness

import com.deepseek.harness.android.domain.model.GoalRef
import com.deepseek.harness.android.domain.model.MessageRole
import com.deepseek.harness.android.domain.model.QuestionAnswer
import com.deepseek.harness.android.domain.model.QueueUpdateKind
import com.deepseek.harness.android.domain.model.QueueUpdateRequest
import com.deepseek.harness.android.domain.model.TimelineItem
import com.deepseek.harness.android.domain.repository.QuestionEvidence
import com.deepseek.harness.android.network.DshEventSocket
import com.deepseek.harness.android.network.DshRpcClient
import com.deepseek.harness.android.network.RpcResult
import com.deepseek.harness.android.network.ServerRequest
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class HarnessRepositoryIntegrationTest {

    @Test
    fun `host workspace frames fold locally without extra workspace list calls`() = runTest {
        val dispatcher = StandardTestDispatcher(testScheduler)
        val rpc = HarnessFakeRpc(
            initialWorkspaces = buildJsonArray {
                add(workspaceJson("ws-a", "/a", "A"))
                add(workspaceJson("ws-b", "/b", "B"))
            },
        )
        val socket = ScriptedHarnessSocket(
            hostFrames = listOf(
                hostFrame(
                    type = "host/workspace-changed",
                    payload = buildJsonObject {
                        put("type", "host/workspace-changed")
                        put(
                            "workspace",
                            workspaceJson("ws-a", "/a", "A renamed", listOf("s1")),
                        )
                    },
                ),
                hostFrame(
                    type = "host/workspace-order-changed",
                    payload = buildJsonObject {
                        put("type", "host/workspace-order-changed")
                        put("workspaceIds", buildJsonArray { add(JsonPrimitive("ws-b")); add(JsonPrimitive("ws-a")) })
                    },
                ),
                hostFrame(
                    type = "host/workspace-removed",
                    payload = buildJsonObject {
                        put("type", "host/workspace-removed")
                        put("workspaceId", "ws-b")
                    },
                ),
            ),
        )
        val repository = harnessRepository(rpc, socket, dispatcher)
        advanceUntilIdle()

        socket.releaseHostFrames()
        advanceUntilIdle()

        val workspaces = repository.observeWorkspaces().first()
        assertEquals(listOf("A renamed"), workspaces.map { it.title })
        assertEquals(listOf("ws-a"), workspaces.map { it.workspaceId })
        assertEquals(1, rpc.callCountFor("workspace.list"))
    }

    @Test
    fun `mux session event reaches an opened session timeline`() = runTest {
        val dispatcher = StandardTestDispatcher(testScheduler)
        val rpc = HarnessFakeRpc(
            initialSessions = buildJsonArray {
                add(
                    buildJsonObject {
                        put("sessionId", "session-1")
                        put("updatedAt", 3L)
                        put("running", false)
                        put("blank", false)
                    },
                )
            },
        )
        val socket = ScriptedHarnessSocket(
            muxFrames = listOf(
                muxFrame(
                    type = "session/event",
                    sessionId = "session-1",
                    event = assistantMessageEvent(),
                ),
            ),
        )
        val repository = harnessRepository(rpc, socket, dispatcher)
        advanceUntilIdle()

        repository.openSession("session-1")
        advanceUntilIdle()

        socket.releaseMuxFrames()
        advanceUntilIdle()

        val timeline = repository.observeTimeline("session-1").first()
        assertEquals(1, timeline.size)
        val message = timeline.single() as TimelineItem.Message
        assertEquals(MessageRole.ASSISTANT, message.value.role)
        assertEquals("hello from fake host", message.value.text)
        assertTrue(message.value.streaming.not())
    }

    @Test
    fun `queue edit serializes text content block`() = runTest {
        val dispatcher = StandardTestDispatcher(testScheduler)
        val rpc = HarnessFakeRpc()
        val repository = harnessRepository(rpc, ScriptedHarnessSocket(), dispatcher)
        advanceUntilIdle()

        repository.updateQueue(
            QueueUpdateRequest(
                sessionId = "session-1",
                itemId = "queued-1",
                kind = QueueUpdateKind.EDIT,
                text = "revised prompt",
            ),
        )

        val payload = rpc.payloads("session.updateQueue").single()
        val action = payload["action"]?.jsonObject ?: error("missing action")
        val content = action["content"]?.jsonArray?.single()?.jsonObject
            ?: error("missing content block")
        assertEquals("edit", action["kind"]?.toString()?.trim('"'))
        assertEquals("text", content["type"]?.toString()?.trim('"'))
        assertEquals("revised prompt", content["text"]?.toString()?.trim('"'))
    }

    @Test
    fun `skipped question response uses empty selected array`() = runTest {
        val dispatcher = StandardTestDispatcher(testScheduler)
        val rpc = HarnessFakeRpc()
        val repository = harnessRepository(rpc, ScriptedHarnessSocket(), dispatcher)
        advanceUntilIdle()

        repository.answerQuestions(
            requestId = "rpc-question",
            evidence = QuestionEvidence(
                sessionId = "session-1",
                answers = listOf(
                    QuestionAnswer(
                        questionId = "question-1",
                        selectedOptions = emptyList(),
                    ),
                ),
            ),
        )

        val received = rpc.receivedResponses().single()
        assertEquals("rpc-question", received.first)
        val value = received.second.value ?: error("missing responded value")
        val answer = value["answer"]?.jsonObject ?: error("missing answer")
        val firstAnswer = answer["answers"]?.jsonArray
            ?.single()
            ?.jsonObject
            ?: error("missing question answer")
        assertEquals("question-1", firstAnswer["id"]?.toString()?.trim('"'))
        assertEquals(0, firstAnswer["selected"]?.jsonArray?.size)
    }

    @Test
    fun `goal edit sends objective with cas ref`() = runTest {
        val dispatcher = StandardTestDispatcher(testScheduler)
        val rpc = HarnessFakeRpc()
        val repository = harnessRepository(rpc, ScriptedHarnessSocket(), dispatcher)
        advanceUntilIdle()

        val edited = repository.editGoal(
            sessionId = "session-1",
            ref = GoalRef(id = "goal-1", revision = 1),
            objective = "ship it v2",
        )

        assertEquals("goal-1", edited.id)
        assertEquals(2L, edited.revision)
        val payload = rpc.payloads("goal.edit").single()
        assertEquals("session-1", payload["sessionId"]?.toString()?.trim('"'))
        assertEquals("ship it v2", payload["objective"]?.toString()?.trim('"'))
        val ref = payload["ref"]?.jsonObject ?: error("missing goal ref")
        assertEquals("goal-1", ref["id"]?.toString()?.trim('"'))
        assertEquals(1L, ref["revision"]?.toString()?.toLong())
    }

    @Test
    fun `directory listing maps host wire shape`() = runTest {
        val dispatcher = StandardTestDispatcher(testScheduler)
        val rpc = HarnessFakeRpc()
        val repository = harnessRepository(rpc, ScriptedHarnessSocket(), dispatcher)
        advanceUntilIdle()

        val listing = repository.listDirectory("/tmp/chosen")

        assertEquals("/tmp/chosen", listing.path)
        assertEquals("/home/user", listing.home)
        assertEquals("src", listing.entries.single().name)
        assertEquals(false, listing.entries.single().hidden)
        assertEquals("/tmp/chosen", rpc.payloads("host.listDirectory").single()["path"]?.toString()?.trim('"'))
    }

    @Test
    fun `directory creation sends host payload`() = runTest {
        val dispatcher = StandardTestDispatcher(testScheduler)
        val rpc = HarnessFakeRpc()
        val repository = harnessRepository(rpc, ScriptedHarnessSocket(), dispatcher)
        advanceUntilIdle()

        val created = repository.createDirectory("/tmp/chosen", "new-folder")

        assertEquals("/tmp/chosen/new-folder", created)
        val payload = rpc.payloads("host.createDirectory").single()
        assertEquals("/tmp/chosen", payload["path"]?.toString()?.trim('"'))
        assertEquals("new-folder", payload["name"]?.toString()?.trim('"'))
    }
}
private fun harnessRepository(
    rpc: DshRpcClient,
    socket: DshEventSocket,
    dispatcher: kotlinx.coroutines.CoroutineDispatcher,
): HarnessRepositoryImpl {
    val json = Json {
        ignoreUnknownKeys = true
        coerceInputValues = true
    }
    val manager = DshConnectionManager(
        rpcClient = rpc,
        eventSocket = socket,
        json = json,
        ioDispatcher = dispatcher,
        backoffDelay = DshBackoffDelay { 10_000L },
    )
    return HarnessRepositoryImpl(
        rpcClient = rpc,
        connectionManager = manager,
        json = json,
        ioDispatcher = dispatcher,
    )
}

private class HarnessFakeRpc(
    private val initialSessions: JsonArray = buildJsonArray {},
    private val initialWorkspaces: JsonArray = buildJsonArray {},
) : DshRpcClient {
    private val calls = mutableMapOf<String, Int>()
    private val payloadsByEndpoint = mutableMapOf<String, MutableList<JsonObject>>()
    private val receivedResponses = mutableListOf<Pair<String, RpcResult>>()

    fun callCountFor(endpoint: String): Int = calls[endpoint] ?: 0

    fun payloads(endpoint: String): List<JsonObject> =
        payloadsByEndpoint[endpoint].orEmpty().toList()

    fun receivedResponses(): List<Pair<String, RpcResult>> = receivedResponses.toList()

    override suspend fun call(
        endpoint: String,
        method: String,
        payload: JsonObject,
    ): RpcResult {
        calls[endpoint] = callCountFor(endpoint) + 1
        payloadsByEndpoint.getOrPut(endpoint) { mutableListOf() }.add(payload)
        val value = when (endpoint) {
            "host.describe" -> buildJsonObject {
                put("version", "fake-host")
                put("cwd", "/tmp/fake-host")
                put("attachedSessions", 0)
            }
            "session.list" -> buildJsonObject {
                put("items", initialSessions)
            }
            "workspace.list" -> buildJsonObject {
                put("items", initialWorkspaces)
                put("archivedSessionIds", buildJsonArray {})
            }
            "session.history" -> buildJsonObject {
                put("events", buildJsonArray {})
                put("hasMore", false)
            }
            "host.listDirectory" -> buildJsonObject {
                put("path", "/tmp/chosen")
                put("home", "/home/user")
                put(
                    "crumbs",
                    buildJsonArray { add(directoryEntryJson("chosen", "/tmp/chosen", false)) },
                )
                put(
                    "entries",
                    buildJsonArray { add(directoryEntryJson("src", "/tmp/chosen/src", false)) },
                )
                put("truncated", false)
            }
            "host.createDirectory" -> buildJsonObject {
                put("path", "/tmp/chosen/new-folder")
            }
            "goal.edit" -> buildJsonObject {
                put(
                    "ref",
                    buildJsonObject {
                        put("id", "goal-1")
                        put("revision", 2)
                    },
                )
            }
            else -> buildJsonObject {}
        }
        return RpcResult(ok = true, value = value)
    }

    override suspend fun respond(
        rpcId: String,
        result: RpcResult,
    ) {
        receivedResponses += rpcId to result
    }
}

private class ScriptedHarnessSocket(
    private val muxFrames: List<ServerRequest> = emptyList(),
    private val hostFrames: List<ServerRequest> = emptyList(),
) : DshEventSocket {
    private val muxRelease = CompletableDeferred<Unit>()
    private val hostRelease = CompletableDeferred<Unit>()
    private val paths = mutableListOf<String>()

    val connectedPaths: List<String> get() = synchronized(this) { paths.toList() }

    fun releaseMuxFrames() {
        muxRelease.complete(Unit)
    }

    fun releaseHostFrames() {
        hostRelease.complete(Unit)
    }

    override fun connect(
        path: String,
        onOpen: () -> Unit,
    ): Flow<ServerRequest> = flow {
        synchronized(this) { paths += path }
        onOpen()
        if (path.endsWith("events.host")) {
            hostRelease.await()
            hostFrames.forEach { emit(it) }
        } else {
            muxRelease.await()
            muxFrames.forEach { emit(it) }
        }
        awaitCancellation()
    }
}
private fun directoryEntryJson(
    name: String,
    path: String,
    hidden: Boolean,
): JsonObject = buildJsonObject {
    put("name", name)
    put("path", path)
    put("hidden", hidden)
}

private fun workspaceJson(
    id: String,
    path: String,
    title: String,
    sessionIds: List<String> = emptyList(),
): JsonObject = buildJsonObject {
    put("workspaceId", id)
    put("path", path)
    put("title", title)
    put("sessionIds", buildJsonArray { sessionIds.forEach { add(JsonPrimitive(it)) } })
    put("createdAt", "2026-01-01T00:00:00Z")
    put("updatedAt", "2026-01-01T00:00:00Z")
}

private fun hostFrame(
    type: String,
    payload: JsonObject,
): ServerRequest = ServerRequest(
    type = "server-request",
    rpcId = "rpc-$type",
    method = type,
    payload = payload,
)

private fun muxFrame(
    type: String,
    sessionId: String,
    event: JsonObject,
): ServerRequest = ServerRequest(
    type = "server-request",
    rpcId = "rpc-$type-$sessionId",
    method = type,
    payload = buildJsonObject {
        put("type", type)
        put("sessionId", sessionId)
        put("event", event)
    },
)

private fun assistantMessageEvent(): JsonObject = buildJsonObject {
    put("type", "assistant/message")
    put("seq", 7L)
    put("time", 7L)
    put(
        "data",
        buildJsonObject {
            put("turn", 1)
            put("step", 1)
            put(
                "message",
                buildJsonObject {
                    put("id", "assistant-1")
                    put("role", "assistant")
                    put(
                        "content",
                        buildJsonArray {
                            add(
                                buildJsonObject {
                                    put("type", "text")
                                    put("text", "hello from fake host")
                                },
                            )
                        },
                    )
                },
            )
        },
    )
}
