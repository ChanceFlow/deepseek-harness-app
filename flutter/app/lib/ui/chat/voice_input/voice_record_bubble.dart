/// Material 3 microphone seat and its anchored recording bubble.
///
/// The session surface is a bubble pinned to the seat that opened it — not a
/// bar inserted into the composer, which shoved the input row aside and covered
/// the draft the reader is watching. The bubble carries the elapsed clock and a
/// live input meter, pops out of the seat, and answers the two gestures that
/// end a capture: release to send, slide up to discard.
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
/// set how much session the eye can see at once: one bar per envelope band, so
/// a wider meter shows more history, not bigger bars.
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

/// Width of the recording bubble. Fixed, because the seat keeps the bubble
/// inside the viewport by arithmetic rather than by measuring the bubble back:
/// a width that drifted with the transcript would slide the tail off the seat
/// the tail points at.
const double kVoiceBubbleWidth = 236;

/// Depth of the tail below the card, the gap between the tail tip and the seat,
/// the seam the bubble keeps from the viewport edge when the seat sits near it,
/// and the card's radius — the house popup radius, shared with the menu sheets.
const double kVoiceBubbleTail = 9;
const double kVoiceBubbleGap = 10;
const double kVoiceBubbleMargin = 16;
const double kVoiceBubbleRadius = kShapeMenuSheet;

/// How far above the seat a held finger travels before the bubble switches to
/// its discard face. Shorter than this, the hold still means "send".
const double kVoiceCancelSlide = 56;

/// The seat's box: the hold is recognised across all of it, and it is the
/// 40px the rest of the tools row already gives an `IconButton`.
const double kVoiceSeatBox = 40;

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
/// legible meter and an bubble that appears instead of popping.
bool voiceMotionAllowed(BuildContext context) =>
    !MediaQuery.disableAnimationsOf(context) &&
    TickerMode.valuesOf(context).enabled;

/// Microphone seat for the Composer tools row, and the owner of the recording
/// bubble its session puts on screen.
///
/// Two gestures cross a capture. A tap opens one and the next tap sends it —
/// the path that stays usable for anyone who cannot hold. A press that keeps
/// holding records only while the finger is down: releasing sends, sliding past
/// [kVoiceCancelSlide] first discards. Every boundary carries a haptic and an
/// earcon, so the reader learns the outcome without looking at the screen.
class VoiceMicButton extends StatefulWidget {
  const VoiceMicButton({
    required this.enabled,
    required this.uiState,
    required this.onStart,
    required this.onFinish,
    required this.onCancel,
    required this.onOpenSettings,
    super.key,
  });

  /// Whether the seat answers at all: a session whose turn the engine holds
  /// declines, as does a composer that cannot send.
  final bool enabled;
  final VoiceInputUiState uiState;
  final VoidCallback onStart;
  final VoidCallback onFinish;
  final VoidCallback onCancel;
  final VoidCallback onOpenSettings;

  @override
  State<VoiceMicButton> createState() => _VoiceMicButtonState();
}

class _VoiceMicButtonState extends State<VoiceMicButton> {
  /// Publishes the seat's box to the follower, so the bubble rides the seat
  /// through a keyboard opening or a scroll instead of being placed once.
  final LayerLink _link = LayerLink();

  /// The portal stays shown for the seat's whole life; what comes and goes is
  /// the bubble the builder returns. Showing it from a frame callback rather
  /// than from [build] is what keeps the controller attached.
  final OverlayPortalController _portal = OverlayPortalController();

  /// Horizontal correction that keeps the bubble inside the viewport, derived
  /// from the seat's own rect after layout (see [_measure]).
  double _shift = 0;

  /// Whether a finger is holding the seat now, and whether that hold has
  /// travelled far enough up to mean "discard".
  bool _holding = false;
  bool _armed = false;

  VoiceInputUiState get _uiState => widget.uiState;

  bool get _live => _uiState.isRecording;

