# Phase 4 network bridges — developer acceptance

The reproducible sequence for accepting Phase 4: Inbox+ installs a real, checksum-pinned mautrix
bridge, registers it with the local homeserver, supervises it, and drives its genuine login flow
through native SwiftUI.

## What Phase 4 changed

Phase 3 built the bridge *contract* — the `bridgev2` protocol models and a scripted dummy bridge —
but nothing external ever ran. Phase 4 makes it real:

- `BridgeCatalog` pins five networks by version and SHA-256.
- `BridgeInstaller` fetches and verifies a binary before it is ever made executable.
- `LibolmProvisioner` supplies the library the prebuilt binaries link against.
- `BridgeConfiguration` and `BridgeRuntime` configure, register, and supervise each bridge.
- `BridgeLoginController` plus `LoginStepView` render whatever step the bridge asks for.

## Prerequisites

Same as Phase 2 and 3 — macOS 15+ on Apple silicon, Swift 6.2, Homebrew CPython 3.12 — plus:

- **`cmake`** (`brew install cmake`), needed once per profile to build libolm. See
  "Why libolm is built from source" below.
- **Network access** to `github.com` and `gitlab.matrix.org` for the pinned artifacts.

## 1. Automated checks

```sh
swift test && swift build -c release && git diff --check
```

Expect 412 tests passing. The live-bridge tests are opt-in and share the Phase 2/3 switch:

```sh
INBOXPLUS_RUNTIME_PYTHON=/opt/homebrew/opt/python@3.12/bin/python3.12 swift test
```

That additionally runs, against a real Synapse and the real `mautrix-instagram` binary:

| Test | Proves |
| --- | --- |
| `realInstagramBridgeInstallsConfiguresRegistersAndServesItsLoginFlow` | fetch, verify, configure, register, supervise, and read the genuine login step |
| `aBridgeWithoutItsProvisioningSecretIsReportedDegradedRatherThanHealthy` | health means *authenticated*, not merely listening |

Neither touches a real Instagram account.

## 2. Install and register a bridge

```sh
swift run InboxPlusRuntimeCLI bridge --profile demo --action install --network instagram
swift run InboxPlusRuntimeCLI bridge --profile demo --action prepare --network instagram
```

`install` downloads the pinned binary, verifies its SHA-256 **before** marking it executable, and
builds libolm beside it. `prepare` writes `config.yaml`, runs the bridge's own
`--generate-registration`, and copies the registration where Synapse reads it.

`prepare` must run while the profile is stopped: Synapse reads `app_service_config_files` once, at
startup, so a registration written afterwards is invisible until a restart.

Check what a profile has:

```sh
swift run InboxPlusRuntimeCLI bridge --profile demo --action list
```

## 3. Confirm the bridge serves its real login flow

```sh
swift run InboxPlusRuntimeCLI bridge --profile demo --action flows --network instagram
```

Expect:

```
bridge instagram phase=healthy port=<n> pid=<n> restarts=0 health=healthy
  flow instagram: instagram.com — Login using cookies from instagram.com
  flows match the pinned expectation
```

`phase=healthy` here means the bridge answered an **authenticated** provisioning request. A bridge
whose socket is open but whose shared secret no longer matches is useless to Inbox+, so it is
reported degraded rather than shown a green light.

## 4. Connect the account in the app

```sh
swift run InboxPlusRuntimeCLI start --profile demo          # shell 1, starts Synapse *and* bridges
INBOXPLUS_PROFILE=demo swift run -c release InboxPlus           # shell 2
```

Shell 1 now prints a line per bridge as well as the homeserver.

In the app: **Settings → Add → Instagram**. A window opens on Instagram's own sign-in page. Sign in
there. Inbox+ captures exactly the five cookies the bridge declared — `sessionid`, `csrftoken`,
`ds_user_id`, `mid`, `ig_did` — and nothing else, then Continue submits them.

**Your password is typed into Instagram's real page inside a webview. Inbox+ never sees it, never
stores it, and never transmits it.** The webview uses a non-persistent data store, so nothing is
left behind in the app afterwards.

## 5. Account management

Settings lists each account with its connection state and last activity. The `…` menu offers:

- **Disconnect** — stops the connection, keeps every message. A connection problem is never a
  reason to delete someone's history.
- **Remove account…** — a separate, confirmed, irreversible erase of the account, its
  conversations, its messages, and its identities. Other accounts are untouched.

The one-account-per-platform rule is enforced twice: the picker disables an already-connected
network, and `InboxPlusAppModel.addAccount` refuses regardless, because a view is not a rule.

## What Phase 4 guarantees

**Nothing unverified is ever executed.** Every bridge is pinned to an exact version and a SHA-256
taken verbatim from upstream's `sha256sums.txt`. Bytes are hashed and compared before anything is
marked executable; a mismatch never reaches the install path. An already-installed binary is
re-hashed rather than trusted by path, so a binary swapped after installation is caught and
replaced.

