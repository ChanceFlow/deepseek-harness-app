# Agent Note: Gradle reads its proxy from the rewritten EGRESS_PROXY file

Status: implemented

## Problem

Every `release-apk.yaml` build on the forge fails at *Build signed release
APK* as soon as the Gradle cache is cold — a Gradle artifact download times
out against a proxy host that no longer answers. The workflow's env sets
`HTTP_PROXY` to the live `vars.EGRESS_PROXY`, and
pub and curl honor it; Gradle does not. The build image ships
`/root/.gradle/gradle.properties` with `systemProp.http(s).proxyHost` baked
from a build arg, the Gradle JVM has no env-proxy fallback, and the
`systemProp` file outranks any env. When the baked host moved off the
network, warm-cache dev builds kept passing — nothing re-downloaded — until
a cache restore miss exposed it; every push since is red and the stable
release channel is dead. Same family as
[the runner-env proxy failure](2026-08-25-ci-runner-env-injection.md),
one layer deeper.

## Decision

`release-apk.yaml` gains an *Align Gradle proxy with EGRESS_PROXY* step
between *Analyze* and the APK build: it rewrites the four
`systemProp.…proxyHost/Port` lines of `/root/.gradle/gradle.properties`
from the resolved `vars.EGRESS_PROXY` (port defaults to 7890), creating
missing lines, and deletes them entirely when the var is unset. The
workflow's env stays the single proxy declaration; the image's baked value
is no longer load-bearing.

## Alternatives considered

- **Rebuild the image with the right build-arg**: rejected as the sole fix —
  it re-bakes a literal that rots exactly this way again, and the
  Dockerfile is not in this repo, so the repair would live in unversioned
  host state.
- **Pass `-Dhttp.proxyHost` through to Gradle**: rejected — `flutter build
  apk` has no clean passthrough for it and the precedence against a
  `systemProp` file line is not documented enough to bet the release
  channel on.
- **Leave it to `org.gradle.jvmargs`**: rejected — same precedence
  ambiguity, and it does not fix standalone `gradlew` invocations in the
  container.

## Consequences

Cold-cache release builds succeed again; the rolling `dev` channel recovers
on the next master push. Any future proxy move is a one-variable edit
(`EGRESS_PROXY`) instead of an image rebuild. If the forge ever runs a
proxy-less network, unsetting `EGRESS_PROXY` now also correctly strips the
Gradle proxy instead of leaving a stale dial-in. The `.github` copy of the
workflow is untouched: its runners are GitHub-hosted and carry no baked
LAN proxy file.
