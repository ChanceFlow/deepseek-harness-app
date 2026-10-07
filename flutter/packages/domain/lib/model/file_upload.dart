/// Composer file-attachment vocabulary for the host's staged file upload
/// (`fileUploads/upload`). Files are stored verbatim — no normalization, no
/// image limits — and the prompt cites the staged receipt instead of bytes.
library;

/// The phone's own bound for one unary upload.
///
/// The Host stores verbatim files without an admission limit
/// (`reference/deepseek-harness/packages/attachment/attachment/src/index.ts`
/// `saveFile`), so this cap is the client's: the base64 body, its decoded
/// copy, and the JSON envelope are resident together while the call runs, and
/// the raw-byte route the reference client uses for blobs is not wired here.
abstract final class FileUploadLimits {
  static const int maxFileBytes = 8 * 1024 * 1024;
}

/// One durable file the Host stored and staged under a session's agent scope.
final class UploadedFile {
  const UploadedFile({
    required this.receiptId,
    required this.attachmentId,
    required this.name,
    required this.byteSize,
  });

  /// Per-upload authority a prompt cites (`{type: 'file', receiptId}`); the
  /// Host accepts it only inside the session that uploaded it.
  final String receiptId;

  /// Content-addressed durable identity — the sha256 digest of the exact
  /// submitted bytes.
  final String attachmentId;

  /// Host-sanitized display name.
  final String name;

  /// Exact byte length of the stored file.
  final int byteSize;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is UploadedFile &&
          other.receiptId == receiptId &&
          other.attachmentId == attachmentId &&
          other.name == name &&
          other.byteSize == byteSize);

  @override
  int get hashCode => Object.hash(receiptId, attachmentId, name, byteSize);
}

/// Where one composer file attachment is in its Host upload.
enum PendingFileStatus {
  /// The `fileUploads/upload` call is in flight.
  uploading,

  /// The Host staged the file; its receipt is ready for the next prompt.
  ready,

  /// The upload failed; [PendingFile.failureReason] states why.
  failed,
}

/// One file the reader attached to the composer, with its upload state.
///
/// The draft survives a failed upload: the row stays in the composer strip
/// with its reason, and only an explicit remove clears it.
final class PendingFile {
  const PendingFile({
    required this.id,
    required this.name,
    required this.byteSize,
    this.status = PendingFileStatus.uploading,
    this.upload,
    this.failureReason,
  });

  /// Client-minted draft identity (the picker's own handle for the file).
  final String id;

  /// Display name the reader picked.
  final String name;

  /// Exact byte length of the local file.
  final int byteSize;

  final PendingFileStatus status;

  /// The staged receipt once [status] is [PendingFileStatus.ready].
  final UploadedFile? upload;

  /// The Host failure (`code: message`) once [status] is
  /// [PendingFileStatus.failed]; null otherwise.
  final String? failureReason;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PendingFile &&
          other.id == id &&
          other.name == name &&
          other.byteSize == byteSize &&
          other.status == status &&
          other.upload == upload &&
          other.failureReason == failureReason);

  @override
  int get hashCode =>
      Object.hash(id, name, byteSize, status, upload, failureReason);
}
