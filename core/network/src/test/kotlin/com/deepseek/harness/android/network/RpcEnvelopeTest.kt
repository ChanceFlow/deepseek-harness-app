package com.deepseek.harness.android.network

import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import org.junit.Assert.assertEquals
import org.junit.Test

class RpcEnvelopeTest {

    private val json = Json { ignoreUnknownKeys = true }

    @Test
    fun `client request keeps rpc identity`() {
        val request = ClientRequest(
            rpcId = "rpc-1",
            method = "session.prompt",
            payload = buildJsonObject { put("sessionId", "s1") },
        )

        val wire = json.encodeToString(request)
        val decoded = json.decodeFromString<ClientRequest>(wire)

        assertEquals(request.rpcId, decoded.rpcId)
        assertEquals(request.method, decoded.method)
    }
}
