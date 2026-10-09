/// One durable attachment read's outcome, and why it can be refused.
///
/// The Host refuses a read whose attachment no command of *that session*
/// referenced — `session/attachment-invalid`, reason `ATTACHMENT_NOT_REFERENCED`
/// (`reference/deepseek-harness/packages/api/session-controller/tests/
/// commands-queue-attachment.host.spec.ts:389`, `:427`; the sibling reason is
/// `FILE_NOT_STAGED`, `commands-upload-file.host.spec.ts:219`).
///
/// The reference is the **Host's** to create, from a command it admitted, and
/// this client has no RPC that mints one: `session/attachment` only reads
/// (`rpc_map.dart:25`) and `fileUploads/upload` only stages (`:173`). That makes
/// the refusal a state to explain, not a fault to retry — and it is a wire
/// fact, not an omission, so no ordering change here can prevent it.
library;

import 'dart:typed_data';

import 'package:domain/model/attachment.dart';

/// The Host's business code for a refused attachment read
/// (`session/attachment-invalid`).
const String kAttachmentInvalidCode = 'session/attachment-invalid';

/// Why a durable attachment could not be read.
enum AttachmentReadFailure {
  /// The Host's rule: the attachment is not part of the session we asked.
  notReferenced,

  /// Anything else — transport, decode, an unknown Host error.
  unavailable,
}

/// What one attachment read produced: its bytes, or why they are absent.
final class AttachmentRead {
  const AttachmentRead.ready(this.bytes) : failure = null;
  const AttachmentRead.failed(this.failure) : bytes = null;

  final Uint8List? bytes;
  final AttachmentReadFailure? failure;

  bool get hasBytes => bytes != null;
}

/// Decodes one durable attachment lazily; a failure names which kind it was.
typedef AttachmentLoader = Future<AttachmentRead> Function(
  String sessionId,
  AttachmentRef ref,
);
