# Agent Note: The composer's voice band is a hold-to-talk bar

Status: implemented

## Problem

The composer's voice input was a 40dp microphone seat: a tap opened a capture
and the next tap sent it, a hold recorded only while the finger was down, and
the anchored bubble grew its own Cancel and Send seats for the tap path. That
is not the shape a phone reader has been trained on. WeChat and QQ put the
whole band behind one press — a mode switch beside the input, one wide
"按住 说话" bar, press to speak, release to send, slide up to cancel — and the
extra seats were exactly where the reader's thumb was not.

## Decision

**A mode seat, and one band that swaps.** The tools row now leads with a
`_VoiceModeToggle` (mic glyph in text mode, keyboard glyph in voice mode, its
icon in `primary` while voice is active). It is the only place the mode
changes: the band above it is the draft field or the hold bar, and it never
becomes the other one on its own. The seat is locked while a session is active,
because swapping it unmounts the control holding the microphone. Leaving text
mode drops the keyboard; returning opens the field, because that is the mode
the reader asked for.

**One full-width bar, no buttons.** `VoiceHoldBar` replaces the field band in
voice mode: `kVoiceHoldBarHeight` (48dp, the Android touch target) on the chip
radius, carrying the phase on its own face — `surfaceContainerHigh` at rest,
`errorContainer` while capturing, `error` once the discard is armed. Press
starts, release sends, sliding up past `kVoiceCancelSlide` arms the discard.
The Cancel/Send seats are gone; both endings are the gesture.

**The gesture is a `Listener`, not a recognizer.** A press that means "record
now" may not wait out `kLongPressTimeout`, and — the failure that motivated the
change — a long-press recognizer that loses its arena leaves an accepted hold
with no release, so the control answers nothing from then on. A `Listener`
sees the pointer down immediately and is guaranteed its `PointerUpEvent` or
`PointerCancelEvent`; a cancel discards rather than guessing at an intent
nobody expressed, and clears the hold.

**The bubble reports and never controls.** `VoiceRecordBubble` still hangs off
the control that opened it (the tail points at the bar, the width is fixed and
the horizontal correction keeps it in the viewport), but it wraps itself in
`IgnorePointer`. Nothing in it is interactive, so it can never be the seat that
fails to answer a tap.

**Accessibility trade-off, taken deliberately.** WCAG 2.2 asks for a
single-pointer alternative to an author-controlled drag, and the slide-up
discard is one. The reader chose WeChat parity over keeping the tap path and
its buttons. What remains is what the platform gives every hold: two boundary
haptics, three earcons, and the bar's own state text, which names the armed
discard before the finger lifts.

## Alternatives considered

- **Keeping the tap path and its Cancel/Send seats.** Declined by the product
  ask: those seats were the surface the reader was trying to get away from.
- **The previous inner `GestureDetector` hold.** Imposes the long-press
  deadline and loses the release when the arena is lost — the stuck control.
- **Making the whole dock band (tools row included) the hold target.** Costs
  the attach and access seats a row, and puts the hold under controls the
  reader presses for other reasons.
- **A modal sheet recorder.** Rejected in
  [the voice bubble note](2026-09-02-voice-record-bubble.md) and still wrong: a
  release straying off the sheet would dismiss the capture.
- **Tinting the bubble instead of the bar.** The thumb is on the bar and the
  eye follows the finger; the state belongs on the surface being pressed.

## Consequences

The control moves to a new file, `voice_hold_bar.dart`; `voice_record_bubble.dart`
keeps the bubble and its meter only. `voice_hold_bar_test.dart` replaces
`voice_record_bubble_test.dart` and drives presses with
`startGesture`/`moveBy`/`up`/`cancel`, including the pointer-cancel case. New
ARB keys (`voiceHoldToTalk`, `voiceInputReleaseToSend`, `voiceModeKeyboard`)
join the two locales, and the dead ones (`voiceInputDone`,
`voiceInputTapToFinish`, `voiceInputCancel`) leave them. The tool-row metrics
hold: the mode seat is the 40dp box the microphone seat occupied.
