/// Stock Material 3 voice recording dock and microphone button.
library;

import 'dart:math';

import 'package:app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

import 'voice_input_ui_state.dart';

/// Formatting helper for elapsed audio recording duration (mm:ss).
String formatVoiceDuration(Duration duration) {
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(1, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}

/// 28px circular microphone button for the Composer tools row.
class VoiceMicButton extends StatelessWidget {
  const VoiceMicButton({
    super.key,
    required this.enabled,
    required this.isRecording,
    required this.hasInstalledModels,
    required this.onTap,
    required this.onOpenSettings,
  });

  final bool enabled;
  final bool isRecording;
  final bool hasInstalledModels;
  final VoidCallback onTap;
  final VoidCallback onOpenSettings;

  void _handleTap(BuildContext context) {
    if (!hasInstalledModels) {
      _showNoModelDialog(context);
      return;
    }
    onTap();
  }

  void _showNoModelDialog(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.voiceInputNoModelTitle),
        content: Text(l10n.voiceInputNoModelBody),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              onOpenSettings();
            },
            child: Text(l10n.voiceInputGoToSettings),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    if (isRecording) {
      return SizedBox(
        width: 28,
        height: 28,
        child: Material(
          color: scheme.errorContainer,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: enabled ? () => _handleTap(context) : null,
            child: Icon(
              Icons.mic,
              size: 16,
              color: scheme.onErrorContainer,
            ),
          ),
        ),
      );
    }

    return SizedBox(
      width: 28,
      height: 28,
      child: Material(
        color: scheme.surfaceContainerHighest,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: enabled ? () => _handleTap(context) : null,
          child: Icon(
            Icons.mic_outlined,
            size: 16,
            color: enabled ? scheme.onSurfaceVariant : scheme.onSurface.withValues(alpha: 0.38),
          ),
        ),
      ),
    );
  }
}

/// M3 surfaceContainerLow banner showing recording duration, soundwave, and Cancel/Done controls.
class VoiceRecordingDock extends StatelessWidget {
  const VoiceRecordingDock({
    super.key,
    required this.uiState,
    required this.onCancel,
    required this.onDone,
  });

  final VoiceInputUiState uiState;
  final VoidCallback onCancel;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        children: <Widget>[
          // Pulsing red recording dot
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: scheme.error,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),

          // Duration timer
          Text(
            formatVoiceDuration(uiState.duration),
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(width: 12),

          // Live animated soundwave
          Expanded(
            child: _SoundWaveform(amplitude: uiState.amplitude),
          ),
          const SizedBox(width: 8),

          // Cancel button
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: l10n.voiceInputCancel,
            icon: Icon(Icons.close, size: 18, color: scheme.onSurfaceVariant),
            onPressed: onCancel,
          ),

          // Done / Stop button
          FilledButton.tonalIcon(
            style: FilledButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            ),
            icon: const Icon(Icons.check, size: 16),
            label: Text(l10n.voiceInputDone),
            onPressed: onDone,
          ),
        ],
      ),
    );
  }
}

/// Dynamic 8-bar audio waveform animating smoothly with PCM RMS amplitude.
class _SoundWaveform extends StatelessWidget {
  const _SoundWaveform({required this.amplitude});

  final double amplitude;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return SizedBox(
      height: 20,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(8, (index) {
          final scale = 0.4 + 0.6 * sin((index + 1) * 0.8);
          final barHeight = (4.0 + 16.0 * amplitude * scale).clamp(4.0, 20.0);

          return AnimatedContainer(
            duration: const Duration(milliseconds: 80),
            curve: Curves.easeOut,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            width: 3,
            height: barHeight,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.7 + 0.3 * amplitude),
              borderRadius: BorderRadius.circular(1.5),
            ),
          );
        }),
      ),
    );
  }
}