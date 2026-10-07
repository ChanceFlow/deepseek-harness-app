# Agent Note: Terminals

Status: implemented

## Problem

The host served a full terminal service — persistent user shells, a screen
stream, input, resize, rename, close — and the phone had none of it: eight unary
methods and two streams were unwired, and nothing rendered a screen. Four facts
from the pin decided the implementation.

- **Every method but `list` takes the Agent lookup.** `TypertLookupMap.agent =
  TypertLookup<Agent, SessionId>` names the wire field `${key}Id`, so the
  argument is `agentId`; `list` and `retain` take a bare `sessionId` so they can
  serve a dormant session. The host refuses an unknown argument outright.
- **A terminal outlives its attachment, and there is no resume offset.** Frames
  number strictly from their snapshot's sequence and a reconnect carries no
  cursor, so the only correct recovery from a gap is a new attachment replaying
  a snapshot.
- **`create` allocates a shell with the host's own system-user permissions**,
  independent of the Agent's sandbox and approval policy; a UI implying
  otherwise would misstate the blast radius.
- **The reference's window management is client-side.** Multi-pane holds,
  drag-resize, pool prewarming, and ZMODEM live in `ui-sidebar-terminal` and the
  browser, with no wire surface behind them.

## Decision

Wire all ten endpoints and render the screen in `app`.

- `follow` and `retain` stay **literal** endpoint strings, like the other mux
  streams: `verify_wire_pin.py` compares unary Remote registrations, and a
  constant would read as a client-only name.
- The Agent lookup is translated in one place: an `_agentScopedEndpoints` set
  in `_prepareArgs` renames `sessionId` to `agentId` and drops the original, so
  one rule covers all seven methods, and the test asserts the exact wire args
  through a raw-payload accessor added for that purpose.
- Frames decode into a closed union (`snapshot` / `output` / `state`) applied by
  `TerminalAttachment`, a repository-free state machine owning the rules the
  wire depends on: a snapshot clears the screen and anchors the sequence,
  `output` continues that anchor exactly, and a jump forces a re-attach. Those
  rules live in a testable object, so the contract is assertable without a
  repository double.
- One attachment per selected terminal; a **window hold** (`retain`) keeps the
  tab alive while the page is open, a transport generation change re-attaches
  rather than pretending the old stream still delivers frames, and the page
  renders through a narrow `TerminalSurface` seam — the presentation split used
  for jobs, teams, plugins, and schedules.
- Input is serialized through one in-flight queue; a write larger than
  `environment.maxInputBytes` is refused client-side rather than sent to fail,
  and `not-controller` reads as a read-only transition, not a transport error.
  Resize is debounced (150 ms), clamped to the host's maxima, and skipped when
  it equals the known dimensions; without a cell grid the size comes from the
  layout box and the monospace advance width.
- Rendering is a **dependency-free text screen**: a line being written plus a
  cursor column, so a carriage return rewrites its line rather than duplicating
  it, a line feed commits, a backspace steps over a character, and an
  erase-display clears. Attributes, colors, and cursor addressing are consumed
  and dropped, and the UI says so in one line. **`xterm` was spiked first and
  removed.** It compiles clean here, but the analyze gate runs `flutter analyze
  --no-pub` against the CI image's pub cache, which lives in the container
  filesystem: a new dependency exists for the `pub get` that fetched it and is
  gone from the `--no-pub` run after it, so this repository's gates could not
  verify it. The sanctioned route — a republished image plus a `ci.image_tag`
  bump — cannot be published from here, so the documented fallback was taken
  instead of shipping unverified; losing color is the cost.
  The sandbox fact is stated where a terminal starts, and a reconnect says
  output may have been missed rather than implying continuity.

## Alternatives considered

Vendor `xterm` and `zmodem` as path dependencies: rejected — copying a third
party's VT emulator into `app` to keep one gate runnable is worse than a stated
rendering limit.
Patch the screen on reconnect instead of clearing it: rejected; with no resume
offset the old text is unverifiable, and a silent splice only looks cleaner.
Assume the Agent's sandbox applies to a shell: rejected as a safety claim the
wire does not support.
Mirror the reference's window tree, drag-resize, and pool prewarming and treat
`not-controller` as an error: rejected as client-only behavior and as an
expected read-only state respectively.

## Consequences

`declared 80 / upstream 125 / identical 78 / missing 47` — the coverage target
for this sync. No dependency was added, so the toolchain pin is untouched, and
the session menu opens a working terminal. What does not exist is documented as
absent rather than approximated — no color or cursor addressing, no resume
offset, no sandbox extension, no window holds, no ZMODEM — each in
docs/spec.md §10.
