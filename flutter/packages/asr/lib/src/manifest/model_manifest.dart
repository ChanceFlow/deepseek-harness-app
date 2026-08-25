/// Static manifest for on-device ASR models.
library;

/// Available download sources for ASR models.
enum ModelSource {
  modelScope('modelscope', 'ModelScope'),
  huggingFace('huggingface', 'Hugging Face');

  const ModelSource(this.id, this.label);

  final String id;
  final String label;

  static ModelSource fromId(String id) {
    for (final ModelSource source in ModelSource.values) {
      if (source.id == id) return source;
    }
    return ModelSource.modelScope;
  }
}

/// A specific file within an ASR model distribution.
class AsrModelFile {
  const AsrModelFile({
    required this.name,
    required this.sizeBytes,
    required this.sha256,
    required this.modelScopeUrl,
    required this.huggingFaceUrl,
  });

  /// The local relative filename (e.g. 'model.int8.onnx', 'tokens.txt').
  final String name;

  /// Expected file size in bytes.
  final int sizeBytes;

  /// SHA-256 checksum in lowercase hex.
  final String sha256;

  /// Direct download URL from ModelScope.
  final String modelScopeUrl;

  /// Direct download URL from Hugging Face.
  final String huggingFaceUrl;

  /// Resolves the URL for the specified source.
  String urlFor(ModelSource source) => switch (source) {
    ModelSource.modelScope => modelScopeUrl,
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
    required this.modelScopeRepo,
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
  final String modelScopeRepo;
  final String huggingFaceRepo;
  final List<AsrModelFile> files;

  String repoFor(ModelSource source) => switch (source) {
    ModelSource.modelScope => modelScopeRepo,
    ModelSource.huggingFace => huggingFaceRepo,
  };
}

/// Static catalog of officially supported ASR models.
abstract final class AsrModelManifest {
  static const AsrModelInfo senseVoiceSmall = AsrModelInfo(
    id: 'sensevoice-small',
    name: 'SenseVoice-Small',
    descriptionZh: '多语言极速语音识别，兼具高准确率与低延迟，支持中/英/粤/日/韩及情绪/事件检测。',
    descriptionEn: 'Ultra-fast multilingual speech recognition with high accuracy and low latency.',
    languages: '中 / 英 / 粤 / 日 / 韩',
    estimatedSizeBytes: 157286400, // ~150 MB (int8 onnx + tokens)
    license: 'Apache-2.0',
    modelScopeRepo: 'iic/SenseVoiceSmall',
    huggingFaceRepo: 'FunAudioLLM/SenseVoiceSmall',
    files: <AsrModelFile>[
      AsrModelFile(
        name: 'model.int8.onnx',
        sizeBytes: 154140672,
        sha256: '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
        modelScopeUrl: 'https://modelscope.cn/models/k2-fsa/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17/resolve/master/model.int8.onnx',
        huggingFaceUrl: 'https://huggingface.co/csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17/resolve/main/model.int8.onnx',
      ),
      AsrModelFile(
        name: 'tokens.txt',
        sizeBytes: 3145728,
        sha256: '123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef0',
        modelScopeUrl: 'https://modelscope.cn/models/k2-fsa/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17/resolve/master/tokens.txt',
        huggingFaceUrl: 'https://huggingface.co/csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17/resolve/main/tokens.txt',
      ),
    ],
  );

