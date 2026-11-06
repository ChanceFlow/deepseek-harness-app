# AGENTS.md — flutter/app (WebView shell)

Supplements the [root conventions](../../AGENTS.md#conventions) and the
[workspace file](../AGENTS.md). This package draws the shell around the host's
own dsh web client; it does not re-implement that client.

## The host's page is the UI

- **The page is the dsh web client** at each host's `BackendConfig.baseUri`.
  One `HostWebView` per enabled host, stacked in an `IndexedStack`, so
  switching is a display change, not a reload. `HostPoolPolicy.maxLive`
  defaults to 3: the least-recently-used page beyond it is released and
  reloads from its URL when next selected, and the active host is never
  evicted.
- **Nothing is injected.** No JavaScript bridge, no injected script, no
  stylesheet. The page keeps its navigation state; the adapter reads the
  host's API on a socket of its own.
- **The shell's chrome is the only surface we draw.** A 44 px host bar
  (label, reachability dot, switcher) and a 280 px drawer (hosts, add,
  select). There is no bottom navigation, no per-screen app bar, and no
  screen tree of our own.
- **No Material 3 port.** The page owns its type, color, spacing, motion and
  layout. A framework component is never used to reproduce host chrome, and
  `ColorScheme` exists only so our own bar and drawer read the pin's aliases.
- **Chrome takes the pin's tokens.** `theme/theme.dart` holds the alias
  table, the named radius scale, `DshType` and `DshMotion`; a call site reads
  a role, never a hex or a literal. `verify_theme_native` rejects a raw color,
  `Colors.<name>`, `ThemeExtension`, or a numeric radius under `lib/` outside
  it. Why the chrome is thin, and the review questions a new chrome element
  answers: [docs/design-standard.md](../../docs/design-standard.md).
- **Notifications are UI-free.** The adapter keeps one event socket per
  enabled host; `ChatRepository.observeSessions()` folds the roster into
  `AppNotificationCenter`, which posts an Android notification, and
  `ShellLifecycle` renders the foreground channel as a tappable toast. The
  pipeline runs with only the shell mounted, reads nothing from the host's
  page, and a tap opens the app on the current host — there is no session
  deep link without a bridge.
- **`SafeArea` is the one page wrapper.** The host ships no `viewport-fit`
  handling; anything else around the page is a defect.

## Structure and state

- `lib/shell/`: `ShellRoot` (bar, drawer, pool reconciliation), `HostWebView`,
  `HostPool` (the platform-free live-page policy), `ShellLifecycle` (keep-alive
  watch set, reconnect/resume sync, permission ask, foreground toast).
- `lib/notifications/`: the center, the working-sessions fold, notification
  copy and the system notifier.
- `lib/backends/`: the device-local host registry.
- `lib/theme/`: every token's home.
- **`lib/di/` is the only code that sees adapter or network types** (root
  import-boundary rule, enforced by `scripts/check_dart_imports.py`).
- **Every user-visible shell string is an ARB key** in `lib/l10n/app_en.arb`
  and `app_zh.arb`, both edited in the same change (`verify_i18n_arb` compares
  key sets and placeholder names); the generated `app_localizations*.dart` are
  committed
  ([the i18n note](../../.agents/notes/implemented/feature/2026-08-20-bilingual-i18n-zh-en.md)).
- **Telemetry stays optional at the call site.**
  `DebugTelemetry.instance?.event(...)` — the shell behaves identically when
  the facade is null ([packages/dev](../packages/dev/AGENTS.md)).

## Evidence

Widget tests pump the real `ShellRoot` with a stand-in host view
(`hostViewBuilder`) and assert what a user would see: widget type, text, the
color read back from the theme's alias
([docs/testing.md](../../docs/testing.md)). A color assertion pumps the same
surface under both `DshTheme.light()` and `DshTheme.dark()`, then a pump past
the theme lerp. Notification tests drive the real center over the fake
repository's roster stream. There is no local screen renderer: the page is
the host's, and the chrome is proved as a widget tree.
