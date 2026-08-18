package com.deepseek.harness.android.harness

import com.deepseek.harness.android.domain.model.CredentialStatus
import com.deepseek.harness.android.domain.model.GoalRef
import com.deepseek.harness.android.domain.model.MessageRole
import com.deepseek.harness.android.domain.model.PendingImage
import com.deepseek.harness.android.domain.model.PlanState
import com.deepseek.harness.android.domain.model.QuestionAnswer
import com.deepseek.harness.android.domain.model.QueueUpdateKind
import com.deepseek.harness.android.domain.model.QueueUpdateRequest
import com.deepseek.harness.android.domain.model.SendMessageRequest
import com.deepseek.harness.android.domain.model.SettingsApplies
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
import kotlinx.serialization.json.add
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.long
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

    @Test
    fun `settings describe maps namespace wire shape`() = runTest {
        val dispatcher = StandardTestDispatcher(testScheduler)
        val rpc = HarnessFakeRpc()
        val repository = harnessRepository(rpc, ScriptedHarnessSocket(), dispatcher)
        advanceUntilIdle()

        val snapshot = repository.describeSettings()

        assertEquals(true, snapshot.writable)
        assertEquals(false, snapshot.hasDocument)
        val deepseek = snapshot.namespaces.first { it.ns == "llm-deepseek" }
        assertEquals(SettingsApplies.LIVE, deepseek.applies)
        assertEquals(3L, deepseek.revision)
        assertEquals(true, deepseek.hasUserLayer)
        assertEquals(1, deepseek.secretCount)
        val shell = snapshot.namespaces.first { it.ns == "shell" }
        assertEquals(SettingsApplies.RESTART, shell.applies)
        assertEquals(false, shell.hasUserLayer)
        assertEquals(listOf("DEEPSEEK_API_KEY"), snapshot.credentialRefs)
        assertEquals(0, rpc.payloads("settings.describe").single().size)
    }

    @Test
    fun `credentials describe sends refs and maps views`() = runTest {
        val dispatcher = StandardTestDispatcher(testScheduler)
        val rpc = HarnessFakeRpc()
        val repository = harnessRepository(rpc, ScriptedHarnessSocket(), dispatcher)
        advanceUntilIdle()

        val described = repository.describeCredentials(listOf("MINIMAX_CN_API_KEY", "DEEPSEEK_API_KEY"))

        assertEquals(listOf("DEEPSEEK_API_KEY", "MINIMAX_CN_API_KEY"), described.map { it.ref })
        val configured = described.first { it.ref == "DEEPSEEK_API_KEY" }
        assertEquals(true, configured.configured)
        assertEquals("file", configured.source)
        assertEquals(true, configured.writable)
        val missing = described.first { it.ref == "MINIMAX_CN_API_KEY" }
        assertEquals(false, missing.configured)
        assertEquals(null, missing.source)
        assertEquals(false, missing.writable)
        val refs = rpc.payloads("credentials.describe").single()["refs"]?.jsonArray
        assertEquals(
            listOf("MINIMAX_CN_API_KEY", "DEEPSEEK_API_KEY"),
            refs?.map { (it as JsonPrimitive).content },
        )
    }

    @Test
    fun `credentials describe skips the wire for empty refs`() = runTest {
        val dispatcher = StandardTestDispatcher(testScheduler)
        val rpc = HarnessFakeRpc()
        val repository = harnessRepository(rpc, ScriptedHarnessSocket(), dispatcher)
        advanceUntilIdle()

        assertEquals(emptyList<CredentialStatus>(), repository.describeCredentials(emptyList()))
        assertEquals(0, rpc.payloads("credentials.describe").size)
    }

    @Test
    fun `history projections seed plan state`() = runTest {
        val dispatcher = StandardTestDispatcher(testScheduler)
        val rpc = HarnessFakeRpc()
        val repository = harnessRepository(rpc, ScriptedHarnessSocket(), dispatcher)
        advanceUntilIdle()

        repository.openSession("session-1")
        advanceUntilIdle()

        assertEquals(PlanState(active = false, pending = true), repository.observePlan("session-1").first())
    }

    @Test
    fun `plan projection frame updates plan state live`() = runTest {
        val dispatcher = StandardTestDispatcher(testScheduler)
        val rpc = HarnessFakeRpc()
        val socket = ScriptedHarnessSocket(
            muxFrames = listOf(
                ServerRequest(
                    type = "server-request",
                    rpcId = "rpc-plan-1",
                    method = "session/projection",
                    payload = buildJsonObject {
                        put("type", "session/projection")
                        put("sessionId", "session-1")
                        put("key", "plan")
                        put(
                            "value",
                            buildJsonObject {
                                put("active", true)
                                put("pending", false)
                            },
                        )
                    },
                ),
            ),
        )
        val repository = harnessRepository(rpc, socket, dispatcher)
        advanceUntilIdle()

        socket.releaseMuxFrames()
        advanceUntilIdle()

        assertEquals(PlanState(active = true, pending = false), repository.observePlan("session-1").first())
    }

    @Test
    fun `skill list sends session scope and maps catalog`() = runTest {
        val dispatcher = StandardTestDispatcher(testScheduler)
        val rpc = HarnessFakeRpc()
        val repository = harnessRepository(rpc, ScriptedHarnessSocket(), dispatcher)
        advanceUntilIdle()

        val catalog = repository.listSkills("session-1")

        assertEquals("session-1", rpc.payloads("skill.list").single()["sessionId"]?.jsonPrimitive?.content)
        assertEquals(2, catalog.size)
        val first = catalog.first()
        assertEquals("generate-image", first.name)
        assertEquals("Generate images from text", first.description)
        assertEquals("user asks for pictures", first.whenToUse)
        assertEquals(true, first.modelInvocable)
        assertEquals(null, catalog[1].whenToUse)
    }

    @Test
    fun `move workspace sends anchor and applies response order`() = runTest {
        val dispatcher = StandardTestDispatcher(testScheduler)
        val rpc = HarnessFakeRpc(
            initialWorkspaces = buildJsonArray {
                add(workspaceJson("ws-a", "/a", "A"))
                add(workspaceJson("ws-b", "/b", "B"))
                add(workspaceJson("ws-c", "/c", "C"))
            },
        )
        val repository = harnessRepository(rpc, ScriptedHarnessSocket(), dispatcher)
        advanceUntilIdle()
        repository.refreshWorkspaces()

        val orderedIds = repository.moveWorkspace("ws-a", beforeWorkspaceId = "ws-c")

        assertEquals(listOf("ws-b", "ws-a", "ws-c"), orderedIds)
        val payload = rpc.payloads("workspace.insertBefore").single()
        assertEquals("ws-a", payload["workspaceId"]?.jsonPrimitive?.content)
        assertEquals("ws-c", payload["beforeWorkspaceId"]?.jsonPrimitive?.content)
        assertEquals(
            listOf("ws-b", "ws-a", "ws-c"),
            repository.observeWorkspaces().first().map { it.workspaceId },
        )
    }

    @Test
    fun `move workspace without anchor omits the field`() = runTest {
        val dispatcher = StandardTestDispatcher(testScheduler)
        val rpc = HarnessFakeRpc()
        val repository = harnessRepository(rpc, ScriptedHarnessSocket(), dispatcher)
        advanceUntilIdle()

        repository.moveWorkspace("ws-a", beforeWorkspaceId = null)

        val payload = rpc.payloads("workspace.insertBefore").single()
        assertEquals("ws-a", payload["workspaceId"]?.jsonPrimitive?.content)
        assertEquals(null, payload["beforeWorkspaceId"])
    }

    @Test
    fun `credential set sends ref and value`() = runTest {
        val dispatcher = StandardTestDispatcher(testScheduler)
        val rpc = HarnessFakeRpc()
        val repository = harnessRepository(rpc, ScriptedHarnessSocket(), dispatcher)
        advanceUntilIdle()

        repository.setCredential("DEEPSEEK_API_KEY", "sk-typed")

        val payload = rpc.payloads("credentials.set").single()
        assertEquals("DEEPSEEK_API_KEY", payload["ref"]?.jsonPrimitive?.content)
        assertEquals("sk-typed", payload["value"]?.jsonPrimitive?.content)
    }

    @Test
    fun `credential unset sends ref only`() = runTest {
        val dispatcher = StandardTestDispatcher(testScheduler)
        val rpc = HarnessFakeRpc()
        val repository = harnessRepository(rpc, ScriptedHarnessSocket(), dispatcher)
        advanceUntilIdle()

        repository.unsetCredential("DEEPSEEK_API_KEY")

        val payload = rpc.payloads("credentials.unset").single()
        assertEquals("DEEPSEEK_API_KEY", payload["ref"]?.jsonPrimitive?.content)
        assertEquals(1, payload.size)
    }

    @Test
    fun `setting update sends patch with cas revision and maps view`() = runTest {
        val dispatcher = StandardTestDispatcher(testScheduler)
        val rpc = HarnessFakeRpc()
        val repository = harnessRepository(rpc, ScriptedHarnessSocket(), dispatcher)
        advanceUntilIdle()

        val updated = repository.updateSetting(
            ns = "llm-deepseek",
            key = "retry",
            jsonValue = """{"attempts": 5}""",
            expectedRevision = 3L,
        )

        val payload = rpc.payloads("settings.update").single()
        assertEquals("llm-deepseek", payload["ns"]?.jsonPrimitive?.content)
        assertEquals(3L, payload["expectedRevision"]?.jsonPrimitive?.long)
        val patch = payload["patch"]?.jsonObject ?: error("missing patch")
        assertEquals(5L, patch["retry"]?.jsonObject?.get("attempts")?.jsonPrimitive?.long)
        // The response arm reuses the settings.describe namespace fixture.
        assertEquals("llm-deepseek", updated.ns)
        assertEquals(3L, updated.revision)
        assertEquals(true, updated.hasUserLayer)
    }

    @Test
    fun `prompt with images appends image content parts`() = runTest {
        val dispatcher = StandardTestDispatcher(testScheduler)
        val rpc = HarnessFakeRpc()
        val repository = harnessRepository(rpc, ScriptedHarnessSocket(), dispatcher)
        advanceUntilIdle()

        repository.sendMessage(
            SendMessageRequest(
                sessionId = "session-1",
                text = "see this",
                images = listOf(
                    PendingImage(
                        id = "u1",
                        mediaType = "image/png",
                        base64Data = "aGk=",
                        name = "shot.png",
                    ),
                ),
            ),
        )

        val payload = rpc.payloads("session.prompt").single()
        val content = payload["content"]?.jsonArray.orEmpty()
        assertEquals(2, content.size)
        assertEquals("text", content[0].jsonObject["type"]?.jsonPrimitive?.content)
        assertEquals("see this", content[0].jsonObject["text"]?.jsonPrimitive?.content)
        val image = content[1].jsonObject
        assertEquals("image", image["type"]?.jsonPrimitive?.content)
        assertEquals("image/png", image["mediaType"]?.jsonPrimitive?.content)
        assertEquals("aGk=", image["data"]?.jsonPrimitive?.content)
        assertEquals("shot.png", image["name"]?.jsonPrimitive?.content)
    }

    @Test
    fun `read attachment sends ids and decodes base64 payload`() = runTest {
        val dispatcher = StandardTestDispatcher(testScheduler)
        val rpc = HarnessFakeRpc()
        val repository = harnessRepository(rpc, ScriptedHarnessSocket(), dispatcher)
        advanceUntilIdle()

        val downloaded = repository.readAttachment("session-1", "sha256:abc")

        val payload = rpc.payloads("session.attachment").single()
        assertEquals("session-1", payload["sessionId"]?.jsonPrimitive?.content)
        assertEquals("sha256:abc", payload["attachmentId"]?.jsonPrimitive?.content)
        assertEquals("sha256:abc", downloaded.ref.attachmentId)
        assertEquals("image/png", downloaded.ref.mediaType)
        assertEquals(2, downloaded.ref.bytes)
        assertTrue(downloaded.data.contentEquals(byteArrayOf(0x68, 0x69)))
    }

    @Test
    fun `image limits projection flows from session list`() = runTest {
        val dispatcher = StandardTestDispatcher(testScheduler)
        val session = buildJsonObject {
            put("sessionId", "session-1")
            put(
                "projections",
                buildJsonObject {
                    put(
                        "values",
                        buildJsonObject {
                            put("title", "titled")
                            put(
                                "imageLimits",
                                buildJsonObject {
                                    put("maxImageBytes", 1_048_576)
                                    put("maxImagesPerMessage", 4)
                                    put("maxMessageImageBytes", 2_097_152)
                                    put("maxImagePixels", 1_000_000)
                                    put(
                                        "mediaTypes",
                                        buildJsonArray {
                                            add("image/png")
                                            add("image/jpeg")
                                        },
                                    )
                                },
                            )
                        },
                    )
                },
            )
        }
        val rpc = HarnessFakeRpc(initialSessions = buildJsonArray { add(session) })
        val repository = harnessRepository(rpc, ScriptedHarnessSocket(), dispatcher)
        advanceUntilIdle()

        repository.refreshSessions()

        val limits = repository.observeImageLimits().first()
        assertEquals(1_048_576L, limits?.maxImageBytes)
        assertEquals(4, limits?.maxImagesPerMessage)
        assertEquals(2_097_152L, limits?.maxMessageImageBytes)
        assertEquals(1_000_000L, limits?.maxImagePixels)
        assertEquals(listOf("image/png", "image/jpeg"), limits?.mediaTypes)
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
            "workspace.insertBefore" -> buildJsonObject {
                put(
                    "workspaceIds",
                    buildJsonArray {
                        add(JsonPrimitive("ws-b"))
                        add(JsonPrimitive("ws-a"))
                        add(JsonPrimitive("ws-c"))
                    },
                )
            }
            "session.history" -> buildJsonObject {
                put("events", buildJsonArray {})
                put("hasMore", false)
                put(
                    "projections",
                    buildJsonObject {
                        put(
                            "values",
                            buildJsonObject {
                                put(
                                    "plan",
                                    buildJsonObject {
                                        put("active", false)
                                        put("pending", true)
                                    },
                                )
                            },
                        )
                    },
                )
            }
            "session.attachment" -> buildJsonObject {
                put(
                    "attachment",
                    buildJsonObject {
                        put("attachmentId", "sha256:abc")
                        put("mediaType", "image/png")
                        put("bytes", 2)
                        put("width", 1)
                        put("height", 1)
                        put("name", "shot.png")
                    },
                )
                put("data", "aGk=")
            }
            "skill.list" -> buildJsonObject {
                put(
                    "skills",
                    buildJsonArray {
                        add(
                            buildJsonObject {
                                put("name", "generate-image")
                                put("description", "Generate images from text")
                                put("whenToUse", "user asks for pictures")
                                put("modelInvocable", true)
                            },
                        )
                        add(
                            buildJsonObject {
                                put("name", "firefly3-manager")
                                put("description", "Manage Firefly III ledgers")
                                put("modelInvocable", false)
                            },
                        )
                    },
                )
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
            "settings.describe" -> buildJsonObject {
                put("writable", true)
                put("hasDocument", false)
                put(
                    "namespaces",
                    buildJsonArray {
                        add(
                            buildJsonObject {
                                put("ns", "llm-deepseek")
                                put(
                                    "schema",
                                    buildJsonObject { put("type", "object") },
                                )
                                put(
                                    "value",
                                    buildJsonObject {
                                        put(
                                            "providers",
                                            buildJsonObject {
                                                put(
                                                    "deepseek-official",
                                                    buildJsonObject { put("apiKeyEnv", "DEEPSEEK_API_KEY") },
                                                )
                                            },
                                        )
                                    },
                                )
                                put("base", buildJsonObject { })
                                put("user", buildJsonObject { put("touched", true) })
                                put("applies", "live")
                                put(
                                    "secrets",
                                    buildJsonArray {
                                        add(
                                            buildJsonObject {
                                                put("path", buildJsonArray { add("providers") })
                                                put("set", true)
                                            },
                                        )
                                    },
                                )
                                put("revision", 3)
                            },
                        )
                        add(
                            buildJsonObject {
                                put("ns", "shell")
                                put("value", buildJsonObject { })
                                put("applies", "restart")
                                put("secrets", buildJsonArray { })
                                put("revision", 0)
                            },
                        )
                    },
                )
            }
            "credentials.describe" -> buildJsonObject {
                put(
                    "credentials",
                    buildJsonObject {
                        put(
                            "DEEPSEEK_API_KEY",
                            buildJsonObject {
                                put("configured", true)
                                put("source", "file")
                                put("writable", true)
                            },
                        )
                        put(
                            "MINIMAX_CN_API_KEY",
                            buildJsonObject {
                                put("configured", false)
                                put("writable", false)
                            },
                        )
                    },
                )
            }
            "settings.update" -> buildJsonObject {
                put("ns", "llm-deepseek")
                put("value", buildJsonObject { })
                put("user", buildJsonObject { put("touched", true) })
                put("applies", "live")
                put("secrets", buildJsonArray { })
                put("revision", 3)
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
