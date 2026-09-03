# Agent Note: ASR downloads retry mid-body connection drops with Range resume

Status: implemented

## Problem

`AsrDownloader` issued exactly one HTTP attempt per model file. When the CDN
dropped the connection mid-body — the HF xet bridge does this routinely on
long transfers (`ClientException: Connection closed while receiving data`) —
the exception propagated straight into the registry entry, the download was
marked failed, and the model card showed the raw client error. Two facts made
it worse:

- The partial `.downloading` file survived (Range resume across app runs
  already worked), but within one run there was no second attempt: a 240 MB
  encoder that dropped at 90% failed exactly as hard as one that dropped
  at 1%.
- Switching the download source does not dodge the failure. Since Hugging
  Face migrated LFS to Xet, hf-mirror.com answers `resolve/` requests for
  xet-backed repos with a signed redirect to the same `*.cdn.hf.co` bridge
  hosts as the global hub — both configured lanes end on one CDN, so the
  "switch mirror and retry" UI kept re-hitting the same drop.

## Decision

- `downloadModel` wraps each file in a bounded attempt loop
  (`maxAttemptsPerFile`, default 4) with linear backoff (500 ms per failed
  attempt, capped at 4 s). Every attempt re-derives the resume position from
  the partial file and re-syncs the progress accounting from disk
  (`_existingBytes`), so a retry appends via Range and never double-counts
  the bytes it resumes over.
- Failures classify as transient versus permanent via the new
  `DownloadFailedException.transient` flag: connection failures and
  mid-body interruptions wrap as transient; truncated bodies (size
  mismatch) and statuses 5xx/408/429 retry; 4xx and SHA-256 mismatch fail
  immediately (a checksum mismatch still deletes the partial, so no retry
  ever resumes corrupt bytes).
- A response body silent beyond `stallTimeout` (45 s) counts as a stalled
  connection and fails the attempt into the same resumable retry instead of
  hanging the progress bar forever.
- Cancellation wins over retrying: cancel is honored at attempt start,
  during the stream, and after every backoff wait.

## Alternatives considered

- **Failover to the other source on connection failure**: rejected — the
  redirect trace above shows both lanes land on the same HF CDN for the
  xet-backed repos in the manifest, so failover doubles the attempts without
  changing the endpoint that fails.
- **Retry by restarting each file from zero**: rejected — it discards
  hundreds of megabytes per hiccup; Range resume already exists and the
  partial file is the natural resume point.
- **Unbounded retries with jittered backoff**: rejected — the download is
  user-initiated and visible; a bounded budget that fails loudly beats a
  spinner that may never resolve.

## Consequences

- A mid-transfer drop costs one backoff wait plus one Range request, not the
  whole download; the failed state only appears after four genuinely failed
  attempts per file.
- The feature note's "resilient download engine" claim
  ([asr-model-download-system](../feature/2026-08-25-asr-model-download-system.md))
  now holds within a single session, not only across app restarts.
- Tests cover drop-then-resume, retry exhaustion, permanent-failure
  fail-fast, 5xx retry, stall-then-resume, and cancel-during-backoff
  ([downloader_test.dart](../../../../flutter/packages/asr/test/downloader_test.dart)).
