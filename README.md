# Inbox+

<p align="center">
  <img src="docs/assets/inboxplus-logo.png" alt="Inbox+ logo" width="320">
</p>

Inbox+ is a local-first universal messaging inbox for macOS. It brings conversations from several
networks into one native SwiftUI app, and it does it without an operated cloud: the application, a
local Matrix homeserver, the bridge processes, your credentials, the message database and the media
cache all live on your Mac.

It is conversation-focused. There are no feeds, posts, stories or calls.

## Status

**A working development build, not a release.** On a Mac with a prepared profile it connects a real
account, loads real conversations, sends and receives, renders media, and supervises the prepared network
bridges alongside the homeserver.

It is not something to hand to anyone else yet. Nothing is code-signed or notarized, no network has
been certified against a live account except Instagram, and a recorded benchmark verdict from Phase
2 — `Require PostgreSQL` — has not been revisited even though the storage load has since grown. See
[`docs/testing/phase-8-release-certification.md`](docs/testing/phase-8-release-certification.md)
for the full gap list.

## Development profile compatibility

The project is now **Inbox+**. The app rebrand is being developed separately; the current
`main` branch still uses `Mimo` module and executable names, `MIMO_` environment variables,
and `Mimo.app`. The commands below match that branch.

Current development builds use the app identity `com.mimo.app`, the runtime root to
`~/Library/Application Support/Mimo/DeveloperRuntime`, and the local homeserver name to
`mimo.localhost`. Existing profiles from earlier builds are not automatically migrated; prepare
a fresh Inbox+ profile using the commands below. Keep earlier profile data backed up and do not
reuse its homeserver database under the new server name. Grant macOS permissions to Inbox+ again
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

Then prepare a profile and start the runtime, which must stay running while you use Inbox+:

```bash
/Applications/Mimo.app/Contents/MacOS/MimoRuntimeCLI bootstrap --profile demo \
  --python /opt/homebrew/opt/python@3.12/bin/python3.12
/Applications/Mimo.app/Contents/MacOS/MimoRuntimeCLI start --profile demo
```

Open the installed `Mimo.app` from Finder. With exactly one prepared profile it attaches automatically; with several,
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
3. **Quit and reopen the app** — macOS only applies the grant to a newly launched process

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

# shell 1 — Synapse and every prepared bridge
swift run -c release MimoRuntimeCLI start --profile demo

# shell 2 — the app, attached to that profile
MIMO_PROFILE=demo swift run -c release Mimo
```

Then **Settings → Add** and pick a network. Sign in on the network's own page; Inbox+ captures only
the credentials the bridge declared it needs.

`swift run` produces a bare executable rather than an `.app` bundle, and macOS starts unbundled
processes as background-only — the window draws but never becomes key, so it takes no clicks and no
keyboard input. `MimoAppDelegate` promotes the process to a regular app at launch, which is what
makes the window usable. It is also why macOS re-asks for permissions on every rebuild: grants bind
to a code identity, and an ad-hoc signature's identity changes every time you build.

## Networks

Five networks can be connected. Two more — Google Messages and Google Voice — remain in the
catalog so an existing profile keeps working, but are no longer offered.

Seven networks are in the catalog in total. Six download a bridge binary pinned to an exact version and
SHA-256, verified before it is ever made executable; iMessage has nothing to download, because it
is reached through macOS itself. A bridge's own login flow is what gets rendered — Inbox+ never
guesses what a network will ask for.

| Network | Login | Verified |
| --- | --- | --- |
| Instagram | web sign-in | live account |
| Facebook Messenger | web sign-in | installs and registers |
| WhatsApp | phone number and pairing code | installs and registers |
| Telegram | phone number | installs and registers |
| iMessage | macOS permissions | reads and sends natively |

**Only Instagram has been driven with a real account.** The rest install, register, supervise and
serve their genuine login flows; that is not the same as proven.

X, Slack, and LinkedIn appear as disabled coming-soon tiles and have no connection implementation.
Two other networks are listed but disabled, with the reason shown in the picker: Discord (its current
release predates the bridge protocol Inbox+ speaks) and external Matrix (needs multi-account
support). Both are blocked on work Inbox+ could plausibly do.

Four are not offered at all. IRC and Google Chat have no route — their maintained bridges publish
no pinned macOS release, so there is nothing Inbox+ could verify before running one, and a
permanently greyed-out entry would only suggest it was coming. Google Messages and Google Voice are
out of scope by decision rather than obstacle; their bridges still work and stay in the catalog, so
a profile that already runs one keeps attributing its conversations correctly.

> Several of these networks ban accounts for connecting with unofficial clients, and those bans are
> permanent. Use a throwaway account.

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
- **Passwords go to the network, not to Inbox+.** Web sign-ins load the network's real page in a
  non-persistent webview. Inbox+ captures only the declared credentials.
- **Secrets stay out of reach.** Configs, registrations and cached media are `0600` in `0700`
  directories; the client store passphrase lives in the Keychain.
- **Diagnostics are redacted.** `MimoRuntimeCLI diagnostics` removes tokens, cookies, message
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

## Contributing

`main` is protected: it takes no direct pushes, and a change reaches it through a pull request whose
checks are green. Approvals are not required — this is a solo repository and GitHub does not let
you approve your own pull request — but CI is.

```bash
git switch -c my-change
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
swift test                    # 583 tests, no network, no homeserver
```

Tests that need a real Synapse are opt-in, because they are slow and download things:

```bash
MIMO_RUNTIME_PYTHON=/opt/homebrew/opt/python@3.12/bin/python3.12 swift test
```

None of them touch a real network account.

## License

[AGPL-3.0-or-later](LICENSE). Every bundled dependency is compatible; see
[`docs/dependencies.md`](docs/dependencies.md).
