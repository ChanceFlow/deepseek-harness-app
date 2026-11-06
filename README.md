# deepseek-harness-app

English | [简体中文](README.zh.md)

[![CI](https://img.shields.io/github/actions/workflow/status/ChanceFlow/deepseek-harness-app/ci.yaml?label=CI&logo=github)](https://github.com/ChanceFlow/deepseek-harness-app/actions/workflows/ci.yaml)
[![Release](https://img.shields.io/github/v/release/ChanceFlow/deepseek-harness-app?include_prereleases&label=release)](https://github.com/ChanceFlow/deepseek-harness-app/releases)
[![Flutter](https://img.shields.io/badge/Flutter-3.47-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![Platform](https://img.shields.io/badge/platform-Android-3DDC84?logo=android&logoColor=white)](#deepseek-harness-app)
[![License: MIT](https://img.shields.io/github/license/ChanceFlow/deepseek-harness-app)](LICENSE)

An Android shell for [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness)
(`dsh`), built with Flutter. It connects to an **unmodified `dsh web` host**
running on your own machine and renders that host's own web client in a
WebView — one page per configured host — so the whole agent surface travels
with you unchanged: the transcript, approvals and questions, workspaces,
models, goals, subagents, plugins, schedules, terminals, and file previews,
in whatever language the host's page serves.

What the shell adds is its own: Android notifications for a turn that finishes
or a request that waits on you, a device-local registry of hosts, and a
keep-alive service that holds the event sockets open while work is in flight.
Nothing is injected into the page, and there is no JavaScript bridge.

## Getting started

### 1. Install the APK

Grab the latest APK from the [Releases page](../../releases):

- **`v<semver>`** — a stable release.
- **`dev`** — the rolling prerelease, refreshed on every merge to
  `master`; the fastest way to try what just landed.

```sh
adb install dsh-android-<version>-arm64-v8a.apk
```

Each release carries one APK per ABI, because the native libraries are the
whole download and a phone installs exactly one of them:

| APK | Take it on |
|---|---|
| `-arm64-v8a` | every phone made since ~2017 (the one to grab) |
| `-armeabi-v7a` | older 32-bit phones |
| `-x86_64` | emulators and Chromebooks |

Every APK carries its own `.sha256` sidecar. The WebView engine ships with the
platform, so an APK is the Flutter shell and nothing else — no downloaded
runtime to install.

### 2. Run the host on your machine

The app speaks to a stock `dsh web` server — no plugins, no patches:

```sh
npx @deepseek-ai/dsh web --port 3080
```

### 3. Point the app at it

`dsh web` listens on loopback only — a deliberate upstream safety
decision, because the agent executes code: `dsh web` refuses
`--host 0.0.0.0` outright ("it would expose remote code execution to
the network"). There is no LAN mode to aim a phone at, so release APKs
ship with `http://127.0.0.1:3080` baked in and you reach the host
by forwarding that loopback port to the machine running dsh:

| Setup | What to do |
|---|---|
| **Phone or emulator over USB** | `adb reverse tcp:3080 tcp:3080` — one command, then the app connects. |
| **Emulator without adb** | Build your own APK with `--dart-define=DSH_BASE_URL=http://10.0.2.2:3080`, the emulator's own route to the host loopback. |
| **Anything else you can reach** — a tunnel, a second machine | Add it as another host right in the app — see [Multiple hosts](#multiple-hosts). |

> The host serves its settings plane to loopback connections only, so the
> host's own settings pages, as rendered in the shell, need the same forward.

## Remote access (gateway)

`adb reverse` is the on-device development path: one command reaches a
`dsh web` on the same machine over USB. It is not the only way in. To
reach a host across a network, put
[dsh-go-gateway](https://github.com/ChanceFlow/dsh-go-gateway) in front of
`dsh web`: it relays HTTP and WebSocket byte-for-byte and rewrites the
request `Host` to loopback, so dsh's reachability fence passes with no
change to dsh itself.

Point the app at the gateway's public origin and nothing else: it is a
plain base URL (`https://<host>:<port>`), with no path prefix and no
credentials to enter. The client performs no authentication — whether
the gateway requires any is the gateway's own deployment choice
(`gateway.json`, `auth.modes`). A gateway with a self-signed or
internal-CA certificate needs the app's per-host **Trust this host's
certificate** opt-in (hosts → edit); leave it off for any host you do not
control.

The client only ever resolves request paths against a base URL's
**origin**, so a deployment must expose the gateway at the root of its
own host or port rather than under a path prefix.

## Multiple hosts

One app, many dsh hosts: the shell's host drawer keeps a device-local
registry — add a host and switch between them at any time. Each configured host renders
in its own WebView; up to three pages stay warm (the active one plus two
neighbours), and a page beyond that budget reloads from its URL when you
select it. A fresh install seeds the registry with the build-time URL, so
nothing changes until you add your second host — a laptop, a build box, a
tunneled remote dsh.

## Feature surface

- **The host's whole web client, unchanged** — the page is served by `dsh`
  and versioned with it: transcript and live runs, approvals and questions,
  plan review, workspaces, models and providers, goals, subagents and teams,
  plugins, schedules, terminals, file previews, and the host's own settings.
  A `dsh` upgrade moves the UI with no app update; nothing is injected or
  restyled.
- **One WebView per host** — every enabled host is a stacked page, so
  switching is a display change rather than a reload; the pool keeps at most
  three live to bound memory, and a released host reloads when selected.
- **Notifications** — a turn that finishes while the app is in the background
  posts an Android notification, and one that finishes in the foreground
  raises a tappable toast; a session that starts waiting on an approval or a
  plan review does too, and ongoing work notifications follow running sessions
  from the same roster fold. The shell cannot tell which session the page is
  showing, so no session is treated as "watched" and every finished turn
  surfaces. A tap opens the app on the current host.
- **Keep-alive while work is in flight** — a running or user-waiting root
  session starts a foreground service with a partial wake lock, so Android's
  cached-process freeze after screen lock cannot kill the event socket; it
  stops 30 seconds after the last session settles.
- **Multi-host registry** — add and select a host, with health shown as one
  dot on the bar. Rename, URL edit, removal and the per-host
  self-signed/internal-CA certificate opt-in are registry actions that have
  no shell editor yet.
- **Localized shell chrome** — the host's page serves its own language; the
  bar, drawer, host editor, permission prompt and notification copy are
  English and 简体中文.
- **Failure surfaces** — the bar's dot names an unreachable host, the page
  paints its own load error where it has one, and an empty registry offers
  the add action instead of a blank screen.

## Wire compatibility

The upstream dsh repository is pinned as a git submodule under
[`reference/deepseek-harness`](reference/) at one official commit —
currently **`dsh-v0.2.2-rc.1`**
([pin and contract map](reference/README.md)). dsh is under active
development with breaking changes: this client tracks that one pinned
contract, so do not assume wire compatibility with any other dsh
version. Coverage today is 103 of 184 Remote methods registered by the pinned
tree — [docs/spec.md §4.6](docs/spec.md#46-wire-coverage) has the exact counts,
the unwired remainder, and the reviewed names the client deliberately leaves
unwired or declares only; the
`verify_wire_pin` gate holds both documents to the two registries and fails a
declared-only name that the wire layer actually calls.

## Module boundaries

The pub workspace lives under `flutter/`:

```text
flutter/app                        WebView shell: host pages and chrome, notifications, registry, theme.
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
adb reverse tcp:3080 tcp:3080    # device loopback 3080 -> the host's dsh
cd flutter/app
flutter run
```

The build-time default host is `http://127.0.0.1:3080`; override it
with `--dart-define=DSH_BASE_URL=...` (see
[§Point the app at it](#3-point-the-app-at-it) for the emulator-only
`10.0.2.2` route).

The shell is the app's home: `main.dart` mounts `ShellRoot` inside
`ShellLifecycle`, and `AppNotificationCenter` runs over the adapter's socket
without depending on any page being mounted. The host's page is the UI, so
this repo ships no screen renderer and no design screenshots; the chrome and
the notification surface are proved by widget tests
([docs/testing.md](docs/testing.md)).

RPC transport rides embedded Cronet on Android: HTTP/2 with opportunistic
HTTP/3 (QUIC upgrades via Alt-Svc; automatic h2/h1 fallback when UDP 443
is blocked). Every Android build must pass
`--dart-define=cronetHttpNoPlay=true` so Cronet ships embedded: it removes
the Google Play Services dependency (the F-Droid channel stays clean) and
sidesteps the play-services-cronet chain, whose cronet-api/cronet-shared
pair fails AGP 9's namespace check. The engine self-identifies as
`dsh-android/<version> http3` in `User-Agent`, so HTTP/3 adoption reads
straight off the gateway's Caddy access log per UA group.

The canonical command list and the aggregate verification gates live in
[AGENTS.md §Commands](AGENTS.md#commands); Flutter 3.47.1 lives in the CI
image, reached through `scripts/flutter.sh`. Real-host e2e is opt-in — see
[§Opt-in real-host e2e](#opt-in-real-host-e2e) below.

### Opt-in real-host e2e

```sh
cd flutter
flutter test --dart-define=DSH_E2E_URL=http://127.0.0.1:3080 \
  packages/harness_adapter/test/local_dsh_e2e_test.dart
```

The target travels as a dart define because `flutter test` forwards only a
fixed set of environment variables to the test process; a plain
`DSH_E2E_URL=… flutter test` reaches nothing.

A 0.2.0 host answers `/api` only for a caller holding the authority-bound
browser cookie minted from the URL token `dsh web` prints, so pass that cookie
as `DSH_E2E_COOKIE` when the target is one:

```sh
curl -s -c jar "http://127.0.0.1:3080/?token=<token dsh web printed>"
cd flutter
flutter test --dart-define=DSH_E2E_URL=http://127.0.0.1:3080 \
  --dart-define=DSH_E2E_COOKIE="$(awk 'NF>=7 && $6 ~ /^dsh/ {print $6"="$7}' jar)" \
  packages/harness_adapter/test/local_dsh_e2e_test.dart
```

The smoke covers the wire surface a preview rides — a workspace listing,
`stat`, and a paged text `read` — so a renamed workspace-file scope argument
fails there instead of only in the UI.

## APK releases

Release APKs are built by the internal forge pipeline
([`.gitea/workflows/release-apk.yaml`](.gitea/workflows/release-apk.yaml))
and mirrored to the [Releases page](../../releases): every `master`
push refreshes the rolling `dev` prerelease, a `v<semver>` tag cuts
the stable Release, and both attach signed per-ABI APKs (release keystore,
not the debug key) each with its own `.sha256` sidecar. Naming follows SemVer
2.0; the internal release body carries a generated `## What's
Changed` changelog, and the mirrored GitHub release carries the
artifact with version metadata. The GitHub-side copy of the workflow
([`.github/workflows/release-apk.yaml`](.github/workflows/release-apk.yaml))
skips its build unless signing secrets are present — this repo is the
mirror, not a second build channel.

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
