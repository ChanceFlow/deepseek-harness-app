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
    this.isDiscontinued = false,
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

  /// A discontinued model no longer offers downloads: it stays listed so an
  /// already-installed copy keeps working (shown, selectable, deletable),
  /// while `AsrModelManager.startDownload` refuses to fetch it again.
  final bool isDiscontinued;

  String repoFor(ModelSource source) => switch (source) {
    ModelSource.hfMirror => huggingFaceRepo,
    ModelSource.huggingFace => huggingFaceRepo,
  };
}

/// Static catalog of officially supported ASR models.
///
/// The lineup is four downloadable models: two offline (SenseVoice-Small,
/// Fun-ASR-Nano 2512 CTC) and two streaming Zipformers (2025 Chinese
/// retrain, eight-language multilingual). Paraformer bilingual and Whisper
/// large-v3-turbo stay listed as discontinued entries so app upgrades never
/// orphan an installed copy.
///
/// Checksums were verified on 2026-09-02 against the Hugging Face LFS
/// metadata (`lfs.sha256` of each file); tokens.txt blobs are stored outside
/// LFS, so their digests were computed from the downloaded bytes. Sizes are
/// the real file sizes, not estimates. Streaming Zipformer exports are
/// k2-fsa/icefall artifacts (Apache-2.0, matching the bilingual repo's
/// license tag).
abstract final class AsrModelManifest {
  /// SenseVoice-Small, 2025-09-09 retrained export. Same architecture and
  /// `OfflineSenseVoiceModelConfig` pipeline as the 2024 model; only the
  /// weights (and this entry's URLs) changed. Installations of the 2024
  /// weights keep running — the id is unchanged — and refresh on the next
  /// delete + re-download.
  static const AsrModelInfo senseVoiceSmall = AsrModelInfo(
    id: 'sensevoice-small',
    name: 'SenseVoice-Small',
    descriptionZh: '多语言极速语音识别（2025 重训版），兼具高准确率与低延迟，支持中/英/粤/日/韩及情绪/事件检测。',
    descriptionEn: 'Ultra-fast multilingual speech recognition (2025 retrain) with high accuracy and low latency.',
    languages: '中 / 英 / 粤 / 日 / 韩',
    estimatedSizeBytes: 237431441,
    license: 'Apache-2.0',
    huggingFaceRepo:
        'csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2025-09-09',
    files: <AsrModelFile>[
      AsrModelFile(
        name: 'model.int8.onnx',
        sizeBytes: 237115547,
        sha256:
            '12ca1a2ae7ecf3e0019ef2822307ee0b5cadc9196569e379b4c4026f8205276d',
        huggingFaceUrl: 'https://huggingface.co/csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2025-09-09/resolve/main/model.int8.onnx',
        hfMirrorUrl: 'https://hf-mirror.com/csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2025-09-09/resolve/main/model.int8.onnx',
      ),
      AsrModelFile(
        name: 'tokens.txt',
        sizeBytes: 315894,
        sha256:
            'f449eb28dc567533d7fa59be34e2abca8784f771850c78a47fb731a31429a1dc',
        huggingFaceUrl: 'https://huggingface.co/csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2025-09-09/resolve/main/tokens.txt',
        hfMirrorUrl: 'https://hf-mirror.com/csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2025-09-09/resolve/main/tokens.txt',
      ),
    ],
  );

