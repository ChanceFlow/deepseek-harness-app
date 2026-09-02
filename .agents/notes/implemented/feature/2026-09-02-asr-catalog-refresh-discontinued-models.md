# Agent Note: ASR catalog refresh and discontinued-model lifecycle

Status: implemented

## Problem

The HF search round (2026-09) found the catalog stale: SenseVoice-Small
still pointed at the 2024-07-17 export, the 2025-09-09 retrained int8
export was out, and Fun-ASR-Nano 2512 (seven Chinese dialects, 26 regional
accents, 31 mixed languages, far-field/noise tuning) had no entry. The
streaming side carried a single 2023-era model (Paraformer bilingual), and
Whisper large-v3-turbo — 1 GB, non-streaming, slow on the phones this app
targets — no longer belonged. Removing shipped models outright, though,
would silently orphan every copy users already downloaded: the model
manager lists only manifest entries, so an installed Whisper would vanish
from Settings while its ~1 GB stayed on disk.

## Decision

- **Lineup: four downloadable models.** Two offline: `sensevoice-small`
  retargets the 2025-09-09 int8 repo (same id, so installed 2024 weights
  keep running and refresh on delete + re-download; tokens.txt is
  byte-identical), and new `funasr-nano-ctc` serves the Fun-ASR-Nano 2512
  CTC export, which upstream built for the SenseVoice pipeline (k2-fsa PR
  #2906) — the engine maps it through the existing
  `OfflineSenseVoiceModelConfig` branch, no new config family. Two
  streaming Zipformers via one shared `OnlineTransducerModelConfig` branch
  with manifest-resolved encoder/decoder/joiner file names:
  `streaming-zipformer-zh` (2025-06-30 retrain, 167.7 MB) and
  `streaming-zipformer-multilingual` (eight languages, 338.9 MB).
  `isStreamingModel` reads the manifest's `isStreaming` flag instead of an
  engine-side id switch.
- **Discontinued, not deleted.** `AsrModelInfo.isDiscontinued` keeps
  Whisper large-v3-turbo and the Paraformer bilingual streamer (both
  shipped in v0.1.0) listed: installed copies stay visible in Settings
  (with an `asrModelDiscontinued` chip), selectable as the active model,
  and deletable; `AsrModelManager.startDownload` refuses them before any
  state change, the controller hides uninstalled discontinued entries, and
  the engine keeps their config branches so installed copies still load.
  Two transducer Zipformers evaluated mid-round (bilingual zh-en, tiny
  zh-hans) were dropped by the user before any release and removed from
  the manifest outright — no installed copies can exist. The "installed /
  total" counter counts downloadable models plus installed discontinued
  ones so neither direction lies.
- **Checksums are real**: `lfs.sha256` for the ONNX weights via the HF API;
  tokens.txt digests computed from downloaded bytes (non-LFS blobs expose
  no oid).

## Alternatives considered

- **Dropping shipped models from `all` and reconstructing orphans from the
  registry**: rejected — the registry stores no file URLs or display
  metadata, so "usable" would need a second metadata store; the manifest
  flag achieves the same user-visible contract with one bool.
- **Bumping the model id for the SenseVoice retrain** (new entry, old one
  discontinued): rejected — same id keeps one card, and the old weights run
  unchanged on the identical config, so no user action is forced.
- **Adopting Fun-ASR-Nano's LLM variant (Qwen3-0.6B decoder, ~1 GB)**:
  rejected for now — same weight class as the Whisper we just removed.
- **Adopting the streaming Zipformer CTC export (zipformer2Ctc config)**:
  rejected for now — the transducer sibling of the same 2025-06-30 retrain
  already covers it, and one decoding path keeps the engine surface small.
- **Keeping the Paraformer bilingual streamer downloadable alongside the
  Zipformers**: rejected by the user — the 2025 Zipformer supersedes it for
  Chinese, and it remains runnable for anyone who already has it installed.

## Consequences

A fresh install offers four downloadable models (two offline, two
streaming) totaling ~1.01 GB; a Whisper or Paraformer owner keeps a
working, deletable local copy that can never re-download. Engine mapping
tests cover `funasr-nano-ctc` and the transducer Zipformers
(manifest-resolved file names) plus the kept discontinued Paraformer
branch, the manifest test pins the 2025-09-09 repo, the discontinued
flags, and the four-downloadable count, manager tests cover download
refusal without state changes and active-model resolution of an installed
discontinued copy, and the screen test covers the local-only chip. The
sherpa-onnx 1.13.6 runtime already ships the needed native support.
