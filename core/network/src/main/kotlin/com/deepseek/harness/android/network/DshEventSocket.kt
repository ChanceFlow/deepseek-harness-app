package com.deepseek.harness.android.network

import kotlinx.coroutines.flow.Flow

interface DshEventSocket {
    /**
     * Opens one downlink-only server stream.
     *
     * @param onOpen invoked once the physical transport is ready, before the
     * first frame; connection readiness uses this callback as a strict
     * handshake signal.
     */
    fun connect(
        path: String,
        onOpen: () -> Unit = {},
    ): Flow<ServerRequest>
}
