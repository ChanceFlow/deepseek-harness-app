package com.deepseek.harness.app

import android.app.ActivityManager
import android.app.ApplicationExitInfo
import android.content.Context
import android.os.Build
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.BufferedInputStream
import java.io.ByteArrayOutputStream
import java.io.InputStream
import java.io.PushbackInputStream
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.ThreadFactory
import java.util.zip.GZIPInputStream

/**
 * MethodChannel bridge for the platform's record of why this process last died.
 *
 * A WebView renderer death can silently take the app process with it: Android
 * reports a kill from outside the app, the Dart error hooks never run, and
 * Play Console does not even surface an unhandled renderer death. Android 11+
 * (API 30) keeps the last few [ApplicationExitInfo] records
 * instead — the reason constant, when the process died, the system's
 * description, the process identity, and a trace of the dying process. The
 * reason and description alone attribute a death; the bounded trace explains
 * it, which is what an ANR or native crash otherwise loses. `lib/logging/
 * exit_reasons.dart` owns the matching Dart seam and records the newest
 * abnormal entry, trace included, into the in-app error log.
 *
 * [register] wires the channel (`dsh/diagnostics`) into the engine's
 * messenger. No permission is required for the app's own exit records. The
 * history query and every trace read run on one shared background worker: the
 * history call is a binder round trip and a trace read can decompress a large
 * stream, so neither may block the platform main thread. Android reports exits
 * for every process in the package, including the WebView sandboxed renderer
 * (`…:sandboxed_process*`), whose routine teardown is not the app's death; the
 * mapped record carries `isOwnProcess` so only the app's own main process is
 * ever attributed, and a trace is probed only for it. The trace is read
 * bounded (64 KiB) and only for the record's own pid or a matching `Cmd line:`
 * block, so a record that points at another process's data contributes
 * nothing; a dump without any block header keeps its bounded head instead.
 * Below API 30 there is no such history: the answer is an empty list and Dart
 * records nothing.
 */
object DiagnosticsBridge {
    /** Channel name; the Dart seam owns the matching constant. */
    const val CHANNEL = "dsh/diagnostics"

    /** How many history entries to ask for; the platform caps the list too. */
    private const val MAX_REASONS = 10

    /** Hard cap on the decompressed trace bytes this bridge reads. */
    private const val MAX_TRACE_BYTES = 64 * 1024

    /**
     * Appended when the trace stream holds more than [MAX_TRACE_BYTES]. The
     * Dart seam renders the same words, so a report states truncation once.
     */
    private const val TRACE_TRUNCATION_MARKER =
        "[... trace truncated at 65536 bytes ...]"

    /** The `----- pid <n> at <time> -----` line that opens an ANR trace block. */
    private val BLOCK_HEADER = Regex("^----- pid (\\d+) at .+ -----$")

    /** The `----- end <n> -----` line that closes an ANR trace block. */
    private val BLOCK_FOOTER = Regex("^----- end (\\d+) -----$")

    /** The trace line that names a block's process without its pid. */
    private const val CMD_LINE_PREFIX = "Cmd line: "

    /**
     * One worker serializes both channel methods: a signed-in app can ask once
     * per launch, the work is short, and a single thread bounds it while
     * keeping history and trace reads ordered behind the same queue.
     */
    private val worker: ExecutorService by lazy {
        Executors.newSingleThreadExecutor(object : ThreadFactory {
            override fun newThread(r: Runnable): Thread =
                Thread(r, "dsh-diagnostics").apply { isDaemon = true }
        })
    }

