package com.deepseek.harness.android.network

import java.util.UUID
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import okhttp3.HttpUrl
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody

class OkHttpDshRpcClient(
    private val baseUrl: HttpUrl,
    private val client: OkHttpClient,
    private val json: Json,
) : DshRpcClient {

    private val jsonMediaType = "application/json; charset=utf-8".toMediaType()

    override suspend fun call(
        endpoint: String,
        method: String,
        payload: JsonObject,
    ): RpcResult {
        val rpcId = UUID.randomUUID().toString()
        val request = ClientRequest(
            rpcId = rpcId,
            method = method,
            payload = payload,
        )
        return execute("api/$endpoint", request.jsonText(), rpcId).result
    }

    override suspend fun respond(
        rpcId: String,
        result: RpcResult,
    ) {
        val request = ClientResponse(
            rpcId = rpcId,
            result = result,
        )
        execute("api/respond", request.jsonText(), rpcId)
    }

    private suspend fun execute(
        path: String,
        requestJson: String,
        expectedRpcId: String,
    ): ServerResponse = withContext(Dispatchers.IO) {
        val url = baseUrl.resolve(path)
            ?: throw DshTransportException("cannot resolve $path against $baseUrl")

        val request = Request.Builder()
            .url(url)
            .post(requestJson.toRequestBody(jsonMediaType))
            .build()

        val rawResponse = client.newCall(request).execute()
        rawResponse.use { response ->
            val responseText = response.body?.string().orEmpty()
            if (!response.isSuccessful) {
                throw DshTransportException(
                    "HTTP ${response.code} for $path: ${responseText.take(300)}",
                )
            }

            val decoded = runCatching {
                json.decodeFromString<ServerResponse>(responseText)
            }.getOrElse { error ->
                throw DshTransportException("invalid server-response for $path", error)
            }

            if (decoded.rpcId != expectedRpcId) {
                throw DshTransportException(
                    "rpcId mismatch for $path: expected $expectedRpcId, got ${decoded.rpcId}",
                )
            }
            decoded
        }
    }

    private inline fun <reified T> T.jsonText(): String =
        json.encodeToString(this)
}
