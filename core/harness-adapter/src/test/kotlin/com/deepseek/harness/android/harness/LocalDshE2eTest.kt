package com.deepseek.harness.android.harness

import com.deepseek.harness.android.domain.model.ConnectionPhase
import com.deepseek.harness.android.network.OkHttpDshEventSocket
import com.deepseek.harness.android.network.OkHttpDshRpcClient
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import kotlinx.serialization.json.Json
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.OkHttpClient
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test

/**
 * Opt-in read-only smoke test against a real `dsh web` host.
 *
 * Set `DSH_E2E_URL` (for example `http://127.0.0.1:3080`) when running local
 * harness tests. The test never creates sessions or sends prompts.
 */
class LocalDshE2eTest {

    @Test
    fun realHostReadOnlySmoke() = runBlocking {
        val endpoint = System.getenv("DSH_E2E_URL")
        assumeTrue("DSH_E2E_URL is not set; skipping real-host smoke", endpoint != null && endpoint.isNotBlank())

        val json = Json {
            ignoreUnknownKeys = true
            encodeDefaults = true
            coerceInputValues = true
        }
        val http = OkHttpClient.Builder()
            .connectTimeout(10, TimeUnit.SECONDS)
            .readTimeout(30, TimeUnit.SECONDS)
            .build()
        val rpc = OkHttpDshRpcClient(
            baseUrl = endpoint!!.toHttpUrl(),
            client = http,
            json = json,
        )
        val socket = OkHttpDshEventSocket(
            baseUrl = endpoint.toHttpUrl(),
            client = http,
            json = json,
        )
        val manager = DshConnectionManager(
            rpcClient = rpc,
            eventSocket = socket,
            json = json,
            ioDispatcher = Dispatchers.IO,
            backoffDelay = ExponentialDshBackoffDelay(),
        )
        try {
            manager.start()
            val connected = withTimeout(15_000L) {
                manager.state.first { it.phase == ConnectionPhase.CONNECTED }
            }
            assertTrue(connected.hostDescription?.version?.isNotBlank() == true)

            val repository = HarnessRepositoryImpl(
                rpcClient = rpc,
                connectionManager = manager,
                json = json,
                ioDispatcher = Dispatchers.IO,
            )
            repository.refreshSessions()
            repository.refreshWorkspaces()

            val directory = repository.listDirectory(null)
            assertTrue(directory.home.isNotBlank())
            // Loopback callers may read the settings plane; the snapshot only
            // needs to decode, whatever namespaces this host declares.
            val settings = repository.describeSettings()
            assertTrue(settings.namespaces.all { it.ns.isNotBlank() })
            val credentials = repository.describeCredentials(settings.credentialRefs)
            assertTrue(credentials.all { it.ref.isNotBlank() })
            val sessions = repository.observeSessions().first()
            val workspaces = repository.observeWorkspaces().first()
            sessions.firstOrNull()?.let { session ->
                repository.openSession(session.id)
                repository.observeTimelineWindow(session.id).first()
            }
            assertTrue(workspaces.firstOrNull()?.path?.isNotBlank() ?: true)
        } finally {
            manager.stop()
        }
    }
}