    /**
     * Registers the handler on [messenger]. [context] supplies the package
     * name whose history is read and the system service; [MainActivity] passes
     * itself.
     */
    fun register(context: Context, messenger: BinaryMessenger) {
        val appContext: Context = context.applicationContext ?: context
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "lastExitReasons" -> worker.execute {
                    deliver(result, lastExitReasonsSafely(appContext))
                }

                "exitTrace" -> {
                    val timestamp = call.argument<Number>("timestamp")?.toLong()
                    val pid = call.argument<Number>("pid")?.toInt()
                    if (timestamp == null || pid == null) {
                        deliver(result, null)
                    } else {
                        worker.execute {
                            deliver(result, readExitTraceSafely(appContext, timestamp, pid))
                        }
                    }
                }

                else -> result.notImplemented()
            }
        }
    }

    /**
     * Completes [result] on the worker thread. Flutter's channel result may be
     * answered from any thread; a detached engine can still make the send
     * fail, and that must not escape onto the worker as an uncaught crash.
     */
    private fun deliver(result: MethodChannel.Result, value: Any?) {
        try {
            result.success(value)
        } catch (_: Throwable) {
            // The engine is gone; there is nobody left to answer.
        }
    }

    /** The mapped exit history, newest first; empty before API 30. */
    private fun lastExitReasonsSafely(context: Context): List<Map<String, Any?>> =
        try {
            lastExitReasons(context)
        } catch (_: Throwable) {
            // A refused or failing history query means the history is
            // unavailable; the caller records nothing rather than treating the
            // absence as a clean exit.
            emptyList()
        }

    private fun lastExitReasons(context: Context): List<Map<String, Any?>> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return emptyList()
        val manager = context.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
            ?: return emptyList()
        return manager.getHistoricalProcessExitReasons(context.packageName, 0, MAX_REASONS)
            .map { info ->
                // The main process runs under the package name; sandboxed
                // WebView renderers carry a `…:sandboxed_process*` suffix.
                val own = info.processName == context.packageName
                mapOf(
                    "timestamp" to info.timestamp,
                    "reason" to info.reason,
                    "description" to info.description,
                    "importance" to info.importance,
                    "status" to info.status,
                    "processName" to info.processName,
                    "pid" to info.pid,
                    "isOwnProcess" to own,
                    // A foreign record's trace is another process's data and
                    // must not even be opened.
                    "hasTrace" to (own && hasTrace(info)),
                )
            }
    }

    /**
     * Whether [info] exposes a trace stream that can be opened; only called
     * for the app's own record. Opening and closing is the only portable
     * check; a refused or unreadable stream is not evidence, so it reports
     * false and Dart asks for no trace.
     */
    private fun hasTrace(info: ApplicationExitInfo): Boolean =
        try {
            info.traceInputStream?.use { true } ?: false
        } catch (_: Throwable) {
            false
        }

    /**
     * The bounded trace for the history record matching [timestamp] and [pid],
     * or null when the record is gone or belongs to another process, its
     * stream is missing, unreadable or a binary tombstone, or the process
     * cannot isolate a block of its own.
     */
    private fun readExitTraceSafely(context: Context, timestamp: Long, pid: Int): String? =
        try {
            readExitTrace(context, timestamp, pid)
        } catch (_: Throwable) {
            // A hostile or truncated stream must never fail the channel call.
            null
        }

    private fun readExitTrace(context: Context, timestamp: Long, pid: Int): String? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return null
        val manager = context.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
            ?: return null
        val info = manager.getHistoricalProcessExitReasons(
            context.packageName,
            0,
            MAX_REASONS,
        ).firstOrNull {
            it.timestamp == timestamp && it.pid == pid &&
                it.processName == context.packageName
        } ?: return null
        return info.traceInputStream?.use { raw ->
            val text = readTraceText(raw) ?: return@use null
            formatTrace(text.text, pid, context.packageName, text.truncated)
        }
    }

    /** The bounded text of a trace stream, whatever its encoding. */
    private class TraceText(val text: String, val truncated: Boolean)

    /**
     * Reads at most [MAX_TRACE_BYTES] decompressed bytes and decodes them
     * leniently as UTF-8. An empty or binary answer (a protobuf tombstone on
     * API 31+) is null rather than megabytes of noise stored in the log.
     */
    private fun readTraceText(raw: InputStream): TraceText? {
        val stream = openMaybeGzip(raw)
        val (bytes, truncated) = readBounded(stream, MAX_TRACE_BYTES)
        if (bytes.isEmpty() || looksBinary(bytes)) return null
        return TraceText(String(bytes, Charsets.UTF_8), truncated)
    }

    /**
     * Wraps [raw] in a gzip stream when it starts with the gzip magic, leaving
     * an uncompressed stream byte-identical by pushing the peeked bytes back.
     */
    private fun openMaybeGzip(raw: InputStream): InputStream {
        val pushback = PushbackInputStream(BufferedInputStream(raw), 2)
        val magic = ByteArray(2)
        var read = 0
        while (read < magic.size) {
            val count = pushback.read(magic, read, magic.size - read)
            if (count < 0) break
            read += count
        }
        val gzipped = read == magic.size &&
            magic[0] == 0x1f.toByte() &&
            magic[1] == 0x8b.toByte()
        if (read > 0) pushback.unread(magic, 0, read)
        return if (gzipped) GZIPInputStream(pushback) else pushback
    }

    /**
     * Reads the whole of [stream] up to [limit] bytes. The second value is
     * true when the stream held more, which the caller marks explicitly.
     */
    private fun readBounded(stream: InputStream, limit: Int): Pair<ByteArray, Boolean> {
        val out = ByteArrayOutputStream()
        val buffer = ByteArray(8 * 1024)
        var truncated = false
        while (true) {
            val count = stream.read(buffer)
            if (count < 0) break
            val room = limit - out.size()
            if (room <= 0) {
                truncated = true
                break
            }
            out.write(buffer, 0, minOf(count, room))
            if (count > room) {
                truncated = true
                break
            }
        }
        return out.toByteArray() to truncated
    }

    /**
     * Whether [bytes] look like a binary tombstone rather than text. A NUL
     * byte is decisive; a sparse tail of other control bytes keeps a mostly
     * textual trace readable.
     */
    private fun looksBinary(bytes: ByteArray): Boolean {
        val sample = minOf(bytes.size, 4096)
        var controls = 0
        for (index in 0 until sample) {
            val value = bytes[index].toInt() and 0xff
            if (value == 0) return true
            if (value < 0x09 || value in 0x0e..0x1f || value == 0x7f) controls++
        }
        return sample > 0 && controls * 10 > sample
    }

    /**
     * Limits [text] to this process's trace blocks and appends the truncation
     * marker when the stream was cut.
     *
     * A trace may hold blocks for several processes; only the block whose pid
     * matches the record, or whose `Cmd line:` names our package, is kept. A
     * text without any block header (an older or non-standard dump) keeps its
     * bounded head whole; a text whose blocks none match is another process's
     * trace and contributes nothing.
     */
    private fun formatTrace(
        text: String,
        pid: Int,
        packageName: String,
        truncated: Boolean,
    ): String? {
        val blocks = parseBlocks(text)
        val body = if (blocks.isEmpty()) {
            text
        } else {
            val ours = blocks.filter { (blockPid, block) ->
                blockPid == pid || block.lineSequence().any {
                    it.trim() == "$CMD_LINE_PREFIX$packageName"
                }
            }
            if (ours.isEmpty()) return null
            val selected = StringBuilder()
            for ((_, block) in ours) selected.append(block)
            selected.toString()
        }
        val trimmed = body.trim()
        if (trimmed.isEmpty()) return null
        val capped = if (trimmed.length > MAX_TRACE_BYTES) {
            trimmed.substring(0, MAX_TRACE_BYTES)
        } else {
            trimmed
        }
        val cut = truncated || capped.length < trimmed.length
        return if (cut) "$capped\n$TRACE_TRUNCATION_MARKER" else capped
    }

    /**
     * The `----- pid … -----` blocks of [text] as (pid, block) pairs, in order;
     * empty when the text has no block header.
     */
    private fun parseBlocks(text: String): List<Pair<Int, String>> {
        val blocks = ArrayList<Pair<Int, String>>()
        var currentPid = -1
        var current = StringBuilder()
        for (rawLine in text.split('\n')) {
            val line = rawLine.trimEnd('\r')
            val header = BLOCK_HEADER.matchEntire(line)
            if (header != null) {
                if (currentPid >= 0) blocks.add(currentPid to current.toString())
                currentPid = header.groupValues[1].toIntOrNull() ?: -1
                current = StringBuilder()
                current.append(line).append('\n')
                continue
            }
            if (currentPid < 0) continue // Text before the first block.
            current.append(line).append('\n')
            if (BLOCK_FOOTER.matches(line)) {
                blocks.add(currentPid to current.toString())
                currentPid = -1
                current = StringBuilder()
            }
        }
        if (currentPid >= 0) blocks.add(currentPid to current.toString())
        return blocks
    }
}
