/// Static manifest for on-device ASR models.
library;

/// Available download sources for ASR models.
///
/// Both sources serve the same bytes: the global Hugging Face hub and its
/// official China mirror (hf-mirror.com). ModelScope was removed because it
/// mirrors none of the sherpa-onnx ONNX packages used here.
enum ModelSource {
  hfMirror('hf-mirror', 'HF Mirror'),
  huggingFace('huggingface', 'Hugging Face');

  const ModelSource(this.id, this.label);

  final String id;
  final String label;

  static ModelSource fromId(String id) {
    for (final ModelSource source in ModelSource.values) {
      if (source.id == id) return source;
    }
    // Legacy registries may carry 'modelscope'; treat it as the China
    // mirror, which is what it used to represent.
    return ModelSource.hfMirror;
  }
}

/// A specific file within an ASR model distribution.
class AsrModelFile {
  const AsrModelFile({
    required this.name,
    required this.sizeBytes,
    required this.sha256,
    required this.huggingFaceUrl,
    required this.hfMirrorUrl,
  });

  /// The local relative filename (e.g. 'model.int8.onnx', 'tokens.txt').
  final String name;

  /// Expected file size in bytes.
  final int sizeBytes;

  /// SHA-256 checksum in lowercase hex.
  ///
  /// Empty means the checksum is not yet provisioned: the downloader then
  /// verifies the file size only. Once a real checksum lands here, the
  /// downloader upgrades to full content verification automatically.
  final String sha256;

  /// Direct download URL from Hugging Face.
  final String huggingFaceUrl;

  /// Direct download URL from the official Hugging Face China mirror.
  final String hfMirrorUrl;

  /// Resolves the URL for the specified source.
  String urlFor(ModelSource source) => switch (source) {
    ModelSource.hfMirror => hfMirrorUrl,
    ModelSource.huggingFace => huggingFaceUrl,
  };
}

/// Metadata and file specification for an on-device ASR model.
class AsrModelInfo {
  const AsrModelInfo({
    required this.id,
    required this.name,
    required this.descriptionZh,
    required this.descriptionEn,
    required this.languages,
    required this.estimatedSizeBytes,
    required this.license,
    required this.huggingFaceRepo,
    required this.files,
    this.isStreaming = false,
  });

  final String id;
  final String name;
  final String descriptionZh;
  final String descriptionEn;
  final String languages;
  final int estimatedSizeBytes;
  final String license;
  final String huggingFaceRepo;
  final List<AsrModelFile> files;
  final bool isStreaming;

  String repoFor(ModelSource source) => switch (source) {
    ModelSource.hfMirror => huggingFaceRepo,
    ModelSource.huggingFace => huggingFaceRepo,
  };
}

/// Static catalog of officially supported ASR models.
///
/// Checksums were verified on 2026-08-25 against both the Hugging Face LFS
/// metadata (the `lfs.oid` of each file) and ModelScope's own sha256 column
/// (which matched byte-for-byte) before ModelScope was removed. Sizes are
/// the real file sizes, not estimates.
abstract final class AsrModelManifest {
  static const AsrModelInfo senseVoiceSmall = AsrModelInfo(
    id: 'sensevoice-small',
    name: 'SenseVoice-Small',
    descriptionZh: '多语言极速语音识别，兼具高准确率与低延迟，支持中/英/粤/日/韩及情绪/事件检测。',
    descriptionEn: 'Ultra-fast multilingual speech recognition with high accuracy and low latency.',
    languages: '中 / 英 / 粤 / 日 / 韩',
    estimatedSizeBytes: 239549735,
    license: 'Apache-2.0',
    huggingFaceRepo:
        'csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17',
    files: <AsrModelFile>[
      AsrModelFile(
        name: 'model.int8.onnx',
        sizeBytes: 239233841,
        sha256:
            'c71f0ce00bec95b07744e116345e33d8cbbe08cef896382cf907bf4b51a2cd51',
        huggingFaceUrl: 'https://huggingface.co/csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17/resolve/main/model.int8.onnx',
        hfMirrorUrl: 'https://hf-mirror.com/csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17/resolve/main/model.int8.onnx',
      ),
      AsrModelFile(
        name: 'tokens.txt',
        sizeBytes: 315894,
        sha256:
            'f449eb28dc567533d7fa59be34e2abca8784f771850c78a47fb731a31429a1dc',
        huggingFaceUrl: 'https://huggingface.co/csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17/resolve/main/tokens.txt',
        hfMirrorUrl: 'https://hf-mirror.com/csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17/resolve/main/tokens.txt',
      ),
    ],
  );

