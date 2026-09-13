# Agent Note: Tactile press feedback is the composer's standard

Status: implemented

## Problem

[DshTappable](../../../../flutter/app/lib/ui/shared/tappable_feedback.dart)
was the client's stated press-feedback contract — a spring scale-down plus
haptics, driven by the `DshMotion` tokens — but only the jump-to-bottom FAB
adopted it. The seats a thumb hits every turn — the composer's send/stop,
`+`, and voice-mic seats, the access chip, the model seat, and the question
card's round icon buttons — rode stock Material ink instead, so the row the
reader touches most answered differently from the app's own standard. No rule
said which feedback a seat owed, so every call site re-decided it.

## Decision

**`DshTappable` is a seat's only press feedback.** A seat that adopts it
contributes one press animation (the wrapper's scale) and at most one haptic.
The wrapper observes the pointer and never owns the tap of a Material control,
which keeps its `onPressed`/`onTap`, enabled state, tooltip, semantics, and
hit box; the wrapper is a skin, not a replacement. A hand-built seat passes
`onTap` so the wrapper owns the gesture.

**Ink goes where the scale arrives.** A control that already paints ink
suppresses it at the call site rather than animating the press twice:
`IconButton`s take `highlightColor: Colors.transparent`,
`NoSplash.splashFactory`, and `enableFeedback: false`; the two wrapped FABs
also take `splashColor: Colors.transparent` and
`highlightElevation == elevation`, with the theme's `highlightColor`
neutralised around them by `_tactileFab`. The hand-built seats (the access
chip, `_RoundIconButton`) drop their `InkWell` so no second gesture recognizer
can double-fire.

**One haptic per press.** `enableHaptic: true` fires one
`HapticFeedback.selectionClick` on pointer down for the send/stop, `+`, model,
access, and round-icon seats. The voice mic leaves it false: it already
answers each capture boundary with its own impact and earcon, so the wrapper
supplies only the scale.

**`enabled` mirrors the seat.** `DshTappable(enabled: false)` passes the child
through untouched, so a disabled seat neither scales nor clicks while its own
disabled rendering and hit box stand. Reduced motion drops the scale
transition, and a muted `TickerMode` mutes the wrapper's ticker so the scale
stays at rest; both leave the seat tappable.

Adopted: `_PrimarySendButton`, `_PlusButton`, the composer's voice mode seat,
`PermissionSelectChip`, `ModelSelect`, `_RoundIconButton`, and the
jump-to-bottom FAB, which now follows the same no-ink rule. The voice control
itself became `VoiceHoldBar` in
[the hold-to-talk pass](2026-09-13-hold-to-talk-composer.md): it carries the
wrapper with `enableHaptic` false, because its own phase impacts are the click.

## Alternatives considered

**A global theme option** (`splashFactory: NoSplash` on `ThemeData`) strips
ink from every Material surface — list rows, menu items, dialogs, buttons —
so a menu row loses the ripple that is its own affordance. The decision
belongs to a seat, not the app. **An app-wide wrapper at the root**
(`MaterialApp.builder`) cannot see which control was pressed, cannot mirror a
seat's enabled state, and would scale whole screens on a stray pointer-down.
**Leaving the call sites as-is** keeps the ripple-plus-squash on the
jump-to-bottom FAB and no feedback contract on the composer. **Driving the
callback through the wrapper** (moving `onPressed` off the FAB/IconButton)
would leave `onPressed` permanently null, contradicting the widget tests that
read the seat's enabled state and the component's own disabled rendering.

## Consequences

The composer row answers a press the same way at every seat, and the rule is
checkable: [tactile_seats_test.dart](../../../../flutter/app/test/ui/chat/tactile_seats_test.dart)
asserts each seat carries one wrapper, the send seat dispatches one prompt per
tap, the empty-draft send seat is inert, and reduced motion keeps the seat
usable while building no scale.
[tappable_feedback_test.dart](../../../../flutter/app/test/ui/shared/tappable_feedback_test.dart)
proves one haptic per press, that a wrapped control's own tap still fires
once, and that a muted `TickerMode` holds the scale at rest. Trade-off: the M3
ink ripple is gone from those six seats, so their press is no longer the stock
Android response; the scale and haptic stand in for it. Menus, sheet rows,
list rows, the queue dock actions, and transcript icon buttons keep plain ink
and are deliberately unwrapped — a row's or a menu item's ripple is its own
affordance, and scaling a full-width row reads as ornament.
