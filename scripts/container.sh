#!/usr/bin/env bash
# Run anything in the CI toolchain image — this repository's local toolchain.
#
# No JDK, Flutter, Android SDK, pub cache or Gradle cache is installed on the
# machine. The toolchain lives in the image CI also uses
# (docker/flutter-android.Dockerfile), and this script is how a workstation
# reaches it. That is the point: the gates and your keyboard run the same
# toolchain by construction instead of by agreement.
#
#   scripts/container.sh flutter analyze
#   scripts/container.sh flutter test app/test
#   scripts/container.sh dart format --output=none --set-exit-if-changed .
#   scripts/container.sh python3 scripts/verify_all.py code
#
# The repository is mounted at its own path, so relative paths and the
# reference submodule resolve exactly as they do outside, and the working
# directory follows you while you are inside it. Dependencies come from the
# image: a package the image does not carry downloads per run until the image
# is rebuilt (docker/build-image.sh), because nothing is written to the host.
#
# Files you create keep your ownership — rootless podman maps the container's
# root to the invoking user.
#
# Egress: export HTTP_PROXY / HTTPS_PROXY / NO_PROXY before calling when this
# host needs a proxy. They are passed through, never stored here.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="${DSH_CI_IMAGE:-localhost/flutter-3.47-android:latest}"

if [ "$#" -eq 0 ]; then
  echo "usage: $(basename "$0") <command> [args...]" >&2
  exit 2
fi

if ! podman image exists "$IMAGE" && [ -z "${DSH_CI_IMAGE:-}" ]; then
  # Which local reference holds this image is not fixed. A local build tags it
  # `localhost/flutter-3.47-android:latest`; the runner pulls the published
  # reference its label pins and leaves the image under that name instead, with
  # no tag at all — podman renders that as `<none>`, which is not a reference
  # anything can run. The bytes are the same either way, so take whichever of
  # the two this machine actually has instead of telling a workstation to
  # rebuild what is already on disk.
  # No early exit here and no `head`: `set -o pipefail` above turns the SIGPIPE
  # either would hand the producer into this script's own failure, which is how
  # an earlier version of this block exited 141 saying nothing at all.
  matches=$(podman images --format '{{.Repository}} {{.Tag}} {{.Digest}}' \
    | awk '$1 ~ /(^|\/)flutter-android$/ {
             if ($2 != "<none>") print $1 ":" $2;
             else if ($3 != "") print $1 "@" $3;
           }')
  fallback=${matches%%$'\n'*}
  if [ -n "$fallback" ]; then
    echo "container.sh: $IMAGE is absent; using $fallback" >&2
    IMAGE="$fallback"
  fi
fi

if ! podman image exists "$IMAGE"; then
  # A reference that names a registry is pulled by the `podman run` below and
  # needs nothing here; `localhost/<name>` is podman's spelling for "the image
  # in my own store" and can never be pulled, so only that kind is fatal.
  case "${IMAGE%%/*}" in
    "$IMAGE"|localhost)
      echo "toolchain image not built: $IMAGE" >&2
      echo "build it: PROXY=<http://host:port> bash docker/build-image.sh" >&2
      echo "or set DSH_CI_IMAGE to the published reference that script prints" >&2
      exit 1
      ;;
  esac
fi

case "$PWD" in
  "$REPO"*) WORKDIR="$PWD" ;;
  *)        WORKDIR="$REPO" ;;
esac

# Same allowances CI gives the job container; without them the JVM's shared
# memory and javac's file descriptors are too small to build this project.
TTY=(); [ -t 0 ] && TTY=(-t)

exec podman run --rm -i "${TTY[@]}" \
  --shm-size=1g \
  --ulimit nofile=65536:65536 \
  --volume "$REPO:$REPO" \
  --workdir "$WORKDIR" \
  --env HTTP_PROXY --env HTTPS_PROXY --env http_proxy --env https_proxy \
  --env NO_PROXY --env no_proxy \
  "$IMAGE" "$@"
