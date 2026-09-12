# Prebaked Flutter + Android SDK builder image for the container-schema runner
# label `flutter-android-ctr`. The label's image reference — a tag pinned by
# digest, published to the forge's own container registry — lives in the
# runner's configuration, outside this repository, like the schema itself. What
# this file owns is the other end: the image states which build it is, and CI
# fails when that is not the build the repository pins.
# Decision: .agents/notes/implemented/process/2026-09-12-ci-image-registry.md
#
# EVERY TOOLCHAIN COMES FROM A STAGE OR AN UPSTREAM RELEASE. Nothing is copied
# from the machine that runs the build: the JDK is installed into a stage, the
# Android SDK is fetched by Google's own command-line tools, and Flutter is the
# pinned upstream release tarball. A builder therefore needs podman and network
# — no JDK, no Android SDK, no Flutter, no warm pub or Gradle cache on the
# host. That is the point: the CI toolchain belongs to the image.
#
# LAYER ORDER IS THE CACHE — the manifests-first pattern an npm/uv image uses:
#
#   stage jdk / android-sdk / flutter   toolchain, keyed on its own ARG
#   layer 1   pubspec.yaml + pubspec.lock   `flutter pub get`
#   layer 2   the committed source tree     `:app:compileDebugKotlin`
#
# Layer 2 is also where this image's Gradle build cache comes from: the warmup
# build bakes task outputs under ~/.gradle/caches/build-cache-1 and transformed
# artifacts under ~/.gradle/caches/<gradle-version>, so a job for a nearby
# commit reuses every task whose inputs did not change. That snapshot is as
# fresh as the image — rebuild the image on master merges to keep it close.
#
# The base is the runners' own slim variant: act executes `uses:` actions with
# the node it ships, and nothing else this image needs comes from the base —
# the toolchains are grafted on. Measured at 205 MB against the full image's
# 1.66 GB. The packages slim drops that jobs do use (git, curl, python3, unzip,
# xz, zip, ca-certificates) are installed in the JDK stage below, which the
# final stage inherits, for about 150 MB: a 1.3 GB saving for no change in what
# a job can do. The name says Ubuntu; it is Debian 12 underneath, and the JDK
# is the distribution's either way.
ARG BASE=docker.gitea.com/runner-images:ubuntu-24.04-slim
ARG FLUTTER_VERSION=3.47.1
ARG CMDLINE_TOOLS_URL=https://dl.google.com/android/repository/commandlinetools-linux-13114758_latest.zip
ARG ANDROID_PLATFORM=android-36
ARG ANDROID_BUILD_TOOLS=36.0.0
# The NDK the Flutter Gradle plugin declares (`flutter.ndkVersion`). Installed
# here, with the rest of the toolchain, rather than left to the warmup's Gradle
# run: measured 2.2 GB, and a download that otherwise repeats on every rebuild
# that changes so much as one Dart file.
ARG ANDROID_NDK=28.2.13676358

