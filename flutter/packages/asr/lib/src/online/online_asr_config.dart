/// Online speech-recognition input modes, providers, and the
/// per-provider credential/endpoint configuration records that back the
/// voice-input settings.
///
/// Two streaming providers are supported:
/// - Volcengine Doubao streaming ASR (`X-Api-Key` auth, full-duplex
///   websocket at `wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_async`)
/// - Tencent Cloud real-time ASR (HMAC-SHA1 signed URL, websocket at
///   `wss://asr.cloud.tencent.com/asr/v2/{appid}`, engine
///   `Hy-ASR-3.0-preview`)
library;

/// Where voice-input audio is transcribed: on-device or an online service.
enum VoiceInputMode {
  offline('offline'),
  online('online');

  const VoiceInputMode(this.id);

  final String id;

  static VoiceInputMode fromId(String? id) =>
      VoiceInputMode.values
          .where((VoiceInputMode mode) => mode.id == id)
          .firstOrNull ??
      VoiceInputMode.offline;
}

/// Online speech-recognition providers supported by the app.
enum OnlineAsrProvider {
  volcengineDoubao('volcengine_doubao'),
  tencentHunyuan('tencent_hunyuan');

  const OnlineAsrProvider(this.id);

  final String id;

  static OnlineAsrProvider fromId(String? id) =>
      OnlineAsrProvider.values
          .where((OnlineAsrProvider provider) => provider.id == id)
          .firstOrNull ??
      OnlineAsrProvider.volcengineDoubao;
}

/// Volcengine Doubao streaming ASR session credentials.
///
/// Auth follows the speech API-key scheme: the key issued in the Volcengine
/// speech console rides in the `X-Api-Key` header and no appid is needed.
class VolcengineDoubaoAsrConfig {
  const VolcengineDoubaoAsrConfig({
    this.apiKey = '',
    this.endpoint = defaultEndpoint,
    this.resourceId = defaultResourceId,
  });

  /// Full-duplex streaming ASR websocket endpoint.
  static const String defaultEndpoint =
      'wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_async';

  /// Default `X-Api-Resource-Id`: Doubao streaming ASR 1.0, billed per
  /// audio duration — the same default the official Python demo ships.
  static const String defaultResourceId = 'volc.bigasr.sauc.duration';

  /// Speech console API key, sent verbatim as the `X-Api-Key` header.
  final String apiKey;

  /// Websocket endpoint override; empty means [defaultEndpoint].
  final String endpoint;

  /// `X-Api-Resource-Id` model/billing selector.
  final String resourceId;

  /// Whether the provider can open a session.
  bool get isConfigured => apiKey.trim().isNotEmpty;

  String get effectiveEndpoint =>
      endpoint.trim().isEmpty ? defaultEndpoint : endpoint.trim();

  VolcengineDoubaoAsrConfig copyWith({
    String? apiKey,
    String? endpoint,
    String? resourceId,
  }) => VolcengineDoubaoAsrConfig(
    apiKey: apiKey ?? this.apiKey,
    endpoint: endpoint ?? this.endpoint,
    resourceId: resourceId ?? this.resourceId,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'apiKey': apiKey,
    'endpoint': endpoint,
    'resourceId': resourceId,
  };

  factory VolcengineDoubaoAsrConfig.fromJson(Map<String, Object?> json) =>
      VolcengineDoubaoAsrConfig(
        apiKey: json['apiKey'] as String? ?? '',
        endpoint: json['endpoint'] as String? ?? defaultEndpoint,
        resourceId: json['resourceId'] as String? ?? defaultResourceId,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VolcengineDoubaoAsrConfig &&
          apiKey == other.apiKey &&
          endpoint == other.endpoint &&
          resourceId == other.resourceId;

  @override
  int get hashCode => Object.hash(apiKey, endpoint, resourceId);
}

/// Tencent Cloud real-time ASR session credentials.
///
/// Auth is a per-session HMAC-SHA1 signature over the sorted query string,
/// computed with the SecretKey; the AppID also names the websocket path.
class TencentHunyuanAsrConfig {
  const TencentHunyuanAsrConfig({
    this.appId = '',
    this.secretId = '',
    this.secretKey = '',
    this.endpoint = defaultEndpoint,
    this.engineModelType = defaultEngineModelType,
  });

  /// Real-time ASR websocket endpoint prefix; the AppID completes the path.
  static const String defaultEndpoint = 'wss://asr.cloud.tencent.com/asr/v2';

  /// The Hunyuan real-time engine id (preview release).
  static const String defaultEngineModelType = 'Hy-ASR-3.0-preview';

  final String appId;
  final String secretId;
  final String secretKey;

  /// Endpoint override; empty means [defaultEndpoint].
  final String endpoint;

  /// Engine selector, fixed to Hunyuan by default.
  final String engineModelType;

  /// Whether the provider can open a session.
  bool get isConfigured =>
      appId.trim().isNotEmpty &&
      secretId.trim().isNotEmpty &&
      secretKey.trim().isNotEmpty;

  String get effectiveEndpoint =>
      endpoint.trim().isEmpty ? defaultEndpoint : endpoint.trim();

  TencentHunyuanAsrConfig copyWith({
    String? appId,
    String? secretId,
    String? secretKey,
    String? endpoint,
    String? engineModelType,
  }) => TencentHunyuanAsrConfig(
    appId: appId ?? this.appId,
    secretId: secretId ?? this.secretId,
    secretKey: secretKey ?? this.secretKey,
    endpoint: endpoint ?? this.endpoint,
    engineModelType: engineModelType ?? this.engineModelType,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'appId': appId,
    'secretId': secretId,
    'secretKey': secretKey,
    'endpoint': endpoint,
    'engineModelType': engineModelType,
  };

  factory TencentHunyuanAsrConfig.fromJson(Map<String, Object?> json) =>
      TencentHunyuanAsrConfig(
        appId: json['appId'] as String? ?? '',
        secretId: json['secretId'] as String? ?? '',
        secretKey: json['secretKey'] as String? ?? '',
        endpoint: json['endpoint'] as String? ?? defaultEndpoint,
        engineModelType:
            json['engineModelType'] as String? ?? defaultEngineModelType,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TencentHunyuanAsrConfig &&
          appId == other.appId &&
          secretId == other.secretId &&
          secretKey == other.secretKey &&
          endpoint == other.endpoint &&
          engineModelType == other.engineModelType;

  @override
  int get hashCode =>
      Object.hash(appId, secretId, secretKey, endpoint, engineModelType);
}
