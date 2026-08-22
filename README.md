# deepseek-harness-app

[![CI](https://img.shields.io/github/actions/workflow/status/ChanceFlow/deepseek-harness-app/ci.yaml?label=CI&logo=github)](https://github.com/ChanceFlow/deepseek-harness-app/actions/workflows/ci.yaml)
[![Release](https://img.shields.io/github/v/release/ChanceFlow/deepseek-harness-app?include_prereleases&label=release)](https://github.com/ChanceFlow/deepseek-harness-app/releases)
[![Flutter](https://img.shields.io/badge/Flutter-3.47-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![Platform](https://img.shields.io/badge/platform-Android-3DDC84?logo=android&logoColor=white)](#deepseek-harness-app)
[![License: MIT](https://img.shields.io/github/license/ChanceFlow/deepseek-harness-app)](LICENSE)

A native Android client for [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness)
(`dsh`), built with Flutter. It connects to an **unmodified `dsh web`
backend** running on your own machine, so you can carry your agent
sessions in your pocket: watch a run live, approve tool calls, answer
questions, and manage workspaces, models, goals and subagents — in
English or 简体中文.

<p align="center">
  <img src="docs/screenshots/chat.png" width="250" alt="Chat timeline">
  <img src="docs/screenshots/sessions.png" width="250" alt="Session drawer">
  <img src="docs/screenshots/markdown.png" width="250" alt="Markdown rendering">
</p>

## Getting started

### 1. Install the APK

Grab the latest APK from the [Releases page](../../releases):

- **`v<semver>`** — a stable release.
- **`dev`** — the rolling prerelease, refreshed on every merge to
  `master`; the fastest way to try what just landed.

```sh
adb install dsh-android-<version>.apk
```

Every release carries a `.sha256` sidecar next to the APK.

### 2. Run the backend on your machine

The app speaks to a stock `dsh web` server — no plugins, no patches:

```sh
npx @deepseek-ai/dsh web --port 3080
```

### 3. Point the app at it

Release APKs ship with `DSH_BASE_URL=http://10.0.2.2:3080` baked in —
the Android emulator's route to the host loopback. Pick the row that
matches your setup:

| Setup | What to do |
|---|---|
| **Emulator** | Nothing — the baked-in default already reaches your host's loopback. |
| **Phone over USB** | `adb reverse tcp:3080 tcp:3080` keeps the default URL valid. |
| **Phone over LAN** | Build your own APK with `flutter build apk --dart-define=DSH_BASE_URL=http://<host-ip>:3080`, or run the [release workflow](.github/workflows/release-apk.yaml) with the `dsh_base_url` input. |

> The backend serves its settings plane to loopback connections only,
> so on a phone that path runs through `adb reverse`.

## Feature surface

- **Chat** — session list (search, create-in-workspace, rename,
  archive, fork, running indicator), flat timeline and ledger-style
  outline with collapsible turn groups, markdown rendering (fenced
  code, headings, lists, tables, clickable links), queue rows,
  approvals, questions, plan-review cards, background jobs, image
  attachments, skill candidates.
- **Workspaces** — create from a path or the in-app host directory
  browser, rename, delete, manual reordering.
- **Models** — provider groups, current selection, reasoning-effort
  chips, provider failures.
- **Subagents** — parent picker, child entries, open a child timeline,
  send a prompt, interrupt.
- **Goals** — create/pause/resume/complete per phase, objective
  editing with CAS revision.
- **Settings** — per-namespace editing with revision CAS, credentials
  describe/set/unset.

## Wire compatibility

The upstream dsh repository is pinned as a git submodule under
[`reference/deepseek-harness`](reference/) at one official commit —
currently **`dsh-v0.1.1-rc.2`**
([pin and contract map](reference/README.md)). dsh is under active
development with breaking changes: this client tracks that one pinned
contract, so do not assume wire compatibility with any other dsh
version. Coverage today is 40 of 48 host RPC methods —
[docs/spec.md](docs/spec.md) has the exact list.

## Module boundaries

The pub workspace lives under `flutter/`:

```text
flutter/app                        Flutter UI (screens, markdown renderer).
flutter/packages/domain            Neutral UI-facing models: ChatMessage, Session, TimelineItem.
flutter/packages/harness_adapter   The ONLY package that understands the dsh wire protocol.
flutter/packages/network           Transport primitives: RPC envelopes, HTTP/WebSocket seams.
flutter/packages/dev               Debug-build tooling: telemetry, frame tracking, crash capture.
```

`app` and `domain` never import dsh types; all wire knowledge stays in
`harness_adapter` behind that boundary, enforced by
`scripts/check_dart_imports.py`.

## Development

```sh
git clone --recurse-submodules https://github.com/ChanceFlow/deepseek-harness-app.git
cd flutter/app
flutter run --dart-define=DSH_BASE_URL=http://10.0.2.2:3080
```

The canonical command list and the aggregate verification gates live in
[AGENTS.md §Commands](AGENTS.md#commands); Flutter 3.47.1 stable is
expected on PATH. Real-host e2e is opt-in — see
[§Opt-in real-host e2e](#opt-in-real-host-e2e) below.

### Opt-in real-host e2e

```sh
cd flutter
DSH_E2E_URL=http://127.0.0.1:3080 flutter test packages/harness_adapter/test/local_dsh_e2e_test.dart
```

## APK releases

Release APKs are built by GitHub Actions
([`.github/workflows/release-apk.yaml`](.github/workflows/release-apk.yaml))
and published on the [Releases page](../../releases): every `master`
push refreshes the rolling `dev` prerelease, a `v<semver>` tag cuts the
stable Release, and both attach a signed APK (release keystore, not the
debug key) plus a `.sha256` sidecar. Naming follows SemVer 2.0; every
release body carries a generated `## What's Changed` changelog.

## Verification status

`python3 scripts/verify_all.py` is the aggregate gate: `flutter
analyze` under strict casts/inference/raw-types, the full test suite
(real-host e2e self-skips without `DSH_E2E_URL`), the import gate, the
launcher-icon drift gate, and the documentation gates. CI runs it as
two parallel jobs — `docs` (python only) and `code` (Flutter) — on
every push and pull request, and both are required to merge.

## History

Rewritten from an original Kotlin/Compose prototype in Flutter — see
[ADR-0001](docs/adr-0001-flutter-rewrite.md). The Kotlin-era commits
remain in this history; the shipped codebase is the Flutter workspace
under `flutter/`.

## License

[ MIT ](LICENSE)
