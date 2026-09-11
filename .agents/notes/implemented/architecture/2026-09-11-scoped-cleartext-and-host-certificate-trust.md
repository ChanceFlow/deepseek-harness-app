# Agent Note: Scoped cleartext and per-host certificate trust

Status: implemented

## Problem

The main manifest carried `android:usesCleartextTraffic="true"`, so every
release APK permitted plaintext HTTP to any host, and `docs/spec.md`
falsely claimed cleartext was a debug-manifest-only allowance. Separately,
a gateway reached as `https://<ip-or-internal-name>` with a self-signed or
internal-CA certificate failed Android's system validation. A network
security config cannot fix that: it trusts by domain at build time, not by
a runtime user decision, and Android cannot import a user CA into the app.

## Decision

Cleartext is scoped by
`flutter/app/android/app/src/main/res/xml/network_security_config.xml`
(`<base-config cleartextTrafficPermitted="false">` plus a domain-config for
`127.0.0.1`, `localhost`, and `10.0.2.2` — the app's own loopback/emulator
routes). The main manifest drops the flag and points
`android:networkSecurityConfig` at it. The debug/profile manifests are
untouched; `src/debug/res/xml/` and `src/profile/res/xml/` overrides keep
their intended broad cleartext, because on API 24+ the network security
config takes precedence over the manifest flag.

Certificate trust is a per-backend, explicit opt-in:
`BackendConfig.trustHostCertificate` (device-local `backends.json`,
defaults false) is surfaced as a `SwitchListTile` with the risk copy in the
host edit sheet. The `di/` layer resolves it — `http_engine.dart` and
`providers.dart` only. A trusted `https` backend's RPC leg rides
`trustedHostRpcClient`, an `IOClient` over an `HttpClient` whose
`badCertificateCallback` accepts the exact configured host and nothing
else; its event socket receives the same client through the new
`customClient` seam on `WebSocketDshEventSocket`. Every untrusted host
keeps Cronet (or dart:io's default client), and the default remains strict.
`packages/network` gains only a transport seam, no protocol knowledge.

`cronet_http` 1.9.0 exposes no certificate-verification override, so a
trusted backend steps off Cronet and loses the opportunistic HTTP/3
upgrade for that host. That is the price of the narrow override.

## Alternatives considered

- **Keep the blanket flag** — rejected: release builds would keep
  permitting plaintext to arbitrary hosts, the exact hole the audit found.
- **Network-security-config only, no trust path** — rejected: it cannot
  import a user CA at runtime, so a self-signed gateway stays unreachable
  and the user gets an opaque failure.
- **A single shared client with a blanket `badCertificateCallback`** —
  rejected: it would weaken TLS for every host, not the opted-in one.
- **Per-URL trust in the provider family key** — rejected: it churns every
  test override; selecting the registry flag keeps the `Uri` key stable and
  rebuilds the transport only when the opt-in flips.

## Consequences

- Release cleartext is loopback/emulator only; every other host must be
  HTTPS, and `docs/spec.md` now states the real policy.
- A trusted backend's transport is dart:io HTTP/1.1 until the opt-in is
  turned off; the setting's description and the
  [HTTP/3 note](../feature/2026-09-02-http3-cronet-engine-default.md) say so.
- Older `backends.json` documents decode as untrusted, and a non-bool
  `trustHostCertificate` fails the load loud.
- Residual risk: a user who enables the opt-in accepts an unverifiable
  certificate for that one host, so interception is possible there; the
  setting copy states it.
- Supersedes the HTTP/3 note's "certificate validation is strict with no
  bypass" consequence, which that note updates in place.
