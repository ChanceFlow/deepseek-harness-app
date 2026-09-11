/// The device's ABI(s), for picking the matching downloadable ASR runtime.
///
/// The runtime libraries are per-ABI and are no longer in the APK
/// (`AsrRuntimeManager`), so the download must match the installed build.
/// The platform side filters the device's ABIs to the class this process runs
/// (`Process.is64Bit`), so a 32-bit build on a 64-bit device never fetches the
/// 64-bit libraries; the unfiltered list follows as the fallback.
library;

import 'package:flutter/services.dart';

/// Channel owned by `MainActivity` (`dsh/device`).
const String kDeviceChannel = 'dsh/device';

/// ABI names in priority order (installed build first, then the device's).
///
/// Empty when the platform side is absent (tests, desktop): the caller then
/// treats the runtime as unavailable rather than guessing an ABI and
/// downloading libraries this device cannot map.
Future<List<String>> deviceAbis({MethodChannel? channel}) async {
  final MethodChannel methodChannel =
      channel ?? const MethodChannel(kDeviceChannel);
  try {
    final List<Object?>? abis = await methodChannel.invokeMethod<List<Object?>>(
      'abis',
    );
    if (abis == null) return const <String>[];
    return <String>[
      for (final Object? abi in abis)
        if (abi is String && abi.isNotEmpty) abi,
    ];
  } on PlatformException {
    return const <String>[];
  } on MissingPluginException {
    return const <String>[];
  }
}
