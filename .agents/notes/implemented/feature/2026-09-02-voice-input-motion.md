# Agent Note: Commercial-grade motion for the on-device voice dock

Status: implemented

## Problem

The dock that [on-device voice input](2026-08-25-on-device-voice-input.md) shipped
with read as a static instrument. Its comment promised a pulsing dot and a live
soundwave; it drew an unmoving dot and eight bars driven by one 10 Hz number.
Loading a model and decoding audio, both slow on a phone, looked exactly like
capturing. The seat was a hand-drawn 28px `Material` + `InkWell`: no tooltip, half
the touch target of its neighbour `_PlusButton`, nothing felt. The signal was
wasted too — one peak-normalized level per 100 ms chunk, spent as one number ten
times a second on a strip that can show forty.

## Decision

**The chunk carries a sub-peak envelope.** `VoiceInputUiState.envelope` holds the
newest chunk's peak per equal time window. The controller derives it from the
`Float32List` it already forwards to the engine and pairs it with the level event
for the same frame one microtask later, so `subPeak / chunkPeak * level` lands in
`amplitude`'s 0..1 space: no second peak tracker, no copy of the recorder's
release. Cadence is derived, never typed — `kVoiceMeterBarStep =
kVoiceCaptureChunkMs ~/ kVoiceEnvelopeBands` — so a change to the native chunk
moves the scroll speed with the audio. An empty envelope means "draw one bar at
`amplitude`".

**The meter is a painter scrolling on the session clock.** A bar enters at the
right edge every 25 ms; the trail slides left at constant speed and fades with
age. No implicit animation gives a continuous x offset per frame without
re-laying-out a growing row, so `_LiveVoiceMeter` is a `CustomPainter` — a third
standing exception in `app`, beside the markdown renderer and the outline. It runs
a `Ticker`, not an `AnimationController`, because its clock *is* session time:
bars land at the instant of the audio they describe, and a frame gap resyncs
instead of replaying missed bars. Two rules keep it honest. With no past the trail
seeds the current level across its window, as a level meter does before it has
history, and holds until the first band drains — a session never opens on an empty
strip. While capturing, a late chunk holds the newest level: the stream is slower
than the bar cadence, not silent. Only a session waiting on the engine scrolls the
trail to the floor.

**One phase, one face.** `VoiceInputUiState.isWaitingOnEngine` names the phases
where the engine holds the turn, and both call sites read it: the surface spins a
ring and says "Getting ready…" / "Transcribing…" while the seat stays live through
the capture. That rule fixed a defect — the seat had disabled itself on `isBusy`
for the whole session, so its own stop-to-finish branch was unreachable and
Material's disabled overlay hid the recording role pair. The mark pulses a halo
that leaves the dot and dies, the seat became a stock 40px `IconButton` like the
rest of its row, and `voiceInputTooltip` — an ARB key in both locales with no call
site — has one. Haptics mark the boundaries: medium on the two capture edges,
light on cancel, heavy where a dead capture surfaces its `SnackBar`. Where that
surface sits moved on to [the bubble note](2026-09-02-voice-record-bubble.md).

Durations and curves are Material motion tokens (`Durations.medium1`,
`Easing.standard`, `Easing.emphasizedDecelerate`), so motion stays a framework
default. Bespoke animation stops on `voiceMotionAllowed`, which reads the platform
reduce-motion flag and `TickerMode`, leaving a stepped, legible meter.

## Alternatives considered

- **Raw PCM at the widget layer**: a capture subscription in a widget,
  duplicating the recorder's normalization.
- **A real FFT or spectrum split**: the capture is one mono peak, so bands would
  be invented — a fake meter — and the CPU belongs to inference.
- **Per-bar `sin(index)` weighting, smoothed**: what shipped — a fake spectral
  variety from a constant, so a steady tone reads as motion it did not earn.

- **A full-screen recorder sheet**: the composer owns this space per
  [the timeline restyle](2026-08-20-chat-timeline-restyle-proposal-a.md).

## Consequences

The dock answers while the microphone listens. `envelope` belongs to the recorder,
not the engine, so cloud capture shares the meter with no extra wiring. Widget
tests must not `pumpAndSettle` a recording surface: a live meter never settles.
The bubble test pumps fixed frames, asserting non-settlement while capturing and
settlement under reduce-motion — the pair guarding both halves of
`voiceMotionAllowed`. `envelope` is `const <double>[]` outside a live frame, so no
stale trail survives a session. The design harness speaks a scripted phrase, one
chunk per pumped frame, since a lumped `pump(400ms)` coalesces four chunks and
reviews an empty meter.