  /// Fun-ASR-Nano 2512 (FunAudioLLM), the CTC variant extracted to the
  /// SenseVoice pipeline by upstream (k2-fsa PR #2906): it loads through the
  /// same `OfflineSenseVoiceModelConfig` as [senseVoiceSmall]. Trained for
  /// far-field high-noise pickup, music/lyric interference, seven Chinese
  /// dialects and 26 regional accents with 31-language free mixing.
  static const AsrModelInfo funasrNanoCtc = AsrModelInfo(
    id: 'funasr-nano-ctc',
    name: 'Fun-ASR-Nano 2512 (CTC)',
    descriptionZh:
        'Fun-ASR-Nano 2512 端侧版：7 大方言与 26 种地区口音、31 语种自由混说，远场高噪与歌词识别优化。',
    descriptionEn: 'Fun-ASR-Nano 2512 CTC export: 7 Chinese dialects and 26 regional accents, 31 mixed languages, tuned for far-field noise and lyrics.',
    languages: '中（7 方言 / 26 口音） / 英 / 日 / 31 语种',
    estimatedSizeBytes: 264471717,
    license: 'Apache-2.0',
    huggingFaceRepo:
        'csukuangfj/sherpa-onnx-sense-voice-funasr-nano-int8-2025-12-17',
    files: <AsrModelFile>[
      AsrModelFile(
        name: 'model.int8.onnx',
        sizeBytes: 263531902,
        sha256:
            '9dc6e72aa8bc6f5966cf2857a0ce3a425b1d72e91500e147d66329f407c017a1',
        huggingFaceUrl: 'https://huggingface.co/csukuangfj/sherpa-onnx-sense-voice-funasr-nano-int8-2025-12-17/resolve/main/model.int8.onnx',
        hfMirrorUrl: 'https://hf-mirror.com/csukuangfj/sherpa-onnx-sense-voice-funasr-nano-int8-2025-12-17/resolve/main/model.int8.onnx',
      ),
      AsrModelFile(
        name: 'tokens.txt',
        sizeBytes: 939815,
        sha256:
            '2db4bb25d046e8849e336c9465e248e1694914d996c58c71bdeca18cfb722992',
        huggingFaceUrl: 'https://huggingface.co/csukuangfj/sherpa-onnx-sense-voice-funasr-nano-int8-2025-12-17/resolve/main/tokens.txt',
        hfMirrorUrl: 'https://hf-mirror.com/csukuangfj/sherpa-onnx-sense-voice-funasr-nano-int8-2025-12-17/resolve/main/tokens.txt',
      ),
    ],
  );

