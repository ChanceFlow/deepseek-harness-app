/// Platform bridge for real disk-space queries.
///
/// Android exposes free bytes through `StatFs` via the `dsh/disk_space`
/// method channel registered in `MainActivity`. Where no host plugin is
/// registered (widget tests, unsupported hosts), the call falls back to a
/// documented generous default so the ASR pre-flight check keeps a value
/// instead of crashing — such environments cannot download anyway.
library;

import 'package:flutter/services.dart';

/// Method channel name; must match `MainActivity.kt`.
const String kDiskSpaceChannel = 'dsh/disk_space';

/// Documented fallback when no host implements the channel: 10 GiB.
const int kDiskSpaceFallbackBytes = 10 * 1024 * 1024 * 1024;

/// Available free bytes on the filesystem containing [path].
///
/// On Android this is `StatFs(path).availableBytes`; a missing or failing
/// channel returns [kDiskSpaceFallbackBytes].
Future<int> freeDiskSpaceBytes(String path) async {
  const MethodChannel channel = MethodChannel(kDiskSpaceChannel);
  try {
    final Object? free = await channel.invokeMethod<int>(
      'availableBytes',
      <String, Object>{'path': path},
    );
    if (free is int && free > 0) return free;
    return kDiskSpaceFallbackBytes;
  } on MissingPluginException {
    return kDiskSpaceFallbackBytes;
  } on PlatformException {
    return kDiskSpaceFallbackBytes;
  }
}
