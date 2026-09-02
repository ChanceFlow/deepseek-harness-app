# Agent Note: Online voice input via Volcengine Doubao and Tencent Hunyuan streaming ASR

Status: implemented

## Problem

Voice input was offline-only: transcription ran on-device through sherpa-onnx, and the
settings surface only managed downloaded model weights. Two gaps followed. First, users on
low-end devices (no installed model, slow inference) had no voice input at all. Second,
users who accept cloud processing for higher accuracy had no path to the mainstream
Chinese streaming ASR services — Volcengine's Doubao streaming ASR (`X-Api-Key` auth) and
Tencent Cloud's real-time ASR running the Hunyuan `Hy-ASR-3.0-preview` engine (signed
credentials).

The 2026-08-25 on-device voice input note rejected a cloud ASR path because the product
was privacy-first. That decision preserved privacy as the default but hard-blocked an
explicit user choice; the rejection is now partial supersession, not a reversal: offline
stays the default mode, online is opt-in with the user's own credentials.

## Decision

Voice input gains a mode selector (offline on-device / online service) in the ASR settings
screen, persisted in a new `OnlineAsrSettingsStore` beside the model registry.

- `packages/asr` owns the online subsystem (`lib/src/online/`): provider/config records,
  the file-backed settings store, a websocket transport seam, the Volcengine v3 binary
  protocol codec, and one session engine per provider — `VolcengineDoubaoAsrEngine`
  (full-duplex `bigmodel_async` endpoint, gzip-framed binary protocol, `X-Api-Key` /
  `X-Api-Resource-Id` / `X-Api-Request-Id` headers) and `TencentHunyuanAsrEngine`
  (HMAC-SHA1-signed session URL, raw PCM binary frames, `{"type":"end"}` close frame).
  Both implement the existing `AsrEngine` interface; `initialize` now takes nullable
  model/modelDir that on-device engines still require (and fail loud without) while online
  engines ignore.
- Online engines are per-recording session objects built by a `cloudEngineFactory` seam;
  `VoiceInputController` branches on mode at session start, and both error paths
  (`ONLINE_NOT_CONFIGURED`, `ONLINE_ASR_FAILED`/`ONLINE_CONNECT_FAILED`) surface as stable
  localizable codes like the existing recording errors.
- Credentials live on-device in `online_asr_settings.json` (atomic temp-file + rename,
  same posture as the model registry). The settings card commits fields only on Save, so
  half-typed secrets never reach the store; mode and provider switches persist immediately.

Both protocol implementations are mirrored from the vendors' official reference clients
(Volcengine `sauc` Python demo, Tencent `tencentcloud-speech-sdk-python`
`speech_recognizer.py`) and pinned by unit tests over their byte/signature formats.

## Alternatives considered

- **Staying offline-only** (extend the rejected 2026-08-25 stance): keeps the privacy
  posture untouched but leaves accuracy-constrained devices without voice input and
  ignores the user's explicit request. Rejected: mode selection makes cloud processing a
  choice, not a default.
- **Routing cloud ASR through the dsh host** (a server-side proxy speaks to the
  providers): would centralize credentials but requires host-side changes the client
  cannot ship alone, adds latency, and moves the user's speech through a third machine.
  Rejected: the phone can hold its own provider credentials and speak to the services
  directly.
- **One generic "cloud engine" with a provider switch inside**: would collapse the two
  wire protocols behind a translator, but their session semantics differ structurally
  (binary framed JSON vs signed-URL JSON text, negative-sequence end vs explicit end
  frame). Rejected: two small engines over a shared session base class keeps each protocol
  byte-faithful and testable.
- **Volcengine resource id hardwired to model 2.0** (`volc.seedasr.sauc.*`): accounts
  enabled on 1.0 would fail auth outright. Rejected: the resource id defaults to the
  official demo's `volc.bigasr.sauc.duration` and stays overridable in config.

## Consequences

- The mic seat's readiness gate is mode-aware: offline needs an installed model, online
  needs the selected provider's credentials, and each gate routes to the same settings
  screen with its own dialog copy.
- Tencent's Hunyuan preview accepts at most one minute of audio per session and 16 kHz
  mono PCM only; the settings card states this, and longer sessions end with whatever the
  service returned before closing.
- Online transcription sends user speech off-device only in online mode; offline behavior,
  default state, and every existing test path are unchanged.
- The `AsrEngine` interface's `initialize` signature changed for all implementers
  (nullable model/modelDir), which future engine authors inherit as the online/offline
  contract.
