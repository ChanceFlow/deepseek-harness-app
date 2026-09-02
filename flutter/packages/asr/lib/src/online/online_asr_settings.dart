/// Durable voice-input settings: offline/online mode, the active online
/// provider, and each provider's credentials.
///
/// The store owns one JSON document next to the ASR model registry
/// (`online_asr_settings.json`), with the same atomic temp-file + rename
/// posture as [ModelsRegistry]. A corrupt or unreadable document is the
/// default settings, not an error — the user re-enters credentials the way
/// they re-enter any lost config.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'online_asr_config.dart';

/// Immutable snapshot of the voice-input configuration.
class OnlineAsrSettings {
  const OnlineAsrSettings({
    this.mode = VoiceInputMode.offline,
    this.provider = OnlineAsrProvider.volcengineDoubao,
    this.volcengine = const VolcengineDoubaoAsrConfig(),
    this.tencent = const TencentHunyuanAsrConfig(),
  });

  final VoiceInputMode mode;
  final OnlineAsrProvider provider;
  final VolcengineDoubaoAsrConfig volcengine;
  final TencentHunyuanAsrConfig tencent;

  /// Whether the currently selected online provider is usable.
  bool get isOnlineReady => switch (provider) {
    OnlineAsrProvider.volcengineDoubao => volcengine.isConfigured,
    OnlineAsrProvider.tencentHunyuan => tencent.isConfigured,
  };

  OnlineAsrSettings copyWith({
    VoiceInputMode? mode,
    OnlineAsrProvider? provider,
    VolcengineDoubaoAsrConfig? volcengine,
    TencentHunyuanAsrConfig? tencent,
  }) => OnlineAsrSettings(
    mode: mode ?? this.mode,
    provider: provider ?? this.provider,
    volcengine: volcengine ?? this.volcengine,
    tencent: tencent ?? this.tencent,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'version': 1,
    'mode': mode.id,
    'provider': provider.id,
    'volcengine': volcengine.toJson(),
    'tencent': tencent.toJson(),
  };

  factory OnlineAsrSettings.fromJson(Map<String, Object?> json) {
    final dynamic volc = json['volcengine'];
    final dynamic tencent = json['tencent'];
    return OnlineAsrSettings(
      mode: VoiceInputMode.fromId(json['mode'] as String?),
      provider: OnlineAsrProvider.fromId(json['provider'] as String?),
      volcengine: volc is Map<String, Object?>
          ? VolcengineDoubaoAsrConfig.fromJson(volc)
          : const VolcengineDoubaoAsrConfig(),
      tencent: tencent is Map<String, Object?>
          ? TencentHunyuanAsrConfig.fromJson(tencent)
          : const TencentHunyuanAsrConfig(),
    );
  }
}

/// File-backed store broadcasting every [settings] change.
class OnlineAsrSettingsStore {
  OnlineAsrSettingsStore(this.settingsFile);

  final File settingsFile;

  OnlineAsrSettings _settings = const OnlineAsrSettings();
  final StreamController<OnlineAsrSettings> _updates =
      StreamController<OnlineAsrSettings>.broadcast();

  OnlineAsrSettings get settings => _settings;

  Stream<OnlineAsrSettings> get updates => _updates.stream;

  /// Loads the document; a missing, corrupt, or unreadable file yields the
  /// default settings (offline mode, no credentials).
  Future<void> load() async {
    if (!await settingsFile.exists()) {
      _notify();
      return;
    }
    try {
      final String content = await settingsFile.readAsString();
      if (content.trim().isEmpty) {
        _notify();
        return;
      }
      final dynamic decoded = jsonDecode(content);
      if (decoded is Map<String, Object?>) {
        _settings = OnlineAsrSettings.fromJson(decoded);
      }
    } on FormatException {
      _settings = const OnlineAsrSettings();
    } on FileSystemException {
      _settings = const OnlineAsrSettings();
    }
    _notify();
  }

  Future<void> setMode(VoiceInputMode mode) async {
    if (_settings.mode == mode) return;
    _settings = _settings.copyWith(mode: mode);
    await _save();
  }

  Future<void> setProvider(OnlineAsrProvider provider) async {
    if (_settings.provider == provider) return;
    _settings = _settings.copyWith(provider: provider);
    await _save();
  }

  Future<void> setVolcengine(VolcengineDoubaoAsrConfig config) async {
    if (_settings.volcengine == config) return;
    _settings = _settings.copyWith(volcengine: config);
    await _save();
  }

  Future<void> setTencent(TencentHunyuanAsrConfig config) async {
    if (_settings.tencent == config) return;
    _settings = _settings.copyWith(tencent: config);
    await _save();
  }

  Future<void> _save() async {
    final String jsonStr = const JsonEncoder.withIndent('  ')
        .convert(_settings.toJson());
    final Directory parent = settingsFile.parent;
    if (!await parent.exists()) {
      await parent.create(recursive: true);
    }
    try {
      final File tempFile = File('${settingsFile.path}.tmp');
      await tempFile.writeAsString(jsonStr, flush: true);
      await tempFile.rename(settingsFile.path);
    } on FileSystemException {
      // Fallback direct write when rename is not supported.
      await settingsFile.writeAsString(jsonStr, flush: true);
    }
    _notify();
  }

  void _notify() {
    if (!_updates.isClosed) {
      _updates.add(_settings);
    }
  }

  Future<void> dispose() async {
    await _updates.close();
  }
}
