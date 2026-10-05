# Mimo

<p align="center">
  <img src="docs/assets/mimo-mascot.png" alt="Mimo, the app's blue puppy mascot" width="320">
</p>

Mimo is a local-first universal messaging inbox for macOS. It brings conversations from several
networks into one native SwiftUI app, and it does it without an operated cloud: the application, a
local Matrix homeserver, the bridge processes, your credentials, the message database and the media
cache all live on your Mac.

It is conversation-focused. There are no feeds, posts, stories or calls.

## Status

**Current version: 0.5.0 — a working development build, not a release.** On a Mac with a
prepared profile it connects a real account, loads real conversations, sends and receives, renders
media, and supervises prepared network bridges alongside the homeserver. Opening Mimo starts the
local runtime automatically; quitting stops the runtime it started. A runtime started separately
in a terminal remains under your control.

Conversation settings and avatar updates are kept out of chat history, so syncing metadata does
not appear as messages.

It is not something to hand to anyone else yet. Local builds are ad-hoc signed but not notarized, no network has
been certified against a live account except Instagram, and a recorded benchmark verdict from Phase
2 — `Require PostgreSQL` — has not been revisited even though the storage load has since grown. See
[`docs/testing/phase-8-release-certification.md`](docs/testing/phase-8-release-certification.md)
for the full gap list.

## Development profile compatibility

This rename changes the app identity to `com.mimo.app`, the runtime root to
`~/Library/Application Support/Mimo/DeveloperRuntime`, and the local homeserver name to
`mimo.localhost`. Existing profiles from earlier builds are not automatically migrated; prepare
a fresh Mimo profile using the commands below. Keep earlier profile data backed up and do not
reuse its homeserver database under the new server name. Grant macOS permissions to Mimo again
and update development environment variables to the `MIMO_` prefix.

## Requirements

- Apple silicon Mac, macOS 15 or later
- Swift 6.2 toolchain or newer (developed against Swift 6.3 / Xcode 26.5)
- Homebrew CPython 3.12 — for the local Synapse runtime
- `cmake` (`brew install cmake`) — needed once per profile to build libolm

## Install

Build a real, double-clickable `Mimo.app` and put it in `/Applications`:

```bash
Scripts/build-app.sh --install
```

Then prepare a profile once:

```bash
/Applications/Mimo.app/Contents/MacOS/MimoRuntimeCLI bootstrap --profile demo \
  --python /opt/homebrew/opt/python@3.12/bin/python3.12
```

Open Mimo from Finder to start the homeserver and prepared bridges. With exactly one prepared
profile it attaches automatically; with several,
set `MIMO_PROFILE` to name one, because guessing would silently attach to the wrong account.

This build is **ad-hoc signed and runs on this Mac only**. Gatekeeper on anyone else's Mac will
refuse it — distributing to other people needs an Apple Developer ID and
`Scripts/package-release.sh`, which has never been run. See
[Phase 7](docs/testing/phase-7-lifecycle-and-security.md).

> Set `MIMO_SIGNING_IDENTITY` before building to sign with a real or self-signed certificate.
> Worth doing: macOS ties Full Disk Access and Automation grants to a code identity, and an ad-hoc
> signature's identity changes on every build — which is why permissions are re-requested after
> every rebuild.

### iMessage

iMessage is read from the local Messages database rather than bridged, so it needs a permission
rather than a password:

1. **System Settings → Privacy & Security → Full Disk Access**
2. Add `/Applications/Mimo.app`
3. **Quit and reopen Mimo** — macOS only applies the grant to a newly launched process

Sending prompts separately for Automation control of Messages the first time.

## Developing

```bash
swift build
swift test
swift run Mimo
```

With no profile configured the app starts with an empty inbox and contacts list.
Nothing connects and no network is contacted.

To run against a real local homeserver:

```bash
# once per profile
swift run MimoRuntimeCLI bootstrap --profile demo --python /opt/homebrew/opt/python@3.12/bin/python3.12
swift run MimoRuntimeCLI bridge --profile demo --action install --network instagram
swift run MimoRuntimeCLI bridge --profile demo --action prepare --network instagram

# launch the app; it starts Synapse and every prepared bridge
MIMO_PROFILE=demo swift run -c release Mimo
```

Then **Settings → Add** and pick a network. Follow the bridge's login flow; web sign-ins use the
network's own page, and Mimo captures only the credentials the bridge declared it needs. If adding
a bridge asks for a runtime restart, quit and reopen Mimo when the app manages the runtime.

For manual runtime control, run `swift run -c release MimoRuntimeCLI start --profile demo` in a
separate terminal before launching the app. Mimo attaches to that runtime and leaves it running
when you quit.

`swift run` produces a bare executable rather than an `.app` bundle, and macOS starts unbundled
processes as background-only — the window draws but never becomes key, so it takes no clicks and no
keyboard input. `MimoAppDelegate` promotes the process to a regular app at launch, which is what
makes the window usable. It is also why macOS re-asks for permissions on every rebuild: grants bind
to a code identity, and an ad-hoc signature's identity changes every time you build.

## Networks

Eight networks can be added. Two more — Google Messages and Google Voice — remain in the
catalog so an existing profile keeps working, but are no longer offered.

