# Phase 3 Matrix client and bridge contract — developer acceptance

The reproducible sequence for accepting Phase 3: Pallo's inbox is driven by a real Matrix
homeserver rather than fixtures, and the bridge provisioning contract every Phase 4 adapter will
use is implemented and tested.

## What Phase 3 changed

Phase 1 built the app on `InMemoryMessagingGateway` with hardcoded fixtures. Phase 2 built the
supervised local Synapse runtime. The two were never connected — nothing the app displayed came
from a server.

Phase 3 fills the `MessagingGateway` seam (`Sources/PalloGateway/MessagingGateway.swift`) with a
real Matrix-backed implementation. `PalloFeatures` and `PalloUI` were not modified: the app layer
still depends only on the protocol, which is what made the swap a one-line change in
`Sources/PalloApp/PalloApp.swift`.

## Prerequisites

Same as Phase 2: macOS 15+ on Apple silicon, Swift 6.2, Homebrew CPython 3.12 at
`/opt/homebrew/opt/python@3.12/bin/python3.12`, run from the repository root.

The Matrix Rust SDK is pinned exactly at `26.08.11` and arrives as a checksum-verified 279 MB
binary xcframework, so the first `swift build` after a clean clone is slow.

## 1. Automated checks

```sh
swift test && swift build -c release && git diff --check
```

Expect 355 tests passing. Real-Synapse integration tests are opt-in:

```sh
PALLO_RUNTIME_PYTHON=/opt/homebrew/opt/python@3.12/bin/python3.12 swift test
```

That additionally runs, against a real homeserver:

| Test | Proves |
| --- | --- |
| `registeringTheSameAccountTwiceIsIdempotent` | a second launch re-authenticates instead of colliding |
| `realMatrixClientRegistersLogsInAndRestoresItsSession` | register, login, persist, and restore the same device |
| `realGatewayLoadsRoomsAndRoundTripsAMessage` | a real room, a real send, and a real server echo |

## 2. Prepare and start a runtime

```sh
swift run PalloRuntimeCLI bootstrap --profile demo \
  --python /opt/homebrew/opt/python@3.12/bin/python3.12
swift run PalloRuntimeCLI start --profile demo
```

Leave that session supervising. Note the allocated port from its `phase=healthy port=<n>` line.

## 3. Seed real conversations

Any Matrix client can populate the homeserver. The account Pallo drives is `@pallo:pallo.localhost`,
whose password is derived from the profile's registration secret — Pallo registers it on first
connect, so it exists after the app has run once.

To create conversations from a second account, register one through Synapse's shared-secret admin
endpoint, create rooms, invite `@pallo`, and send messages. Room identifiers contain `!` and `:`
and **must be percent-encoded** in request paths.

## 4. Run the app against the live runtime

```sh
PALLO_PROFILE=demo swift run -c release Pallo
```

Expect on stderr:

```
Pallo: using local Matrix runtime 'demo' on port <n>.
```

Expect in the window: the inbox lists the real rooms with their real latest-message previews,
timestamps, and unread badges. Open one and its real history appears; type a message and it sends.

Without `PALLO_PROFILE` the app prints that it is running on demo fixtures. If the named profile is
absent or not running, the app reports why and shows an empty inbox — it never presents fixture
conversations as though they were live.

## 5. Verify the acknowledgement rule by hand

Send a message and watch its state. It must appear as pending first and only become sent once the
homeserver echoes it back through sync. The design forbids showing a successful send before
acknowledgement, and the local echo is deliberately reported as `pending`.

## What Phase 3 guarantees

**Encrypted client store.** The SDK store lives under the profile at `0700`; its passphrase is
generated once and held in the macOS Keychain, never beside the data it protects. `destroy()`
removes the store, the saved session, and the Keychain key together — removing one without the
others leaves a profile that can never be opened again.

**Application services.** Synapse now emits `app_service_config_files`, so bridges can register.
`AppServiceRegistration` generates the registration with user and alias namespaces, escaping the
server name's regex metacharacters, and writes it `0600`. Registration paths flow through the same
YAML scalar validation as every other configuration value, so a hostile filename cannot inject.

**Nothing is silently dropped.** `MatrixEventNormalizer` maps every timeline event onto Pallo's
model. Undecryptable, redacted, unparseable, and unknown event types all become visible messages
with a placeholder body and a `NormalizedEventKind` describing what they were. Attachments prefer
the sender's caption, fall back to the filename, and only then to a generic label, so an attachment
is never rendered as an empty message.

**Ordering and idempotency.** Messages order by remote timestamp with the event identifier as a
stable tie-break, so bridged out-of-order events do not shuffle. Timeline diffs dedupe by event
identifier, so replayed or duplicated diffs cannot double-post.

**The bridge contract.** `PalloBridge` implements the mautrix `bridgev2` provisioning protocol —
all six step types, all ten input field types, and the display and cookie parameter shapes — taken
from the real connectors rather than invented. `DummyBridge` scripts the genuine login flows for
Instagram (cookies), WhatsApp (QR), and Telegram (phone, code, two-factor), so every view Pallo must
render is exercised without credentials or a live network. Field patterns are validated locally, so
an obviously wrong value never reaches a remote service.

## Known limitations entering Phase 4

- **New rooms appear on refresh, not live.** Message updates stream through timeline listeners, but
  a newly created room is picked up on the next `loadSnapshot()`. A room-list listener publishing
  `conversationUpserted` is needed, and lands with the bridge work, since bridges create rooms
  dynamically as conversations are discovered.
- **No contact linking against Matrix identities.** Each conversation stands for itself; the
  Phase 1 linking model is not yet wired to real remote identities.
- **Media is not rendered.** Attachments show placeholder text. Native rendering is Phase 5.
- **The sync loop does not stop on teardown.** It long-polls on a 30-second cycle for the client's
  lifetime. Tests that start sync must not depend on the process exiting promptly.
- **Still SQLite.** Phase 2's verdict was `Require PostgreSQL`; Phase 3 continues on SQLite, which
  is correct for a developer spike but must be revisited before any release.
