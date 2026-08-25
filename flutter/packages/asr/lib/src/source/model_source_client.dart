/// Source-specific download adapters for Hugging Face and its China mirror.
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

/// Official Hugging Face China mirror (hf-mirror.com), the fast lane for
/// domestic networks. Serves the same bytes as the global hub; the mirror's
/// model/repo id is identical to the Hugging Face one.
class HfMirrorSourceClient implements ModelSourceClient {
  const HfMirrorSourceClient();

  @override
  ModelSource get source => ModelSource.hfMirror;

  @override
  String buildFileUrl(AsrModelInfo model, AsrModelFile file) {
    return file.hfMirrorUrl;
  }

  @override
  Map<String, String> getHeaders() => <String, String>{
    'User-Agent': 'DeepSeekHarness-Android/1.0',
    'Accept': '*/*',
  };
}
