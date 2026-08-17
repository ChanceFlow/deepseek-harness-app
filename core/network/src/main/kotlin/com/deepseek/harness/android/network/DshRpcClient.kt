package com.deepseek.harness.android.network

import kotlinx.serialization.json.JsonObject

interface DshRpcClient {
    suspend fun call(
        endpoint: String,
        method: String,
        payload: JsonObject,
    ): RpcResult

    suspend fun respond(
        rpcId: String,
        result: RpcResult,
    )
}
