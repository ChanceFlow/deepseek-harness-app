/// Source-specific download adapters for ModelScope and Hugging Face.
library;

import '../manifest/model_manifest.dart';

/// Interface for resolving download URLs and headers for a specific source.
abstract interface class ModelSourceClient {
  ModelSource get source;

  /// Resolves the direct download URL for a model file.
  String buildFileUrl(AsrModelInfo model, AsrModelFile file);

  /// Default HTTP headers for requests to this source.
  Map<String, String> getHeaders();
}

/// ModelScope source client (optimized for network access within China).
class ModelScopeSourceClient implements ModelSourceClient {
  const ModelScopeSourceClient();

  @override
  ModelSource get source => ModelSource.modelScope;

  @override
  String buildFileUrl(AsrModelInfo model, AsrModelFile file) {
    return file.modelScopeUrl;
  }

  @override
  Map<String, String> getHeaders() => <String, String>{
    'User-Agent': 'DeepSeekHarness-Android/1.0',
    'Accept': '*/*',
  };
}

/// Hugging Face source client (global community repository).
class HuggingFaceSourceClient implements ModelSourceClient {
  const HuggingFaceSourceClient();

  @override
  ModelSource get source => ModelSource.huggingFace;

  @override
  String buildFileUrl(AsrModelInfo model, AsrModelFile file) {
    return file.huggingFaceUrl;
  }

  @override
  Map<String, String> getHeaders() => <String, String>{
    'User-Agent': 'DeepSeekHarness-Android/1.0',
    'Accept': '*/*',
  };
}
