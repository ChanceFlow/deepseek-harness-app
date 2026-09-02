# Agent Note: The recording surface becomes a bubble anchored to the mic

Status: implemented

## Problem

[The motion pass](2026-09-02-voice-input-motion.md) left the session surface as a
dock inside the composer: a bar in the input row that, on opening, pushed the
draft and tool row apart and covered the field the transcript was arriving in. The
ask was the native shape — a popup that pops, carrying the waveform and the clock
— with the capture boundaries audible as well as felt.

## Decision

**The bubble hangs off the seat that opened it.** `VoiceMicButton` is stateful and
owns the session surface: a `LayerLink`/`CompositedTransformTarget` on the seat,
an `OverlayPortal` whose child is a `CompositedTransformFollower`, so the bubble
follows the seat through a keyboard opening or a tool-row wrap. `OverlayPortal`
not `OverlayEntry`, because the overlay child then keeps the seat's inherited
scope — the only reason theme and `voiceMotionAllowed` still resolve for it — and
cannot outlive the seat. The controller is shown from a frame callback; it is not
attached during build.

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

**Two gestures, one surface.** A tap opens a capture and the next tap sends it,
keeping the seat usable for anyone who cannot hold. A press that keeps holding
records only while the finger is down: release sends, sliding past
`kVoiceCancelSlide` first arms a discard — the bubble turns to the
`errorContainer` pair and says "松开取消". The hold is recognised **inside** the
`icon:` slot, not around the button: a Material `Tooltip` shows itself on long
press, and its recognizer is deeper than any detector wrapped around the seat, so
an outer hold detector loses the arena and a hold only ever revealed the tooltip.
In the slot the hold wins while a tap still falls through; `iconSize` and
`padding` are set so the detector covers the whole seat with no dead ring.
`onLongPressUp` sends or discards unconditionally — gating on `isRecording` would
drop the intent when a release beats the controller's first state change, leaving
a capture running with nobody holding it.

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

`VoiceMicButton` takes `uiState` plus `onStart`/`onFinish`/`onCancel` instead of
flags and one `onTap`; the composer's draft-restore cancel moved onto `onCancel`,
and with the dock gone there is exactly one recording surface. Tests cannot
reach the bubble in the `Overlay`, so
`voice_record_bubble_test.dart` asserts through text and geometry, drives holds
with `startGesture`/`moveBy`, and reads earcons back from a mocked
`dsh/audio_record`. A live session never settles while motion is allowed, and the
exit needs one pump to begin and one to finish.