  /// Discontinued (2026-09-02) in favor of the 2025-trained streaming
  /// Zipformer: the catalog keeps this entry so installed copies from the
  /// v0.1.0 release stay listed, selectable, and deletable, while downloads
  /// are refused. The engine's Paraformer online-config branch stays for the
  /// same reason.
  static const AsrModelInfo paraformerBilingualStreaming = AsrModelInfo(
    id: 'paraformer-bilingual-streaming',
    name: 'Paraformer Bilingual (Streaming)',
    descriptionZh: '中英双语原生流式语音识别，阿里开源架构，支持边说边出字与中英代码混说。',
    descriptionEn: 'Streaming bilingual Chinese/English ASR by Alibaba FunASR with real-time partial drafts.',
    languages: '中 + 英 (双语流式)',
    estimatedSizeBytes: 237202501,
    license: 'Apache-2.0',
    isStreaming: true,
    isDiscontinued: true,
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

  /// New-generation streaming Zipformer (2025-06-30 retrain), Chinese.
  /// Current best streaming quality for pure-Mandarin input; transducer
  /// decoding through `OnlineTransducerModelConfig`.
  static const AsrModelInfo streamingZipformerZh = AsrModelInfo(
    id: 'streaming-zipformer-zh',
    name: 'Zipformer 中文流式 (2025)',
    descriptionZh: '新一代流式 Zipformer（2025 重训），中文识别当前最强流式选择，边说边出字。',
    descriptionEn: 'New-generation streaming Zipformer (2025 retrain), the strongest current streaming option for Chinese.',
    languages: '中文',
    estimatedSizeBytes: 167660920,
    license: 'Apache-2.0',
    isStreaming: true,
    huggingFaceRepo:
        'csukuangfj/sherpa-onnx-streaming-zipformer-zh-int8-2025-06-30',
    files: <AsrModelFile>[
      AsrModelFile(
        name: 'encoder.int8.onnx',
        sizeBytes: 161141793,
        sha256:
            '5ac51e27981bb4dab01bb9be4958453ba50c3b61c063ddda0eab23fd3671aa4f',
        huggingFaceUrl: 'https://huggingface.co/csukuangfj/sherpa-onnx-streaming-zipformer-zh-int8-2025-06-30/resolve/main/encoder.int8.onnx',
        hfMirrorUrl: 'https://hf-mirror.com/csukuangfj/sherpa-onnx-streaming-zipformer-zh-int8-2025-06-30/resolve/main/encoder.int8.onnx',
      ),
      AsrModelFile(
        name: 'decoder.onnx',
        sizeBytes: 5165083,
        sha256:
            '06522ad63cec0fdf6809f4e1db9bb4f7d710c34582e3b35db62ac60eccafac7e',
        huggingFaceUrl: 'https://huggingface.co/csukuangfj/sherpa-onnx-streaming-zipformer-zh-int8-2025-06-30/resolve/main/decoder.onnx',
        hfMirrorUrl: 'https://hf-mirror.com/csukuangfj/sherpa-onnx-streaming-zipformer-zh-int8-2025-06-30/resolve/main/decoder.onnx',
      ),
      AsrModelFile(
        name: 'joiner.int8.onnx',
        sizeBytes: 1033416,
        sha256:
            'b34584dc6f561089e1d747fedebb3765f2caa72c927ef54d7ca55e5ae40a814b',
        huggingFaceUrl: 'https://huggingface.co/csukuangfj/sherpa-onnx-streaming-zipformer-zh-int8-2025-06-30/resolve/main/joiner.int8.onnx',
        hfMirrorUrl: 'https://hf-mirror.com/csukuangfj/sherpa-onnx-streaming-zipformer-zh-int8-2025-06-30/resolve/main/joiner.int8.onnx',
      ),
      AsrModelFile(
        name: 'tokens.txt',
        sizeBytes: 20628,
        sha256:
            '6193c7ea1c96d0d9a1e9652789b40d13a8a913b434a5451e93158f5a09fd6652',
        huggingFaceUrl: 'https://huggingface.co/csukuangfj/sherpa-onnx-streaming-zipformer-zh-int8-2025-06-30/resolve/main/tokens.txt',
        hfMirrorUrl: 'https://hf-mirror.com/csukuangfj/sherpa-onnx-streaming-zipformer-zh-int8-2025-06-30/resolve/main/tokens.txt',
      ),
    ],
  );

  /// Multilingual streaming Zipformer: eight languages (Arabic, English,
  /// Indonesian, Japanese, Russian, Thai, Vietnamese, Chinese) in one model.
  static const AsrModelInfo streamingZipformerMultilingual = AsrModelInfo(
    id: 'streaming-zipformer-multilingual',
    name: 'Zipformer 多语种流式',
    descriptionZh: '单模型 8 语种流式 Zipformer（中/英/日/泰/越/俄/印尼/阿），一次下载覆盖多语言边说边出字。',
    descriptionEn: 'One-model eight-language streaming Zipformer (zh/en/ja/th/vi/ru/id/ar) with real-time partial drafts.',
    languages: '中 / 英 / 日 / 泰 / 越 / 俄 / 印尼 / 阿',
    estimatedSizeBytes: 338873347,
    license: 'Apache-2.0',
    isStreaming: true,
    huggingFaceRepo: 'csukuangfj/sherpa-onnx-streaming-zipformer-ar_en_id_ja_ru_th_vi_zh-2025-02-10',
    files: <AsrModelFile>[
      AsrModelFile(
        name: 'encoder-epoch-75-avg-11-chunk-16-left-128.int8.onnx',
        sizeBytes: 296583597,
        sha256:
            'f9001ed7a9e46d0294438c1a30cd7c72d1cc4bdd4e7880edbcda36f67081e32e',
        huggingFaceUrl: 'https://huggingface.co/csukuangfj/sherpa-onnx-streaming-zipformer-ar_en_id_ja_ru_th_vi_zh-2025-02-10/resolve/main/encoder-epoch-75-avg-11-chunk-16-left-128.int8.onnx',
        hfMirrorUrl: 'https://hf-mirror.com/csukuangfj/sherpa-onnx-streaming-zipformer-ar_en_id_ja_ru_th_vi_zh-2025-02-10/resolve/main/encoder-epoch-75-avg-11-chunk-16-left-128.int8.onnx',
      ),
      AsrModelFile(
        name: 'decoder-epoch-75-avg-11-chunk-16-left-128.onnx',
        sizeBytes: 33837085,
        sha256:
            '7ebc63f34b21c8efb4a41a5a2eee7fe1448829ce0230ecc5369e67fc14d90d48',
        huggingFaceUrl: 'https://huggingface.co/csukuangfj/sherpa-onnx-streaming-zipformer-ar_en_id_ja_ru_th_vi_zh-2025-02-10/resolve/main/decoder-epoch-75-avg-11-chunk-16-left-128.onnx',
        hfMirrorUrl: 'https://hf-mirror.com/csukuangfj/sherpa-onnx-streaming-zipformer-ar_en_id_ja_ru_th_vi_zh-2025-02-10/resolve/main/decoder-epoch-75-avg-11-chunk-16-left-128.onnx',
      ),
      AsrModelFile(
        name: 'joiner-epoch-75-avg-11-chunk-16-left-128.int8.onnx',
        sizeBytes: 8257421,
        sha256:
            'db88e3172323551abaa99b91b18fb422a27ea4a834fd0db10389f9478816f917',
        huggingFaceUrl: 'https://huggingface.co/csukuangfj/sherpa-onnx-streaming-zipformer-ar_en_id_ja_ru_th_vi_zh-2025-02-10/resolve/main/joiner-epoch-75-avg-11-chunk-16-left-128.int8.onnx',
        hfMirrorUrl: 'https://hf-mirror.com/csukuangfj/sherpa-onnx-streaming-zipformer-ar_en_id_ja_ru_th_vi_zh-2025-02-10/resolve/main/joiner-epoch-75-avg-11-chunk-16-left-128.int8.onnx',
      ),
      AsrModelFile(
        name: 'tokens.txt',
        sizeBytes: 195244,
        sha256:
            '784f24950f6bcce1b0021035632dd60fd4617ecd8ca0581ab57d7b39d77ba5ab',
        huggingFaceUrl: 'https://huggingface.co/csukuangfj/sherpa-onnx-streaming-zipformer-ar_en_id_ja_ru_th_vi_zh-2025-02-10/resolve/main/tokens.txt',
        hfMirrorUrl: 'https://hf-mirror.com/csukuangfj/sherpa-onnx-streaming-zipformer-ar_en_id_ja_ru_th_vi_zh-2025-02-10/resolve/main/tokens.txt',
      ),
    ],
  );

  /// Whisper large-v3-turbo exported by k2-fsa; the HF repo is
  /// `csukuangfj/sherpa-onnx-whisper-turbo` (a `*-large-v3-turbo` repo does
  /// not exist).
  ///
  /// Discontinued (2026-09-02): too heavy for the phones this app targets
  /// and non-streaming. The entry stays in [all] so an installed copy keeps
  /// being listed, selectable, and deletable; downloads are refused.
  static const AsrModelInfo whisperLargeV3Turbo = AsrModelInfo(
    id: 'whisper-large-v3-turbo',
    name: 'Whisper large-v3-turbo',
    descriptionZh: 'OpenAI 顶级大模型端侧量化版，强抗噪鲁棒性，英文第一梯队，中文及多语言识别优秀。',
    descriptionEn: 'Quantized on-device Whisper model with superior noise robustness and multilingual coverage.',
    languages: '英 (第一梯队) / 中 / 多语言',
    estimatedSizeBytes: 1036613791,
    license: 'MIT',
    isDiscontinued: true,
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
    funasrNanoCtc,
    streamingZipformerZh,
    streamingZipformerMultilingual,
    paraformerBilingualStreaming,
    whisperLargeV3Turbo,
  ];

  /// Models a fresh install can download: the catalog minus discontinued
  /// entries that exist only to keep installed copies manageable.
  static List<AsrModelInfo> get downloadable =>
      all.where((AsrModelInfo model) => !model.isDiscontinued).toList();

  static AsrModelInfo? findById(String id) {
    for (final AsrModelInfo model in all) {
      if (model.id == id) return model;
    }
    return null;
  }
}
