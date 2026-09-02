/// Material 3 voice recording dock and microphone seat.
///
/// The dock is one row that reads as a live instrument: a recording mark that
/// breathes, the elapsed clock, an input meter scrolling over the real
/// sub-peak detail of the PCM stream, and the two seats that end the session.
/// Every phase of the session has its own face — preparing, capturing,
/// transcribing — so the reader always knows whose turn it is.
library;

import 'dart:async';

import 'package:app/l10n/app_localizations.dart';
import 'package:app/platform/audio_recorder.dart';
import 'package:asr/asr.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../theme/theme.dart';
import 'voice_input_ui_state.dart';

/// Logical pixels from one meter bar to the next, the stroke width of a bar,
/// and the height of the strip they live in. With [kVoiceMeterBarStep] these
/// set how much session the eye can see at once: one bar per envelope band,
/// so a wider meter shows more history, not bigger bars.
const double kVoiceMeterBarPitch = 5;
const double kVoiceMeterBarWidth = 2.5;
const double kVoiceMeterHeight = 24;

/// One envelope band covers this much audio, so the meter advances a bar every
/// 25ms of session time and the trail slides [kVoiceMeterBarPitch] dp per bar.
/// Derived from the capture contract, never typed: change the chunk size or the
/// band count and the scroll speed follows the audio.
const int kVoiceMeterBarStepMs = kVoiceCaptureChunkMs ~/ kVoiceEnvelopeBands;
const Duration kVoiceMeterBarStep = Duration(
  milliseconds: kVoiceMeterBarStepMs,
);

/// A meter bar: the level captured at one moment of the session, and that
/// moment in milliseconds since the session clock started.
typedef _MeterBar = ({int atMs, double value});

