#!/usr/bin/env bash
# dart format wrapper for lefthook jobs, with the pinned Flutter's dart on
# PATH fallback (mirrors verify_all.py's ensure_flutter_on_path).
#
# Modes:
#   --fix <files...>   format the given (staged) files in place
#   --check            verify the whole workspace is format-clean
set -euo pipefail

if ! command -v dart >/dev/null 2>&1 \
    && [ -x "$HOME/tools/flutter-3.47.1/bin/dart" ]; then
  export PATH="$HOME/tools/flutter-3.47.1/bin:$PATH"
fi

SOURCE_DIRS=(app/lib app/test packages/domain/lib packages/domain/test \
  packages/network/lib packages/network/test packages/harness_adapter/lib \
  packages/harness_adapter/test packages/dev/lib packages/dev/test \
  packages/asr/lib packages/asr/test)

if [ "${1:-}" = "--fix" ]; then
  shift
  exec dart format "$@"
fi

cd "$(git rev-parse --show-toplevel)/flutter"
exec dart format --output=none --set-exit-if-changed "${SOURCE_DIRS[@]}"