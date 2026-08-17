package com.deepseek.harness.android.network

import kotlinx.coroutines.flow.Flow

interface DshEventSocket {
    fun connect(path: String): Flow<ServerRequest>

    suspend fun respond(rpcId: String, result: RpcResult)
}