**Each bridge is isolated.** Its own directory, database, loopback port, provisioning secret,
appservice registration, and supervisor. One bridge crashing, failing to start, or being
reinstalled cannot disturb another or the homeserver — a failure is reported and stepped over.

**The bridge is the authority on its own protocol.** Registrations are generated by the bridge's own
`--generate-registration`, because a bridge knows which users and aliases it claims. Login screens
are chosen by the step type the bridge returns, so a network Inbox+ has never heard of logs in
correctly as long as its bridge speaks `bridgev2`. Where Inbox+ records an expectation — Instagram's
flow list — it was read from a running bridge, and drift against the pin is reported rather than
silently accepted.

**Secrets stay out of reach.** Configs and registrations are `0600` in `0700` directories. The
provisioning secret is registered as a sensitive value with the process supervisor, so it is
redacted from captured logs. Secret input fields are marked in the protocol and rendered as
`SecureField`, so they are never drawn on screen.

**Nothing incomplete leaves the machine.** Every step validates against its own declared fields —
in the view on each keystroke, and again in the controller immediately before submitting.

## How a bridged conversation reaches the inbox

Three steps that are each invisible when they fail, and all three were missing when the Instagram
bridge was first connected:

1. **The invite is accepted.** A bridge creates a portal room and *invites* the account rather than
   joining it. An unaccepted invite is a conversation that exists on the homeserver and nowhere in
   the app. `BridgeInvitePolicy` accepts only invites from users inside a prepared bridge's own
   namespace on the local server, so an ordinary local account cannot put a room in the inbox.
2. **An identity precedes the conversation.** `InboxProjector` drops any conversation whose identity
   it does not know, so the gateway must emit `identityUpserted` before `conversationUpserted` — and
   must synthesise an identity for a room that has not delivered a message yet.
3. **History is paginated in.** A live timeline begins where this account's view of the room begins.
   In a freshly joined portal that is the join event, leaving everything the bridge backfilled
   behind it. Attaching a timeline paginates backwards once.

## Why libolm is built from source

Every prebuilt mautrix binary links `@rpath/libolm.3.dylib`. libolm reached end of life, Homebrew no
longer carries it, and **libolm 3.2.16 does not compile with a current clang**: `List::operator=`
declares its cursor `T * const` and then increments it. That function has therefore never compiled
anywhere, so it has never run — and it is wrong a second way, dereferencing the list rather than the
cursor. libolm is archived, so upstream will not fix it; `master` carries the same defect.

`LibolmProvisioner` therefore fetches the pinned 3.2.16 tarball, verifies its SHA-256, applies a
patch pinned as an exact before/after pair, and builds with cmake. If the source ever stops matching
verbatim the build fails loudly rather than applying a fuzzy edit to a crypto library. The result is
installed beside the bridge binary, where dyld resolves `@rpath` first — no `DYLD_*` variables,
which macOS strips from hardened processes anyway.

Building from a checksum-verified tarball keeps the provenance chain intact rather than committing
an opaque binary to the repository.

## Protocol facts read from a running bridge

Phase 3's model was built from the mautrix source and was close but not exact. Read from
`mautrix-instagram v0.2607.0`:

- Every provisioning request must carry `?user_id=<mxid>`; without it the request is attributed to
  nobody and refused with `M_FORBIDDEN`.
- `Authorization: Bearer <shared_secret>`.
- Submitting a step is `POST …/login/step/{login_id}/{step_id}/{step_type}` — three segments. The
  `login_id` arrives in the first response of a flow.
- Instagram's flow is named `instagram`, not `cookies`; `cookies` is the step *type*.

## Known limitations entering Phase 5

- **Live Instagram certification is not done.** Everything up to and including the real login step
  is verified, but signing in needs a real (throwaway) account. Meta actively detects unofficial
  clients and bans are permanent.
- **Only Instagram's flows are pinned.** Facebook Messenger, WhatsApp, and Telegram are installed and
  supervised by the same code, but their flow lists were never read from a running bridge, so
  `expectedLoginFlowIDs` is empty for them and drift detection stays silent rather than asserting a
  guess.
- **iMessage reports one permission, not two.** Full Disk Access is probed by attempting the read it
  gates. Automation is only decided when the first Apple event is sent, so it is not independently
  observable and currently tracks the same signal.
- **Room discovery polls rather than listens.** Inbox+ re-reads the room list every three seconds to
  pick up portals a bridge has just created. The SDK offers a room-list listener that would make
  this event-driven; polling is what is implemented.
- **`client_http` and `webauthn` steps are modelled but not rendered.** They decode and the user is
  told plainly, rather than the login stalling on a screen Inbox+ cannot draw.
- **Still SQLite.** Phase 2's verdict was `Require PostgreSQL`, and each bridge adds another SQLite
  database. This must be revisited before any release.
