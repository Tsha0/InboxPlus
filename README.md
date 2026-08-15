# Pallo

<p align="center">
  <img src="docs/assets/pallo-mascot.png" alt="Pallo, the app's blue puppy mascot" width="320">
</p>

Pallo is a local-first universal messaging inbox for macOS. It brings conversations from several
networks into one native SwiftUI app, and it does it without an operated cloud: the application, a
local Matrix homeserver, the bridge processes, your credentials, the message database and the media
cache all live on your Mac.

It is conversation-focused. There are no feeds, posts, stories or calls.

## Status

**A working development build, not a release.** On a Mac with a prepared profile it connects a real
account, loads real conversations, sends and receives, renders media, and supervises eight network
bridges alongside the homeserver.

It is not something to hand to anyone else yet. Nothing is code-signed or notarized, no network has
been certified against a live account except Instagram, and a recorded benchmark verdict from Phase
2 — `Require PostgreSQL` — has not been revisited even though the storage load has since grown. See
[`docs/testing/phase-8-release-certification.md`](docs/testing/phase-8-release-certification.md)
for the full gap list.

## Requirements

- Apple silicon Mac, macOS 15 or later
- Swift 6.2 toolchain or newer (developed against Swift 6.3 / Xcode 26.5)
- Homebrew CPython 3.12 — for the local Synapse runtime
- `cmake` (`brew install cmake`) — needed once per profile to build libolm

## Install

Build a real, double-clickable `Pallo.app` and put it in `/Applications`:

```bash
Scripts/build-app.sh --install
```

Then prepare a profile and start the runtime, which must stay running while you use Pallo:

```bash
/Applications/Pallo.app/Contents/MacOS/PalloRuntimeCLI bootstrap --profile demo \
  --python /opt/homebrew/opt/python@3.12/bin/python3.12
/Applications/Pallo.app/Contents/MacOS/PalloRuntimeCLI start --profile demo
```

Open Pallo from Finder. With exactly one prepared profile it attaches automatically; with several,
set `PALLO_PROFILE` to name one, because guessing would silently attach to the wrong account.

This build is **ad-hoc signed and runs on this Mac only**. Gatekeeper on anyone else's Mac will
refuse it — distributing to other people needs an Apple Developer ID and
`Scripts/package-release.sh`, which has never been run. See
[Phase 7](docs/testing/phase-7-lifecycle-and-security.md).

> Set `PALLO_SIGNING_IDENTITY` before building to sign with a real or self-signed certificate.
> Worth doing: macOS ties Full Disk Access and Automation grants to a code identity, and an ad-hoc
> signature's identity changes on every build — which is why permissions are re-requested after
> every rebuild.

### iMessage

iMessage is read from the local Messages database rather than bridged, so it needs a permission
rather than a password:

1. **System Settings → Privacy & Security → Full Disk Access**
2. Add `/Applications/Pallo.app`
3. **Quit and reopen Pallo** — macOS only applies the grant to a newly launched process

Sending prompts separately for Automation control of Messages the first time.

## Developing

```bash
swift build
swift test
swift run Pallo
```

With no profile configured the app runs on deterministic local fixtures and says so on stderr.
Nothing connects and no network is contacted.

To run against a real local homeserver:

```bash
# once per profile
swift run PalloRuntimeCLI bootstrap --profile demo --python /opt/homebrew/opt/python@3.12/bin/python3.12
swift run PalloRuntimeCLI bridge --profile demo --action install --network instagram
swift run PalloRuntimeCLI bridge --profile demo --action prepare --network instagram

# shell 1 — Synapse and every prepared bridge
swift run -c release PalloRuntimeCLI start --profile demo

# shell 2 — the app, attached to that profile
PALLO_PROFILE=demo swift run -c release Pallo
```

Then **Settings → Add** and pick a network. Sign in on the network's own page; Pallo captures only
the credentials the bridge declared it needs.

`swift run` produces a bare executable rather than an `.app` bundle, and macOS starts unbundled
processes as background-only — the window draws but never becomes key, so it takes no clicks and no
keyboard input. `PalloAppDelegate` promotes the process to a regular app at launch, which is what
makes the window usable. It is also why macOS re-asks for permissions on every rebuild: grants bind
to a code identity, and an ad-hoc signature's identity changes every time you build.

## Networks

Twelve networks are in the catalog. Eleven download a bridge binary pinned to an exact version and
SHA-256, verified before it is ever made executable; iMessage has nothing to download, because it
is reached through macOS itself. A bridge's own login flow is what gets rendered — Pallo never
guesses what a network will ask for.

