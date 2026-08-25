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

A follow-up round targets the cases that survive the above — a real device
that grants permission and starts capture but delivers no usable audio:

4. **Mid-session capture death ends the dock.** The recorder's event-channel
   `onError` previously called `stop()` silently; any transport failure left
   the dock in a phantom recording state. The recorder now publishes capture
   errors on an `errors` stream, which the controller turns into a real
   `RECORD_INPUT_FAILED` / `RECORD_SILENT_INPUT` error state with a SnackBar.
5. **Silent input is detectable, not invisible.** Android 12+ delivers
   silence (not an error) when the mic access toggle is off or another app
   holds the microphone. The native capture loop tracks the max |sample| of
   every buffer and raises `input_silent` via the event channel after ~2 s of
   pure zeros; the controller maps it to the localizable
   `RECORD_SILENT_INPUT` error naming the toggle.
6. **Source fallback for OEM quirks.** Some devices return silence on
   `VOICE_RECOGNITION`; `startAudioCapture` now tries `VOICE_RECOGNITION`,
   then `MIC`, then `UNPROCESSED` (API 24+), and records which source won.
7. **In-app diagnostics (no adb/logcat needed).** A `dsh/audio_debug` method
   channel exposes native read counts, events sent, max amplitude, the
   active source, and the mic-mute state; in debug builds the recording dock
   shows the strip so the data flow is visible on-screen. Amplitude mapping
   was raised from `rms * 4` to `rms * 8` because `VOICE_RECOGNITION` /
   `MIC` carry no AGC and quiet speech otherwise sits at the floor.
8. **Adaptive waveform normalization.** A device probe sent
   `reads=84 max=0.011 sent=84 got=84` — capture fully healthy, yet a
   fixed `rms * 8` gain still rendered near-floor bars (0.011 peak → ~0.03
   amplitude). The recorder now tracks a fast-attack / slow-release peak
   (`_peakLevel`, ×0.96 per 100 ms frame) and normalizes each frame's peak
   against it, so the bars stay visibly alive from near-silence to loud
   input; silence still decays to the floor.

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
- **Require adb/logcat to diagnose silent input**: rejected — the reporter
  had no adb access; the debug strip puts the same signal on the screen.
- **Keep `VOICE_RECOGNITION` as the only source**: rejected — some OEM
  devices return silence on it, and a silent fallback chain is cheap.

## Consequences

A native capture failure now ends the session with a real error state and a
SnackBar instead of a silent flat waveform, and no audio is lost at session
start. Silent input halts after ~2 s with a named, localizable reason, and
the debug strip shows exactly where the data flow stops. Regression tests
cover: the controller no longer reports `recording` on a `record_error`;
`PlatformAudioRecorder.start()` rethrows the native failure; a native
`input_silent` envelope ends a phantom recording; `debugStats` surfaces
native counters; and the dock renders the debug strip only with stats. The
ASR engine runners remain stubs (empty transcription is a separate, known
limitation of the inference integration, not this defect).
