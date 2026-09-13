/// The composer's press-and-hold voice control.
///
/// One surface carries the whole capture: the finger goes down and recording
/// starts, the finger stays down for as long as the reader speaks, and it
/// comes up to send. Sliding up past [kVoiceCancelSlide] first arms the
/// discard, and the surface says so before the finger lifts — the same two
/// gestures the native voice memo has trained, on a target the width of the
/// dock rather than a 40dp glyph.
///
/// The gesture is a [Listener], not a long-press recognizer: a press that
/// means "record now" must not wait out a long-press deadline, and every
/// `PointerCancelEvent` has to reach the control. A recognizer that loses its
/// arena to a system gesture leaves an accepted hold with no release, which is
/// how a control ends up stuck mid-capture and answering nothing.
library;

import 'dart:async';

import 'package:app/l10n/app_localizations.dart';
import 'package:app/platform/audio_recorder.dart';
import 'package:asr/asr.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../shared/tappable_feedback.dart';
import '../../theme/theme.dart';
import 'voice_input_ui_state.dart';
import 'voice_record_bubble.dart';

/// The bar's own height: tall enough to be the Android touch target on its
/// own, because it replaces the draft field as the band the thumb stands in.
const double kVoiceHoldBarHeight = 48;

/// The mode seat's box: the 40px the rest of the composer's tools row already
/// gives an `IconButton`, so swapping the mic for the mode switch moves no
/// other seat.
const double kVoiceSeatBox = 40;

/// The composer's hold-to-talk bar, and the owner of the recording surface it
/// anchors.
///
/// A press opens a capture and holds it; releasing sends, and sliding up past
/// [kVoiceCancelSlide] discards instead. Every boundary carries a haptic and an
/// earcon, so the outcome is legible without looking at the screen.
class VoiceHoldBar extends StatefulWidget {
  const VoiceHoldBar({
    required this.enabled,
    required this.busy,
    required this.uiState,
    required this.onStart,
    required this.onFinish,
    required this.onCancel,
    required this.onOpenSettings,
    super.key,
  });

  /// Whether the composer accepts input at all. Stable for the life of a hold:
  /// [busy] carries the engine's own phases, so the bar is never rebuilt out
  /// from under a finger that is already recording.
  final bool enabled;

  /// Whether the engine, not the reader, holds the session (loading a model,
  /// decoding audio). The bar refuses a press and says which wait it is.
  final bool busy;

  final VoiceInputUiState uiState;
  final VoidCallback onStart;
  final VoidCallback onFinish;
  final VoidCallback onCancel;
  final VoidCallback onOpenSettings;

  @override
  State<VoiceHoldBar> createState() => _VoiceHoldBarState();
}

class _VoiceHoldBarState extends State<VoiceHoldBar> {
  /// Publishes the bar's box to the follower, so the bubble rides the bar
  /// through a keyboard opening or a dock re-layout instead of being placed
  /// once.
  final LayerLink _link = LayerLink();

  /// The portal stays shown for the bar's whole life; what comes and goes is
  /// the bubble the builder returns. Showing it from a frame callback rather
  /// than from [build] is what keeps the controller attached.
  final OverlayPortalController _portal = OverlayPortalController();

  /// Horizontal correction that keeps the bubble inside the viewport, derived
  /// from the bar's own rect after layout (see [_measure]).
  double _shift = 0;

  /// The pointer that owns the hold, or null when no finger is down. Tracking
  /// the id keeps a second finger from reading as the release.
  int? _pointer;

  /// Where that pointer went down, in global coordinates: the slide is
  /// measured from here so a finger that drifts without ever leaving the bar
  /// still cannot arm the discard.
  double _downY = 0;

  /// Whether the hold has travelled far enough up to mean "discard".
  bool _armed = false;

  VoiceInputUiState get _uiState => widget.uiState;

  bool get _live => _uiState.isRecording;

  bool get _holding => _pointer != null;

