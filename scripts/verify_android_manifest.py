#!/usr/bin/env python3
"""Gate: the Android manifest declares what WebView audio capture needs.

A missing `MODIFY_AUDIO_SETTINGS` declaration breaks nothing the build can
see: the manifest is valid, the app installs, and the page's `getUserMedia`
rejects with `NotReadableError "Could not start audio source"` only on a
phone, where Chromium's `AudioManagerAndroid` needs the permission to select
the communication audio device. `RECORD_AUDIO` is the other half of that
selection. A microphone `uses-feature` left required silently narrows installs
to devices that have a microphone, so a host that only renders a page cannot
install the app.

The gate parses the app manifest
(`flutter/app/android/app/src/main/AndroidManifest.xml`) with ElementTree and
requires:
  - `android.permission.RECORD_AUDIO`
  - `android.permission.MODIFY_AUDIO_SETTINGS`
  - `android:required="false"` on `uses-feature android.hardware.microphone`

Exit code 0 = every declaration is present, 1 = a declaration is missing,
malformed, or the manifest cannot be read.
"""

from __future__ import annotations

import sys
import xml.etree.ElementTree as ET
from pathlib import Path

REPO: Path = Path(__file__).resolve().parent.parent
MANIFEST: Path = REPO / "flutter" / "app" / "android" / "app" / "src" / "main" / "AndroidManifest.xml"
ANDROID_NS: str = "{http://schemas.android.com/apk/res/android}"
MICROPHONE_FEATURE: str = "android.hardware.microphone"

# The silent failure each permission prevents, keyed by the declaration.
PERMISSION_REASONS: dict[str, str] = {
    "android.permission.RECORD_AUDIO": (
        "the page's capture ask cannot be granted without it"
    ),
    "android.permission.MODIFY_AUDIO_SETTINGS": (
        "Chromium's AudioManagerAndroid needs it to select the communication "
        "device; without it capture returns NotReadableError"
    ),
}


def manifest_label() -> str:
    """The manifest path relative to the repository, for gate output."""
    try:
        return MANIFEST.relative_to(REPO).as_posix()
    except ValueError:
        return str(MANIFEST)


def check() -> int:
    try:
        manifest = ET.parse(MANIFEST).getroot()
    except (OSError, ET.ParseError) as error:
        print(f"ANDROID-MANIFEST GATE: cannot read {manifest_label()}: {error}")
        return 1

    violations: list[str] = []
    declared = {
        element.get(f"{ANDROID_NS}name")
        for element in manifest.findall("uses-permission")
    }
    for permission, reason in PERMISSION_REASONS.items():
        if permission not in declared:
            violations.append(
                f"missing <uses-permission android:name=\"{permission}\"/> — "
                f"{reason}"
            )

    features = {
        element.get(f"{ANDROID_NS}name"): element.get(f"{ANDROID_NS}required")
        for element in manifest.findall("uses-feature")
    }
    if MICROPHONE_FEATURE not in features:
        violations.append(
            f"missing <uses-feature android:name=\"{MICROPHONE_FEATURE}\" "
            "android:required=\"false\"/> — a device without a microphone "
            "could not install"
        )
    elif features[MICROPHONE_FEATURE] != "false":
        found = (
            "no android:required attribute"
            if features[MICROPHONE_FEATURE] is None
            else f"android:required=\"{features[MICROPHONE_FEATURE]}\""
        )
        violations.append(
            f"<uses-feature android:name=\"{MICROPHONE_FEATURE}\"/> has "
            f"{found}; it must be android:required=\"false\" so a device "
            "without a microphone can install"
        )

    if violations:
        print("ANDROID-MANIFEST GATE: violations found:")
        for violation in violations:
            print(f"  {violation}")
        return 1
    print("ANDROID-MANIFEST GATE: CLEAN")
    return 0


if __name__ == "__main__":
    sys.exit(check())