/// Formatting helper for elapsed audio recording duration (mm:ss).
String formatVoiceDuration(Duration duration) {
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(1, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}

/// Whether the bespoke session motion should run: the platform reduce-motion
/// setting and a muted [TickerMode] both stop it, leaving a stepped, still
/// legible meter.
bool voiceMotionAllowed(BuildContext context) =>
    !MediaQuery.disableAnimationsOf(context) &&
    TickerMode.valuesOf(context).enabled;

/// Microphone seat for the Composer tools row.
///
/// A stock [IconButton] like every other tool in the row. While a session runs
/// it takes the recording role pair and breathes with the captured level, so
/// the seat that started the capture also reads as the live one.
class VoiceMicButton extends StatelessWidget {
  const VoiceMicButton({
    required this.enabled,
    required this.isRecording,
    required this.hasInstalledModels,
    required this.onTap,
    required this.onOpenSettings,
    this.inputMode = VoiceInputMode.offline,
    this.onlineReady = false,
    this.amplitude = 0.0,
    super.key,
  });

  final bool enabled;
  final bool isRecording;
  final bool hasInstalledModels;
  final VoidCallback onTap;
  final VoidCallback onOpenSettings;

  /// Where voice input sends audio; decides which readiness gate the tap
  /// crosses (installed on-device models, or configured online credentials).
  final VoiceInputMode inputMode;

  /// Whether the selected online provider has usable credentials.
  final bool onlineReady;

  /// Newest capture level (0..1), read only while recording.
  final double amplitude;

  void _handleTap(BuildContext context) {
    if (inputMode == VoiceInputMode.online && !onlineReady) {
      _showSetupDialog(
        context,
        title: AppLocalizations.of(context)!.voiceInputCloudSetupTitle,
        body: AppLocalizations.of(context)!.voiceInputCloudSetupBody,
      );
      return;
    }
    if (inputMode == VoiceInputMode.offline && !hasInstalledModels) {
      _showSetupDialog(
        context,
        title: AppLocalizations.of(context)!.voiceInputNoModelTitle,
        body: AppLocalizations.of(context)!.voiceInputNoModelBody,
      );
      return;
    }
    // The seat owns the boundary of a capture in both directions, and so does
    // the dock's Done seat: the same firm tap either way.
    unawaited(HapticFeedback.mediumImpact());
    onTap();
  }

  void _showSetupDialog(
    BuildContext context, {
    required String title,
    required String body,
  }) {
    final l10n = AppLocalizations.of(context)!;
    unawaited(
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Text(body),
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
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final live = isRecording && voiceMotionAllowed(context);

    return IconButton(
      // While a session runs the seat is the stop control the dock's own seat
      // is, so it says so.
      tooltip: isRecording ? l10n.voiceInputDone : l10n.voiceInputTooltip,
      onPressed: enabled ? () => _handleTap(context) : null,
      style: IconButton.styleFrom(
        foregroundColor: isRecording
            ? scheme.onErrorContainer
            : scheme.onSurfaceVariant,
        disabledForegroundColor: scheme.outline,
        backgroundColor: isRecording ? scheme.errorContainer : null,
        shape: const CircleBorder(),
      ),
      icon: AnimatedScale(
        duration: Durations.short2,
        curve: Easing.standard,
        scale: live ? 1 + 0.16 * amplitude.clamp(0.0, 1.0) : 1.0,
        child: Icon(isRecording ? Icons.mic : Icons.mic_outlined, size: 22),
      ),
    );
  }
}

/// Recording banner: elapsed clock, live input meter, and Cancel/Done seats.
///
/// The dock is mounted with the composer and animates its own height, so it
/// grows out of the input dock instead of dropping over it. With no session on
/// screen it collapses to nothing and keeps no controls in the tree.
class VoiceRecordingDock extends StatelessWidget {
  const VoiceRecordingDock({
    required this.uiState,
    required this.onCancel,
    required this.onDone,
    super.key,
  });

  final VoiceInputUiState uiState;
  final VoidCallback onCancel;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final phase = uiState.phase;
    final recording = phase == VoiceInputPhase.recording;
    // Preparing and transcribing are the phases where the engine, not the
    // reader, holds the turn: the seat says so and declines to be pressed.
    final waiting = uiState.isWaitingOnEngine;
    final motion = voiceMotionAllowed(context) && uiState.isRecording;

    final seatLabel = switch (phase) {
      VoiceInputPhase.initializing => l10n.voiceInputInitializing,
      VoiceInputPhase.finalizing => l10n.voiceInputFinalizing,
      VoiceInputPhase.recording ||
      VoiceInputPhase.idle ||
      VoiceInputPhase.error => l10n.voiceInputDone,
    };

    return AnimatedSize(
      duration: Durations.medium1,
      curve: Easing.emphasizedDecelerate,
      alignment: Alignment.topCenter,
      child: uiState.isRecording
          ? Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(kShapeCard),
                  border: Border.all(
                    color: scheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        _RecordPhaseIndicator(
                          recording: recording,
                          motion: motion,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          formatVoiceDuration(uiState.duration),
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            fontFamily: 'monospace',
                            color: scheme.onSurface,
                            // The clock steps once a second; fixed-width
                            // digits stop the row from shuffling under it.
                            fontFeatures: const <FontFeature>[
                              FontFeature.tabularFigures(),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _LiveVoiceMeter(
                            envelope: uiState.envelope,
                            level: uiState.amplitude,
                            live: uiState.isRecording,
                            capturing: recording,
                            dim: waiting,
                            motion: motion,
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          tooltip: l10n.voiceInputCancel,
                          visualDensity: VisualDensity.compact,
                          icon: Icon(
                            Icons.close,
                            size: 18,
                            color: scheme.onSurfaceVariant,
                          ),
                          onPressed: () {
                            unawaited(HapticFeedback.lightImpact());
                            onCancel();
                          },
                        ),
                        FilledButton.tonalIcon(
                          style: FilledButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                          ),
                          icon: waiting
                              ? const SizedBox.square(
                                  dimension: 16,
                                  child: Center(child: _MiniProgress()),
                                )
                              : const Icon(Icons.check, size: 16),
                          label: Text(seatLabel),
                          onPressed: waiting
                              ? null
                              : () {
                                  unawaited(HapticFeedback.mediumImpact());
                                  onDone();
                                },
                        ),
                      ],
                    ),
                    // Debug-only strip: native capture telemetry, so the data
                    // flow is visible on-screen without adb/logcat.
                    if (kDebugMode && uiState.debugStats != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          formatDebugStats(uiState.debugStats!) ?? '',
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontFamily: 'monospace',
                            color: scheme.primary,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            )
          : const SizedBox(width: double.infinity),
    );
  }
}

/// The mark that says "capturing", or a ring while the session waits on the
/// engine instead of on the reader.
class _RecordPhaseIndicator extends StatelessWidget {
  const _RecordPhaseIndicator({required this.recording, required this.motion});

  final bool recording;
  final bool motion;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox.square(
      dimension: 18,
      child: AnimatedSwitcher(
        duration: Durations.short4,
        switchInCurve: Easing.standard,
        switchOutCurve: Easing.standard,
        child: recording
            ? _RecordingPulse(
                key: const ValueKey<String>('capturing'),
                color: scheme.error,
                motion: motion,
              )
            : const Center(
                key: ValueKey<String>('waiting'),
                child: _MiniProgress(),
              ),
      ),
    );
  }
}

