#!/usr/bin/env bash
# Build the prebaked Flutter + Android SDK image for the container-schema
# runner label
# (`flutter-android:docker://localhost/flutter-3.47-android:latest`).
#
# PODMAN, ROOTLESS. The image lands in the caller's own store and the runner
# creates job containers from it over the rootless podman socket. No root, no
# Docker daemon, no /var/run/docker.sock compatibility symlink: the runner is a
# Docker-API *client*, and it speaks to podman's native socket.
#
# The tag carries a `localhost/` prefix deliberately. A bare
# `flutter-3.47-android:latest` resolves to docker.io and the runner would try
# to pull it from a registry instead of using the local image.
#
# The only thing this script takes from the machine is a git archive of the
# committed flutter/ workspace, which the image needs to warm its own caches.
# Every toolchain is built inside the image from an upstream release (see the
# Dockerfile), so a builder needs podman and network — not a JDK, an Android
# SDK, Flutter, or a warm pub/Gradle cache.
#
# Override via env:
#   IMAGE_TAG  PROXY  FLUTTER_VERSION  CMDLINE_TOOLS_URL
#   ANDROID_PLATFORM  ANDROID_BUILD_TOOLS
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
  "${BUILD_ARGS[@]}" \
  -f flutter-android.Dockerfile \
  -t "$IMAGE_TAG" \
  .

podman image inspect "$IMAGE_TAG" --format "built: {{.Id}} size: {{.Size}} bytes"
