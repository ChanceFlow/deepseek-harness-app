# Agent Note: Loopback backend default — release APKs ship with 127.0.0.1

Status: implemented

## Problem

The release APK baked `http://10.0.2.2:3080` as its backend default —
the Android *emulator's* route to the host loopback. A real phone
installing the released APK could never connect with it: `10.0.2.2`
routes nowhere off an emulator, and the README's "phone over LAN" row
promised a path that does not exist upstream — the reference dsh
webserver schema accepts only `127.0.0.1` or `0.0.0.0`
(`packages/host/webserver`), and the `dsh web` CLI rejects
`--host 0.0.0.0` as a remote-code-execution hazard
(`packages/bundle/web-app`). A vanilla `dsh web` never listens on the
LAN, so no client default aimed at the LAN can work.

## Decision

The release default is the device loopback: `kDshBaseUrl` in
`flutter/app/lib/config.dart` and the `dsh_base_url` fallback in both
`release-apk.yaml` workflows are `http://127.0.0.1:3080`. The supported
path to a backend is a loopback forward — `adb reverse tcp:3080
tcp:3080` over USB, which works identically on emulators and phones.
The emulator-only `10.0.2.2` route stays documented as a build-time
override, and any other reachable endpoint (tunnel, second machine) is
added through the shipped multi-backend registry — the settings page
keeps a device-local list of backends with add/rename/switch, seeded
from the build-time URL. The backend-URL hint strings in both locales
show the loopback example, and the README's connection table states the
upstream loopback-only stance instead of the LAN row.

## Alternatives considered

- **Keep the emulator default**: zero-config for emulators, but the
  release channel's main audience is real phones, where the default
  could never connect; the "which URL do I need" confusion moves into
  every support conversation.
- **LAN straight-shot guidance**: not implementable — upstream refuses
  all-interfaces binding for safety, so the README would promise a
  deployment mode that dsh rejects.
- **In-app first-launch URL prompt**: already covered better by the
  multi-backend registry, which edits and switches backends after
  install without blocking first use.

## Consequences

- A fresh install plus one `adb reverse` command connects on any device
  over USB; the seeded backend keeps the single-backend behavior.
- Release workflow dispatches keep the `dsh_base_url` override; the
  Gitea release body still prints it, the sanitized GitHub shadow body
  does not (contract unchanged, rationale comment updated).
- Developer docs (`AGENTS.md`, README §Development) lead with the
  loopback forward instead of the emulator route.