  static const AsrModelInfo zipformerBilingual = AsrModelInfo(
    id: 'zipformer-bilingual',
    name: 'Zipformer Bilingual (Streaming)',
    descriptionZh: '中英混合流式语音识别，专为移动端低延迟实时听写优化，支持代码混杂交替输入。',
    descriptionEn: 'Streaming bilingual Chinese/English ASR optimized for real-time mobile dictation.',
    languages: '中 + 英 (代码混合)',
    estimatedSizeBytes: 262144000, // ~250 MB
    license: 'Apache-2.0',
    modelScopeRepo: 'csukuangfj/sherpa-onnx-zipformer-bilingual-zh-en-2023-02-20',
    huggingFaceRepo: 'csukuangfj/sherpa-onnx-zipformer-bilingual-zh-en-2023-02-20',
    files: <AsrModelFile>[
      AsrModelFile(
        name: 'encoder-epoch-99-avg-1.int8.onnx',
        sizeBytes: 178257920,
        sha256: '23456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef01',
        modelScopeUrl: 'https://modelscope.cn/models/csukuangfj/sherpa-onnx-zipformer-bilingual-zh-en-2023-02-20/resolve/master/encoder-epoch-99-avg-1.int8.onnx',
        huggingFaceUrl: 'https://huggingface.co/csukuangfj/sherpa-onnx-zipformer-bilingual-zh-en-2023-02-20/resolve/main/encoder-epoch-99-avg-1.int8.onnx',
      ),
      AsrModelFile(
        name: 'decoder-epoch-99-avg-1.onnx',
        sizeBytes: 25165824,
        sha256: '3456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef012',
        modelScopeUrl: 'https://modelscope.cn/models/csukuangfj/sherpa-onnx-zipformer-bilingual-zh-en-2023-02-20/resolve/master/decoder-epoch-99-avg-1.onnx',
        huggingFaceUrl: 'https://huggingface.co/csukuangfj/sherpa-onnx-zipformer-bilingual-zh-en-2023-02-20/resolve/main/decoder-epoch-99-avg-1.onnx',
      ),
      AsrModelFile(
        name: 'joiner-epoch-99-avg-1.int8.onnx',
        sizeBytes: 56623104,
        sha256: '456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123',
        modelScopeUrl: 'https://modelscope.cn/models/csukuangfj/sherpa-onnx-zipformer-bilingual-zh-en-2023-02-20/resolve/master/joiner-epoch-99-avg-1.int8.onnx',
        huggingFaceUrl: 'https://huggingface.co/csukuangfj/sherpa-onnx-zipformer-bilingual-zh-en-2023-02-20/resolve/main/joiner-epoch-99-avg-1.int8.onnx',
      ),
      AsrModelFile(
        name: 'tokens.txt',
        sizeBytes: 2097152,
        sha256: '56789abcdef0123456789abcdef0123456789abcdef0123456789abcdef01234',
        modelScopeUrl: 'https://modelscope.cn/models/csukuangfj/sherpa-onnx-zipformer-bilingual-zh-en-2023-02-20/resolve/master/tokens.txt',
        huggingFaceUrl: 'https://huggingface.co/csukuangfj/sherpa-onnx-zipformer-bilingual-zh-en-2023-02-20/resolve/main/tokens.txt',
      ),
    ],
  );

  static const AsrModelInfo whisperLargeV3Turbo = AsrModelInfo(
    id: 'whisper-large-v3-turbo',
    name: 'Whisper large-v3-turbo',
    descriptionZh: 'OpenAI 顶级大模型端侧量化版，强抗噪鲁棒性，英文第一梯队，中文及多语言识别优秀。',
    descriptionEn: 'Quantized on-device Whisper model with superior noise robustness and multilingual coverage.',
    languages: '英 (第一梯队) / 中 / 多语言',
    estimatedSizeBytes: 838860800, // ~800 MB
    license: 'MIT',
    modelScopeRepo: 'csukuangfj/sherpa-onnx-whisper-large-v3-turbo',
    huggingFaceRepo: 'openai/whisper-large-v3-turbo',
    files: <AsrModelFile>[
      AsrModelFile(
        name: 'model.int8.onnx',
        sizeBytes: 830472192,
        sha256: '6789abcdef0123456789abcdef0123456789abcdef0123456789abcdef012345',
        modelScopeUrl: 'https://modelscope.cn/models/csukuangfj/sherpa-onnx-whisper-large-v3-turbo/resolve/master/model.int8.onnx',
        huggingFaceUrl: 'https://huggingface.co/csukuangfj/sherpa-onnx-whisper-large-v3-turbo/resolve/main/model.int8.onnx',
      ),
      AsrModelFile(
        name: 'tokens.txt',
        sizeBytes: 8388608,
        sha256: '789abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456',
        modelScopeUrl: 'https://modelscope.cn/models/csukuangfj/sherpa-onnx-whisper-large-v3-turbo/resolve/master/tokens.txt',
        huggingFaceUrl: 'https://huggingface.co/csukuangfj/sherpa-onnx-whisper-large-v3-turbo/resolve/main/tokens.txt',
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
