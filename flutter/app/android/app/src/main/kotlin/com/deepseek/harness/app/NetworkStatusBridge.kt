package com.deepseek.harness.app

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel

/**
 * Reports the device's default network becoming available, so the client can
 * reconnect the mux WebSocket immediately instead of waiting out its
 * exponential backoff.
 *
 * [ConnectivityManager.registerDefaultNetworkCallback] delivers `onAvailable`
 * when the default network returns or is replaced: a screen unlock that
 * restores the transport, a Wi-Fi/cellular switch, and a Doze exit all arrive
 * here. Availability — not
 * [NetworkCapabilities.NET_CAPABILITY_VALIDATED] — is the trigger, because a
 * dsh host on a local network without internet access is reachable while
 * Android still reports that network unvalidated.
 *
 * Register from `MainActivity.configureFlutterEngine`, after the super call:
 *
 * ```kotlin
 * NetworkStatusBridge.register(this, flutterEngine)
 * ```
 *
 * The manifest declares `android.permission.ACCESS_NETWORK_STATE`; without
 * it `registerDefaultNetworkCallback` throws `SecurityException`, which the
 * handler reports as an event error instead of crashing the process.
 */
object NetworkStatusBridge {
    const val CHANNEL_NAME = "dsh/network_status"

    /**
     * Attaches the event channel to [engine]. [context] supplies the
     * system service (`MainActivity` is itself a `Context`).
     */
    fun register(context: Context, engine: FlutterEngine) {
        EventChannel(engine.dartExecutor.binaryMessenger, CHANNEL_NAME)
            .setStreamHandler(NetworkStatusStreamHandler(context.applicationContext))
    }
}

/**
 * One stream subscription's worth of connectivity callback: registration
 * starts in [onListen], stops in [onCancel]. Connectivity callbacks arrive on
 * a binder thread, so every event-sink call and every mutation of the
 * announced-network set is posted to the platform thread, which is also where
 * `onListen`/`onCancel` run.
 */
private class NetworkStatusStreamHandler(
    private val context: Context,
) : EventChannel.StreamHandler {
    private val mainHandler = Handler(Looper.getMainLooper())

    /** Networks that already produced a hint, cleared when a network is lost. */
    private val announced = mutableSetOf<Network>()

    private var sink: EventChannel.EventSink? = null
    private var callback: ConnectivityManager.NetworkCallback? = null

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        if (events == null || callback != null) return
        val manager = context.getSystemService(Context.CONNECTIVITY_SERVICE)
            as? ConnectivityManager ?: return
        // Registration reports the network that is already the default as its
        // first onAvailable. That report is current state, not a return, so
        // the network it names is marked announced before registering; a
        // network that appears afterwards is a real transition and emits.
        manager.activeNetwork?.let(announced::add)
        val networkCallback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                mainHandler.post {
                    val live = sink ?: return@post
                    if (!announced.add(network)) return@post
                    live.success(null)
                }
            }

            override fun onLost(network: Network) {
                mainHandler.post { announced.remove(network) }
            }
        }
        sink = events
        try {
            registerDefaultCallback(manager, networkCallback)
        } catch (e: Exception) {
            // SecurityException without ACCESS_NETWORK_STATE, and
            // RuntimeException from the per-uid callback limit, both mean the
            // hint is unavailable; Dart records the error and stays inert.
            sink = null
            mainHandler.post { events.error("register_failed", e.message, null) }
            return
        }
        callback = networkCallback
    }

    override fun onCancel(arguments: Any?) {
        sink = null
        announced.clear()
        val registered = callback ?: return
        callback = null
        val manager = context.getSystemService(Context.CONNECTIVITY_SERVICE)
            as? ConnectivityManager ?: return
        try {
            manager.unregisterNetworkCallback(registered)
        } catch (_: Exception) {
            // Already unregistered, or the system service is gone.
        }
    }

    private fun registerDefaultCallback(
        manager: ConnectivityManager,
        callback: ConnectivityManager.NetworkCallback,
    ) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            manager.registerDefaultNetworkCallback(callback)
        } else {
            // registerDefaultNetworkCallback is API 24+; below it, match any
            // internet-capable network instead.
            manager.registerNetworkCallback(
                NetworkRequest.Builder()
                    .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
                    .build(),
                callback,
            )
        }
    }
}
