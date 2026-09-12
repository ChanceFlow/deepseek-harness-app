#!/usr/bin/env bash
# Build the prebaked Flutter + Android SDK image for the container-schema
# runner label `flutter-android-ctr`, and — with PUSH=1 — publish it to the
# forge's own container registry, where the label pins it by digest.
#
# PODMAN, ROOTLESS. The image lands in the caller's own store and the runner
# creates job containers from it over the rootless podman socket. No root, no
# Docker daemon, no /var/run/docker.sock compatibility symlink: the runner is a
# Docker-API *client*, and it speaks to podman's native socket.
#
# The DEFAULT tag carries a `localhost/` prefix deliberately: a bare
# `flutter-3.47-android:latest` resolves to docker.io, and `localhost/` is how
# podman is told to use the image in its own store. That default builds only —
# an image nothing can pull is an artifact of one machine. Naming a registry in
# IMAGE_TAG is what makes it addressable, and PUSH=1 is what publishes it.
#
# The only thing this script takes from the machine is a git archive of the
# committed flutter/ workspace, which the image needs to warm its own caches.
# Every toolchain is built inside the image from an upstream release (see the
# Dockerfile), so a builder needs podman and network — not a JDK, an Android
# SDK, Flutter, or a warm pub/Gradle cache.
#
# Override via env:
#   IMAGE_TAG  PROXY  PUSH  REGISTRY_SCHEME  IMAGE_VERSION  IMAGE_REVISION
#   FLUTTER_VERSION  CMDLINE_TOOLS_URL  ANDROID_PLATFORM  ANDROID_BUILD_TOOLS
#
# PUBLISHING. The registry is never named in this repository — the label's
# image reference lives in the runner's own configuration, and the leak rules
# here reject internal addresses — so a publisher supplies it in IMAGE_TAG and
# logs in first:
#
#   podman login <registry> -u <user>              # a token, not the password
#   PROXY=<http://host:port> PUSH=1 \
#     IMAGE_TAG=<registry>/<owner>/flutter-android:<version> \
#     bash docker/build-image.sh
#
# Use a NEW TAG for each publish. The registry keeps the blobs of a manifest
# that a later push under the same tag replaced — measured at 2.6 GB after
# three pushes under one tag — and a distinct package version is the only
# handle the API offers for retiring an image that is no longer pinned.
#
# The digest that matters is the one the REGISTRY serves, and it is what this
# script prints last: see the note at the push for why podman's own record of
# that digest is a different value.
#
# The build runs its RUN steps in a container whose /dev/shm defaults to 64 MB,
# which is where the JVM's shared-memory files live: too small and the Gradle
# daemon dies with "Gradle build daemon disappeared unexpectedly" after minutes
# of work. The 1 GB below is the same allowance the job containers get, so a
# warmup that fits here also fits a job.
#
# PROXY is the egress the build uses (base-image pull, apt, Google's SDK
# downloads, the pinned Flutter tarball, pub.dev, Gradle). It has no default on
# purpose: an address baked into an image is how a moved egress becomes a
# silent "repository disabled" compile with no error anywhere. Pass it per
# build; omit it when the builder has direct egress.
#
# On a memory-tight host, run the build in a capped scope — the in-image Gradle
# daemon asks for -Xmx8G and the Kotlin daemon for another 8G, so an unbounded
# build on a 15 GB machine is how the whole box goes down:
#   systemd-run --user --scope -p MemoryMax=10G -p MemorySwapMax=2G \
#     env PROXY=http://<host>:<port> bash docker/build-image.sh
set -euo pipefail
cd "$(dirname "$0")"

REPO_ROOT=$(git rev-parse --show-toplevel)

