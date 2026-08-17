# Reference to deepseek-harness

This directory contains the upstream dsh repository as a **git submodule**, not a filesystem
symlink. The submodule pins a specific dsh commit, so the Android contract source of truth is
reproducible across clones.

- Render/UI decision reference: `reference/deepseek-harness/packages/client/runtime/`
- Wire contract source of truth: `reference/deepseek-harness/packages/host/apiproxy/src/api/`
- Connection lifecycle: `reference/deepseek-harness/packages/client/connection/src/client/connection.ts`
- Web server routes: `reference/deepseek-harness/packages/client/connection/src/api-path.ts`

Upstream repository hyperlink:

<http://127.0.0.1:3000/ChanceFlow/deepseek-harness>

The hyperlink above points to the same repository referenced by `.gitmodules`. The submodule is
the executable reference used by git; the hyperlink is the human-clickable reference.
