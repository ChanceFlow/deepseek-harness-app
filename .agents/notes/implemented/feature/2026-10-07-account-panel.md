# Agent Note: Account settings surface (Settings → Account)

Status: implemented

## Problem

The reference web client ships an account settings surface
(`reference/deepseek-harness/packages/client/ui-settings-account/`), and the
pinned account controller
(`packages/api/account-controller/src/index.ts`) registers six unary Remote
verbs for it. The phone wired none of them: its Settings index had no account
row, `ChatRepository` had no account read, and `DshRpcEndpoints` declared no
`account/*` constant. A deployment with a stored account credential could not
show who is signed in, the balance, or a waiting granted bonus — facts the host
already serves. Absence was also the harder half:
the account projection is the one surface where a host legitimately reports
nothing (no grant, no account plane), and inventing a zero balance or an empty
name would be worse than saying nothing.

## Decision

**Wire five verbs, not nine.** `account/getState`, `account/getProfile`,
`account/getBalance`, `account/getUnnotifiedBonuses` and
`account/ackBonusNotified` are declared in `rpc_map.dart` beside the
settings/credentials block and implemented in
`HarnessRepositoryImpl`. `account/startSignIn`, `account/cancelSignIn` and
`account/signOut` stay unwired: each needs a browser OAuth redirect with a
loopback `callbackOrigin` (or a Platform revocation call) that a phone surface
cannot complete honestly, and a half-built sign-in button that cannot finish is
worse than none. `account/hasRunningAccountTasks` only gates that flow.
`account/watch` and `account/watchExpiry` are streams and stay literals, as
docs/spec.md §4.6 requires.

**Hand-written decoders mirror the reference fields exactly.** The account DTOs
live at the end of `dsh_wire_types.dart`. Three required keys may hold null in
the reference — `AccountView.attempt`, `AccountProfile.id/name/contact` — so
their absence throws naming the field while a present null stays null; only
`AccountProfile.avatarUrl` defaults. The `status`, sign-in `phase` and
`currency` unions are closed, so an unknown member fails loud rather than
decoding as the nearest variant. `AccountProfileFailed` and
`AccountBalanceFailed` are separate outcomes from a null answer: null is the
host holding no grant, `failed` is the host failing to read Platform.

**The requesting UI's identity travels per call.** `AccountClientIdentity`
(version, locale, timezone offset) is a domain value the page builds at call
time, mirroring the reference's `accountClientMetadata(locale, version)`. The
adapter cannot know the active UI language, and the language selects the
server-authored bonus copy, so caching it in the adapter would send stale
notices. Version comes from `kDshAppVersion`; the offset is already seconds
east of Greenwich.

**The page states absence instead of defaults.** A deployment that composes no
account service answers an RPC failure, and the page names that. A host with no
credential renders the signed-out state and reads no profile, balance or bonus
at all. A failed or absent wallet read prints "could not read" / "reports no
balance" — never `0`. Amounts print the server's own decimal strings after the
currency symbol; the phone has no arbitrary-precision decimal, and re-rounding
would report a figure the account does not hold.

**Acknowledgement follows the reference's display boundary.** An unnotified
bonus renders as one card, and its acknowledgement is queued as a post-frame
callback for the frame that carried it, mirroring the reference's
`shown`-after-presented-frame rule. Closing the card also acknowledges it,
mirroring `dismiss`. A `false` answer or a thrown call leaves the bonus unseen
on the server and shows the retry, never a silent success.

**The row sits at the head of the App section.** The reference registers its
account section at `order: -10`, ahead of General. The phone's index is a fixed
list, and its App section is the first section after Host and the one
immediately before Chat (the phone's `generalIntro` section), so the account
row leads App as the closest neighbour to "before General".

## Alternatives considered

Putting the client identity in `HarnessRepositoryImpl`'s constructor: the UI
language changes at runtime, the adapter has no localizations, and the
reference deliberately samples metadata per call. Building the browser sign-in
flow anyway with a loopback callback listener: a phone can open the authorize
page, but the host completes the exchange behind its own callback origin, so
the phone would ship a button it cannot guarantee. A manual-only
acknowledgement button: simpler, but it drifts from the reference, where a
painted notice is what records display. Placing the row in the Models section
next to Credentials: defensible, since the account grant supplies the API key,
but it breaks the reference's account-first order. Defaulting absent balances
to zero and an absent profile to an empty name: rejected outright — the page's
whole job is to report what the host said.

## Consequences

The endpoint registry gains five constants, so the wire-coverage block's
`declared` and `identical` counts move by five and `missing` drops by five; the
four sign-in/task verbs stay uncovered and visible there. The account surface
is read-only plus one acknowledgement — a later sign-in feature must extend
this seam rather than reuse it, and the decoded `attempt` is currently carried
but not rendered. Every account fact is asserted through the real repository
and decoder paths, including the null-versus-failed-versus-absent split.
