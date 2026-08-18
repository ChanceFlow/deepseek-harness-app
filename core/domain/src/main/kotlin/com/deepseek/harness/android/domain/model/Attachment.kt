package com.deepseek.harness.android.domain.model

/**
 * Image-attachment vocabulary for the version-one path. Raster images ride
 * the prompt wire as inline content parts; durable references come back in
 * the session log and download through `session.attachment`.
 */

/** One composer-held image awaiting send, encoded as base64. */
data class PendingImage(
    val id: String,
    val mediaType: String,
    val base64Data: String,
    val name: String? = null,
    val byteSize: Long = 0L,
)

/** Durable image reference found inside a message's content blocks. */
data class AttachmentRef(
    val attachmentId: String,
    val mediaType: String,
    val bytes: Long,
    val width: Int,
    val height: Int,
    val name: String? = null,
)

/** One downloaded image: its durable reference plus decoded bytes. */
class AttachmentData(
    val ref: AttachmentRef,
    val data: ByteArray,
) {
    override fun equals(other: Any?): Boolean =
        other is AttachmentData && other.ref == ref && other.data.contentEquals(data)

    override fun hashCode(): Int = ref.hashCode() * 31 + data.contentHashCode()
}

/**
 * Host admission limits for images, mirrored from the `imageLimits`
 * session projection. Null fields fall back to client-side defaults until
 * the host projection arrives.
 */
data class ImageLimits(
    val maxImageBytes: Long = DEFAULT_MAX_IMAGE_BYTES,
    val maxImagesPerMessage: Int = DEFAULT_MAX_IMAGES_PER_MESSAGE,
    val maxMessageImageBytes: Long = DEFAULT_MAX_IMAGE_BYTES,
    val maxImagePixels: Long = DEFAULT_MAX_IMAGE_PIXELS,
    val mediaTypes: List<String> = DEFAULT_MEDIA_TYPES,
) {
    companion object {
        const val DEFAULT_MAX_IMAGE_BYTES: Long = 5L * 1024 * 1024
        const val DEFAULT_MAX_IMAGES_PER_MESSAGE: Int = 20
        const val DEFAULT_MAX_IMAGE_PIXELS: Long = 30_000_000L
        val DEFAULT_MEDIA_TYPES: List<String> = listOf(
            "image/png",
            "image/jpeg",
            "image/webp",
            "image/gif",
        )
    }
}
