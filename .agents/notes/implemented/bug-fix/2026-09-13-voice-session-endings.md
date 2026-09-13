# Agent Note: A voice session ends once, and only the session that began it publishes

Status: implemented

## Problem

The recording surface's Cancel and Send seats sometimes did nothing: the reader
tapped, and the capture stayed on screen or came back a moment later.

`VoiceInputController` had no notion of which session an in-flight
`startRecording` belonged to. Its awaits — the permission round trip, the
`AsrEngine.initialize` model load, the native `_recorder.start()` — resumed
after the reader's ending and published `recording` again, over the `idle` the
ending had just emitted. `stopRecording` re-entered on its own state (the
guard was `isRecording`, which is true while `finalizing`), running a second
`AsrEngine.finish` over audio the first had already decoded. And a session that
ended in `error` refused every later press, because the gate was `phase !=
idle`: the control latched dead with nothing on screen to clear it.

## Decision

**A session generation, checked after every await.** `_epoch` is bumped by
every start and every ending; `startRecording` claims `++_epoch` before its
first await and re-reads it at each subsequent one, returning without touching
state when it no longer matches. The reader's ending is therefore final:
whatever the load or the native start does afterwards is void.

**An engine is published only after `initialize` returns.** `_activeEngine` is
assigned once the native load has completed, so a teardown landing mid-load has
no half-initialized engine to dispose underneath itself; the abandoned start
releases what it built on its own way out. A stale window after
`_recorder.start()` stops the recorder it just opened, or the microphone stays
hot under a session nobody owns.

**One session, one finish.** `stopRecording` returns the `_finishInFlight`
future to every later caller, so a release plus a repeated callback run one
`AsrEngine.finish` and emit one final transcript.

**An ending states its own outcome.** `_teardown` releases the capture without
touching state; the caller emits `idle` (cancel) or `error` (failure). A
release that arrives before the first audio is a cancel, not a finalize: there
is no complete capture to send, and an empty final transcript over the draft
would be an invented one.

**A stale error does not close the control.** `startRecording` refuses only
while `VoiceInputUiState.isSessionActive` (preparing, capturing, decoding), so
a failure is a state the reader can leave by pressing again.

## Alternatives considered

- **Disable the seats while the engine is preparing.** They already were
  disabled for the microphone seat, and the defect did not change: the state
  machine, not the skin, was publishing over the ending.
- **A `mounted`-style boolean flag instead of a generation.** Weaker: after a
  cancel and a new press, the first session's tail would still match a boolean
  and publish over the second session's state.
- **Gate `stopRecording` on `phase == recording`.** Drops the release that
  beats the controller's first state change, which is the intent the hold path
  exists to keep.
- **Let the error phase clear on a timer.** Invents a duration for a condition
  the reader, not the clock, resolves.

## Consequences

`VoiceInputUiState` gains `isSessionActive` beside `isBusy`, and the composer
gates its mode seat on it. The controller's endings are now idempotent and
epoch-scoped; `voice_input_controller_test.dart` holds a cancel during the
model load, a release during the load, a repeated ending, and the press after
an error. The tap-driven seats this defect was found on are gone — see
[the hold-to-talk note](../feature/2026-09-13-hold-to-talk-composer.md) — but
the guard is what makes any ending on that surface trustworthy.
