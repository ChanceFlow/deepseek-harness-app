/// UI state for voice recording and on-device speech-to-text.
library;

import 'package:app/platform/audio_recorder.dart';
import 'package:asr/asr.dart';

/// How long the native capture thread fills one PCM chunk before it emits
/// it, in milliseconds. The meter's bar cadence derives from this, so
/// changing it moves the scroll speed of the input meter with the audio, not
/// against it.
const int kVoiceCaptureChunkMs = 100;

/// How long the native capture thread fills one PCM chunk before it emits it.
const Duration kVoiceCaptureChunk = Duration(
  milliseconds: kVoiceCaptureChunkMs,
);

/// How many equal time windows one capture chunk is split into for the
/// input meter. One window becomes one bar, so the meter renders
/// `kVoiceEnvelopeBands` bars per chunk instead of a single flat level.
const int kVoiceEnvelopeBands = 4;

/// Lifecycle phase of the voice recording session.
enum VoiceInputPhase { idle, initializing, recording, finalizing, error }

/// State for the voice recording UI dock and microphone button.
class VoiceInputUiState {
  const VoiceInputUiState({
    this.phase = VoiceInputPhase.idle,
    this.duration = Duration.zero,
    this.amplitude = 0.0,
    this.envelope = const <double>[],
    this.liveTranscription = '',
    this.errorMessage,
    this.activeModel,
    this.hasInstalledModels = false,
    this.inputMode = VoiceInputMode.offline,
    this.onlineReady = false,
    this.debugStats,
  });

  final VoiceInputPhase phase;
  final Duration duration;
  final double amplitude;

  /// Per-window peak levels of the newest capture chunk, each 0..1 and each
  /// already carrying the chunk's own normalized level. Empty when the level
  /// arrived without a matching chunk — a mocked source, or the frame before
  /// the first audio event — in which case the meter draws one bar at
  /// [amplitude].
  final List<double> envelope;
  final String liveTranscription;
  final String? errorMessage;
  final AsrModelInfo? activeModel;
  final bool hasInstalledModels;

  /// Where voice input sends audio: on-device or an online service.
  final VoiceInputMode inputMode;

  /// Whether the selected online provider has usable credentials. Only
  /// meaningful when [inputMode] is online.
  final bool onlineReady;

  /// Native capture diagnostics; populated only in debug builds.
  final AudioDebugStats? debugStats;

  bool get isRecording =>
      phase == VoiceInputPhase.recording ||
      phase == VoiceInputPhase.finalizing ||
      phase == VoiceInputPhase.initializing;

  bool get isBusy => phase != VoiceInputPhase.idle;

  /// Whether the engine, not the reader, holds the turn: loading a model or
  /// decoding audio. Every control that would interrupt that work declines
  /// while this is true — including the microphone seat, which stays live
  /// while the reader is the one talking.
  bool get isWaitingOnEngine =>
      phase == VoiceInputPhase.initializing ||
      phase == VoiceInputPhase.finalizing;

  VoiceInputUiState copyWith({
    VoiceInputPhase? phase,
    Duration? duration,
    double? amplitude,
    List<double>? envelope,
    String? liveTranscription,
    String? errorMessage,
    bool clearError = false,
    AsrModelInfo? activeModel,
    bool? hasInstalledModels,
    VoiceInputMode? inputMode,
    bool? onlineReady,
    AudioDebugStats? debugStats,
  }) {
    return VoiceInputUiState(
      phase: phase ?? this.phase,
      duration: duration ?? this.duration,
      amplitude: amplitude ?? this.amplitude,
      envelope: envelope ?? this.envelope,
      liveTranscription: liveTranscription ?? this.liveTranscription,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      activeModel: activeModel ?? this.activeModel,
      hasInstalledModels: hasInstalledModels ?? this.hasInstalledModels,
      inputMode: inputMode ?? this.inputMode,
      onlineReady: onlineReady ?? this.onlineReady,
      debugStats: debugStats ?? this.debugStats,
    );
  }
}