| Network | Login | Verified |
| --- | --- | --- |
| Instagram | web sign-in | live account |
| Signal | QR pairing | flows read from a running bridge |
| Slack | token | flows read from a running bridge |
| X | web sign-in | flows read from a running bridge |
| LinkedIn | web sign-in | flows read from a running bridge |
| Google Messages | QR pairing | flows read from a running bridge |
| Google Voice | web sign-in | flows read from a running bridge |
| Bluesky | app password | flows read from a running bridge |
| Facebook Messenger | web sign-in | installs and registers |
| WhatsApp | QR pairing | installs and registers |
| Telegram | phone number | installs and registers |
| iMessage | macOS permissions | reads and sends natively |

**Only Instagram has been driven with a real account.** The rest install, register, supervise and
serve their genuine login flows; that is not the same as proven.

Four networks the design lists are deliberately absent, each for a reason the picker now shows:
Discord (its current release predates the bridge protocol Pallo speaks), Google Chat (no macOS
binary to checksum), IRC (no pinned macOS release), and external Matrix (needs multi-account
support).

> Several of these networks ban accounts for connecting with unofficial clients, and those bans are
> permanent. Use a throwaway account.

## How it fits together

```
PalloApp          the executable; chooses fixtures or a live profile at launch
  PalloUI         SwiftUI views — inbox, conversation, login engine, account management
  PalloFeatures   app model, inbox projection, contact linking, media loading
  PalloGateway    the MessagingGateway seam, media cache, in-memory fake
  PalloCore       domain model — messages, attachments, platforms, deep links
  PalloMatrix     Matrix Rust SDK, event normalization, invite policy   (SDK stays here)
  PalloBridge     bridge catalog and login protocol, as pure data
  PalloBridgeService  installer, configuration, supervision, provisioning
  PalloIMessage   the local Messages database and Apple-event sending
  PalloRuntime    Synapse bootstrap, process supervision, backups, diagnostics, SBOM
PalloRuntimeCLI   the developer tool for everything above
```

`MessagingGateway` is the seam. The app layer never imports the Matrix SDK, which is why the whole
UI runs unchanged on fixtures.

## Runtime CLI

```
bootstrap    prepare the pinned profile-local Synapse runtime
start        run Synapse and every prepared bridge, supervised
status       report lifecycle phase and health
stop         stop gracefully and verify the listener is gone
bridge       install, configure, or interrogate a network bridge
backup       checksummed offline backup of a stopped profile
restore      restore a verified backup
verify       verify the runtime, fixtures, or destructive recovery
benchmark    run the representative workload and write a redacted report
diagnostics  export a redacted bundle safe to attach to a bug report
sbom         emit the CycloneDX software bill of materials
remove       stop and remove exactly one profile, after confirmation
```

## Privacy and security

- **No operated cloud.** Nothing leaves your Mac except traffic to the networks you connect.
- **Nothing unverified is executed.** Bridges are pinned to an exact version and a SHA-256 taken
  verbatim from upstream; bytes are hashed and compared before anything is made executable.
- **Passwords go to the network, not to Pallo.** Web sign-ins load the network's real page in a
  non-persistent webview. Pallo captures only the declared credentials.
- **Secrets stay out of reach.** Configs, registrations and cached media are `0600` in `0700`
  directories; the client store passphrase lives in the Keychain.
- **Diagnostics are redacted.** `PalloRuntimeCLI diagnostics` removes tokens, cookies, message
  bodies and attachment URLs, and pseudonymises identifiers rather than deleting them, so a bundle
  is still readable. Databases and key material are never collected at all.
- **Deep links are verified.** An **Open in app** action only ever follows an `https` link on a
  domain the named platform demonstrably owns.

## Documentation

Per-phase acceptance notes, including what each phase deliberately did *not* deliver:

- [Phase 2 — local Synapse runtime](docs/testing/phase-2-runtime-acceptance.md)
- [Phase 3 — Matrix client and bridge contract](docs/testing/phase-3-matrix-acceptance.md)
- [Phase 4 — network bridges](docs/testing/phase-4-bridge-acceptance.md)
- [Phase 5 — message and media](docs/testing/phase-5-media-acceptance.md)
- [Phase 6 — extended adapters](docs/testing/phase-6-extended-adapters.md)
- [Phase 7 — lifecycle and security](docs/testing/phase-7-lifecycle-and-security.md)
- [Phase 8 — release certification](docs/testing/phase-8-release-certification.md)
- [Dependency inventory](docs/dependencies.md) and [SBOM](docs/sbom.cdx.json)

## Tests

```bash
swift test                    # 563 tests, no network, no homeserver
```

Tests that need a real Synapse are opt-in, because they are slow and download things:

```bash
PALLO_RUNTIME_PYTHON=/opt/homebrew/opt/python@3.12/bin/python3.12 swift test
```

None of them touch a real network account.

## License

[AGPL-3.0-or-later](LICENSE). Every bundled dependency is compatible; see
[`docs/dependencies.md`](docs/dependencies.md).
