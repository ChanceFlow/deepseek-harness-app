package com.deepseek.harness.app

import android.Manifest
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Build
import android.os.StatFs
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong
import kotlin.math.abs

class MainActivity : FlutterActivity() {
    private val RECORD_PERMISSION_CODE = 1001
    private var pendingPermissionResult: MethodChannel.Result? = null

    private var audioRecord: AudioRecord? = null
    private val isRecording = AtomicBoolean(false)
    private var recordingThread: Thread? = null
    private var audioEventSink: EventChannel.EventSink? = null

    // Live capture diagnostics, readable from the app without adb/logcat.
    private val statsReads = AtomicLong(0)
    private val statsEventsSent = AtomicLong(0)
    @Volatile private var statsMaxAbs = 0f
    @Volatile private var statsSourceUsed = "none"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Real free-space probe for ASR model pre-flight check.
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

        // Live capture diagnostics: what the native side sees, for the
        // in-app debug strip. Distinguishes "device feeds silence"
        // (maxAbs stays 0) from "events never reach Dart" (reads grow,
        // events do not).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dsh/audio_debug")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getStats" -> {
                        val micMuted = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                            val am = getSystemService(AUDIO_SERVICE) as AudioManager
                            am.isMicrophoneMute
                        } else {
                            null
                        }
                        val map = mapOf<String, Any?>(
                            "reads" to statsReads.get(),
                            "eventsSent" to statsEventsSent.get(),
                            "maxAbs" to statsMaxAbs,
                            "sourceUsed" to statsSourceUsed,
                            "isRecording" to isRecording.get(),
                            "micMuted" to micMuted,
                        )
                        result.success(map)
                    }
                    else -> result.notImplemented()
                }
            }

        // Microphone permissions & recording control channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dsh/audio_record")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "hasPermission" -> {
                        val granted = ContextCompat.checkSelfPermission(
                            this,
                            Manifest.permission.RECORD_AUDIO
                        ) == PackageManager.PERMISSION_GRANTED
                        result.success(granted)
                    }
                    "requestPermission" -> {
                        if (ContextCompat.checkSelfPermission(
                                this,
                                Manifest.permission.RECORD_AUDIO
                            ) == PackageManager.PERMISSION_GRANTED
                        ) {
                            result.success(true)
                        } else {
                            pendingPermissionResult = result
                            ActivityCompat.requestPermissions(
                                this,
                                arrayOf(Manifest.permission.RECORD_AUDIO),
                                RECORD_PERMISSION_CODE
                            )
                        }
                    }
                    "startRecording" -> {
                        val sampleRate = call.argument<Int>("sampleRate") ?: 16000
                        try {
                            startAudioCapture(sampleRate)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("record_error", e.message, null)
                        }
                    }
                    "stopRecording" -> {
                        stopAudioCapture()
                        result.success(true)
                    }
                    // Earcons for the three boundaries of a capture, taken from
                    // the platform's own UI-sound set — the switch tick, the
                    // dialpad key, the delete key — rather than shipped assets:
                    // they follow the device's sound-effects setting, stay
                    // audible while the microphone is hot, and cost the APK no
                    // bytes. The public AudioManager FX_ ids are the whole
                    // vocabulary playSoundEffect accepts, so the mapping stays
                    // inside it; a device without an id leaves that boundary
                    // silent, which the Dart side reads as success.
                    "playSoundEffect" -> {
                        val am = getSystemService(AUDIO_SERVICE) as AudioManager
                        val effect = when (call.argument<String>("effect")) {
                            "start" -> AudioManager.FX_FOCUS_NAVIGATION_UP
                            "send" -> AudioManager.FX_KEYPRESS_STANDARD
                            "cancel" -> AudioManager.FX_KEYPRESS_DELETE
                            else -> null
                        }
                        if (effect != null) am.playSoundEffect(effect)
                        result.success(effect != null)
                    }
                    else -> result.notImplemented()
                }
            }

        // Audio PCM streaming event channel
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "dsh/audio_stream")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    audioEventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    audioEventSink = null
                    stopAudioCapture()
                }
            })
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == RECORD_PERMISSION_CODE) {
            val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
            pendingPermissionResult?.success(granted)
            pendingPermissionResult = null
        }
    }

    private fun startAudioCapture(sampleRate: Int) {
        if (isRecording.get()) return

        val channelConfig = AudioFormat.CHANNEL_IN_MONO
        val audioFormat = AudioFormat.ENCODING_PCM_16BIT
        val minBufferSize = AudioRecord.getMinBufferSize(sampleRate, channelConfig, audioFormat)
        val bufferSize = maxOf(minBufferSize, sampleRate / 10 * 2) // at least 100ms buffer

        if (ActivityCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            throw SecurityException("RECORD_AUDIO permission not granted")
        }

        // Some OEM devices return silence on VOICE_RECOGNITION; fall back to
        // MIC, then UNPROCESSED (API 24+) before giving up.
        val sources = buildList {
            add(MediaRecorder.AudioSource.VOICE_RECOGNITION)
            add(MediaRecorder.AudioSource.MIC)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                add(MediaRecorder.AudioSource.UNPROCESSED)
            }
        }
        var record: AudioRecord? = null
        for (source in sources) {
            val candidate = AudioRecord(source, sampleRate, channelConfig, audioFormat, bufferSize)
            if (candidate.state == AudioRecord.STATE_INITIALIZED) {
                record = candidate
                statsSourceUsed = when (source) {
                    MediaRecorder.AudioSource.VOICE_RECOGNITION -> "voice_recognition"
                    MediaRecorder.AudioSource.MIC -> "mic"
                    MediaRecorder.AudioSource.UNPROCESSED -> "unprocessed"
                    else -> "unknown"
                }
                break
            }
            candidate.release()
        }
        val recordFinal = record
            ?: throw IllegalStateException("Failed to initialize AudioRecord on any source")

        audioRecord = recordFinal
        recordFinal.startRecording()
        isRecording.set(true)
        statsReads.set(0)
        statsEventsSent.set(0)
        statsMaxAbs = 0f

        var silentBufferCount = 0
        recordingThread = Thread {
            val shortBuffer = ShortArray(1600) // 100ms at 16kHz
            while (isRecording.get()) {
                val readCount = recordFinal.read(shortBuffer, 0, shortBuffer.size)
                if (readCount > 0) {
                    statsReads.incrementAndGet()
                    var maxAbs = 0f
                    val floatArray = FloatArray(readCount)
                    for (i in 0 until readCount) {
                        val v = shortBuffer[i] / 32768.0f
                        floatArray[i] = v
                        if (abs(v) > maxAbs) maxAbs = abs(v)
                    }
                    statsMaxAbs = maxOf(statsMaxAbs, maxAbs)

                    // The system delivers silence (not an error) when the
                    // Android 12+ mic toggle is off or another app holds the
                    // microphone; surface it after ~2s of pure zeros.
                    if (maxAbs == 0f) {
                        silentBufferCount++
                        if (silentBufferCount >= 20) {
                            silentBufferCount = 0
                            runOnUiThread {
                                audioEventSink?.error(
                                    "input_silent",
                                    "No audio signal detected from the microphone",
                                    null
                                )
                            }
                        }
                    } else {
                        silentBufferCount = 0
                    }

                    runOnUiThread {
                        audioEventSink?.success(floatArray)
                        statsEventsSent.incrementAndGet()
                    }
                }
            }
        }.apply {
            priority = Thread.MAX_PRIORITY
            start()
        }
    }

    private fun stopAudioCapture() {
        if (!isRecording.compareAndSet(true, false)) return
        // Stop() unblocks a read() in flight, so the recording thread can
        // observe isRecording=false and exit before we release the record.
        // release() while read() is still running is undefined and can crash.
        try {
            audioRecord?.stop()
        } catch (_: Exception) {}
        val thread = recordingThread
        recordingThread = null
        thread?.join(500)
        try {
            audioRecord?.release()
        } catch (_: Exception) {}
        audioRecord = null
    }

    override fun onDestroy() {
        stopAudioCapture()
        super.onDestroy()
    }
}