package com.deepseek.harness.android.harness

import com.deepseek.harness.android.domain.model.ConnectionPhase
import com.deepseek.harness.android.network.DshEventSocket
import com.deepseek.harness.android.network.DshRpcClient
import com.deepseek.harness.android.network.RpcError
import com.deepseek.harness.android.network.RpcResult
import com.deepseek.harness.android.network.ServerRequest
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class DshConnectionManagerTest {

    @Test
    fun `connected only after host describe and both streams open`() = runTest {
        val dispatcher = StandardTestDispatcher(testScheduler)
        val socket = ClosableTestSocket()
        val rpc = FakeDshRpcClient(failFirstCall = false)
        val manager = DshConnectionManager(
            rpcClient = rpc,
            eventSocket = socket,
            json = Json { ignoreUnknownKeys = true },
            ioDispatcher = dispatcher,
            backoffDelay = DshBackoffDelay { 1_000L },
        )

        manager.start()
        assertEquals(ConnectionPhase.DISCONNECTED, manager.state.value.phase)
        advanceUntilIdle()

        val state = manager.state.value
        assertEquals(ConnectionPhase.CONNECTED, state.phase)
        assertEquals(1L, state.generation)
        assertEquals("0.0.0-test", state.hostDescription?.version)
        assertEquals("/tmp/dsh", state.hostDescription?.cwd)
        assertEquals(1, rpc.callCount)
        assertEquals(listOf("/api/events.mux", "/api/events.host"), socket.connectedPaths)
    }

    @Test
    fun `backoff attempt resets after a generation reached connected`() = runTest {
        val dispatcher = StandardTestDispatcher(testScheduler)
        val socket = ClosableTestSocket()
        val rpc = FakeDshRpcClient(failFirstCall = true)
        val backoffAttempts = mutableListOf<Int>()
        val manager = DshConnectionManager(
            rpcClient = rpc,
            eventSocket = socket,
            json = Json { ignoreUnknownKeys = true },
            ioDispatcher = dispatcher,
            backoffDelay = DshBackoffDelay { attempt ->
                backoffAttempts += attempt
                if (backoffAttempts.size == 1) 0L else 5_000L
            },
        )

        manager.start()
        advanceUntilIdle()

        // First describe failed, retry delay 0, second describe succeeded and
        // both streams are still open.
        assertEquals(ConnectionPhase.CONNECTED, manager.state.value.phase)
        assertEquals(2, rpc.callCount)
        assertTrue(socket.connectCount >= 2)

        // Lose the healthy generation and process only tasks due now. The 5s
        // delay must not elapse yet, so this isolates the attempt-number reset.
        socket.closeAllStreams()
        runCurrent()

        assertEquals(ConnectionPhase.RECONNECTING, manager.state.value.phase)
        assertEquals(2, rpc.callCount)
        assertEquals(listOf(0, 0), backoffAttempts)
    }

    @Test
    fun `missing socket open keeps generation from publishing connected`() = runTest {
        val dispatcher = StandardTestDispatcher(testScheduler)
        val socket = ClosableTestSocket(autoOpen = false)
        val rpc = FakeDshRpcClient(failFirstCall = false)
        val manager = DshConnectionManager(
            rpcClient = rpc,
            eventSocket = socket,
            json = Json { ignoreUnknownKeys = true },
            ioDispatcher = dispatcher,
            backoffDelay = DshBackoffDelay { 5_000L },
        )
        manager.start()
        runCurrent()
        advanceTimeBy(3_001L)
        runCurrent()

        // The exact transient phase depends on when the timed-out generation
        // is swept; the invariant is that CONNECTED is never published.
        assertTrue(rpc.callCount >= 1)
        assertTrue(manager.hostDescription.value == null)
        assertTrue(manager.state.value.phase != ConnectionPhase.CONNECTED)
    }

    @Test
    fun `exponential backoff reaches its configured cap`() {
        val policy = ExponentialDshBackoffDelay(
            baseMillis = 10L,
            maxMillis = 80L,
        )
        repeat(20) {
            val delay = policy.delayMillis(10_000)
            assertTrue("expected capped delay, got $delay", delay in 40L..80L)
        }
    }
}

private class ClosableTestSocket(
    private val autoOpen: Boolean = true,
) : DshEventSocket {
    private val closures = mutableListOf<CompletableDeferred<Unit>>()

    val connectedPaths: List<String> get() = paths.toList()
    val connectCount: Int get() = paths.size
    private val paths = mutableListOf<String>()

    override fun connect(
        path: String,
        onOpen: () -> Unit,
    ): Flow<ServerRequest> = flow {
        synchronized(this) { paths += path }
        if (autoOpen) onOpen()
        val closed = CompletableDeferred<Unit>()
        synchronized(this) { closures += closed }
        closed.await()
    }

    fun closeAllStreams() {
        synchronized(this) { closures.toList() }.forEach { it.complete(Unit) }
    }
}

private class FakeDshRpcClient(
    private val failFirstCall: Boolean,
) : DshRpcClient {
    var callCount: Int = 0
        private set

    override suspend fun call(
        endpoint: String,
        method: String,
        payload: JsonObject,
    ): RpcResult {
        callCount += 1
        if (failFirstCall && callCount == 1) {
            return RpcResult(
                ok = false,
                error = RpcError(code = "test-failure", message = "first attempt fails"),
            )
        }
        return RpcResult(
            ok = true,
            value = buildJsonObject {
                put("version", "0.0.0-test")
                put("cwd", "/tmp/dsh")
                put("attachedSessions", 2)
            },
        )
    }

    override suspend fun respond(
        rpcId: String,
        result: RpcResult,
    ) = Unit
}
