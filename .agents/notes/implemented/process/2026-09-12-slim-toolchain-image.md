# Agent Note: The toolchain image is built on the slim base

Status: implemented

## Problem

The image measured 12 GB, and most of it is the toolchains a job actually runs:
Flutter 2.5 GB, the Android SDK 2.9 GB (2.2 GB of that the NDK), the warm Gradle
caches 3.2 GB and the pub cache 0.7 GB. None of that is removable — a job runs
inside this image, so every toolchain must be present at run time, and the NDK
is not optional either: `jni`'s Android build declares `externalNativeBuild`.
What *was* removable is the base all of it sat on. The runners'
`ubuntu-24.04` is 1.66 GB, and this image needs one thing from it: the `node`
act executes `uses:` actions with.

Alpine is not the answer, and measuring says so quickly. The Dart SDK's binary
is glibc-linked (`libdl.so.2 => /lib/x86_64-linux-gnu/...`), and so are
`flutter_tester`, `aapt2`, `adb` and the NDK's clang. Alpine is musl, so
supporting it means a compatibility layer under each of them. It would also
save the wrong thing: about 200 MB against the slim base, on a 12 GB image.

## Decision

- **The base is `ubuntu-24.04-slim`, 205 MB measured.** The packages it drops
  that jobs use — git, curl, python3, unzip, xz-utils, zip, ca-certificates —
  are installed in the JDK stage, which the final stage already inherits, for
  about 100 MB on top of the JDK that stage installed anyway. Net 1.3 GB, with
  no change in what a job can do. The name says Ubuntu; it is Debian 12
  underneath, and the JDK is the distribution's either way.
- **Only the Android platform this project compiles against is installed** (36,
  not 34 and 35). Licenses are still accepted, so a Gradle run asking for
  another revision fetches it instead of failing. 285 MB.
- **Gradle's `-bin` distribution, and the wrapper archive deleted after
  extraction.** The wrapper left both the unpacked distribution and the archive
  it came from (768 MB measured, 235 MB of it the archive nothing reads), and
  no step reads Gradle's sources or documentation. About 615 MB together.
- **A loopback proxy is rewritten to `host.containers.internal`** in
  [scripts/container.sh](../../../../scripts/container.sh) and the workstation
  shim. A host proxy at `127.0.0.1` addresses the container itself, so anything
  that inherited one failed with "Connection refused" while the host's proxy was
  healthy — that is what stopped a `pub get` here from resolving. Measured: the
  same proxy returns 200 through `host.containers.internal`.

## Alternatives considered

- **Alpine.** Rejected on the measurement above; it optimises the layer that was
  never the problem.
- **Pruning the warm caches** (Gradle `modules-2` 1.1 GB, `caches/9.3.1` 1.4 GB,
  pub's non-Android `sherpa_onnx` packages 225 MB). Rejected: those bytes come
  back as downloads in every job, so it moves size into job time instead of
  removing it.
- **Trimming Flutter's engine artifacts** (profile and release variants, the x86
  debug engine). Deferred, not rejected: the tool's own cache manifest lists
  `android-x86` among the artifacts it manages, so deleting one invites a
  re-download. Worth doing with a job that proves the ABI is unused.
- **Dropping `cmdline-tools`** (159 MB). Rejected: it is what lets Gradle fetch
  a missing SDK component at job time, which is the property that made trimming
  platforms safe in the first place.

## Consequences

The image is 9.7 GB instead of 12 GB, and a republish under a new tag is what
carries that to the runner — which is why `gates_manifest.json` pins the build
name. A job that asks for an Android platform or build-tools revision this image
does not carry downloads it; the accepted licenses are what make that work, and
it is the same egress the job already uses for pub.
