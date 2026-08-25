package com.deepseek.harness.app

import android.Manifest
import android.content.pm.PackageManager
import android.media.AudioFormat
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

class MainActivity : FlutterActivity() {
    private val RECORD_PERMISSION_CODE = 1001
    private var pendingPermissionResult: MethodChannel.Result? = null

    private var audioRecord: AudioRecord? = null
    private val isRecording = AtomicBoolean(false)
    private var recordingThread: Thread? = null
    private var audioEventSink: EventChannel.EventSink? = null

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

        val record = AudioRecord(
            MediaRecorder.AudioSource.VOICE_RECOGNITION,
            sampleRate,
            channelConfig,
            audioFormat,
            bufferSize
        )

        if (record.state != AudioRecord.STATE_INITIALIZED) {
            throw IllegalStateException("Failed to initialize AudioRecord")
        }

        audioRecord = record
        record.startRecording()
        isRecording.set(true)

        recordingThread = Thread {
            val shortBuffer = ShortArray(1600) // 100ms at 16kHz
            while (isRecording.get()) {
                val readCount = record.read(shortBuffer, 0, shortBuffer.size)
                if (readCount > 0) {
                    val floatArray = FloatArray(readCount)
                    for (i in 0 until readCount) {
                        floatArray[i] = shortBuffer[i] / 32768.0f
                    }
                    runOnUiThread {
                        audioEventSink?.success(floatArray)
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