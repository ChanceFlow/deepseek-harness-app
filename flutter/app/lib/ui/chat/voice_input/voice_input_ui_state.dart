/// UI state for voice recording and on-device speech-to-text.
library;

import 'package:asr/asr.dart';

/// Lifecycle phase of the voice recording session.
enum VoiceInputPhase {
  idle,
  initializing,
  recording,
  finalizing,
  error,
}

/// State for the voice recording UI dock and microphone button.
class VoiceInputUiState {
  const VoiceInputUiState({
    this.phase = VoiceInputPhase.idle,
    this.duration = Duration.zero,
    this.amplitude = 0.0,
    this.liveTranscription = '',
    this.errorMessage,
    this.activeModel,
    this.hasInstalledModels = false,
  });

  final VoiceInputPhase phase;
  final Duration duration;
  final double amplitude;
  final String liveTranscription;
  final String? errorMessage;
  final AsrModelInfo? activeModel;
  final bool hasInstalledModels;

  bool get isRecording =>
      phase == VoiceInputPhase.recording ||
      phase == VoiceInputPhase.finalizing ||
      phase == VoiceInputPhase.initializing;

  bool get isBusy => phase != VoiceInputPhase.idle;

  VoiceInputUiState copyWith({
    VoiceInputPhase? phase,
    Duration? duration,
    double? amplitude,
    String? liveTranscription,
    String? errorMessage,
    bool clearError = false,
    AsrModelInfo? activeModel,
    bool? hasInstalledModels,
  }) {
    return VoiceInputUiState(
      phase: phase ?? this.phase,
      duration: duration ?? this.duration,
      amplitude: amplitude ?? this.amplitude,
      liveTranscription: liveTranscription ?? this.liveTranscription,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      activeModel: activeModel ?? this.activeModel,
      hasInstalledModels: hasInstalledModels ?? this.hasInstalledModels,
    );
  }
}