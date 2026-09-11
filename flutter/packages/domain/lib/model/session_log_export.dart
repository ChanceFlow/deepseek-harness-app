/// One downloaded session-log archive, in the neutral vocabulary: the
/// archive bytes plus the filename the host's `content-disposition` names
/// for it. Where the bytes land is the platform layer's decision, not this
/// model's.
library;

import 'dart:typed_data';

/// A complete session-log ZIP held in memory and ready to be written out.
final class SessionLogExport {
  const SessionLogExport({required this.filename, required this.bytes});

  /// The suggested on-disk name, already sanitized by the adapter against
  /// the untrusted session id (the host's own `dsh-session-<id>.zip`).
  final String filename;

  /// The archive bytes, exactly as the host streamed them.
  final Uint8List bytes;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SessionLogExport &&
          other.filename == filename &&
          _bytesEqual(other.bytes, bytes));

  @override
  int get hashCode => Object.hash(filename, Object.hashAll(bytes));
}

bool _bytesEqual(Uint8List left, Uint8List right) {
  if (identical(left, right)) return true;
  if (left.length != right.length) return false;
  for (var i = 0; i < left.length; i++) {
    if (left[i] != right[i]) return false;
  }
  return true;
}