  /// Which readiness gate a press crosses: on-device capture needs an installed
  /// model and the downloaded runtime, online capture needs configured
  /// credentials.
  bool get _ready => switch (_uiState.inputMode) {
    VoiceInputMode.offline =>
      _uiState.hasInstalledModels && _uiState.runtimeInstalled,
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
  void didUpdateWidget(VoiceHoldBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The bar's own box moves when the keyboard opens or the tools row wraps,
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
    final bar = box.localToGlobal(Offset.zero);
    final ideal = bar.dx + box.size.width / 2 - kVoiceBubbleWidth / 2;
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
    // Three gates, three dialogs: online credentials, a missing model, or the
    // runtime the engine maps (which is downloaded separately from the model).
    final (String title, String body) = switch (_uiState) {
      _ when online => (
        l10n.voiceInputCloudSetupTitle,
        l10n.voiceInputCloudSetupBody,
      ),
      VoiceInputUiState(hasInstalledModels: false) => (
        l10n.voiceInputNoModelTitle,
        l10n.voiceInputNoModelBody,
      ),
      _ => (l10n.voiceInputNoRuntimeTitle, l10n.voiceInputNoRuntimeBody),
    };
    _showSetupDialog(context, title: title, body: body);
    return false;
  }

  void _handleDown(PointerDownEvent event) {
    if (_holding || !widget.enabled || widget.busy) return;
    // The gate runs on the press, not the release: a reader without a model
    // gets the dialog the moment they reach for the control.
    if (!_gateReady()) return;
    setState(() {
      _pointer = event.pointer;
      _downY = event.position.dy;
      _armed = false;
    });
    if (!_live) _start();
  }

  void _handleMove(PointerMoveEvent event) {
    if (event.pointer != _pointer) return;
    final armed = event.position.dy - _downY <= -kVoiceCancelSlide;
    if (armed == _armed) return;
    unawaited(HapticFeedback.selectionClick());
    setState(() => _armed = armed);
  }

  void _handleUp(PointerUpEvent event) {
    if (event.pointer != _pointer) return;
    // The release carries the reader's intent whether or not the state has
    // caught up: lifting a finger whose session is still arriving must end it,
    // not leave a capture running with nobody holding it.
    final discard = _armed;
    _endHold();
    if (discard) {
      _discard();
    } else {
      _finish();
    }
  }

  void _handleCancel(PointerCancelEvent event) {
    if (event.pointer != _pointer) return;
    // The platform took the pointer — a system gesture at the screen edge, the
    // app leaving the foreground. Nobody said "send", so the capture is
    // discarded rather than guessed at; clearing the hold here is also what
    // stops an interrupted press from leaving the control dead.
    _endHold();
    _discard();
  }

  void _endHold() => setState(() {
    _pointer = null;
    _armed = false;
  });

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

  /// The one line the bar says: the engine's wait while it holds the session,
  /// else the gesture the finger is in the middle of, else the invitation.
  String _label(AppLocalizations l10n) {
    // The engine's wait outranks the finger: while it holds the session there
    // is nothing the reader's gesture can change.
    if (widget.busy) {
      return switch (_uiState.phase) {
        VoiceInputPhase.initializing => l10n.voiceInputInitializing,
        VoiceInputPhase.finalizing => l10n.voiceInputFinalizing,
        _ => l10n.voiceHoldToTalk,
      };
    }
    if (_holding) {
      return _armed
          ? l10n.voiceInputReleaseToCancel
          : l10n.voiceInputReleaseToSend;
    }
    return l10n.voiceHoldToTalk;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final holding = _holding;
    final label = _label(l10n);
    // One tone per phase, from the role map: resting, capturing, and the
    // discard the reader has armed. The bar is the surface's only status
    // display, so the state is legible from the thumb's own corner of the eye.
    final (Color fill, Color ink) = switch ((holding, _armed)) {
      (true, true) => (scheme.error, scheme.onError),
      (true, false) => (scheme.errorContainer, scheme.onErrorContainer),
      _ => (scheme.surfaceContainerHigh, scheme.onSurfaceVariant),
    };

    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _portal,
        overlayChildBuilder: (context) => VoiceRecordBubble(
          live: _live,
          link: _link,
          shift: _shift,
          armed: _armed,
          holding: holding,
          uiState: _uiState,
        ),
        child: DshTappable(
          // The bar's own phase impacts are the click this gesture produces,
          // so the wrapper supplies only the scale — at a gentler ratio than a
          // 40dp seat's, because a full-width band shrinking five percent
          // reads as the layout wobbling under the thumb.
          enabled: widget.enabled,
          enableHaptic: false,
          pressedScale: 0.99,
          child: Semantics(
            button: true,
            enabled: widget.enabled && !widget.busy,
            // The announced name tracks the phase with the visible one, so a
            // screen reader says what the bar says.
            label: label,
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: _handleDown,
              onPointerMove: _handleMove,
              onPointerUp: _handleUp,
              onPointerCancel: _handleCancel,
              child: Container(
                height: kVoiceHoldBarHeight,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: fill,
                  borderRadius: BorderRadius.circular(kShapeChip),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(
                      holding ? Icons.mic : Icons.mic_none,
                      size: 18,
                      color: ink,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _label(l10n),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        height: 1.2,
                        fontWeight: FontWeight.w500,
                        color: ink,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
