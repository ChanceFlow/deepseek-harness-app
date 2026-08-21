# deepseek-harness-android

A Flutter client for [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness)
(`dsh`) — an Open-Standard Android app that talks to an unmodified `dsh web`
backend on your LAN.

> Rewritten from an original Kotlin/Compose prototype in Flutter — see
> [ADR-0001](docs/adr-0001-flutter-rewrite.md). The Kotlin-era commits remain
> in this history; the shipped codebase is the Flutter workspace under
> `flutter/`.

## Goals

- Flutter (3.47 stable) + Dart; Riverpod for assembly wiring. UI state is
  plain controller classes with UDF state streams (no per-screen Notifiers).
- UI spatial layout is fully owned by client code and can be rearranged freely.
- dsh harness concepts are isolated in `packages/harness_adapter`; UI code
  only sees neutral domain models.
- The dsh backend stays unchanged. Translation happens client-side inside
  the adapter package.
- No codegen (no freezed/json_serializable): hand-written DTO decoders with
  required-field semantics.

## Module boundaries

Pub workspace under `flutter/`:

```text
flutter/app                        Flutter UI (screens, markdown renderer).
flutter/packages/domain            Neutral UI-facing models: ChatMessage, Session, TimelineItem.
flutter/packages/harness_adapter   The ONLY package that understands the dsh wire protocol.
flutter/packages/network           Transport primitives: RPC envelopes, HTTP/WebSocket seams.
flutter/packages/dev               Debug-build tooling — telemetry (log/event/metric), frame tracking, crash capture, OTLP export.
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

- **Chat** — session list (search, create-in-workspace, rename, archive,
  fork, running indicator), flat timeline and ledger-style outline
  (collapsible turn groups, compaction markers), markdown rendering
  (fenced code, headings, lists, tables, clickable links), queue rows,
  approvals, questions, plan-review cards, background jobs, image
  attachments, skill candidates.
- **Workspaces** — create from path or the in-app host directory browser,
  rename, delete, durable manual reordering.
- **Models** — provider groups, current selection, reasoning-effort chips,
  provider failures.
- **Subagents** — parent picker, child entries, open child timeline, send
  prompt, interrupt.
- **Goals** — create/pause/resume/complete per phase, objective editing
  with CAS revision.
- **Settings** — per-namespace editing with revision CAS, credentials
  describe/set/unset (the host serves this plane only to loopback
  connections; use `adb reverse` on devices).

Wire coverage: 40 of 48 host RPC methods — see [docs/spec.md](docs/spec.md)
for the exact list and the pinned dsh version.

## Backend

The upstream dsh repository is pinned as a git submodule in
[`reference/deepseek-harness`](reference/) at a **specific official commit**
([`reference/README.md`](reference/README.md) has the pin and the
source-of-truth contract files). dsh is under active development with
breaking changes — this client tracks one pinned contract; do not assume
wire compatibility with a different dsh version than the pin.

Clone with submodules:

```sh
git clone --recurse-submodules https://github.com/OWNER/REPO.git
```

## Development

The canonical command list — analyze, tests, the import gate, the
launcher-icon drift gate, and the aggregate verification gate — lives in
[AGENTS.md §Commands](AGENTS.md#commands). Flutter 3.47.1 stable is expected
on PATH.

Run on a device/emulator:

```sh
cd flutter/app
flutter run --dart-define=DSH_BASE_URL=http://10.0.2.2:3080
```

The default base URL is `http://10.0.2.2:3080` (Android emulator loopback);
override with `--dart-define=DSH_BASE_URL=http://<your-host>:3080`.

Debug builds and prerelease release APKs report telemetry (logs, events,
metrics, frame-rate) to a self-hosted OTLP endpoint
(`http://10.0.2.2:4318` by default; override `DSH_DEBUG_OTLP_URL`).
Stable releases compile telemetry out. Report the exact source commit so
the collector can pin the source of every signal:

```sh
flutter run --dart-define=DSH_SOURCE_COMMIT=$(git rev-parse HEAD)
```

A local dev server can be reached with:

```sh
adb reverse tcp:3080 tcp:3080
npx @deepseek-ai/dsh web --port 3080
```

### Opt-in real-host e2e

```sh
cd flutter
DSH_E2E_URL=http://127.0.0.1:3080 flutter test packages/harness_adapter/test/local_dsh_e2e_test.dart
```

### APK releases

Release APKs are built by GitHub Actions
([`.github/workflows/release-apk.yaml`](.github/workflows/release-apk.yaml))
and published on the [GitHub Releases page](../../releases): every `master`
push refreshes the rolling `dev` prerelease, a `v<semver>` tag cuts the
stable Release, and both attach the signed APK plus a `.sha256` sidecar.
Artifacts are signed with a release keystore held in repository secrets
(not the debug key).

Naming follows SemVer 2.0: `v0.1.0`, prereleases `v0.1.0-alpha.1` /
`-beta.2` / `-rc.1`; the APK is `dsh-android-<versionName>.apk`. Every
release body carries a `## What's Changed` changelog generated by
[`scripts/gen_release_notes.py`](scripts/gen_release_notes.py) followed by
artifact metadata.

## Verification status

`python3 scripts/verify_all.py` is the aggregate gate: `flutter analyze`,
the full test suite (real-host e2e self-skips without `DSH_E2E_URL`), the
import gate, the launcher-icon drift gate, and the documentation gates. CI
runs it as two parallel jobs — `docs` (python only) and `code` (Flutter) —
on every push and pull request.

## License

[ MIT ](LICENSE)