  /// Which readiness gate a press crosses: on-device capture needs an installed
  /// model, online capture needs configured credentials.
  bool get _ready => switch (_uiState.inputMode) {
    VoiceInputMode.offline => _uiState.hasInstalledModels,
    VoiceInputMode.online => _uiState.onlineReady,
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_portal.isShowing) _portal.show();
      _measure();
    });
  }

  @override
  void didUpdateWidget(VoiceMicButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The seat's own box moves when the keyboard opens or the tool row wraps,
    // and the bubble has to follow in the frame it moves.
    if (_live) _scheduleMeasure();
  }

  void _scheduleMeasure() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _measure();
    });
  }

  /// A follower cannot read its leader's box during build, so the correction is
  /// computed after layout and applied on the next frame.
  void _measure() {
    if (!_live) {
      if (_shift != 0) setState(() => _shift = 0);
      return;
    }
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    final seat = box.localToGlobal(Offset.zero);
    final ideal = seat.dx + box.size.width / 2 - kVoiceBubbleWidth / 2;
    final maxLeft =
        MediaQuery.sizeOf(context).width -
        kVoiceBubbleMargin -
        kVoiceBubbleWidth;
    final left = maxLeft <= kVoiceBubbleMargin
        ? kVoiceBubbleMargin
        : ideal.clamp(kVoiceBubbleMargin, maxLeft);
    final shift = left - ideal;
    if (shift != _shift) setState(() => _shift = shift);
  }

  /// Returns false when a press stopped at a setup dialog instead of opening a
  /// capture.
  bool _gateReady() {
    if (_ready) return true;
    final l10n = AppLocalizations.of(context)!;
    final online = _uiState.inputMode == VoiceInputMode.online;
    _showSetupDialog(
      context,
      title: online
          ? l10n.voiceInputCloudSetupTitle
          : l10n.voiceInputNoModelTitle,
      body: online ? l10n.voiceInputCloudSetupBody : l10n.voiceInputNoModelBody,
    );
    return false;
  }

  void _handleTap() {
    if (!_gateReady()) return;
    if (_live) {
      _finish();
    } else {
      _start();
    }
  }

  void _start() {
    unawaited(HapticFeedback.mediumImpact());
    unawaited(playVoiceSound(VoiceSound.start));
    widget.onStart();
  }

  void _finish() {
    unawaited(HapticFeedback.mediumImpact());
    unawaited(playVoiceSound(VoiceSound.send));
    widget.onFinish();
  }

  void _discard() {
    unawaited(HapticFeedback.lightImpact());
    unawaited(playVoiceSound(VoiceSound.cancel));
    widget.onCancel();
  }

  void _handleHoldStart(LongPressStartDetails _) {
    if (!widget.enabled || !_gateReady()) return;
    setState(() {
      _holding = true;
      _armed = false;
    });
    if (!_live) _start();
  }

  void _handleHoldMove(LongPressMoveUpdateDetails details) {
    if (!_holding) return;
    final armed = details.localOffsetFromOrigin.dy <= -kVoiceCancelSlide;
    if (armed != _armed) setState(() => _armed = armed);
  }

  void _handleHoldUp() {
    if (!_holding) return;
    final discard = _armed;
    setState(() {
      _holding = false;
      _armed = false;
    });
    // The release carries the reader's intent whether or not the state has
    // caught up: lifting a finger whose session is still arriving must send,
    // not leave a capture running with nobody holding it.
    if (discard) {
      _discard();
    } else {
      _finish();
    }
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
                widget.onOpenSettings();
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
    final live = _live && voiceMotionAllowed(context);

    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _portal,
        overlayChildBuilder: (context) => _BubbleSwitcher(
          live: _live,
          child: _VoiceRecordBubble(
            link: _link,
            shift: _shift,
            armed: _armed,
            holding: _holding,
            uiState: _uiState,
          ),
        ),
        child: IconButton(
          // While a session runs the seat is the send control that the
          // release gesture is, so it says so.
          tooltip: _live ? l10n.voiceInputDone : l10n.voiceInputTooltip,
          onPressed: widget.enabled ? _handleTap : null,
          // The hold's hit box is the icon slot, so the slot is the whole
          // seat: no dead ring where a thumb would hit the tooltip instead.
          iconSize: kVoiceSeatBox,
          style: IconButton.styleFrom(
            padding: EdgeInsets.zero,
            minimumSize: const Size.square(kVoiceSeatBox),
            foregroundColor: _live
                ? scheme.onErrorContainer
                : scheme.onSurfaceVariant,
            disabledForegroundColor: scheme.outline,
            backgroundColor: _live ? scheme.errorContainer : null,
            shape: const CircleBorder(),
          ),
          // The hold is recognised inside the button rather than around it,
          // because a Material `Tooltip` shows itself on long press: a
          // detector outside the seat loses that arena and the press only ever
          // reveals the tooltip. As the deepest competitor here it wins a hold
          // while a tap still falls through to the button, which is what keeps
          // both gestures on one seat.
          icon: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onLongPressStart: _handleHoldStart,
            onLongPressMoveUpdate: _handleHoldMove,
            onLongPressUp: _handleHoldUp,
            child: SizedBox(
              width: kVoiceSeatBox,
              height: kVoiceSeatBox,
              child: Center(
                child: AnimatedScale(
                  duration: Durations.short2,
                  curve: Easing.standard,
                  scale: live
                      ? 1 + 0.16 * _uiState.amplitude.clamp(0.0, 1.0)
                      : 1.0,
                  child: Icon(_live ? Icons.mic : Icons.mic_outlined, size: 22),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The bubble's coming and going, in both directions: a surface that only
/// arrives would leave the way it went unstated.
///
/// The switcher is the framework's, keyed on presence, and the empty state is a
/// zero box rather than nothing at all so the outgoing bubble has something to
/// cross-fade against instead of being cut.
class _BubbleSwitcher extends StatelessWidget {
  const _BubbleSwitcher({required this.live, required this.child});

  final bool live;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final motion = voiceMotionAllowed(context);
    return AnimatedSwitcher(
      duration: motion ? Durations.medium1 : Duration.zero,
      switchInCurve: Easing.emphasizedDecelerate,
      switchOutCurve: Easing.standardAccelerate,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          // Scaled about the tail: the bubble grows out of the seat it points
          // at, which is what makes it read as coming from that control.
          scale: Tween<double>(begin: 0.86, end: 1).animate(animation),
          alignment: Alignment.bottomCenter,
          child: child,
        ),
      ),
      child: live
          ? KeyedSubtree(key: const ValueKey<String>('bubble'), child: child)
          : const SizedBox.shrink(key: ValueKey<String>('no-bubble')),
    );
  }
}

/// The recording bubble: an elapsed clock, the live meter, and the line that
/// names the gesture the reader is in the middle of.
///
/// Hand-drawn rather than a framework surface because a bubble has to point:
/// card and tail are one contour, so the hairline runs around both and the
/// shadow falls from both — which a rounded [Card] with a separate triangle
/// cannot do without a seam where the two meet. Recorded in
/// [the voice bubble note](../../../../../../.agents/notes/implemented/feature/2026-09-02-voice-record-bubble.md).
class _VoiceRecordBubble extends StatelessWidget {
  const _VoiceRecordBubble({
    required this.link,
    required this.shift,
    required this.armed,
    required this.holding,
    required this.uiState,
  });

  final LayerLink link;
  final double shift;
  final bool armed;
  final bool holding;
  final VoiceInputUiState uiState;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final recording = uiState.phase == VoiceInputPhase.recording;
    final waiting = uiState.isWaitingOnEngine;
    final motion = voiceMotionAllowed(context) && uiState.isRecording;

    final hint = switch ((holding, armed, uiState.phase)) {
      (true, true, _) => l10n.voiceInputReleaseToCancel,
      (true, false, _) => l10n.voiceInputSlideToSend,
      (_, _, VoiceInputPhase.initializing) => l10n.voiceInputInitializing,
      (_, _, VoiceInputPhase.finalizing) => l10n.voiceInputFinalizing,
      (_, _, _) => l10n.voiceInputTapToFinish,
    };

    return CompositedTransformFollower(
      link: link,
      showWhenUnlinked: false,
      targetAnchor: Alignment.topCenter,
      // The tail tip, not the card's edge, seats itself above the mic: the
      // pointer is what ties the bubble to the control that opened it.
      followerAnchor: Alignment.bottomCenter,
      offset: Offset(shift, -kVoiceBubbleGap),
      child: IgnorePointer(
        child: SizedBox(
          width: kVoiceBubbleWidth,
          child: CustomPaint(
            painter: _BubbleShell(
              fill: armed ? scheme.errorContainer : scheme.surfaceContainer,
              hairline: scheme.outlineVariant,
              shadow: scheme.shadow,
              // The tail answers to the seat, wherever the viewport pushed the
              // card to stay out of it.
              tailX: kVoiceBubbleWidth / 2 - shift,
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                12,
                12,
                12,
                12 + kVoiceBubbleTail,
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
                          color: armed
                              ? scheme.onErrorContainer
                              : scheme.onSurface,
                          // The clock steps once a second; fixed-width digits
                          // stop the row shuffling under it.
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
                          // A hold that means "discard" stops showing the
                          // reader's voice and starts showing its own state.
                          dim: waiting || armed,
                          motion: motion,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    hint,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: armed
                          ? scheme.onErrorContainer
                          : scheme.onSurfaceVariant,
                    ),
                  ),
                  // Debug-only strip: native capture telemetry, so the data flow
                  // is visible on-screen without adb/logcat.
                  if (kDebugMode && uiState.debugStats != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        formatDebugStats(uiState.debugStats!) ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontFamily: 'monospace',
                          color: scheme.primary,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Card and tail as one contour: fill, hairline and shadow all follow the
/// combined path, so the tail cannot show a seam against the card's border.
class _BubbleShell extends CustomPainter {
  _BubbleShell({
    required this.fill,
    required this.hairline,
    required this.shadow,
    required this.tailX,
  });

  final Color fill;
  final Color hairline;
  final Color shadow;
  final double tailX;

  @override
  void paint(Canvas canvas, Size size) {
    final card = Rect.fromLTWH(
      0,
      0,
      size.width,
      size.height - kVoiceBubbleTail,
    );
    final body = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          card,
          const Radius.circular(kVoiceBubbleRadius),
        ),
      );
    // The tail's base overlaps the card by a pixel so the union leaves no notch
    // for the hairline to catch on.
    final tail = Path()
      ..addPolygon(<Offset>[
        Offset(tailX - 7, card.bottom - 1),
        Offset(tailX + 7, card.bottom - 1),
        Offset(tailX, card.bottom + kVoiceBubbleTail),
      ], true);
    final bubble = Path.combine(PathOperation.union, body, tail);

    canvas.drawShadow(bubble, shadow, 3, false);
    canvas.drawPath(bubble, Paint()..color = fill);
    canvas.drawPath(
      bubble,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = hairline,
    );
  }

  @override
  bool shouldRepaint(_BubbleShell oldDelegate) =>
      oldDelegate.fill != fill ||
      oldDelegate.hairline != hairline ||
      oldDelegate.tailX != tailX;
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

  /// The newest chunk's per-window peaks (0..1), one entry per band. Empty when
  /// a level arrived without a matching chunk.
  final List<double> envelope;

  /// The newest chunk's overall level, the meter's only input when there are no
  /// bands to show.
  final double level;

  /// Whether a session is on screen at all: the clock runs and the trail keeps
  /// its shape until the reader ends the session.
  final bool live;

  /// Whether the microphone is the live half of the session. When it is not —
  /// the engine is preparing or decoding — the trail scrolls out to the silence
  /// floor instead of freezing mid-word.
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

  /// The frame already turned into bars. A controller emit that carries no new
  /// audio — the once-a-second clock tick, which copies the state — keeps the
  /// same envelope object identity and the same level, so the meter does not
  /// draw the same chunk twice.
  List<double>? _seenEnvelope;
  double? _seenLevel;

  /// Whether real bands have reached the trail. Until they do it holds its
  /// seeded level rather than scrolling into silence nobody recorded.
  bool _hasInput = false;

  /// Newest level the stream reported, held on screen while the capture stream
  /// is slower than the meter's own bar cadence.
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
      // Newest last in the list, so the band order reads left to right the way
      // the queued bands will once they scroll in.
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
    // A frame gap — a paused app, a busy isolate, or the engine still loading a
    // model — must not replay every missed bar. Re-anchor the clock to now, and
    // while only the seeded level is on screen the seed moves with it, so a
    // session never opens on an empty strip.
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
      // Nothing in flight. A live capture holds the newest level — the stream is
      // slower than this cadence, not silent — while a session waiting on the
      // engine scrolls its trail out to the floor.
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

    // Walk back from the newest bar: it sits at the right edge and every earlier
    // one is older, so the first bar that has left the strip ends the run. Bars
    // the session clock has not reached yet sit past the right edge and simply
    // wait for the next frame.
    for (int i = bars.length - 1; i >= 0; i--) {
      final bar = bars[i];
      final x = rightEdge - (clockMs - bar.atMs) * dpPerMs;
      if (x < 0) break;
      if (x > size.width) continue;
      // The tail fades with age: motion the eye can follow before the bar has
      // to leave the strip.
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
