# Agent Note: Voice recording failures surface instead of a phantom dock

Status: implemented

## Problem

After granting the microphone permission, voice input entered a "recording"
state that never produced audio: the dock appeared with the timer running,
but the soundwave stayed flat and no transcription arrived, with no error
anywhere. The grant flow proved the method channel and `MainActivity` were
alive, so the failure was downstream of permission.

## Decision

Three defects in the recording path are fixed:

1. **Native start failures are no longer swallowed.** `PlatformAudioRecorder
   .start()` caught `PlatformException` and discarded it (setting only
   `_isRecording = false`), so when `MainActivity`'s `AudioRecord` failed to
   initialize, the controller still emitted `VoiceInputPhase.recording` — a
   phantom dock. `start()` now cleans up its event subscription and rethrows;
   `VoiceInputController` catches that specific case and emits the stable,
   localizable `RECORD_START_FAILED` error (new `voiceInputRecordFailed` ARB
   key, both locales), shown as a SnackBar in the composer.
2. **The subscribe-after-start race is closed.** `startRecording()` awaited
   `_recorder.start()` before subscribing to `audioStream`/`amplitudeStream`;
   both are broadcast (non-buffering) controllers, so events emitted in that
   window were dropped, losing the first ~100 ms of input. The controller now
   subscribes first, then starts capture.
3. **The native stop path no longer releases under a live `read()`.** `stop
   AudioCapture()` called `AudioRecord.release()` from the platform thread
   while the recording thread could still be blocked in `read()`, which is
   undefined and can crash. It now `stop()`s (which unblocks `read()`), joins
   the thread (bounded 500 ms), then releases.

## Alternatives considered

- **Ignore native errors and let the phantom dock stand**: rejected — it is
  the reported bug; a recording UI with no audio and no feedback is worse
  than a clear failure.
- **Only log the error**: rejected — the user gets no visible signal; the
  composer already had the SnackBar path for `PERMISSION_DENIED`, so the
  failure rides the same channel.
- **Leave `stopAudioCapture` as-is and only guard `read()`**: rejected — the
  guard belongs at the release, and `stop()` + `join()` is the documented
  way to drain a blocking `read()`.

## Consequences

A native capture failure now ends the session with a real error state and a
SnackBar instead of a silent flat waveform, and no audio is lost at session
start. Regression tests cover both: the controller no longer reports
`recording` on a `record_error`, and `PlatformAudioRecorder.start()` rethrows
the native failure. The ASR engine runners remain stubs (empty transcription
is a separate, known limitation of the inference integration, not this
defect).
