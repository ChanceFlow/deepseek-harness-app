package com.deepseek.harness.app

import android.app.ActivityManager
import android.content.Context
import android.os.Build
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * MethodChannel bridge for the platform's record of why this process last died.
 *
 * A WebView renderer death can silently take the app process with it: Android
 * reports a kill from outside the app, the Dart error hooks never run, and
 * Play Console does not even surface an unhandled renderer death. Android 11+
 * (API 30) keeps the last few [ActivityManager.ApplicationExitInfo] records
 * instead — the reason constant, when the process died, the system's
 * description, and the process identity — which is the only on-device
 * evidence of the previous run's end. `lib/logging/exit_reasons.dart` owns the
 * matching Dart seam and records the newest abnormal entry into the in-app
 * error log.
 *
 * [register] wires the channel (`dsh/diagnostics`) into the engine's
 * messenger. The call reads history only: no permission is required for the
 * app's own exit records, and the trace streams are deliberately not read —
 * they are large and a record may point at another process's data. Below API
 * 30 there is no such history, so the answer is an empty list and Dart records
 * nothing.
 */
object DiagnosticsBridge {
    /** Channel name; the Dart seam owns the matching constant. */
    const val CHANNEL = "dsh/diagnostics"

    /**
     * Registers the handler on [messenger]. [context] supplies the package
     * name whose history is read and the system service; [MainActivity] passes
     * itself.
     */
    fun register(context: Context, messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "lastExitReasons" -> result.success(lastExitReasons(context))
                else -> result.notImplemented()
            }
        }
    }

    /** The mapped exit history, newest first; empty before API 30. */
    private fun lastExitReasons(context: Context): List<Map<String, Any?>> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return emptyList()
        val manager = context.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
            ?: return emptyList()
        return try {
            manager.getHistoricalProcessExitReasons(context.packageName, 0, MAX_REASONS)
                .map { info ->
                    mapOf(
                        "timestamp" to info.timestamp,
                        "reason" to info.reason,
                        "description" to info.description,
                        "importance" to info.importance,
                        "status" to info.status,
                        "processName" to info.processName,
                    )
                }
        } catch (_: Exception) {
            // A system service that refuses the query means the history is
            // unavailable; the caller records nothing rather than treating the
            // absence as a clean exit.
            emptyList()
        }
    }

    /** How many history entries to ask for; the platform caps the list too. */
    private const val MAX_REASONS = 10
}