# ── stage: JDK 17 ──────────────────────────────────────────────────────────
# The base image lists a Microsoft apt repository this egress cannot reach;
# left in place, `apt-get update` exits non-zero over that one index and takes
# the whole stage with it. Dropping the list is narrower than tolerating a
# failed update, which would let a genuinely broken index through.
#
# /opt/jdk is a symlink to the distribution's JDK, not a copy: Ubuntu's openjdk
# reads configuration from /etc/java-17-openjdk, so a copied tree alone breaks
# Java's own logging initialisation (seen as an AccessControlException out of
# LogManager during the image build). The final stage inherits this stage, which
# keeps both the configuration and the symlink in place.
# The install list is what the slim base omits and the jobs use: git and curl
# for `actions/checkout` and every download, python3 for the doc and code gates,
# and unzip/xz/zip for the archives those steps handle. `--no-install-recommends`
# keeps the rest of Debian's dependency closure out; measured ~100 MB on top of
# the JDK this stage installed anyway, against the 1.45 GB the full base adds.
FROM ${BASE} AS jdk
RUN rm -f /etc/apt/sources.list.d/microsoft-prod.list \
 && apt-get update \
 && apt-get install -y --no-install-recommends \
      openjdk-17-jdk-headless \
      ca-certificates curl git python3 unzip xz-utils zip \
 && rm -rf /var/lib/apt/lists/* \
 && ln -s "$(dirname "$(dirname "$(readlink -f "$(command -v javac)")")")" /opt/jdk \
 && /opt/jdk/bin/java -version

# ── stage: Android SDK, installed by Google's command-line tools ───────────
# Derived from the JDK stage because sdkmanager runs on Java. Only the platform
# this project compiles against is named here; the licenses accepted below let
# Gradle install whatever else it decides it needs. Measured: it fetches 34 and
# 35 during the warmup regardless, so this is a statement of what is required
# rather than a guess at what a future build might ask for.
FROM jdk AS android-sdk
ARG CMDLINE_TOOLS_URL
ARG ANDROID_PLATFORM
ARG ANDROID_BUILD_TOOLS
ARG ANDROID_NDK
ENV ANDROID_HOME=/opt/android-sdk \
    ANDROID_SDK_ROOT=/opt/android-sdk
RUN mkdir -p "$ANDROID_HOME/cmdline-tools" \
 && curl -fsSL "$CMDLINE_TOOLS_URL" -o /tmp/cmdline-tools.zip \
 && unzip -q /tmp/cmdline-tools.zip -d "$ANDROID_HOME/cmdline-tools" \
 && mv "$ANDROID_HOME/cmdline-tools/cmdline-tools" "$ANDROID_HOME/cmdline-tools/latest" \
 && rm /tmp/cmdline-tools.zip \
 && yes | "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" --licenses > /dev/null \
 && SDKM="$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager"; \
    for attempt in 1 2 3; do \
      if "$SDKM" --install "platform-tools" "platforms;$ANDROID_PLATFORM" \
           "build-tools;$ANDROID_BUILD_TOOLS" "ndk;$ANDROID_NDK"; then break; fi; \
      echo "sdkmanager attempt $attempt failed — a truncated download, most likely; retrying"; \
      rm -rf "$ANDROID_HOME/.temp" "$ANDROID_HOME/.downloadIntermediates"; \
      [ "$attempt" != 3 ] || exit 1; \
    done \
 && rm -rf "$ANDROID_HOME/.temp" "$ANDROID_HOME/.downloadIntermediates"

# ── stage: Flutter, the pinned upstream release ────────────────────────────
FROM ${BASE} AS flutter
ARG FLUTTER_VERSION
# The slim base ships neither curl, xz nor git, and this stage downloads a
# .tar.xz and marks it a safe git directory. The layer dies with the stage; only
# /opt/flutter is copied out of it.
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl git xz-utils \
 && rm -rf /var/lib/apt/lists/* \
 && curl -fsSL \
      "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" \
      -o /tmp/flutter.tar.xz \
 && tar -xJf /tmp/flutter.tar.xz -C /opt \
 && rm /tmp/flutter.tar.xz \
 && git config --global --add safe.directory /opt/flutter \
 && /opt/flutter/bin/flutter config --no-analytics > /dev/null \
 && /opt/flutter/bin/flutter --version

# ── the image jobs run in ──────────────────────────────────────────────────
# Derived from the JDK stage so the distribution's Java configuration travels
# with the /opt/jdk symlink; only the SDK and Flutter are copied in.
FROM jdk
ENV ANDROID_HOME=/opt/android-sdk \
    ANDROID_SDK_ROOT=/opt/android-sdk \
    JAVA_HOME=/opt/jdk \
    FLUTTER_ROOT=/opt/flutter \
    PUB_CACHE=/root/.pub-cache
COPY --from=android-sdk /opt/android-sdk /opt/android-sdk
COPY --from=flutter /opt/flutter /opt/flutter
ENV PATH=/opt/jdk/bin:/opt/flutter/bin:/opt/android-sdk/cmdline-tools/latest/bin:/opt/android-sdk/platform-tools:$PATH

# What the grafted toolchain has to answer for; a broken stage fails the image
# build here rather than inside a job.
RUN git config --global --add safe.directory /opt/flutter \
 && flutter config --no-analytics --android-sdk /opt/android-sdk > /dev/null \
 && flutter --version \
 && java -version \
 && "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" --version

# The build's own egress, supplied per build and never left as the job's route:
# the runner passes its environment to every job, and both workflows rewrite
# ~/.gradle/gradle.properties from the live EGRESS_PROXY variable before a
# Gradle invocation. Empty is legitimate — a builder with direct egress needs
# no proxy, and nothing here bakes an address that can go stale.
ARG proxy_host
ARG proxy_port

# ── layer 1: dependency resolution, keyed on the manifests alone ───────────
COPY --from=repo /flutter/pubspec.yaml /flutter/pubspec.lock /tmp/warmup/flutter/
COPY --from=repo /flutter/app/pubspec.yaml /tmp/warmup/flutter/app/
COPY --from=repo /flutter/packages/asr/pubspec.yaml /tmp/warmup/flutter/packages/asr/
COPY --from=repo /flutter/packages/dev/pubspec.yaml /tmp/warmup/flutter/packages/dev/
COPY --from=repo /flutter/packages/domain/pubspec.yaml /tmp/warmup/flutter/packages/domain/
COPY --from=repo /flutter/packages/harness_adapter/pubspec.yaml /tmp/warmup/flutter/packages/harness_adapter/
COPY --from=repo /flutter/packages/network/pubspec.yaml /tmp/warmup/flutter/packages/network/

RUN set -eu; \
    if [ -n "$proxy_host" ]; then \
      mkdir -p /root/.gradle; \
      printf 'systemProp.http.proxyHost=%s\nsystemProp.http.proxyPort=%s\nsystemProp.https.proxyHost=%s\nsystemProp.https.proxyPort=%s\n' \
        "$proxy_host" "$proxy_port" "$proxy_host" "$proxy_port" > /root/.gradle/gradle.properties; \
    fi; \
    cd /tmp/warmup/flutter && flutter pub get

# ── layer 2: the committed source, and the warmup build ────────────────────
# COPY merges into the directory, so layer 1's .dart_tool/ and generated plugin
# metadata survive; only the sources and the lockfile are replaced.
#
# The warmup runs `:app:compileDebugKotlin` — exactly what the merge gate's
# android job runs — rather than a full `flutter build apk`. It resolves the
# same Gradle graph and populates the same build cache for every task the gate
# needs, at a fraction of the memory an assembleDebug wants, and memory is the
# binding constraint on a host that also runs this repository's other work.
# The release channel's dex and packaging run in its own job, over the cache
# this leaves behind.
#
# The wrapper leaves both the unpacked distribution and the archive it came
# from — 768 MB measured, of which the archive is 235 MB that nothing reads
# once the distribution is unpacked — so the warmup drops the archive on its
# way out. The repository's wrapper properties ask for the `-bin` distribution
# rather than `-all` for the same reason: no step here reads Gradle's sources
# or documentation, and the difference is 235 MB against 783 MB unpacked.
COPY --from=repo /flutter /tmp/warmup/flutter
RUN set -eu; \
    if [ -n "$proxy_host" ]; then \
      export GRADLE_OPTS="-Dhttp.proxyHost=$proxy_host -Dhttp.proxyPort=$proxy_port -Dhttps.proxyHost=$proxy_host -Dhttps.proxyPort=$proxy_port"; \
    fi; \
    cd /tmp/warmup/flutter && flutter pub get; \
    cd /tmp/warmup/flutter/app/android; \
    WRAPPER=/opt/flutter/bin/cache/artifacts/gradle_wrapper; \
    cp -n "$WRAPPER/gradlew" gradlew; \
    cp -n "$WRAPPER/gradle/wrapper/gradle-wrapper.jar" gradle/wrapper/gradle-wrapper.jar; \
    chmod +x gradlew; \
    ./gradlew :app:compileDebugKotlin; \
    rm -f /root/.gradle/wrapper/dists/*/*/*.zip; \
    cd / && rm -rf /tmp/warmup

# ── this image's identity ──────────────────────────────────────────────────
# Declared after every expensive layer on purpose: the identity is a few bytes,
# so a rebuild that changes only it reuses every toolchain layer above and
# re-pushing moves that one layer and the image config, not the toolchain.
#
# A job cannot read the runner's label configuration, so it cannot see the
# reference it was created from. What it can see is this: the image states its
# own build, the repository states the build it pins (`gates_manifest.json`
# `ci.image_tag`), and the workflow compares the two before any gate runs. A
# label repointed at some other image then fails on the first step instead of
# quietly running the gates against a different toolchain.
#
# The revision and source are metadata for whoever inspects the image later.
# The source is empty unless a publisher supplies one: an internal address baked
# into an image travels with that image to every registry it is later pushed to.
ARG IMAGE_VERSION=unknown
ARG IMAGE_REVISION=unknown
ARG IMAGE_SOURCE=

# The identity is written by a RUN, and not only by the ENV an image would
# normally use: a metadata instruction that interpolates an ARG is served from
# the build cache even when that ARG has changed — two builds differing only in
# IMAGE_VERSION produced one image with the first one's version baked in.
# Consuming the ARG here is what makes this layer, the labels below and the
# job's reading of this file agree with the build the publisher asked for.
RUN printf 'DSH_CI_IMAGE_VERSION=%s\nDSH_CI_IMAGE_REVISION=%s\n' \
      "$IMAGE_VERSION" "$IMAGE_REVISION" > /etc/dsh-ci-image \
 && cat /etc/dsh-ci-image

LABEL org.opencontainers.image.title="flutter-android" \
      org.opencontainers.image.description="Flutter, Android SDK and JDK 17 for this repository's CI jobs" \
      org.opencontainers.image.version="${IMAGE_VERSION}" \
      org.opencontainers.image.revision="${IMAGE_REVISION}" \
      org.opencontainers.image.source="${IMAGE_SOURCE}"

WORKDIR /workspace
