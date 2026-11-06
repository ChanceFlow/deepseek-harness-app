# Agent Note: The client is a WebView shell over the host's own UI

Status: implemented

## Problem

The native client re-implemented a UI the host already ships: at the pivot it
carried 147 files and 63,775 lines under `flutter/app/lib/ui`, 1,433 of the
suite's roughly 1,703 cases, and every upstream design change landed as a
porting pass on our side. The two things this client has that the host's page
does not are the notification pipeline and the multi-host registry, and
neither depends on a UI: `AppNotificationCenter` consumes the adapter's
`ChatRepository.observeSessions()` on its own socket, and the registry lives
in `lib/backends`. The pinned web client is also the surface a human asked to
look at.

## Decision

**One WebView per enabled host, one chrome, no injected script.**

- **Hosts.** Each enabled `BackendConfig` renders `HostWebView`, a
  `webview_flutter` controller loading `baseUri` with nothing injected. Hosts
  are stacked in an `IndexedStack`, so switching is a display change, not a
  reload. `HostPoolPolicy.maxLive` defaults to 3: the least-recently-used live
  host beyond it is released and reloads when next selected, and the active
  host is protected from eviction. Editing a host's URL bumps a revision so
  its page reloads in place. Origins isolate cookies and storage, and the
  page's own `localStorage` restores each host's last session.
- **Chrome.** A 44 px bar carries the active host's label, its reachability
  dot and the switcher; a 280 px drawer lists hosts with add and select.
  There is no bottom navigation, no per-screen app bar, and no design-system
  port. `SafeArea` wraps the page because the host ships no `viewport-fit`
  handling; nothing else wraps it.
- **Notifications.** Unchanged: the adapter keeps one event socket per
  enabled host, the roster folds through `AppNotificationCenter` to an Android
  notification, `ShellLifecycle` renders the foreground channel as a toast,
  and the keep-alive foreground service holds the sockets open while work is
  in flight. The shell adds no JavaScript bridge — the page keeps its own
  navigation state, and a notification tap opens the app on the current host.
- **What moved and what was deleted.** The theme seam moved from
  `flutter/app/lib/ui/theme/theme.dart` to `flutter/app/lib/theme/theme.dart`
  so deleting the screens would not take the shell's palette; the keep-alive,
  reconnect/resume, permission and toast wiring moved from the native root to
  `ShellLifecycle`. The cut-over deleted `flutter/app/lib/ui/**`,
  `flutter/app/test/ui/**`, `flutter/app/test/design/**`,
  `scripts/render_design.py`, the dependencies that only served those
  screens, and the M3 widget rules. Voice input and its ASR models, the
  in-app error-log viewer, gesture shortcuts, and the aggregated cross-host
  workspace view went with them; the host's page owns those surfaces now.
  `docs/spec.md` no longer carries a "No WebView UI" non-goal.

## Alternatives considered

- **Keep porting the native UI.** Rejected: it is the cost the shell exists
  to delete, and the port never stops while the pin moves.
- **Hybrid (native chrome plus a native chat).** Rejected: two surfaces that
  must drift together, which is the reimplementation problem with extra
  state.
- **A JavaScript bridge into the client store** (`__ModuleLoader__` capture,
  `uiSession`/`uiWorkspace` handles). Rejected for now: it wraps a private
  façade, fails silently on upstream refactors, and buys only "which session
  is on screen" plus deep links. The notification pipeline needs neither to
  be correct; it only needs the API.
- **TWA/Bubblewrap.** Rejected: one origin and a Play-hosted provider, so it
  cannot hold a device-local multi-host registry or our notification copy.

## Consequences

- An upstream design change lands by bumping the pin, not by porting a screen;
  the shell is the client's only drawn UI.
- The pool is the memory lever: a live page costs roughly 100–200 MB, and a
  fourth host reloads.
- Cookies ignore ports, so two hosts on one domain at different ports share
  storage; distinct hosts or subdomains are safe.
- The host page has no safe-area handling, so the shell's `SafeArea` is the
  phone's only protection at the screen edge.
- `verify_theme_native` now scans a tree whose only styled surface is the
  chrome, and its exempt token home is `lib/theme/theme.dart`; shell widget
  tests pump `ShellRoot` with a stand-in host view, and no local screen
  renderer exists.
