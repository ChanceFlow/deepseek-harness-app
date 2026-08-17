package com.deepseek.harness.android.network

import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.serialization.json.Json
import okhttp3.HttpUrl
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener

@OptIn(ExperimentalCoroutinesApi::class)
class OkHttpDshEventSocket(
    private val baseUrl: HttpUrl,
    private val client: OkHttpClient,
    private val json: Json,
) : DshEventSocket {

    override fun connect(path: String): Flow<ServerRequest> = callbackFlow {
        val httpUrl = baseUrl.resolve(path)
            ?: throw DshTransportException("cannot resolve $path against $baseUrl")
        val webSocketUrl = httpUrl.newBuilder()
            .scheme(if (httpUrl.scheme == "https") "wss" else "ws")
            .build()

        val listener = object : WebSocketListener() {
            override fun onMessage(webSocket: WebSocket, text: String) {
                runCatching {
                    json.decodeFromString<ServerRequest>(text)
                }.onSuccess { envelope ->
                    trySend(envelope)
                }.onFailure { error ->
                    close(DshTransportException("invalid server-request on $path", error))
                }
            }

            override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                close()
            }

            override fun onFailure(webSocket: WebSocket, throwable: Throwable, response: Response?) {
                close(DshTransportException("event stream $path failed", throwable))
            }
        }

        val webSocket = client.newWebSocket(
            Request.Builder().url(webSocketUrl).build(),
            listener,
        )

        awaitClose {
            webSocket.close(1000, null)
        }
    }
}
