/// The on-device ASR runtime (sherpa-onnx + onnxruntime) as a downloadable
/// artifact set.
///
/// The native runtime is the only part of offline speech recognition that a
/// release APK used to carry: the models are already downloaded per model
/// ([AsrModelInfo]), and the runtime is the same bytes for every app version
/// built on the same sherpa-onnx release. Bundling it cost 21.7 MB
/// (`libonnxruntime.so`) plus 4.5 MB (`libsherpa-onnx-c-api.so`) on arm64 —
/// 26.2 MB of a 57.2 MB APK, carried by every install whether or not the user
/// ever turns on offline voice input.
///
/// The release workflows publish one asset per ABI and library, next to the
/// APK they belong to:
///
///     https://…/releases/download/<tag>/asr-runtime-<version>-<abi>-<lib>
///
/// The manifest below pins the bytes: [AsrRuntimeLib.sizeBytes] and
/// [AsrRuntimeLib.sha256] are the **uncompressed** library's facts, which is
/// exactly what the downloader verifies and what the loader maps, so a
/// corrupt or swapped asset cannot reach `dlopen`.
///
/// Bumping `sherpa_onnx` changes every size and hash here; regenerate them
/// from the resolved `sherpa_onnx_android_*` packages (see the decision note
/// `2026-09-11-asr-runtime-on-demand.md`) or the download fails its check.
library;

/// The `sherpa_onnx` release these runtime bytes come from.
///
/// Every library in one download set must come from the same release: the
/// c-api library links against exactly this onnxruntime
/// (`readelf -d` shows `NEEDED libonnxruntime.so`), so a mismatched pair is a
/// loader failure at best and undefined behaviour at worst.
const String kSherpaOnnxVersion = '1.13.6';

/// One native library of the runtime.
final class AsrRuntimeLib {
  const AsrRuntimeLib({
    required this.name,
    required this.sizeBytes,
    required this.sha256,
  });

  /// The library's file name; also the local file name it is written as and
  /// the last path segment of its release asset.
  final String name;

  /// Uncompressed size in bytes, verified by the downloader.
  final int sizeBytes;

  /// Lowercase hex SHA-256 of the uncompressed library, verified by the
  /// downloader.
  final String sha256;

  /// The release asset name for [abi].
  String assetName(String abi) => 'asr-runtime-$kSherpaOnnxVersion-$abi-$name';
}

/// One ABI's runtime: the libraries the loader needs, in load order.
final class AsrRuntimeArtifact {
  const AsrRuntimeArtifact({required this.abi, required this.libs});

  final String abi;

  /// Load order matters: the c-api library needs onnxruntime.
  final List<AsrRuntimeLib> libs;

  AsrRuntimeLib? libNamed(String name) {
    for (final AsrRuntimeLib lib in libs) {
      if (lib.name == name) return lib;
    }
    return null;
  }

  int get totalBytes => libs.fold<int>(0, (sum, lib) => sum + lib.sizeBytes);
}

/// Every ABI the app ships (`flutter build apk` targets exactly these).
///
/// The sizes and hashes are the ones published in
/// `dsh-android-<version>-<abi>.apk`'s build of `sherpa_onnx` 1.13.6.
const Map<String, AsrRuntimeArtifact>
kAsrRuntimeArtifacts = <String, AsrRuntimeArtifact>{
  'arm64-v8a': AsrRuntimeArtifact(
    abi: 'arm64-v8a',
    libs: <AsrRuntimeLib>[
      AsrRuntimeLib(
        name: 'libonnxruntime.so',
        sizeBytes: 21684880,
        sha256:
            'dc5e4c172b1be9e530c6a62ad8f1be3e0a911cabdee6195abf28dab72477e194',
      ),
      AsrRuntimeLib(
        name: 'libsherpa-onnx-c-api.so',
        sizeBytes: 4486984,
        sha256:
            'aebe0700d58b5138d8814f736a9cdf3cdefbe7ce2819e81f3ebb704140f26f5d',
      ),
    ],
  ),
  'armeabi-v7a': AsrRuntimeArtifact(
    abi: 'armeabi-v7a',
    libs: <AsrRuntimeLib>[
      AsrRuntimeLib(
        name: 'libonnxruntime.so',
        sizeBytes: 15027384,
        sha256:
            '0866987761e134b2e598875839967832db015f5fc1c363b9d11d882a6604bb04',
      ),
      AsrRuntimeLib(
        name: 'libsherpa-onnx-c-api.so',
        sizeBytes: 3193472,
        sha256:
            'c42ed5d933e27b3ce6e1245caeef9018adaabfddd991cc15909877c140b8891a',
      ),
    ],
  ),
  'x86_64': AsrRuntimeArtifact(
    abi: 'x86_64',
    libs: <AsrRuntimeLib>[
      AsrRuntimeLib(
        name: 'libonnxruntime.so',
        sizeBytes: 25000416,
        sha256:
            'b2e0b6b0ffde094837df455d6e67b865dc4f7bf246b976ad4687a5220211f751',
      ),
      AsrRuntimeLib(
        name: 'libsherpa-onnx-c-api.so',
        sizeBytes: 4984824,
        sha256:
            'f82eac5a82b19b95b190a674bc673ee752bec203a8fb64398c9a5b4aa7563a17',
      ),
    ],
  ),
};

/// The runtime artifact for [abi], or null on an ABI this app does not ship.
AsrRuntimeArtifact? asrRuntimeArtifactFor(String abi) =>
    kAsrRuntimeArtifacts[abi];
