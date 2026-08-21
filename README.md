# deepseek-harness-android

Cross-platform client for [DeepSeek Harness](https://github.com/deepseek-ai/dsh),
built with Flutter.

> **Rewrite complete (route A).** Per
> [ADR-0001](docs/adr-0001-flutter-rewrite.md) the original Kotlin/Compose
> stack was rewritten in Flutter in the same repository (branch
> `flutter-rewrite`) and the legacy `app/`/`core/` Gradle stack has been
> removed once the parity gates passed: 40/48 RPC adapter parity, 81/81
> legacy test parity (now 121 + 1 opt-in e2e in the Dart suite), real-host
> e2e, and the import gate. The migration log lives in
> [ROADMAP.md](ROADMAP.md); the pre-rewrite MVP history is preserved in
> [PLAN.md](PLAN.md); the migration analysis is
> [docs/flutter-migration-analysis.md](docs/flutter-migration-analysis.md).

## Goals

- Flutter (3.47 stable) + Dart; Riverpod for assembly wiring. UI state is
  plain controller classes with UDF state streams (no per-screen Notifiers).
- UI spatial layout is fully owned by client code and can be rearranged freely.
- dsh harness concepts are isolated in `packages/harness_adapter`; UI code
  only sees neutral domain models.
- The dsh backend stays unchanged. Translation happens client-side inside
  the adapter package.
- No codegen (no freezed/json_serializable): hand-written DTO decoders with
  required-field semantics matching kotlinx-serialization.

## Module boundaries

pub workspace under `flutter/`:

```text
flutter/app                        Flutter UI (six screens, markdown renderer).
flutter/packages/domain            Neutral UI-facing models: ChatMessage, Session, TimelineItem.
flutter/packages/harness_adapter   The ONLY package that understands dsh wire protocol.
flutter/packages/network           Transport primitives: RPC envelopes, HTTP/WebSocket seams.
flutter/packages/dev               Debug-build tooling — telemetry (log/event/metric), frame tracking, crash capture (ring log buffer, crash marker, restart detection), OTLP export to SigNoz.
```

Dependency direction:

```text
app -> domain
app -> assembly wiring (lib/di — the only file allowed to touch network/harness_adapter types)
app -> dev (debug tooling; dev depends on no repo package, so there is no reverse edge)
harness_adapter -> domain
harness_adapter -> network
```

Forbidden import: `app` (outside `lib/di`) or `domain` must never import from
`harness_adapter`/`network` or any dsh type such as `SessionEvent`,
`MuxFrame`, or `HostFrame`. Enforced by `scripts/check_dart_imports.py`.

## Feature surface

All six legacy screens are ported with widget-test parity:

- **Chat** — session list (search, create-in-workspace, rename, archive,
  fork, running indicator), flat timeline and ledger-style outline
  (collapsible turn groups with prompt echo and per-tool summaries,
  compaction markers), markdown rendering (fenced code with language label
  and streaming-open fences, headings, nested bullets, quotes, pipe tables,
  inline styles, clickable links via a self-drawn parser/renderer), queue
  rows with edit/steer/remove, approvals, questions (multi-select, custom
  text, skip, plan-review decision card), background jobs, image
  attachments (picker → admission against host `imageLimits`, thumbnails,
  lazy `session.attachment` download with retry), `/` skill candidates, and
  plan-mode chip.
- **Workspaces** — create from path or the in-app host directory browser
  (navigate, create folder, show-hidden), rename, delete, durable manual
  reordering (`workspace.insertBefore`).
- **Models** — provider groups, current selection, reasoning-effort chips,
  provider failures.
- **Subagents** — parent picker, child entries with kind/mode/activity
  metadata, open child timeline, send prompt, interrupt.
- **Goals** — create (with optional max rounds), pause/resume/complete/clear
  per phase, objective editing with CAS revision.
- **Settings** — snapshot chips, per-namespace editing (one-key patch and
  whole-section replace with revision CAS), credentials describe/set/unset;
  the host serves this plane only to loopback connections (surface the
  `adb reverse` hint on transport errors).

Wire coverage: 40 of 48 host RPC methods — the same set the legacy client
covered; the eight remaining methods are host-desktop verbs or
loopback-privileged deep-settings surfaces (see [docs/spec.md](docs/spec.md)).

## Backend reference

The upstream dsh repository is pinned as a git submodule in
[`reference/deepseek-harness`](reference/). See
[reference/README.md](reference/README.md) for details and the
source-of-truth contract files.

## Project skills

This repository ships project-scoped Agent Skills in [`.agents/skills/`](.agents/skills/):
the official Flutter/Dart skills vendored from
[flutter/agent-plugins](https://github.com/flutter/agent-plugins) (BSD-3-Clause),
plus repo-specific `dsh-*` workflow skills. See
[`.agents/skills/README.md`](.agents/skills/README.md) for the full list and
how to refresh them.

## Development

The canonical command list — analyze, tests, the import gate, the launcher-icon
drift gate, and the aggregate verification gate — lives in
[AGENTS.md §Commands](AGENTS.md#commands). Flutter 3.47.1 stable is expected on
PATH (`export PATH="$HOME/tools/flutter-3.47.1/bin:$PATH"`).

Run on a device/emulator (`cd flutter/app` for `flutter run` commands):

```sh
cd flutter/app
flutter run --dart-define=DSH_BASE_URL=http://10.0.2.2:3080
```

The default base URL is `http://10.0.2.2:3080` (Android emulator loopback);
override with `--dart-define=DSH_BASE_URL=http://192.168.1.10:3080`.

Debug builds and prerelease release APKs report telemetry (logs, events,
metrics, frame-rate) and crashes to a self-hosted SigNoz instance over OTLP/HTTP
(`http://10.0.2.2:4318` by default; override `DSH_DEBUG_OTLP_URL` with a
LAN address for real devices). Report the exact source commit so SigNoz
can pin the source of every signal:

```sh
flutter run --dart-define=DSH_SOURCE_COMMIT=$(git rev-parse HEAD)
```

Without `DSH_SOURCE_COMMIT` telemetry reports `unknown` for the source.
Other build-provenance defines: `DSH_SOURCE_REPO`, `DSH_APP_VERSION`,
`DSH_BUILD_NUMBER` (defaults are well-formed but generic).

A local dev server can be reached with:

```sh
adb reverse tcp:3080 tcp:3080
pnpm dsh web --port 3080
```

### Opt-in real-host e2e

```sh
cd flutter
DSH_E2E_URL=http://127.0.0.1:3080 flutter test packages/harness_adapter/test/local_dsh_e2e_test.dart
```

### Gradle notes

Gradle downloads honor `~/.gradle/gradle.properties` proxy settings
(`systemProp.http(s).proxyHost/Port`); the first `assembleDebug` after a
clean Gradle cache takes ~14 minutes, subsequent builds ~3 minutes.
JDK 17 is required for the Android Gradle plugin.

### APK releases

Release APKs are built by Gitea Actions
([`.gitea/workflows/release-apk.yaml`](.gitea/workflows/release-apk.yaml))
on the prebaked `flutter-android` runner image
([`docker/`](docker/)); they are signed with a release keystore held in
Gitea Actions secrets, not the debug key. The repository's
[Releases page](http://127.0.0.1:3000/ChanceFlow/deepseek-harness-android/releases)
is the only distribution channel — every build publishes a Release with
the APK and its `.sha256` attached.

Naming follows SemVer 2.0: release tags are `v<semver>`
(`v0.1.0`, prereleases `v0.1.0-alpha.1` / `-beta.2` / `-rc.1`), the APK
is `dsh-android-<versionName>.apk`, and every `master` push — plus manual
dispatch — republishes the rolling dev prerelease under the `dev` tag
(`/releases/tag/dev` — always the newest `master` build). A dev build's
versionName is the latest stable `v*` tag with its patch bumped plus an
`-alpha.<run>` suffix (v0.0.2 → `0.0.3-alpha.50`); every release is
titled `DSH Android <versionName>` and its body opens with a
`## What's Changed` changelog — merged pull-request titles since the
previous stable tag, grouped by Conventional Commit type and linked to
their pull requests (generated by
[`scripts/gen_release_notes.py`](scripts/gen_release_notes.py)) —
followed by the artifact metadata. Dispatch takes an optional
`dsh_base_url` input (default `http://127.0.0.1:3080`). Local
`flutter build apk --release` without the `DSH_KEYSTORE_*` environment
still debug-signs.

## Verification status

`python3 scripts/verify_all.py` is the aggregate gate: `flutter analyze`,
the full test suite (real-host e2e self-skips without `DSH_E2E_URL`), the
import gate, the launcher-icon drift gate, and the documentation gates. CI
runs it as two parallel jobs — `docs` (python only) and `code` (Flutter) —
on every push and pull request, and both are required before a merge; its
output is the live verification status. Local work runs the narrowest tool
for the change instead ([docs/testing.md](docs/testing.md) §Select evidence
by surface).

Deferred beyond parity, matching [docs/spec.md](docs/spec.md):
schema-driven settings forms, secret-slot writes, session-drag ordering,
attachment downsampling (deliberate divergence — the host rejects
oversized images), production TLS/auth hardening.
