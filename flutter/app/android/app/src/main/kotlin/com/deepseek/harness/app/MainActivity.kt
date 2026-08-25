package com.deepseek.harness.app

import android.os.StatFs
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Real free-space probe for the ASR model download pre-flight check.
        // Channel name must match `kDiskSpaceChannel` in
        // app/lib/platform/disk_space.dart.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dsh/disk_space")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "availableBytes" -> {
                        val path = call.argument<String>("path")
                        if (path == null) {
                            result.error("bad_args", "path argument is required", null)
                        } else {
                            try {
                                result.success(StatFs(path).availableBytes)
                            } catch (e: Exception) {
                                result.error("stat_failed", e.message, null)
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}