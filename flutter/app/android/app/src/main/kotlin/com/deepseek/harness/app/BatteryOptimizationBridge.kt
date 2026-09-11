package com.deepseek.harness.app

import android.annotation.SuppressLint
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * MethodChannel bridge for the Android battery-optimization exemption.
 *
 * A foreground service keeps the process out of the cached state, but it does
 * not survive Doze or an OEM kill-list: for the mux connection to outlast the
 * screen going off, the device must put this app on the system's
 * battery-optimization exemption list. Android exposes that state through
 * [PowerManager.isIgnoringBatteryOptimizations] and the request through a
 * system dialog; neither is reachable from Dart without a channel.
 *
 * [register] wires the channel (`dsh/battery_optimization`, the contract with
 * `lib/platform/battery_optimization.dart`) into the engine's messenger. The
 * request answer is "did an activity resolve": the system's dialog activity is
 * only exported to callers holding `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`, so
 * a build without that manifest permission honestly reports `false` instead of
 * pretending the dialog opened.
 */
object BatteryOptimizationBridge {
    /** Channel name; the Dart seam owns the matching constant. */
    const val CHANNEL = "dsh/battery_optimization"

    /**
     * Registers the handler on [messenger]. [context] supplies package
     * identity and starts the request dialog; [MainActivity] passes itself.
     */
    fun register(context: Context, messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "isIgnoringBatteryOptimizations" -> result.success(isIgnoring(context))
                "requestIgnoreBatteryOptimizations" -> result.success(requestIgnore(context))
                else -> result.notImplemented()
            }
        }
    }

    /** Whether the system currently exempts this app from battery optimization. */
    private fun isIgnoring(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return false
        val powerManager =
            context.getSystemService(Context.POWER_SERVICE) as? PowerManager ?: return false
        return powerManager.isIgnoringBatteryOptimizations(context.packageName)
    }

    /**
     * Opens the system's "ignore battery optimizations" dialog for this app
     * and answers whether an activity resolved and was started.
     *
     * The start is the authoritative probe: `resolveActivity` can answer null
     * for a handler that package-visibility filtering hides, and the system
     * gates this activity on `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` — without
     * that manifest permission the activity is filtered out and the start
     * throws. Either way no dialog opened, so the honest answer is `false`.
     * `FLAG_ACTIVITY_NEW_TASK` is required because the intent leaves the
     * activity task even when started from the activity context.
     */
    @SuppressLint("BatteryLife")
    private fun requestIgnore(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return false
        val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
            data = Uri.parse("package:${context.packageName}")
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        return try {
            context.startActivity(intent)
            true
        } catch (e: ActivityNotFoundException) {
            false
        } catch (e: SecurityException) {
            false
        }
    }
}
