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
    huggingFaceRepo: 'csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17',
    files: <AsrModelFile>[
      AsrModelFile(
        name: 'model.int8.onnx',
        sizeBytes: 239233841,
        sha256: 'c71f0ce00bec95b07744e116345e33d8cbbe08cef896382cf907bf4b51a2cd51',
        huggingFaceUrl: 'https://huggingface.co/csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17/resolve/main/model.int8.onnx',
        hfMirrorUrl: 'https://hf-mirror.com/csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17/resolve/main/model.int8.onnx',
      ),
      AsrModelFile(
        name: 'tokens.txt',
        sizeBytes: 315894,
        sha256: 'f449eb28dc567533d7fa59be34e2abca8784f771850c78a47fb731a31429a1dc',
        huggingFaceUrl: 'https://huggingface.co/csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17/resolve/main/tokens.txt',
        hfMirrorUrl: 'https://hf-mirror.com/csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17/resolve/main/tokens.txt',
      ),
    ],
  );

  static const AsrModelInfo zipformerBilingual = AsrModelInfo(
    id: 'zipformer-bilingual',
    name: 'Zipformer Bilingual (Streaming)',
    descriptionZh: '中英混合流式语音识别，专为移动端低延迟实时听写优化，支持代码混杂交替输入。',
    descriptionEn: 'Streaming bilingual Chinese/English ASR optimized for real-time mobile dictation.',
    languages: '中 + 英 (代码混合)',
    estimatedSizeBytes: 198459312,
    license: 'Apache-2.0',
    huggingFaceRepo: 'csukuangfj/sherpa-onnx-streaming-zipformer-bilingual-zh-en-2023-02-20',
    files: <AsrModelFile>[
      AsrModelFile(
        name: 'encoder-epoch-99-avg-1.int8.onnx',
        sizeBytes: 181895032,
        sha256: '8fa764187a261844f859d7143ebaa563af5d10adfece4c18a8f414c88cba2a9b',
        huggingFaceUrl: 'https://huggingface.co/csukuangfj/sherpa-onnx-streaming-zipformer-bilingual-zh-en-2023-02-20/resolve/main/encoder-epoch-99-avg-1.int8.onnx',
        hfMirrorUrl: 'https://hf-mirror.com/csukuangfj/sherpa-onnx-streaming-zipformer-bilingual-zh-en-2023-02-20/resolve/main/encoder-epoch-99-avg-1.int8.onnx',
      ),
      AsrModelFile(
        name: 'decoder-epoch-99-avg-1.int8.onnx',
        sizeBytes: 13091040,
        sha256: '1a70c593d71e53f023f5f55b0b4cfff5055abb786ee3992e5f63dc2e273cc4fa',
        huggingFaceUrl: 'https://huggingface.co/csukuangfj/sherpa-onnx-streaming-zipformer-bilingual-zh-en-2023-02-20/resolve/main/decoder-epoch-99-avg-1.int8.onnx',
        hfMirrorUrl: 'https://hf-mirror.com/csukuangfj/sherpa-onnx-streaming-zipformer-bilingual-zh-en-2023-02-20/resolve/main/decoder-epoch-99-avg-1.int8.onnx',
      ),
      AsrModelFile(
        name: 'joiner-epoch-99-avg-1.int8.onnx',
        sizeBytes: 3228404,
        sha256: '1ed689c5ed19dbaa725d9d191bb4822b5f4855a39e1ffd28cbc1f340d25b2ee0',
        huggingFaceUrl: 'https://huggingface.co/csukuangfj/sherpa-onnx-streaming-zipformer-bilingual-zh-en-2023-02-20/resolve/main/joiner-epoch-99-avg-1.int8.onnx',
        hfMirrorUrl: 'https://hf-mirror.com/csukuangfj/sherpa-onnx-streaming-zipformer-bilingual-zh-en-2023-02-20/resolve/main/joiner-epoch-99-avg-1.int8.onnx',
      ),
      // BPE tokenizer — the streaming zipformer decoder reads this file,
      // not tokens.txt.
      AsrModelFile(
        name: 'bpe.model',
        sizeBytes: 244836,
        sha256: 'bcae393dbc5611be5ffa4c7ae0841558978a5a4f484008cb9dff3a2cc97ebe01',
        huggingFaceUrl: 'https://huggingface.co/csukuangfj/sherpa-onnx-streaming-zipformer-bilingual-zh-en-2023-02-20/resolve/main/bpe.model',
        hfMirrorUrl: 'https://hf-mirror.com/csukuangfj/sherpa-onnx-streaming-zipformer-bilingual-zh-en-2023-02-20/resolve/main/bpe.model',
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
        sha256: 'b02dcdf54f348741e93fe732b67d933c8dcb6735655f710640143081db38878b',
        huggingFaceUrl: 'https://huggingface.co/csukuangfj/sherpa-onnx-whisper-turbo/resolve/main/turbo-encoder.int8.onnx',
        hfMirrorUrl: 'https://hf-mirror.com/csukuangfj/sherpa-onnx-whisper-turbo/resolve/main/turbo-encoder.int8.onnx',
      ),
      AsrModelFile(
        name: 'turbo-decoder.int8.onnx',
        sizeBytes: 361080764,
        sha256: '20accd02388482eb3a46bd615631adfdc85e1eb2c7db9ea3f02a40ffe6b81547',
        huggingFaceUrl: 'https://huggingface.co/csukuangfj/sherpa-onnx-whisper-turbo/resolve/main/turbo-decoder.int8.onnx',
        hfMirrorUrl: 'https://hf-mirror.com/csukuangfj/sherpa-onnx-whisper-turbo/resolve/main/turbo-decoder.int8.onnx',
      ),
      AsrModelFile(
        name: 'turbo-tokens.txt',
        sizeBytes: 816730,
        sha256: 'b34b360dbb493e781e479794586d661700670d65564001f23024971d1f2fa126',
        huggingFaceUrl: 'https://huggingface.co/csukuangfj/sherpa-onnx-whisper-turbo/resolve/main/turbo-tokens.txt',
        hfMirrorUrl: 'https://hf-mirror.com/csukuangfj/sherpa-onnx-whisper-turbo/resolve/main/turbo-tokens.txt',
      ),
    ],
  );

  static const List<AsrModelInfo> all = <AsrModelInfo>[
    senseVoiceSmall,
    zipformerBilingual,
    whisperLargeV3Turbo,
  ];

  static AsrModelInfo? findById(String id) {
    for (final AsrModelInfo model in all) {
      if (model.id == id) return model;
    }
    return null;
  }
}