/// The recording mark: a solid dot with a halo that leaves it and dies.
class _RecordingPulse extends StatefulWidget {
  const _RecordingPulse({required this.color, required this.motion, super.key});

  final Color color;
  final bool motion;

  @override
  State<_RecordingPulse> createState() => _RecordingPulseState();
}

class _RecordingPulseState extends State<_RecordingPulse>
    with SingleTickerProviderStateMixin {
  static const double _core = 8;
  static const double _haloMax = 18;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(_RecordingPulse oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    if (widget.motion) {
      if (!_controller.isAnimating) _controller.repeat();
    } else {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = Easing.standardDecelerate.transform(_controller.value);
        final halo = _core + (_haloMax - _core) * t;
        return SizedBox.square(
          dimension: _haloMax,
          child: Stack(
            alignment: Alignment.center,
            children: <Widget>[
              Container(
                width: halo,
                height: halo,
                decoration: BoxDecoration(
                  color: widget.color.withValues(alpha: 0.28 * (1 - t)),
                  shape: BoxShape.circle,
                ),
              ),
              Container(
                width: _core,
                height: _core,
                decoration: BoxDecoration(
                  color: widget.color,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// A 14px indeterminate ring, for the waits the session does not own.
class _MiniProgress extends StatelessWidget {
  const _MiniProgress();

  @override
  Widget build(BuildContext context) {
    return const SizedBox.square(
      dimension: 14,
      child: CircularProgressIndicator(strokeWidth: 2),
    );
  }
}

/// Scrolling live input meter.
///
/// A [CustomPainter] rather than a row of widgets because the bars move on the
/// audio clock, not the build clock: a bar enters at the right edge every
/// [kVoiceMeterBarStep] of session time and the whole trail slides left at a
/// constant speed, which no implicit animation expresses without re-laying-out
/// a growing row every frame. Recorded in
/// [the voice motion note](../../../../../../.agents/notes/implemented/feature/2026-09-02-voice-input-motion.md).
class _LiveVoiceMeter extends StatefulWidget {
  const _LiveVoiceMeter({
    required this.envelope,
    required this.level,
    required this.live,
    required this.capturing,
    required this.dim,
    required this.motion,
  });

  /// The newest chunk's per-window peaks (0..1), one entry per band. Empty
  /// when a level arrived without a matching chunk.
  final List<double> envelope;

  /// The newest chunk's overall level, the meter's only input when there are
  /// no bands to show.
  final double level;

  /// Whether a session is on screen at all: the clock runs and the trail
  /// keeps its shape until the reader ends the session.
  final bool live;

  /// Whether the microphone is the live half of the session. When it is not
  /// — the engine is preparing or decoding — the trail scrolls out to the
  /// silence floor instead of freezing mid-word.
  final bool capturing;

  /// Dimmed while the session waits on the engine rather than the reader.
  final bool dim;

  /// Whether the trail slides continuously or steps one chunk at a time.
  final bool motion;

  @override
  State<_LiveVoiceMeter> createState() => _LiveVoiceMeterState();
}

class _LiveVoiceMeterState extends State<_LiveVoiceMeter>
    with SingleTickerProviderStateMixin {
  /// Bars to draw, oldest first. Bounded, so a long session costs exactly what
  /// a short one does; the painter only ever shows the tail that fits.
  static const int _maxBars = 96;

  final List<_MeterBar> _bars = <_MeterBar>[];
  final List<double> _queue = <double>[];

  late final Ticker _ticker = createTicker(_onTick);

  /// Session time the newest drawn bar belongs to.
  int _clockMs = 0;

  /// Session time at which the next queued band becomes a bar.
  int _nextBarMs = 0;

  /// The frame already turned into bars. A controller emit that carries no
  /// new audio — the once-a-second clock tick, which copies the state — keeps
  /// the same envelope object identity and the same level, so the meter does
  /// not draw the same chunk twice.
  List<double>? _seenEnvelope;
  double? _seenLevel;

  /// Whether real bands have reached the trail. Until they do it holds its
  /// seeded level rather than scrolling into silence nobody recorded.
  bool _hasInput = false;

  /// Newest level the stream reported, held on screen while the capture
  /// stream is slower than the meter's own bar cadence.
  double _lastLevel = 0;

  int get _stepMs => kVoiceMeterBarStep.inMilliseconds;

  @override
  void initState() {
    super.initState();
    _observe(newSession: true);
    _syncTicker();
  }

  @override
  void didUpdateWidget(_LiveVoiceMeter oldWidget) {
    super.didUpdateWidget(oldWidget);
    _observe(newSession: widget.live && !oldWidget.live);
    _syncTicker();
  }

  /// Turns the frame on screen into meter input: a fresh session resets the
  /// trail and seeds it, a new frame queues its bands.
  void _observe({bool newSession = false}) {
    final envelope = widget.envelope;
    final fresh =
        !identical(envelope, _seenEnvelope) ||
        envelope.isEmpty && widget.level != _seenLevel;
    if (newSession) {
      _bars.clear();
      _queue.clear();
      _hasInput = false;
      _clockMs = 0;
      _nextBarMs = 0;
    } else if (!fresh) {
      // Unchanged frame: nothing new was captured.
      if (_bars.isEmpty) _seed(_bands());
      return;
    }
    _seenEnvelope = envelope;
    _seenLevel = widget.level;
    final bands = _bands();
    _lastLevel = bands.last;
    if (_bars.isEmpty) {
      _seed(bands);
      return;
    }
    _queue.addAll(bands);
    // Two chunks is the most the meter owes anyone: a UI isolate that falls
    // behind shows the newest audio, not a backlog replaying old speech.
    final overflow = _queue.length - kVoiceEnvelopeBands * 2;
    if (overflow > 0) _queue.removeRange(0, overflow);
    if (!widget.motion) _drainStepped();
  }

  /// The bands describing the newest frame: its real sub-peaks when the
  /// recorder supplied them, one bar at the chunk level when it did not.
  List<double> _bands() =>
      widget.envelope.isNotEmpty ? widget.envelope : <double>[widget.level];

  /// With no past to show, the meter holds the current level across its window
  /// — what a level meter does before it has history. Real bands scroll it out
  /// from the right edge as soon as the stream arrives.
  void _seed(List<double> bands) {
    _bars.clear();
    final n = bands.length;
    for (var i = _maxBars - 1; i >= 0; i--) {
      // Newest last in the list, so the band order reads left to right the
      // way the queued bands will once they scroll in.
      _bars.add((atMs: _clockMs - i * _stepMs, value: bands[n - 1 - i % n]));
    }
    _nextBarMs = _clockMs + _stepMs;
  }

  void _syncTicker() {
    final shouldRun = widget.live && widget.motion;
    if (shouldRun && !_ticker.isActive) {
      _ticker.start();
    } else if (!shouldRun && _ticker.isActive) {
      _ticker.stop();
    }
  }

  void _onTick(Duration elapsed) {
    if (_queue.isEmpty && !_hasInput) return;
    final now = elapsed.inMilliseconds;
    // A frame gap — a paused app, a busy isolate, or the engine still loading
    // a model — must not replay every missed bar. Re-anchor the clock to now,
    // and while only the seeded level is on screen the seed moves with it, so
    // a session never opens on an empty strip.
    if (now - _nextBarMs > 4 * _stepMs) {
      if (!_hasInput) {
        _clockMs = now;
        _seed(_bands());
      }
      _nextBarMs = now;
    }
    while (_queue.isNotEmpty && now >= _nextBarMs) {
      _addBar(_nextBarMs, _queue.removeAt(0));
      _nextBarMs += _stepMs;
      _hasInput = true;
    }
    if (_queue.isEmpty && now >= _nextBarMs) {
      // Nothing in flight. A live capture holds the newest level — the stream
      // is slower than this cadence, not silent — while a session waiting on
      // the engine scrolls its trail out to the floor.
      final held = widget.capturing ? _lastLevel : 0.0;
      while (now >= _nextBarMs) {
        _addBar(_nextBarMs, held);
        _nextBarMs += _stepMs;
      }
    }
    setState(() => _clockMs = now);
  }

  /// Reduced motion: one chunk in, one step of trail out, nothing sliding.
  void _drainStepped() {
    if (_nextBarMs < _clockMs) _nextBarMs = _clockMs;
    while (_queue.isNotEmpty) {
      _addBar(_nextBarMs, _queue.removeAt(0));
      _nextBarMs += _stepMs;
      _hasInput = true;
    }
    _clockMs = _nextBarMs - _stepMs;
    setState(() {});
  }

  void _addBar(int atMs, double value) {
    _bars.add((atMs: atMs, value: value));
    if (_bars.length > _maxBars) _bars.removeAt(0);
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: kVoiceMeterHeight,
      child: CustomPaint(
        size: const Size(double.infinity, kVoiceMeterHeight),
        painter: _VoiceMeterPainter(
          bars: _bars,
          clockMs: _clockMs,
          color: widget.dim ? scheme.onSurfaceVariant : scheme.primary,
          dim: widget.dim,
        ),
      ),
    );
  }
}

class _VoiceMeterPainter extends CustomPainter {
  _VoiceMeterPainter({
    required this.bars,
    required this.clockMs,
    required this.color,
    required this.dim,
  });

  final List<_MeterBar> bars;
  final int clockMs;
  final Color color;
  final bool dim;

  @override
  void paint(Canvas canvas, Size size) {
    const dpPerMs = kVoiceMeterBarPitch / kVoiceMeterBarStepMs;
    const minHalf = kVoiceMeterBarWidth / 2;
    final mid = size.height / 2;
    final headroom = mid - kVoiceMeterBarWidth;
    final rightEdge = size.width - minHalf;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = kVoiceMeterBarWidth
      ..strokeCap = StrokeCap.round;

    // Walk back from the newest bar: it sits at the right edge and every
    // earlier one is older, so the first bar that has left the strip ends the
    // run. Bars the session clock has not reached yet sit past the right edge
    // and simply wait for the next frame.
    for (int i = bars.length - 1; i >= 0; i--) {
      final bar = bars[i];
      final x = rightEdge - (clockMs - bar.atMs) * dpPerMs;
      if (x < 0) break;
      if (x > size.width) continue;
      // The tail fades with age: motion the eye can follow before the bar
      // has to leave the strip.
      final near = (x / rightEdge).clamp(0.0, 1.0);
      stroke.color = color.withValues(alpha: dim ? 0.32 : 0.18 + 0.82 * near);
      final half = minHalf + bar.value.clamp(0.0, 1.0) * headroom;
      canvas.drawLine(Offset(x, mid - half), Offset(x, mid + half), stroke);
    }
  }

  @override
  bool shouldRepaint(_VoiceMeterPainter oldDelegate) =>
      oldDelegate.clockMs != clockMs ||
      oldDelegate.color != color ||
      oldDelegate.dim != dim;
}
