package com.deepseek.harness.android.harness

import com.deepseek.harness.android.domain.model.ConnectionPhase
import com.deepseek.harness.android.domain.model.ConnectionState
import com.deepseek.harness.android.domain.model.HostDescription
import com.deepseek.harness.android.network.DshEventSocket
import com.deepseek.harness.android.network.DshRpcClient
import com.deepseek.harness.android.network.DshBusinessException
import com.deepseek.harness.android.network.ServerRequest
import java.util.concurrent.atomic.AtomicLong
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withTimeout
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.decodeFromJsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject

private const val EVENTS_MUX_PATH = "/api/events.mux"
private const val EVENTS_HOST_PATH = "/api/events.host"
private const val HOST_DESCRIBE = "host.describe"
private const val STREAM_OPEN_TIMEOUT_MS = 3_000L

/**
 * Retry-time policy seam. The product uses exponential backoff; tests inject a
 * deterministic schedule so generation transitions are exact-time assertions.
 */
fun interface DshBackoffDelay {
    fun delayMillis(attempt: Int): Long
}

class ExponentialDshBackoffDelay(
    private val baseMillis: Long = 500L,
    private val maxMillis: Long = 10_000L,
) : DshBackoffDelay {
    override fun delayMillis(attempt: Int): Long {
        val cap = exponentialCap(attempt.coerceAtMost(20))
        return cap / 2 + kotlin.random.Random.nextLong(cap / 2 + 1)
    }

    private fun exponentialCap(times: Int): Long {
        var value = baseMillis.coerceAtLeast(1L).coerceAtMost(maxMillis)
        repeat(times) {
            value = if (value > maxMillis / 2L) {
                maxMillis
            } else {
                minOf(maxMillis, value * 2L)
            }
        }
        return value
    }
}

@Serializable
private data class HostDescriptionWire(
    val version: String,
    val cwd: String,
    val provider: String? = null,
    val model: String? = null,
    val attachedSessions: Int = 0,
    val canOpenPath: Boolean = false,
)

@Singleton
class DshConnectionManager @Inject constructor(
    private val rpcClient: DshRpcClient,
    private val eventSocket: DshEventSocket,
    private val json: Json,
    private val ioDispatcher: CoroutineDispatcher,
    private val backoffDelay: DshBackoffDelay,
) {
    private val scope = CoroutineScope(SupervisorJob() + ioDispatcher)
    private val startMutex = Mutex()
    private val generation = AtomicLong(0L)
    private val _state = MutableStateFlow(ConnectionState())
    private val _hostDescription = MutableStateFlow<HostDescription?>(null)
    private val _muxFrames = MutableSharedFlow<ServerRequest>(
        extraBufferCapacity = 256,
    )
    private val _hostFrames = MutableSharedFlow<ServerRequest>(
        extraBufferCapacity = 64,
    )

    val state: StateFlow<ConnectionState> = _state.asStateFlow()
    val hostDescription: StateFlow<HostDescription?> = _hostDescription.asStateFlow()
    val muxFrames: SharedFlow<ServerRequest> = _muxFrames.asSharedFlow()
    val hostFrames: SharedFlow<ServerRequest> = _hostFrames.asSharedFlow()

    fun start() {
        scope.launch {
            startMutex.withLock {
                if (_state.value.phase != ConnectionPhase.DISCONNECTED) return@withLock
                _state.update { it.copy(phase = ConnectionPhase.CONNECTING) }
                connectLoop()
            }
        }
    }

    /**
     * The loop owns generations: each generation opens both downlinks and
     * requires a successful `host.describe` plus both WebSocket onOpen events
     * before publishing CONNECTED. Any stream loss counts as generation loss.
     */
    private fun connectLoop() {
        scope.launch {
            var attempt = 0
            while (scope.isActive) {
                val connected = runGeneration()
                _hostDescription.value = null
                _state.update { it.copy(phase = ConnectionPhase.RECONNECTING) }
                // A generation that reached CONNECTED was healthy until stream
                // loss; its loss starts a fresh backoff sequence.
                if (connected) attempt = 0
                delay(backoffDelay.delayMillis(attempt))
                attempt += 1
            }
        }
    }

    private suspend fun runGeneration(): Boolean {
        var connected = false
        val generationId = generation.incrementAndGet()
        val generationJob = Job()
        val generationScope = CoroutineScope(scope.coroutineContext + generationJob)

        val muxOpened = CompletableDeferred<Unit>()
        val hostOpened = CompletableDeferred<Unit>()
        val failure = CompletableDeferred<Throwable?>()

        pump(
            scope = generationScope,
            path = EVENTS_MUX_PATH,
            opened = muxOpened,
            failure = failure,
            sink = _muxFrames,
        )
        pump(
            scope = generationScope,
            path = EVENTS_HOST_PATH,
            opened = hostOpened,
            failure = failure,
            sink = _hostFrames,
        )

        try {
            val result = rpcClient.call(
                endpoint = HOST_DESCRIBE,
                method = HOST_DESCRIBE,
                payload = buildJsonObject {},
            )
            if (!result.ok) {
                throw DshBusinessException(
                    code = result.error?.code ?: "internal",
                    message = result.error?.message ?: "host.describe failed",
                )
            }
            val value = result.value
                ?: throw DshBusinessException("bad-response", "host.describe missing value")
            val description = json.decodeFromJsonElement<HostDescriptionWire>(value)

            withTimeout(STREAM_OPEN_TIMEOUT_MS) {
                muxOpened.await()
                hostOpened.await()
            }

            val host = HostDescription(
                version = description.version,
                cwd = description.cwd,
                provider = description.provider,
                model = description.model,
                attachedSessions = description.attachedSessions,
                canOpenPath = description.canOpenPath,
            )
            _hostDescription.value = host
            _state.value = ConnectionState(
                phase = ConnectionPhase.CONNECTED,
                hostDescription = host,
                generation = generationId,
            )
            connected = true

            if (!failure.isCompleted) failure.await()
        } catch (error: CancellationException) {
            throw error
        } catch (_: Throwable) {
            // Generation failed before readiness; the common retry loop owns it.
        } finally {
            generationJob.cancel()
        }
        return connected
    }

    private fun pump(
        scope: CoroutineScope,
        path: String,
        opened: CompletableDeferred<Unit>,
        failure: CompletableDeferred<Throwable?>,
        sink: MutableSharedFlow<ServerRequest>,
    ) {
        scope.launch {
            try {
                eventSocket.connect(path, onOpen = { opened.complete(Unit) })
                    .collect { frame -> sink.tryEmit(frame) }
            } catch (error: CancellationException) {
                throw error
            } catch (error: Throwable) {
                if (!failure.isCompleted) failure.complete(error)
            } finally {
                if (!failure.isCompleted) failure.complete(null)
            }
        }
    }

}
