# Agent Note: Command image envelope (composer images riding host commands)

Status: implemented

## Problem

The live host's command registry advertises image acceptance on `plan`
and `goal` (`input.images: true` in `commands/list`), and
`commands/execute` carries a base64 `images` arg with host-side
admission (`dsh-attachment` `admitEncodedImages`). The app always sent
`images: []` and cleared the composer's pending images on success — a
user attaching a mockup and sending `/goal <objective>` silently lost
the images, and a submission carrying images for a non-accepting
command executed the command and dropped the images instead of
refusing. The pinned reference submodule predates this surface (its
`CommandInputDescriptor` has only `hint`); the running host's installed
packages (`~/.npm-global/.../dsh-*`) are the current source of truth.

## Decision

The web `matchEnter` envelope policy (live `dsh-client-ui-commands`):
an enter submission carrying images resolves only through a command
declaring image acceptance — popup, non-accepting claim, and bare
detached routes refuse before anything executes ("the draft and images
stay in place; nothing executes and nothing is dropped"), and the
refused notice is `/{command} does not accept image attachments; remove
them first`. A claim that accepts submits with the images
(`execute(sessionId, line, images)`); a handler error on a submission
that carried images reports an error outcome so the composer keeps the
submission for correction.

The Flutter port mirrors this:

- Roster (`command_roster.dart`): `HostCommand` gains `acceptsImages`
  (plan and goal `true`, mirrored from the live registry); the
  `matchEnter` table moves into the shared `hostCommandLineFor`, and
  `hostCommandImageRefusal` names the command a submission with images
  must refuse.
- Composer (`chat_screen.dart` `_send`): before the draft is consumed,
  a submission with pending images refuses a dispatched command that
  does not accept them — `CommandImageRefusal` (localized message,
  `l10n.commandImagesUnsupported`) surfaces in the shared error strip;
  the draft and image chips stay in place.
- Controller (`chat_controller.dart`): the dispatch passes the pending
  images to the repository; success consumes them, an error result
  keeps them (the web's keep-for-correction), and a dispatch failure
  keeps them (the
  [dispatch-failure contract](../bug-fix/2026-08-20-command-dispatch-failure-prompt-fallback.md)).
- Adapter (`harness_repository_impl.dart`): `executeCommand` encodes
  each image as `{mediaType, data, name?}` in submission order — the
  shape the host's typert schema validates (mediaType literals
  png/jpeg/webp/gif, canonical base64) and `admitEncodedImages`
  decodes; the app's admission limits use the same four media types.

Empirical verification against the live host (throwaway session):
`/goal edit <objective>` with one PNG returned `Goal updated` (image
admitted as the objective's followup message); `/feedback nice` with
one PNG settled as ``/feedback does not accept image attachments``.

## Alternatives considered

- **Relying on the host-side admission alone** (dispatch everything,
  let the host settle the error): rejected — the web refuses in the
  composer precisely so nothing executes and the session log stays
  clean; a host-refused batch still appends `command/run`+`command/done`
  error lifecycle events.
- **Fetching `commands/list` live instead of extending the static
  roster**: deferred — same trade-off as before; the static flags
  mirror the registry verbatim and the unmatched-null fallback keeps
  preset differences web-faithful.
- **Surfacing the refusal as a SnackBar**: rejected — the shared error
  strip (`errorMessage`) is the app's established composer-notice
  surface; a second notice channel would split where users look.

## Consequences

Attachments no longer vanish behind `/plan` and `/goal` submissions;
non-accepting commands with images refuse up front with the draft and
images intact. Host-side grammar still owns the finer rejections
(`/plan off` with images, images on `/goal pause`), which arrive as
error results with the images kept for correction. The success text
(`Goal created`, `Plan mode on`) still surfaces only through the state
projections — rendering the command lifecycle as timeline cards
remains the open gap toward web parity.

## Testing

`chat_controller_test.dart`: the dispatch carries the composer images
and success consumes them; an error result keeps the images that rode
the dispatch. `chat_screen_test.dart`: a submission with images refuses
`/compact` (no `SendPrompt`, refusal action, draft and chip retained)
and still sends `/goal <objective>`. `harness_repository_integration_test.dart`:
the images encode as `{mediaType, data, name?}` in submission order.