Ten networks are in the catalog in total. Nine download a bridge binary pinned to an exact version
and SHA-256, verified before it is ever made executable; iMessage has nothing to download, because it
is reached through macOS itself. A bridge's own login flow is what gets rendered — Mimo never
guesses what a network will ask for.

| Network | Login | Verified |
| --- | --- | --- |
| Instagram | web sign-in | live account |
| Slack | token | flows read from a running bridge |
| X | web sign-in | flows read from a running bridge |
| LinkedIn | web sign-in | flows read from a running bridge |
| Facebook Messenger | web sign-in | installs and registers |
| WhatsApp | QR pairing | installs and registers |
| Telegram | phone number | installs and registers |
| iMessage | macOS permissions | reads and sends natively |

**Only Instagram has been driven with a real account.** The rest install, register, supervise and
serve their genuine login flows; that is not the same as proven.

Two networks are listed but disabled, with the reason shown in the picker: Discord (its current
release predates the bridge protocol Mimo speaks) and external Matrix (needs multi-account
support). Both are blocked on work Mimo could plausibly do.

Four are not offered at all. IRC and Google Chat have no route — their maintained bridges publish
no pinned macOS release, so there is nothing Mimo could verify before running one, and a
permanently greyed-out entry would only suggest it was coming. Google Messages and Google Voice are
out of scope by decision rather than obstacle; their bridges still work and stay in the catalog, so
a profile that already runs one keeps attributing its conversations correctly.

> Several of these networks ban accounts for connecting with unofficial clients, and those bans are
> permanent. Use a throwaway account.

Bluesky and Signal support has been removed.

## How it fits together

```
MimoApp          the executable; chooses an empty inbox or a live profile at launch
  MimoUI         SwiftUI views — inbox, conversation, login engine, account management
  MimoFeatures   app model, inbox projection, contact linking, media loading
  MimoGateway    the MessagingGateway seam, media cache, in-memory fake
  MimoCore       domain model — messages, attachments, platforms, deep links
  MimoMatrix     Matrix Rust SDK, event normalization, invite policy   (SDK stays here)
  MimoBridge     bridge catalog and login protocol, as pure data
  MimoBridgeService  installer, configuration, supervision, provisioning
  MimoIMessage   the local Messages database and Apple-event sending
  MimoRuntime    Synapse bootstrap, process supervision, backups, diagnostics, SBOM
MimoRuntimeCLI   the developer tool for everything above
```

Each network is drawn with its own mark on its own brand colour, converted from
[Simple Icons](https://simpleicons.org) (CC0) into Swift vector paths at authoring time — no
bundled images, no SVG parsing at runtime. The marks are trademarks of their owners and are used to
identify networks, not to imply affiliation.

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
- **Passwords go to the network, not to Mimo.** Web sign-ins load the network's real page in a
  non-persistent webview. Mimo captures only the declared credentials.
- **Secrets stay out of reach.** Configs, registrations and cached media are `0600` in `0700`
  directories; the client store passphrase lives in the Keychain.
- **Diagnostics are redacted.** `MimoRuntimeCLI diagnostics` removes tokens, cookies, message
  bodies and attachment URLs, and pseudonymises identifiers rather than deleting them, so a bundle
  is still readable. Databases and key material are never collected at all.
- **Deep links are verified.** An **Open in app** action only ever follows an `https` link on a
  domain the named platform demonstrably owns.

## Contributing

`main` is protected: it takes no direct pushes, and a change reaches it through a pull request whose
checks are green. Approvals are not required — this is a solo repository and GitHub does not let
you approve your own pull request — but CI is.

```bash
git switch -c codex/my-change
# ...
gh pr create --fill
```

Three checks must pass before a merge is allowed:

| Check | What it protects |
| --- | --- |
| **Build and test** | The suite passes on a clean checkout, not just on the machine that wrote it |
| **Generated files are current** | The brand marks, app icon and SBOM still match the sources they are generated from |
| **Package the app** | The `.app` bundle assembles and the CLI inside it runs |

If **Generated files are current** fails, regenerate and commit:

```bash
swift Scripts/make-platform-glyphs.swift Scripts/brand-icons Sources/MimoUI/PlatformGlyphPaths.swift
swift Scripts/make-icon.swift docs/assets/mimo-mascot.png Resources/AppIcon.icns
swift run MimoRuntimeCLI sbom --output docs/sbom.cdx.json
```

CI runs on a shared, virtualised macOS runner that is markedly slower than a developer Mac. A test
that waits on a real process needs a timeout generous enough to survive that: the timeout is a
guard against hanging, not an assertion about speed, and one tuned to a fast machine turns a busy
one into a false failure.

## Tests

```bash
swift test                    # default suite; no live accounts or homeserver
```

Tests that need a real Synapse are opt-in, because they are slow and download things:

```bash
MIMO_RUNTIME_PYTHON=/opt/homebrew/opt/python@3.12/bin/python3.12 swift test
```

None of them touch a real network account.

## License

[AGPL-3.0-or-later](LICENSE). Every bundled dependency is compatible; see
[`docs/dependencies.md`](docs/dependencies.md).
