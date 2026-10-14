package com.deepseek.harness.app

import android.content.Context
import android.graphics.Bitmap
import android.graphics.pdf.PdfRenderer
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.IOException
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import kotlin.math.floor
import kotlin.math.sqrt

/**
 * MethodChannel bridge for PDF page rendering (`dsh/pdf_page_renderer`, the
 * contract with `lib/platform/pdf_page_renderer.dart`).
 *
 * Android ships its PDF renderer in the platform — [PdfRenderer] (API 21+) — so
 * the preview sheet gets real pages without a native dependency, which the
 * F-Droid rule forbids anyway. [PdfRenderer] reads a seekable file descriptor
 * rather than a byte array, so `open` copies the complete bytes into one temp
 * file under the cache directory and keeps it for the document's lifetime:
 * pdfium reads pages on demand, so deleting that file before `close` breaks
 * rendering. The renderer takes ownership of the descriptor it is handed and
 * closes it; the temp file is deleted when the token closes.
 *
 * Every open document is a token in [documents]. [PdfRenderer] admits one open
 * page at a time and refuses to close while a page is open, so each document
 * serializes its own use behind a lock: a render in flight finishes before a
 * close can run under it. Raster work runs on its own thread, and every answer
 * is posted back to the platform thread, where Flutter expects it.
 *
 * Register from `MainActivity.configureFlutterEngine` beside the other
 * bridges:
 *
 * ```kotlin
 * PdfPageRendererBridge.register(this, flutterEngine)
 * ```
 */
object PdfPageRendererBridge {
    /** Channel name; the Dart seam owns the matching constant. */
    const val CHANNEL = "dsh/pdf_page_renderer"

    /** Answers are posted here: Flutter expects a result on the platform thread. */
    private val mainHandler = Handler(Looper.getMainLooper())

    /**
     * Open documents by token. An entry owns its renderer, the descriptor the
     * renderer reads through, and the temp file that descriptor points at.
     */
    private val documents = ConcurrentHashMap<String, OpenPdfDocument>()

