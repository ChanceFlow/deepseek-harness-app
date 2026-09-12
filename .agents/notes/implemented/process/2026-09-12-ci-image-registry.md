# Agent Note: The CI image is published, and both ends of its pin are checked

Status: implemented

## Problem

The container label made the runner machine's toolchain irrelevant, but the
image it names existed only in that machine's podman store, and the store is not
a place a build artifact should live. A `localhost/flutter-3.47-android:latest`
tag belongs to one machine: a `podman rmi`, a prune, or a disk failure removes
the only copy, and nothing outside that store can pull it. The `latest` in it is
also a moving name — no record said which build was running.

The label's image reference lives in the runner's configuration, outside this
repository, so the repository could not tell whether its gates had run against
the toolchain it pins. `verify_ci_container_jobs.py` holds a workflow to the
container label's *name*; it cannot see what that name resolves to.

## Decision

- **The image is published** to the forge's own container registry. The Gitea
  instance already serves one (`[packages] ENABLED = true`), and Gitea's own
  design document names it as the intended image registry for its Actions.
  [docker/build-image.sh](../../../../docker/build-image.sh) gained `PUSH=1` for
  it. The registry is never named in the repository: the leak rules reject
  internal addresses, and the reference belongs with the rest of the label.
- **The label pins the digest, not `latest`.** Gitea's runner documentation asks
  for tag-or-digest pinning and notes that a digest-pinned image is never
  re-pulled; a digest also cannot be re-pointed the way a tag can.
- **Both ends of the pin are checked.** The image writes its own build name to
  `/etc/dsh-ci-image` ([docker/flutter-android.Dockerfile](../../../../docker/flutter-android.Dockerfile),
  from the `IMAGE_VERSION` build arg); `gates_manifest.json` `ci.image_tag`
  states the build the repository expects; every toolchain job in both workflows
  compares the two before any gate runs. A label repointed at another image now
  fails on its first step. The digest is the operator's half and stays in the
  runner configuration, because a job cannot read its own digest.
- **The identity is written by a `RUN`, not by an `ENV`.** Measured while
  publishing: a `LABEL` or `ENV` that interpolates an `ARG` is served from the
  build cache even when that `ARG` has changed, so two builds differing only in
  `IMAGE_VERSION` produced one image carrying the first one's version. Consuming
  the argument in a `RUN` is what makes the metadata and the file agree with the
  build that was actually asked for.
- **The published package is public.** It holds a JDK, an Android SDK and
  Flutter — no secret — and an anonymous pull token is what spares the runner a
  credential that would otherwise have to survive a reboot: `podman login`
  writes `/run/user/1000/containers/auth.json`, which is tmpfs.

## Alternatives considered

- **Keep the image machine-local.** Rejected as the whole answer: the build is
  reproducible but slow and needs the egress proxy, and its tag said nothing
  about what had been built. The local tag stays as the build's own output.
- **Publish and leave the repository as it was.** Rejected: that moves an
  invisible mapping from one store to another. A registry adds addressability,
  not visibility.
- **Push from CI on every Dockerfile change.** Rejected for now: Gitea Actions
  cannot publish to its own package registry with `GITEA_TOKEN` (documented as
  unimplemented, workaround a PAT secret), and a build of this size inside a job
  would need a privileged container the runner deliberately does not offer.
- **A private package with a stored credential.** Rejected: it buys nothing, and
  the image is not a secret.
- **Pin the digest `podman push` reports.** Rejected after measuring: the
  registry re-serialises the pushed schema2 manifest as an OCI one, so the
  digest it serves is not the digest podman records for itself. The script asks
  the registry for the manifest instead of trusting the push.

## Consequences

The first job after a rebuild pulls the changed layers; later jobs use the local
copy. A rebuild must bump `ci.image_tag` — the assertion fails loudly if it does
not, and that is the intended cost. A new tag per publish is not only tidiness:
the registry keeps the blobs of a manifest that a later push under the same tag
replaced (measured at 2.6 GB after three pushes under one tag), and a distinct
package version is the only handle the API offers for retiring an image. The
published copy measured 8 GB for an 11.4 GB image, because a registry stores
layers compressed and holds each digest once: publishing is a second copy on the
same disk, not a backup. Gitea does not support podman as a runner engine
("Podman is not a supported configuration"), so this arrangement is measured
here rather than guaranteed upstream.
