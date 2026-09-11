/// Platform bridge that writes a downloaded session-log archive where the
/// user can find it.
///
/// Android has no writable, user-visible directory a plain Dart `File` can
/// address on API 29+: the shared Downloads collection is owned by
/// MediaStore, and the app-specific external directory is invisible to most
/// file managers. The native side therefore performs the write — a
/// `MediaStore.Downloads` insert on API 29+, and the app-specific
/// `Download` directory on API 24-28 where MediaStore inserts into the
/// public collection would need `WRITE_EXTERNAL_STORAGE` — and returns the
/// location it wrote to.
library;

import 'package:flutter/services.dart';

/// Method channel name; must match `MainActivity.kt`.
const String kSessionLogExportChannel = 'dsh/session_log_export';

/// The save failed on the host: no channel (widget tests, unsupported
/// hosts), a rejected argument, or a filesystem/MediaStore error.
class SessionLogSaveException implements Exception {
  const SessionLogSaveException(this.message);

  final String message;

  @override
  String toString() => 'SessionLogSaveException: $message';
}

/// Writes [bytes] as [filename] into the user's Downloads collection and
/// returns the location a person can act on (for example
/// `Download/dsh-session-<id>.zip`, or an absolute path on API 24-28).
///
/// Throws [SessionLogSaveException] when the archive did not land.
Future<String> saveSessionLogZip({
  required String filename,
  required Uint8List bytes,
}) async {
  const MethodChannel channel = MethodChannel(kSessionLogExportChannel);
  final Object? location;
  try {
    location = await channel.invokeMethod<String>(
      'saveToDownloads',
      <String, Object>{'filename': filename, 'bytes': bytes},
    );
  } on MissingPluginException {
    throw const SessionLogSaveException('no session-log save channel');
  } on PlatformException catch (error) {
    throw SessionLogSaveException(error.message ?? error.code);
  }
  if (location is! String || location.isEmpty) {
    throw const SessionLogSaveException('the host reported no location');
  }
  return location;
}

/// The save step a chat controller performs after a successful download.
/// Injected so tests drive the outcome without a platform channel.
typedef SessionLogSaver = Future<String> Function({
  required String filename,
  required Uint8List bytes,
});
