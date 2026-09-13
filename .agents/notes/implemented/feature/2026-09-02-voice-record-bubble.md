# Agent Note: The recording surface becomes a bubble anchored to the mic

Status: implemented

## Problem

[The motion pass](2026-09-02-voice-input-motion.md) left the session surface as a
dock inside the composer: a bar in the input row that, on opening, pushed the
draft and tool row apart and covered the field the transcript was arriving in. The
ask was the native shape — a popup that pops, carrying the waveform and the clock
— with the capture boundaries audible as well as felt.

## Decision

**The bubble hangs off the control that opened it.** `VoiceHoldBar` is stateful
and owns the session surface: a `LayerLink`/`CompositedTransformTarget` on the
bar, an `OverlayPortal` whose child is a `CompositedTransformFollower`, so the
bubble follows the bar through a keyboard opening or a dock re-layout.
`OverlayPortal` not `OverlayEntry`, because the overlay child then keeps the
bar's inherited scope — the only reason theme and `voiceMotionAllowed` still
resolve for it — and cannot outlive the control. The controller is shown from a
frame callback; it is not attached during build.

**A sheet was refused.** `showModalBottomSheet` and the house `showMenuSheet` both
put a modal route and a barrier over the composer: a release straying off the
sheet dismisses the surface mid-sentence, and the draft the transcript lands in
sits behind a scrim. The bubble is non-modal, takes no focus, and is
`IgnorePointer`ed — it reports the session and is never the control that ends one.

**One contour, not a card with a triangle.** `_BubbleShell` paints card and tail
as a single `Path` union, so the `outlineVariant` hairline runs around both and
`drawShadow` falls from both; a rounded container plus a separate tail seams where
they meet. Geometry stays house: `kShapeMenuSheet` radius, `surfaceContainer`, and
the tail tip — not the card edge — seats above the mic, since the pointer is what
ties surface to control. Width is fixed and the seat corrects horizontally after
layout (a follower cannot read its leader's box during build), so a bubble near
the screen edge cannot hang off it.

**One gesture, one surface.** A press holds a capture for as long as the finger
is down: release sends, sliding past `kVoiceCancelSlide` first arms a discard —
the surface turns to the `errorContainer` pair and says "松开取消". Both the
press and the release are a raw `Listener` on the bar. The tap path and its
Cancel/Send seats are gone; the hold moved from the 40dp seat to a full-width
bar, and the reason the recognizer was replaced is in
[the hold-to-talk note](2026-09-13-hold-to-talk-composer.md), which supersedes
this paragraph. A release always sends or discards unconditionally — gating on
`isRecording` would drop the intent when a release beats the controller's first
state change, leaving a capture running with nobody holding it.

**Earcons are the platform's.** `playVoiceSound(VoiceSound)` rides the
`dsh/audio_record` channel to `AudioManager.playSoundEffect` — `start` →
`FX_FOCUS_NAVIGATION_UP` (the switch tick), `send` → `FX_KEYPRESS_STANDARD`
(the dialpad key), `cancel` → `FX_KEYPRESS_DELETE` (the delete key), the
closest distinct entries in the public `FX_` list, all `playSoundEffect`
accepts. No asset ships, the device's sound-effects setting governs them, and
they stay audible while the microphone is hot. A host without an effect goes
silent: a missing earcon never reads as a failed capture.

**Both edges animate.** Entrance and exit are one `AnimatedSwitcher` keyed on
presence — `Easing.emphasizedDecelerate` in, `standardAccelerate` out — scaled
about `Alignment.bottomCenter` so it grows out of the seat; the empty state is a
zero box so an outgoing bubble has something to cross-fade against. Under
`voiceMotionAllowed` the switch and the meter's slide stop together.

## Alternatives considered

- **Keep the in-composer dock**: the row it displaces is the row the transcript
  needs.
- **`showModalBottomSheet` / `showMenuSheet`**: modal, scrimmed, barrier
  dismissible — wrong for a surface a sliding thumb must survive.
- **`OverlayEntry`**: builds under the `Overlay`, so the bubble loses the seat's
  inherited scope and can outlive it.
- **Bundled WAV earcons via `SoundPool`**: the most authored sound, paid for in
  binary assets, lifecycle code and F-Droid disclosure, for a sound the platform
  already owns.
- **`SystemSound.play(click)`**: no channel work, but one click for three outcomes.

## Consequences

`VoiceHoldBar` takes `uiState` plus `onStart`/`onFinish`/`onCancel` instead of
flags and one `onTap`; the composer's draft-restore cancel moved onto `onCancel`,
and with the dock gone there is exactly one recording surface. Tests cannot
reach the bubble in the `Overlay`, so `voice_hold_bar_test.dart` asserts through
text and geometry, drives holds with `startGesture`/`moveBy`, and reads earcons
back from a mocked `dsh/audio_record`. A live session never settles while motion
is allowed, and the exit needs one pump to begin and one to finish.