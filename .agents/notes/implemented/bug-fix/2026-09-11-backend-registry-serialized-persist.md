# Agent Note: The backend registry serializes its persists

Status: implemented

## Problem

CI's `code` job failed on the `fix/session-mirror-release` branch with one
test: `trusting a host certificate toggles one backend and persists` asserted
that the document on disk holds `"trustHostCertificate":false` and read back a
document whose `default` backend still carried `true`. That test issues four
mutations back to back; the state it asserts was the state of the **last** one.

`BackendRegistryController._persist` started a fresh `BackendStore.save` on
every mutation and only kept the newest future in `_pendingPersist`. Awaiting
that future therefore said nothing about the writes started before it: the
store's write is a temp-file-plus-rename with several real IO turns, so on a
loaded runner an older snapshot could land after the newer one and win the
file. The test had been "fixed" once by awaiting `pendingPersist` instead of
polling a clock, which removed the timing dependence from the assertion but
not the race underneath it.

The same race is a user-visible defect: two quick mutations (add a host, then
flip its trust toggle) can leave the older document on disk, and the next
launch shows the state the user already moved past.

## Decision

`_persist` chains on the previous write — `(_pendingPersist ?? Future.value())
.then((_) => _store.save(snapshot))` — so the writes are ordered instead of
merely tracked, and the last mutation's snapshot is the last snapshot written.
The snapshot is still taken at call time, so a queued write carries the state
that mutation produced.

`pendingPersist` is now the tail of that chain: awaiting it means every write
queued so far has settled, which is what the existing tests read.

## Alternatives considered

- **Coalesce to one in-flight write and re-write only the latest state when it
  finishes**: rejected as the first fix — fewer writes, but it adds a dirty
  flag and a second settlement path, and a mutation is a user tap, so the
  write count is irrelevant. The chain keeps one code path.
- **Make the store's `save` re-entrant-safe with a lock**: rejected — the
  ordering requirement belongs to the controller that owns the state, and the
  store stays a plain document reader/writer.
- **Delete the assertion that the bytes land**: rejected — it is the only
  evidence that a mutation reached the disk at all.

## Consequences

- Two mutations in flight leave the second state on disk.
  `backend_registry_controller_test.dart` pins it with a store double whose
  first save stalls eight event-loop turns; with the chain removed the file
  ends up holding the first snapshot, which is the CI failure reproduced
  deterministically.
- `pendingPersist` settles later than before when several mutations are queued
  (it waits for the queue, not just the newest write); it never throws.
