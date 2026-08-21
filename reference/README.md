# Reference to deepseek-harness

This directory contains the upstream dsh repository as a **git submodule**, not a filesystem
symlink. The submodule pins a specific official dsh commit, so the Android contract source of
truth is reproducible across clones. dsh is under active development with breaking changes —
the pin is the wire contract; do not assume compatibility with a different dsh version.

- Pinned commit: `b150a551b8d465e31e418e1b2eaf5e79bbb7d28e` (official `dsh-v0.1.1-rc.2`).
- Render/UI decision reference: `reference/deepseek-harness/packages/client/runtime/`
- Wire contract source of truth: `reference/deepseek-harness/packages/host/apiproxy/src/api/`
- Connection lifecycle: `reference/deepseek-harness/packages/client/connection/src/client/connection.ts`
- Web server routes: `reference/deepseek-harness/packages/client/connection/src/api-path.ts`

Upstream repository:

<https://github.com/deepseek-ai/deepseek-harness>

The submodule is the executable reference used by git; the hyperlink above is the
human-clickable reference. To re-pin, update the gitlink to another official commit and
re-run the wire-parity tests in `flutter/`.