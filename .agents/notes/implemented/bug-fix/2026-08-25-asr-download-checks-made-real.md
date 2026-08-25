# Agent Note: ASR downloads verify content and real free space

Status: implemented

## Problem

The ASR model download system shipped with two inert safeguards:

1. **SHA-256 checksums were placeholders** — every `AsrModelFile.sha256`
   in the manifest carried a sequential dummy digest (`0123…`, `1234…`),
   and `AsrDownloader.verifySha256` had no call site in the download
   path. The decision record claimed SHA-256 validation; the code
   verified file size only.
2. **Disk-space pre-flight was hard-coded** — the manager's default
   `DiskSpaceChecker` returned a constant 10 GiB ("native statvfs isn't
   available"), so a phone with 200 MB free would happily start an
   800 MB Whisper download and fail mid-stream.

## Decision

- The manifest's dummy digests become an explicit empty sentinel with a
  TODO: an empty checksum means "not provisioned" and downgrades
  verification to the size check; the moment a real digest lands, content
  verification activates automatically. No fake value can ever pass or
  fail a check it does not mean.
- On the same change, every digest was provisioned: each
  `AsrModelFile.sha256` now carries the checksum read from the Hugging
  Face LFS `lfs.oid` of the exact file, cross-checked against ModelScope's
  own `Sha256` column (identical bytes) before ModelScope was removed.
- The audit behind the digests corrected the manifest's distribution
  facts: the zipformer repo is
  `sherpa-onnx-streaming-zipformer-bilingual-zh-en-2023-02-20` (the
  `-streaming-` segment was missing, so every zipformer URL 404'd); the
  whisper repo is `sherpa-onnx-whisper-turbo` (`*-large-v3-turbo` does not
  exist) with `turbo-encoder.int8.onnx`, `turbo-decoder.int8.onnx`, and
  `turbo-tokens.txt`; the streaming zipformer needs `bpe.model` rather
  than `tokens.txt`; and all file sizes were replaced with real byte
  counts (the old ones were estimates).
- ModelScope was removed as a download source entirely: none of the three
  sherpa-onnx packages is mirrored there — only whisper-turbo had one
  (under `pengzhendong`) — so every previous `modelscope.cn/resolve/...`
  URL was a dead link. The two sources are now Hugging Face and the
  official hf-mirror.com China mirror serving identical bytes; legacy
  registry entries carrying `"source":"modelscope"` map to the mirror.
- `AsrDownloader` now calls `verifySha256` on the completed
  `.downloading` file before the final rename; a mismatch deletes the
  partial and throws `DownloadFailedException`, so a retry restarts from
  zero instead of resuming corrupt bytes.
- Real free space comes from the platform: a `dsh/disk_space` method
  channel in `MainActivity` answers `availableBytes` via
  `android.os.StatFs`, and app DI injects it as the manager's
  `DiskSpaceChecker` (see
  [disk_space.dart](../../../../flutter/app/lib/platform/disk_space.dart)).
  Missing-plugin hosts (widget tests, unsupported platforms) fall back to
  the documented 10 GiB constant.

## Alternatives considered

- **Adding a pub.dev disk-space plugin**: rejected — the workspace is
  offline-pinned, and a dependency for one `StatFs` call is heavier than
  a five-line channel handler.
- **Making the default checker throw when the channel is absent**:
  rejected — the seam is legitimately missing in widget tests; a
  documented fallback keeps those honest while the app always injects the
  real probe.
- **Keeping the dummy hashes and wiring verification anyway**: rejected —
  every download would then fail against a digest that is not the file's;
  the sentinel is the only truthful state until real digests are
  recorded.
- **Keeping ModelScope as a labeled source**: rejected — for two of the
  three models the labeled "ModelScope" URLs were dead links; keeping a
  source that fails by default for the majority of the catalog is worse
  than the one honest mirror that works everywhere.

## Consequences

- Downloads genuinely fail fast on corrupt or truncated content, and the
  space pre-flight reflects the device instead of a canned 10 GiB.
- Digests were recorded from upstream metadata on 2026-08-25; a future
  upstream rebuild of any ONNX artifact must update the manifest digest
  and size in the same change.
- Corrects the over-claims of
  [asr-model-download-system](../feature/2026-08-25-asr-model-download-system.md),
  now cross-linked from it.