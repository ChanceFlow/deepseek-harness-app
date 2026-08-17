package com.deepseek.harness.android.network

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonObject

@Serializable
data class ClientRequest(
    val type: String = "client-request",
    val rpcId: String,
    val method: String,
    val payload: JsonObject,
)

@Serializable
data class ClientResponse(
    val type: String = "client-response",
    val rpcId: String,
    val result: RpcResult,
)

@Serializable
data class ServerResponse(
    val type: String = "server-response",
    val rpcId: String,
    val result: RpcResult,
)

@Serializable
data class ServerRequest(
    val type: String = "server-request",
    val rpcId: String,
    val method: String,
    val payload: JsonObject,
)

@Serializable
data class RpcResult(
    val ok: Boolean,
    val value: JsonObject? = null,
    val error: RpcError? = null,
)

@Serializable
data class RpcError(
    val code: String,
    val message: String,
    val details: JsonObject? = null,
)

@Serializable
data class RpcReceipt(
    val accepted: Boolean,
    val reason: String? = null,
)