    /** Attaches the channel to [engine]. [context] supplies the cache directory. */
    fun register(context: Context, engine: FlutterEngine) {
        val appContext = context.applicationContext
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "open" -> open(appContext, call.argument<ByteArray>("bytes"), result)
                    "renderPage" -> renderPage(call, result)
                    "close" -> close(call.argument<String>("token"), result)
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Copies [bytes] to the cache directory, opens them with [PdfRenderer] and
     * answers the new token with the document's page count.
     *
     * The write and the renderer's read of the document header both touch the
     * disk, so the work runs on a worker thread. Android reports a document
     * that needs a password — and one whose security scheme pdfium does not
     * support — as a [SecurityException], and a document it cannot parse as an
     * [IOException]; running out of memory while loading the page tree is the
     * one honest "this device cannot render this document" answer.
     */
    private fun open(context: Context, bytes: ByteArray?, result: MethodChannel.Result) {
        if (bytes == null || bytes.isEmpty()) {
            result.error("invalid", "bytes argument is required", null)
            return
        }
        val directory = context.cacheDir
        if (directory == null) {
            result.error("failed", "the app has no cache directory to render from", null)
            return
        }
        Thread {
            try {
                val document = openDocument(directory, bytes)
                val count = document.pageCount
                val token = UUID.randomUUID().toString()
                documents[token] = document
                mainHandler.post { result.success(mapOf("token" to token, "count" to count)) }
            } catch (e: SecurityException) {
                postError(result, "password", e.message)
            } catch (e: IOException) {
                postError(result, "invalid", e.message)
            } catch (e: OutOfMemoryError) {
                postError(result, "unsupported", "the document is too large to render on this device")
            } catch (e: Exception) {
                postError(result, "failed", e.message)
            }
        }.start()
    }

    /**
     * Builds one document's file, descriptor and renderer.
     *
     * A failure anywhere before the handle exists deletes the temp file, so a
     * refused document leaves no cache copy behind.
     */
    private fun openDocument(directory: File, bytes: ByteArray): OpenPdfDocument {
        val file = File.createTempFile("dsh-pdf-", ".pdf", directory)
        try {
            file.writeBytes(bytes)
            val descriptor = ParcelFileDescriptor.open(
                file,
                ParcelFileDescriptor.MODE_READ_ONLY,
            )
            val renderer = try {
                PdfRenderer(descriptor)
            } catch (e: Throwable) {
                // The renderer owns the descriptor from construction on; a
                // failed construction is the one place this close is needed.
                closeQuietly(descriptor)
                throw e
            }
            return OpenPdfDocument(renderer, descriptor, file)
        } catch (e: Throwable) {
            file.delete()
            throw e
        }
    }

    /**
     * Renders one page of the document [call] names, answering its PNG bytes
     * and the pixel size they decode to.
     *
     * An unknown token — closed, or from a process that never opened one — and
     * an index outside the document are both `failed`: the Dart seam turns
     * either into that page's retryable state instead of a crash.
     */
    private fun renderPage(call: MethodCall, result: MethodChannel.Result) {
        val token = call.argument<String>("token")
        val index = call.argument<Number>("index")?.toInt()
        val targetWidth = call.argument<Number>("targetWidth")?.toInt() ?: 0
        val maxPixels = call.argument<Number>("maxPixels")?.toLong() ?: 0L
        if (token == null || index == null) {
            result.error("failed", "token and index are required", null)
            return
        }
        val document = documents[token]
        if (document == null) {
            result.error("failed", "the document token is unknown or already closed", null)
            return
        }
        Thread {
            try {
                val page = document.renderPng(index, targetWidth, maxPixels)
                mainHandler.post {
                    result.success(
                        mapOf(
                            "bytes" to page.bytes,
                            "width" to page.width,
                            "height" to page.height,
                        )
                    )
                }
            } catch (e: OutOfMemoryError) {
                postError(result, "unsupported", "the page is too large to render on this device")
            } catch (e: Exception) {
                postError(result, "failed", e.message)
            }
        }.start()
    }

    /**
     * Releases the document [token] names and deletes its temp file. An unknown
     * token succeeds: the only state `close` wants is "this document is gone",
     * which is already true.
     */
    private fun close(token: String?, result: MethodChannel.Result) {
        val document = token?.let(documents::remove)
        if (document == null) {
            result.success(null)
            return
        }
        Thread {
            document.close()
            mainHandler.post { result.success(null) }
        }.start()
    }

    /** Answers [result] with [code] and [message] on the platform thread. */
    private fun postError(result: MethodChannel.Result, code: String, message: String?) {
        mainHandler.post { result.error(code, message, null) }
    }
}

/**
 * One open document: the platform renderer, the descriptor it reads through,
 * and the cache file that descriptor points at.
 *
 * [PdfRenderer] admits one open page at a time and refuses to close while a
 * page is open, so every use of the renderer holds [lock]: a render in flight
 * therefore finishes — and answers — before a close can run under it.
 */
private class OpenPdfDocument(
    private val renderer: PdfRenderer,
    private val descriptor: ParcelFileDescriptor,
    private val file: File,
) {
    private val lock = Any()

    /** The page count the renderer reported when the document was opened. */
    val pageCount: Int get() = renderer.pageCount

    /**
     * Renders page [index] to PNG bytes [targetWidth] pixels wide.
     *
     * The destination bitmap is sized before the render, so pdfium draws the
     * page straight at the size reported back and no full-size bitmap is ever
     * allocated. A page's natural size is its PDF size in points — 72 dpi —
     * which is too coarse for a dense screen, so the bitmap is first sized to
     * [targetWidth] with the page's aspect ratio kept, then shrunk further
     * when that would exceed the [maxPixels] ceiling. Both sides are floored,
     * so the product cannot exceed the budget. A [targetWidth] below one is
     * treated as the natural width, and [maxPixels] is coerced to at least one
     * pixel.
     */
    fun renderPng(index: Int, targetWidth: Int, maxPixels: Long): RenderedPage = synchronized(lock) {
        val page = renderer.openPage(index)
        try {
            val naturalWidth = page.width
            val naturalHeight = page.height
            if (naturalWidth <= 0 || naturalHeight <= 0) {
                throw IOException("page $index reports no size")
            }
            val budget = maxPixels.coerceAtLeast(1L)
            val requested = if (targetWidth >= 1) targetWidth else naturalWidth
            var width = requested
            var height = floor(requested.toDouble() * naturalHeight / naturalWidth)
                .toInt()
                .coerceAtLeast(1)
            val pixels = width.toLong() * height.toLong()
            if (pixels > budget) {
                val scale = sqrt(budget.toDouble() / pixels.toDouble())
                width = floor(width * scale).toInt().coerceAtLeast(1)
                height = floor(height * scale).toInt().coerceAtLeast(1)
            }
            val bitmap = Bitmap.createBitmap(
                width,
                height,
                Bitmap.Config.ARGB_8888,
            )
            try {
                // A null transform fits the whole page into the bitmap, so the
                // render itself performs the scale-down.
                page.render(bitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                val png = ByteArrayOutputStream()
                if (!bitmap.compress(Bitmap.CompressFormat.PNG, 100, png)) {
                    throw IOException("PNG compression failed")
                }
                RenderedPage(png.toByteArray(), width, height)
            } finally {
                bitmap.recycle()
            }
        } finally {
            page.close()
        }
    }

    /** Closes the renderer, its descriptor and the temp file it read. */
    fun close() {
        synchronized(lock) {
            try {
                renderer.close()
            } catch (_: Exception) {}
            closeQuietly(descriptor)
            file.delete()
        }
    }
}

/** One rendered page's PNG bytes and the pixel size they decode to. */
private class RenderedPage(val bytes: ByteArray, val width: Int, val height: Int)

/** Closes [descriptor], ignoring one that is already gone. */
private fun closeQuietly(descriptor: ParcelFileDescriptor) {
    try {
        descriptor.close()
    } catch (_: IOException) {}
}
