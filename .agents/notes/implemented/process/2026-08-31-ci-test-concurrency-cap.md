# Agent Note: The forge CI caps flutter-test concurrency

Status: implemented

## Problem

Three code-gate jobs on the forge (PRs #141, #144) died with exit 137 —
SIGKILL from the host, not a test failure. The runner container shares a
loaded 16 GB host (Gitea, Postgres, the design server, live DSH sessions)
and inherits its full CPU count, so `flutter test` defaults to one
flutter_tester per core. A dozen testers at a few hundred MB each spike
past what the host can give: the kernel kills the suite mid-run, and the
same pressure has twice wedged the `Release-APK` job's container in
storage cleanup afterward. Reruns flip a coin; the queue blocks behind
each zombie.

## Decision

`verify_all.py` reads `DSH_TEST_CONCURRENCY` at load and, when set,
injects `--concurrency=N` into the `flutter-test` gate's command. The
forge `code` job (`.gitea/workflows/ci.yaml`) sets `DSH_TEST_CONCURRENCY: 4`
— four testers ≈ 2–3 GB, survivable next to the host's baseline, and
the suite still finishes well inside its 1800s timeout. Local runs and
the GitHub workflow leave the variable unset and keep the framework
default (their runners have the memory to use it).

## Alternatives considered

- **cpu/memory-limit the runner container**: rejected for now — it is
  forge infrastructure outside the repo, drifts silently from the
  workflow's story, and `flutter test` reads the cgroup's core count
  unreliably; the flag is explicit and version-controlled.
- **Retry red 137 jobs until they pass**: rejected — the flakes are
  deterministic under load, and a retry loop hides the real cost
  (blocked queue, wedged containers).
- **Cap the concurrency in the gate command itself**: rejected — local
  suites run fast precisely because they do use the cores.

## Consequences

- Exit 137 code-gate failures should now be treated as host incidents,
  not flakes; the queue no longer serializes behind OOMed release jobs.
- The cap lives in one place (the env var); a future runner with more
  headroom raises the number in the workflow file, no script change.
- `verify_env_names` keeps to Dart sources; the new name is CI-only and
  documented here.
