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
import kotlin.random.Random
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
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
private const val BACKOFF_BASE_MS = 500L
private const val BACKOFF_FACTOR = 2.0
private const val BACKOFF_MAX_MS = 10_000L

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
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
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
                runGeneration()
                _hostDescription.value = null
                _state.update { it.copy(phase = ConnectionPhase.RECONNECTING) }
                delay(backoffDelay(attempt))
                attempt += 1
            }
        }
    }

    private suspend fun runGeneration() {
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

            if (!failure.isCompleted) failure.await()
        } catch (error: CancellationException) {
            throw error
        } catch (_: Throwable) {
            // Generation failed before readiness; the common retry loop owns it.
        } finally {
            generationJob.cancel()
        }
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
                failure.trySend(error).getOrThrow()
            } finally {
                failure.trySend(null)
            }
        }
    }

    private fun backoffDelay(attempt: Int): Long {
        val cap = minOf(
            BACKOFF_MAX_MS,
            (BACKOFF_BASE_MS * FAST_POW[attempt.coerceAtMost(20)]).toLong(),
        )
        return cap / 2 + Random.nextLong(cap / 2 + 1)
    }

    companion object {
        private val FAST_POW = LongArray(21) { index ->
            var value = 1L
            repeat(index) { value = (value * BACKOFF_FACTOR).toLong() }
            value
        }
    }
}
