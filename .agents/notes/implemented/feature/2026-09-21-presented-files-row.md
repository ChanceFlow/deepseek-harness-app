# Agent Note: Delivered files (`交付文件`) — the `present` tool's row and cards

Status: implemented

## Problem

The reference's deliverables surface is **two** file rows under a closing
reply, and this client had one. `ProducedFiles` lists what the turn's
mutation calls changed (`本轮文件改动`, the reference's `produced.label`);
the `PresentRow` plus the delivered-file cards list what the model explicitly
handed over through the `present` tool (`交付文件`, `row.title`, driven by the
`deliverables/presented` event —
`reference/.../packages/fs/tool-present/src/index.ts`,
`ui-deliverables/src/client/{Deliverables,PresentRow,PresentedFileCard}.tsx`).

This client decoded neither the event nor the tool: `deliverables/presented`
fell into the reducer's unrecognised-type arm (a debug diagnostic, no item),
`present` classified as the generic `others` variant, and the declared files
were invisible. A turn whose whole point was handing over an artifact showed a
`Tool call · present · {"files":[{"path":"out/…` row and nothing else — which
is also why the two labels looked interchangeable: only one row existed.

## Decision

**The declaration rides the `present` call.** `deliverables/presented` names
its `callId`, so the reducer folds the event's `files` onto that call's own
row (`TimelineToolCall.presentedFiles`) instead of publishing a second item
kind. A declaration whose call lies outside the folded window has no row to
ride and publishes nothing; a file entry without a non-empty `path` is skipped
(the reference's `isPresentedFile` posture). The fold is idempotent against
either journal order — the host appends the event from its own `tools/result`
hook, so the two events race, and both `_appendToolResult` and `_withChildren`
carry an already-folded declaration forward.

**One turn walk, two facts.** `turn_files.dart`'s `TurnFiles` replaces the
produced-files-only walk: per turn it collects mutation paths and declared
files, snapshots both at the closing assistant message, and dedupes paths
(first-seen order; a declared path keeps its **last** declaration, the
reference's `files.set(path, file)`). `produced_files.dart` keeps the
per-call mutation extraction and projects the produced half for its existing
readers.

**The phone renders both reference surfaces.** The `present` call gets its own
tool-row variant: title `交付文件` and the collapsed summary the reference's
`PresentRow` builds — `files[].path` comma-joined, with the raw arguments
still visible while the payload is partial. Under the produced-files chips,
`PresentedFilesRow` renders one card per declared file: a file-type seat, the
basename, the model's description (uppercased extension when it wrote none,
the bare word when the name carries no extension), and an open seat. More than
four files collapse behind a `全部 N 个文件` / `收起` toggle
(`COLLAPSED_PRESENTED_COUNT`). A card and its open seat both open the in-app
preview sheet.

Two reference affordances are deliberately absent. There is no host-desktop
action ("open in default app" / "show in file manager"): that rides
`/api/present.open`, which asks the *host's* desktop to open a path — the same
promise the produced-file chips already decline for a directly-connected
phone. And with no menu the reference's host-status line ("this Host has no
desktop") has nothing to explain, so it is absent too. A label above the cards
is the one addition: the reference's wide card row needs no header, a phone
column does.

## Alternatives considered

- **A new `TimelinePresentedFiles` item kind.** Rejected: the event already
  names the call it belongs to, so a second item would duplicate the pairing
  the reducer can do exactly, and would need arms in every exhaustive switch
  over `TimelineItem`.
- **Publish the delivered row per `deliverables/presented` event.** Rejected:
  the reference's row is per *turn* (`presentedForClosing`), and a turn can
  declare files in several calls; a per-event row would repeat the header.
- **Implement `/api/present.open` and the file-manager menu.** Rejected for
  this pass: it opens the file on the host's desktop through a route the phone
  may not reach, and the preview sheet is the affordance the client can always
  honor. The reference's states around that menu (`opening`/`revealed`/
  `revealError`, host availability) exist only to explain it.
- **Keep the produced-files walk and add a second one.** Rejected: both facts
  attach to the same closing message, so two walks would duplicate the
  turn-grouping and closing-message snapshot rules that must not drift.

## Consequences

- New ARB keys: `presentedFilesLabel`, `presentedFilesOpen`,
  `presentedFilesOpenName`, `presentedFilesFile`, `presentedFilesAll`,
  `presentedFilesCollapse`.
- `docs/spec.md` §6 gains the `deliverables/presented` fold row; the README
  feature list names the delivered-files row.
- New design shots `presented-files` and `presented-files-call`.
- The adapter and the fold are verified by unit tests against the pinned
  contract; no session on the development host has recorded a
  `deliverables/presented` event yet, so there is no live-host sample to
  replay. The `present` tool is mounted by the `standard`, `ptc`, and
  `cordis` agent presets.
