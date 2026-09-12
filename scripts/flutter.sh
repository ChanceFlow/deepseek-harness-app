#!/usr/bin/env bash
# Run the Flutter tool from the pub workspace root, inside the CI image.
#
#   scripts/flutter.sh test app/test/ui/chat/chat_screen_test.dart
#   scripts/flutter.sh analyze app/lib/ui/chat
#   scripts/flutter.sh pub get
#
# `flutter` resolves this repository's pub workspace from `flutter/`, not from
# the repository root, so this is the shortcut for the common case. Everything
# about the image — the toolchain, the caches, the container allowances — is
# owned by scripts/container.sh.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO/flutter"
exec "$REPO/scripts/container.sh" flutter "$@"
