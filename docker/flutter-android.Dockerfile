# Prebaked Flutter + Android SDK builder image for the container-schema runner
# label (`flutter-android:docker://localhost/flutter-3.47-android:latest`).
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
#   layer 2   the committed source tree     `flutter build apk --debug`
#
# Layer 2 is also where this image's Gradle build cache comes from: the warmup
# build bakes task outputs under ~/.gradle/caches/build-cache-1 and transformed
# artifacts under ~/.gradle/caches/<gradle-version>, so a job for a nearby
# commit reuses every task whose inputs did not change. That snapshot is as
# fresh as the image — rebuild the image on master merges to keep it close.
#
# The final stage stays on the runners' own Ubuntu base because act executes
# `uses:` actions with the node it ships; the toolchains are grafted onto it.
ARG BASE=docker.gitea.com/runner-images:ubuntu-24.04
ARG FLUTTER_VERSION=3.47.1
ARG CMDLINE_TOOLS_URL=https://dl.google.com/android/repository/commandlinetools-linux-13114758_latest.zip
ARG ANDROID_PLATFORM=android-36
ARG ANDROID_BUILD_TOOLS=36.0.0

# ── stage: JDK 17, relocated to a fixed path so the final stage can copy it ──
FROM ${BASE} AS jdk
RUN apt-get update \
 && apt-get install -y --no-install-recommends openjdk-17-jdk-headless \
 && rm -rf /var/lib/apt/lists/* \
 && mv "$(dirname "$(dirname "$(readlink -f "$(command -v javac)")")")" /opt/jdk \
 && /opt/jdk/bin/java -version

# ── stage: Android SDK, installed by Google's command-line tools ───────────
# Licenses are accepted here so a later Gradle run may fetch any platform or
# build-tools revision this project's Flutter pin asks for, instead of failing
# on a missing license inside a job.
FROM ${BASE} AS android-sdk
ARG CMDLINE_TOOLS_URL
ARG ANDROID_PLATFORM
ARG ANDROID_BUILD_TOOLS
ENV ANDROID_HOME=/opt/android-sdk \
    ANDROID_SDK_ROOT=/opt/android-sdk
RUN mkdir -p "$ANDROID_HOME/cmdline-tools" \
 && curl -fsSL "$CMDLINE_TOOLS_URL" -o /tmp/cmdline-tools.zip \
 && unzip -q /tmp/cmdline-tools.zip -d "$ANDROID_HOME/cmdline-tools" \
 && mv "$ANDROID_HOME/cmdline-tools/cmdline-tools" "$ANDROID_HOME/cmdline-tools/latest" \
 && rm /tmp/cmdline-tools.zip \
 && yes | "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" --licenses > /dev/null \
 && "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" --install \
      "platform-tools" "platforms;$ANDROID_PLATFORM" "build-tools;$ANDROID_BUILD_TOOLS" \
 && rm -rf "$ANDROID_HOME/.temp" "$ANDROID_HOME/.downloadIntermediates"

# ── stage: Flutter, the pinned upstream release ────────────────────────────
FROM ${BASE} AS flutter
ARG FLUTTER_VERSION
RUN curl -fsSL \
      "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" \
      -o /tmp/flutter.tar.xz \
 && tar -xJf /tmp/flutter.tar.xz -C /opt \
 && rm /tmp/flutter.tar.xz \
 && git config --global --add safe.directory /opt/flutter \
 && /opt/flutter/bin/flutter config --no-analytics > /dev/null \
 && /opt/flutter/bin/flutter --version

# ── the image jobs run in ──────────────────────────────────────────────────
FROM ${BASE}
ENV ANDROID_HOME=/opt/android-sdk \
    ANDROID_SDK_ROOT=/opt/android-sdk \
    JAVA_HOME=/opt/jdk \
    FLUTTER_ROOT=/opt/flutter \
    PUB_CACHE=/root/.pub-cache
COPY --from=jdk /opt/jdk /opt/jdk
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
COPY --from=repo /flutter /tmp/warmup/flutter
RUN set -eu; \
    if [ -n "$proxy_host" ]; then \
      export GRADLE_OPTS="-Dhttp.proxyHost=$proxy_host -Dhttp.proxyPort=$proxy_port -Dhttps.proxyHost=$proxy_host -Dhttps.proxyPort=$proxy_port"; \
    fi; \
    cd /tmp/warmup/flutter/app && flutter build apk --debug; \
    cd / && rm -rf /tmp/warmup

WORKDIR /workspace