  static const AsrModelInfo paraformerBilingualStreaming = AsrModelInfo(
    id: 'paraformer-bilingual-streaming',
    name: 'Paraformer Bilingual (Streaming)',
    descriptionZh: '中英双语原生流式语音识别，阿里开源架构，支持边说边出字与中英代码混说。',
    descriptionEn: 'Streaming bilingual Chinese/English ASR by Alibaba FunASR with real-time partial drafts.',
    languages: '中 + 英 (双语流式)',
    estimatedSizeBytes: 237202501,
    license: 'Apache-2.0',
    isStreaming: true,
    huggingFaceRepo:
        'csukuangfj/sherpa-onnx-streaming-paraformer-bilingual-zh-en',
    files: <AsrModelFile>[
      AsrModelFile(
        name: 'encoder.int8.onnx',
        sizeBytes: 165462184,
        sha256:
            '81a70226a8934e6ed92aa1d4fc486b428b5398e2f2619ed4897b7294cab90e9a',
        huggingFaceUrl: 'https://huggingface.co/csukuangfj/sherpa-onnx-streaming-paraformer-bilingual-zh-en/resolve/main/encoder.int8.onnx',
        hfMirrorUrl: 'https://hf-mirror.com/csukuangfj/sherpa-onnx-streaming-paraformer-bilingual-zh-en/resolve/main/encoder.int8.onnx',
      ),
      AsrModelFile(
        name: 'decoder.int8.onnx',
        sizeBytes: 71664561,
        sha256:
            'f3cca9f77bb9d93c8fcbfb63ae617b6b1ee96818df3aa3b151c40658fe38594f',
        huggingFaceUrl: 'https://huggingface.co/csukuangfj/sherpa-onnx-streaming-paraformer-bilingual-zh-en/resolve/main/decoder.int8.onnx',
        hfMirrorUrl: 'https://hf-mirror.com/csukuangfj/sherpa-onnx-streaming-paraformer-bilingual-zh-en/resolve/main/decoder.int8.onnx',
      ),
      AsrModelFile(
        name: 'tokens.txt',
        sizeBytes: 75756,
        sha256:
            '59aba8873a2ed1e122c25fee421e25f283b63290efbde85c1f01a853d83cb6e6',
        huggingFaceUrl: 'https://huggingface.co/csukuangfj/sherpa-onnx-streaming-paraformer-bilingual-zh-en/resolve/main/tokens.txt',
        hfMirrorUrl: 'https://hf-mirror.com/csukuangfj/sherpa-onnx-streaming-paraformer-bilingual-zh-en/resolve/main/tokens.txt',
      ),
    ],
  );

  /// Whisper large-v3-turbo exported by k2-fsa; the HF repo is
  /// `csukuangfj/sherpa-onnx-whisper-turbo` (a `*-large-v3-turbo` repo does
  /// not exist).
  static const AsrModelInfo whisperLargeV3Turbo = AsrModelInfo(
    id: 'whisper-large-v3-turbo',
    name: 'Whisper large-v3-turbo',
    descriptionZh: 'OpenAI 顶级大模型端侧量化版，强抗噪鲁棒性，英文第一梯队，中文及多语言识别优秀。',
    descriptionEn: 'Quantized on-device Whisper model with superior noise robustness and multilingual coverage.',
    languages: '英 (第一梯队) / 中 / 多语言',
    estimatedSizeBytes: 1036613791,
    license: 'MIT',
    huggingFaceRepo: 'csukuangfj/sherpa-onnx-whisper-turbo',
    files: <AsrModelFile>[
      AsrModelFile(
        name: 'turbo-encoder.int8.onnx',
        sizeBytes: 674716297,
        sha256:
            'b02dcdf54f348741e93fe732b67d933c8dcb6735655f710640143081db38878b',
        huggingFaceUrl: 'https://huggingface.co/csukuangfj/sherpa-onnx-whisper-turbo/resolve/main/turbo-encoder.int8.onnx',
        hfMirrorUrl: 'https://hf-mirror.com/csukuangfj/sherpa-onnx-whisper-turbo/resolve/main/turbo-encoder.int8.onnx',
      ),
      AsrModelFile(
        name: 'turbo-decoder.int8.onnx',
        sizeBytes: 361080764,
        sha256:
            '20accd02388482eb3a46bd615631adfdc85e1eb2c7db9ea3f02a40ffe6b81547',
        huggingFaceUrl: 'https://huggingface.co/csukuangfj/sherpa-onnx-whisper-turbo/resolve/main/turbo-decoder.int8.onnx',
        hfMirrorUrl: 'https://hf-mirror.com/csukuangfj/sherpa-onnx-whisper-turbo/resolve/main/turbo-decoder.int8.onnx',
      ),
      AsrModelFile(
        name: 'turbo-tokens.txt',
        sizeBytes: 816730,
        sha256:
            'b34b360dbb493e781e479794586d661700670d65564001f23024971d1f2fa126',
        huggingFaceUrl: 'https://huggingface.co/csukuangfj/sherpa-onnx-whisper-turbo/resolve/main/turbo-tokens.txt',
        hfMirrorUrl: 'https://hf-mirror.com/csukuangfj/sherpa-onnx-whisper-turbo/resolve/main/turbo-tokens.txt',
      ),
    ],
  );

  static const List<AsrModelInfo> all = <AsrModelInfo>[
    senseVoiceSmall,
    paraformerBilingualStreaming,
    whisperLargeV3Turbo,
  ];

  static AsrModelInfo? findById(String id) {
    for (final AsrModelInfo model in all) {
      if (model.id == id) return model;
    }
    return null;
  }
}