IMAGE_TAG=${IMAGE_TAG:-localhost/flutter-3.47-android:latest}
PROXY=${PROXY:-}
FLUTTER_VERSION=${FLUTTER_VERSION:-3.47.1}
CMDLINE_TOOLS_URL=${CMDLINE_TOOLS_URL:-https://dl.google.com/android/repository/commandlinetools-linux-13114758_latest.zip}
ANDROID_PLATFORM=${ANDROID_PLATFORM:-android-36}
ANDROID_BUILD_TOOLS=${ANDROID_BUILD_TOOLS:-36.0.0}

# What the image declares about itself, and what CI checks it against. The tag
# is the build's name — `gates_manifest.json` `ci.image_tag` holds the same
# string — and the revision is the commit whose sources it was built from.
#
# The source label is empty unless a publisher sets it. Reading it from this
# checkout's remote would be convenient and wrong: this script cannot tell a
# public remote from an internal one, and an internal address baked into an
# image travels with that image to every registry it is later pushed to.
IMAGE_VERSION=${IMAGE_VERSION:-${IMAGE_TAG##*:}}
IMAGE_REVISION=${IMAGE_REVISION:-$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null || echo unknown)}
IMAGE_SOURCE=${IMAGE_SOURCE:-}
# The internal forge serves its registry over plain HTTP behind the LAN; a
# builder whose registry speaks TLS sets REGISTRY_SCHEME=https.
REGISTRY_SCHEME=${REGISTRY_SCHEME:-http}

WARMUP=$(mktemp -d /tmp/flutter-image-repo.XXXXXX)
trap 'rm -rf "$WARMUP"' EXIT
git -C "$REPO_ROOT" archive HEAD flutter | tar -x -C "$WARMUP"
[ -d "$WARMUP/flutter" ] || { echo "git archive produced no flutter/ tree" >&2; exit 1; }

PROXY_HOST= PROXY_PORT= BUILD_ARGS=()
if [ -n "$PROXY" ]; then
  authority=${PROXY#*://}
  PROXY_HOST=${authority%%:*}
  PROXY_PORT=${authority##*:}
  [ "$PROXY_PORT" != "$authority" ] || { echo "PROXY needs an explicit port: $PROXY" >&2; exit 1; }
  # Both the registry pull and the RUN steps take their route from the client
  # environment, so one variable drives both.
  export HTTP_PROXY="$PROXY" HTTPS_PROXY="$PROXY" http_proxy="$PROXY" https_proxy="$PROXY"
  export NO_PROXY=localhost,127.0.0.1,::1 no_proxy=localhost,127.0.0.1,::1
  BUILD_ARGS+=(
    --build-arg "http_proxy=$PROXY" --build-arg "https_proxy=$PROXY"
    --build-arg "no_proxy=localhost,127.0.0.1,::1"
    --build-arg "proxy_host=$PROXY_HOST" --build-arg "proxy_port=$PROXY_PORT"
  )
fi

echo "repo    : $(git -C "$REPO_ROOT" rev-parse --short HEAD) (committed flutter/ tree)"
echo "flutter : $FLUTTER_VERSION (upstream release tarball)"
echo "android : platform $ANDROID_PLATFORM, build-tools $ANDROID_BUILD_TOOLS (Google command-line tools)"
echo "jdk     : openjdk-17 from the base image's distribution"
echo "proxy   : ${PROXY:-none — the build reaches the network directly}"
echo "tag     : $IMAGE_TAG"
echo "version : $IMAGE_VERSION (baked as DSH_CI_IMAGE_VERSION, asserted by CI)"
echo "builder : $(podman --version)  rootless=$(podman info --format '{{.Host.Security.Rootless}}')"

# The build runs its RUN steps in a container whose /dev/shm defaults to 64 MB
# and whose file-descriptor limit defaults to 1024. Both are too small for a
# Gradle build: the JVM's shared-memory files die without room, and javac hits
# "Too many open files" opening classpath jars, which surfaces as a bogus
# "cannot find symbol" cascade. The allowances below match what the job
# containers get, so a warmup that fits here also fits a job.
podman build \
  --shm-size=1g \
  --ulimit nofile=65536:65536 \
  --build-context repo="$WARMUP" \
  --build-arg "FLUTTER_VERSION=$FLUTTER_VERSION" \
  --build-arg "CMDLINE_TOOLS_URL=$CMDLINE_TOOLS_URL" \
  --build-arg "ANDROID_PLATFORM=$ANDROID_PLATFORM" \
  --build-arg "ANDROID_BUILD_TOOLS=$ANDROID_BUILD_TOOLS" \
  --build-arg "IMAGE_VERSION=$IMAGE_VERSION" \
  --build-arg "IMAGE_REVISION=$IMAGE_REVISION" \
  --build-arg "IMAGE_SOURCE=$IMAGE_SOURCE" \
  "${BUILD_ARGS[@]}" \
  -f flutter-android.Dockerfile \
  -t "$IMAGE_TAG" \
  .

podman image inspect "$IMAGE_TAG" --format "built: {{.Id}} size: {{.Size}} bytes"

if [ "${PUSH:-0}" != "1" ]; then
  echo "pushed  : no — PUSH=1 publishes it and prints the digest to pin"
  exit 0
fi

podman push "$IMAGE_TAG"

# The digest a label pins is the one the REGISTRY serves, and that is not the
# one podman records for itself. The push hands the registry a docker-schema2
# manifest; the registry stores it as an OCI one, and re-serialising a manifest
# changes its bytes, so its digest changes with them. A pin copied from
# `podman image inspect .RepoDigests` right after a push therefore names a
# digest no registry resolves, and the failure lands on the runner — as a job
# that cannot pull its image — rather than here. Asking the registry for the
# manifest is what makes the printed pin true.
registry=${IMAGE_TAG%%/*}
repository=${IMAGE_TAG#*/}
repository=${repository%%:*}
tag=${IMAGE_TAG##*:}
token=$(curl -fsS \
  "${REGISTRY_SCHEME}://${registry}/v2/token?service=container_registry&scope=repository:${repository}:pull" \
  | python3 -c 'import json,sys; print(json.load(sys.stdin).get("token", ""))')
digest=$(curl -fsSI \
  -H "Authorization: Bearer ${token}" \
  -H 'Accept: application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.v2+json' \
  "${REGISTRY_SCHEME}://${registry}/v2/${repository}/manifests/${tag}" \
  | tr -d '\r' | awk 'tolower($1) == "docker-content-digest:" { print $2 }')
[ -n "$digest" ] || { echo "pushed, but the registry reported no manifest digest" >&2; exit 1; }

echo "digest  : ${digest}"
echo "label   : <name>:docker://${registry}/${repository}@${digest}"
