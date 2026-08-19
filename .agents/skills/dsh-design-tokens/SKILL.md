---
name: dsh-design-tokens
description: Regenerate or extend the DeepSuite design tokens (flutter/app/lib/ui/theme/deepsuite_tokens.dart) generated from the dsh web CSS in the reference submodule. Use when theme colors, spacing, or motion look off versus the dsh web client, when adding a new token for UI work, or when gen_deepsuite_tokens.py --check reports drift.
---

# Design token workflow

`deepsuite_tokens.dart` is machine-generated — hand edits are drift and fail
the gate. The generator owns the file; the CSS owns the values.

## Sources of truth

- CSS: `reference/deepseek-harness/packages/client/ui-theme/src/styles/design-platform.css`
  and `base.css` (see [reference/README.md](../../../../reference/README.md))
- Generator: [scripts/gen_deepsuite_tokens.py](../../../../scripts/gen_deepsuite_tokens.py)
- Output: `flutter/app/lib/ui/theme/deepsuite_tokens.dart`

## Regenerate

```sh
python3 scripts/gen_deepsuite_tokens.py            # rewrite the Dart file
python3 scripts/gen_deepsuite_tokens.py --check    # exit 1 on drift (gate)
```

## Add a token the UI needs

1. Find the value in the reference CSS (light block, and
   `body[data-ds-dark-theme]` for dark). If the CSS lacks it, that is a
   signal to reconcile with web first — do not invent a value.
2. Extend the generator's extraction (never the Dart file by hand).
3. Regenerate; the sampling/invariant test in
   `flutter/app/test/ui/theme/deepsuite_tokens_test.dart` gains the new
   assertion (representative value from the CSS, both themes).
4. Consume via `DeepSuiteColors`/theme in `app` — no raw hex in widgets.

## Prove it

```sh
python3 scripts/gen_deepsuite_tokens.py --check
cd flutter && flutter test app/test/ui/theme/
```

Both run in `python3 scripts/verify_all.py`. A drift failure means someone
edited the Dart file or the submodule CSS moved — regenerate or re-pin,
never hand-merge.
