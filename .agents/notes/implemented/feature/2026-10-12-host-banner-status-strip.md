# Agent Note: the sidebar's host banner is a status strip

Status: implemented

## Problem

With more than one host configured, the session drawer put a dense `ListTile`
above each host's tree: connection dot, host label, `host:port` under it, and an
`Active` / `Standby` badge trailing, over the nav-item fill on the active host.
Seven hosts — the crowded case the drawer is built for — read as a wall of
identical bands. The reader could not see which host was theirs, which one had
work in flight, or how much sat under each, while the address, which is needed
once, held the second line of every band forever.

## Decision

One host, one 44dp strip (`_BackendSectionHeader`, `session_panel.dart`):

- the live connection dot, the host's name in `titleMedium` — one level above
  the workspace headers below it (`labelLarge`) — then the facts that answer
  what the host is doing, following the name on the same line:
  `hostRunningCount` in `primary`, `hostWaitingCount` in `warning`. A host with
  nothing in flight says nothing, which is the point;
- the strip reports state, not inventory: the session total stays off it,
  because every workspace header below prints its own count and a host total
  above them repeats the same number in the same column;
- the host the reader is on is marked by a 3px `primary` bar and
  `Semantics(selected: true)` — not by a fill and not by a word; a host they
  could switch to stays quiet. The bar's slot is reserved on every host, so the
  names still line up in one column;
- `host:port` leaves the browsing column: it lives on that host's row in
  Settings, where hosts are managed;
- a hairline under the strip separates a host's header from the tree it owns,
  so the section gap drops from 12dp to 8dp of space plus that rule.

The counts follow the tree's own visibility rule — `sessionVisible`, so the
live archived filter, blank placeholders and subagent children are all
respected. A strip can never claim a row its tree is hiding.

The strip yields instead of striping. When the name and the facts cannot share
the line — a long host label, or the largest platform text steps — the facts
drop under the name and wrap (`host-banner-scale-20`). The decision reuses the
row's existing width measurement (`_intrinsicWidth`) so the branch cannot drift
from the layout it decides.

Two ARB keys carry the new words, in both locales: `hostRunningCount`,
`hostWaitingCount`.

The strip is hand-built chrome rather than a native `ListTile`, which the
sidebar's component note otherwise prefers: the three facts, the conditional
bar and the yield cannot be expressed through `ListTile`'s title/subtitle/
trailing slots, and the ink host is still a Material ancestor with an `InkWell`
row. The section's search seat and the group headers stay native.

## Alternatives considered

- **Host identity card** — a monogram chip, the name, the address and the live
  facts, one card per host. The most legible banner; rejected on height: seven
  hosts spend roughly 450dp of an 844dp phone before the first session row.
- **A tinted band per host** — each host owns a `ColorScheme` container tone,
  drawn full width. The most scannable; rejected on palette: M3 keeps only
  three container roles apart in both brightnesses, so a fourth host repeats a
  tone, and keeping more would mean a declared host palette in `theme.dart`
  with its own decision record.
- **Keep the address on the strip** — rejected: it is the host's own business,
  it is needed once, and it cost the second line of every band.
- **Print the host's session total on the strip** — rejected: every workspace
  header below prints its own count, so a host total above them reads as the
  same number twice in one column (`3 sessions` over `3 sessions`), and it spends
  the width the 2.0x yield exists for.

## Consequences

- The Workspaces tab's aggregate host header (`workspace_screen.dart`) still
  draws the older two-line header, so the two surfaces disagree about how a host
  presents itself. Aligning it is a separate change.
- The strip's counts move with the archived filter, exactly as the workspace
  headers below them do: a host hidden behind the filter is not reported on.
- Inventory lives one level down. A reader who wants "how many sessions does
  this host hold" reads the workspace headers; the strip answers "what is
  moving here" only.
- `Active` / `Standby` stay in the Settings host rows and in the copy that
  names them; only the browsing column stops printing the words.
