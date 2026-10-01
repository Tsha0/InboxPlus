# Phase 6 extended adapters — developer acceptance

Phase 6 widens the catalog from five networks to ten. Nothing in the Phase 4 machinery changed
to make this work, which was the point of building it that way: each new network is a pinned
descriptor, not new code.

## What is in the catalog now

| Network | Bridge | Version | Login flows | Verified |
| --- | --- | --- | --- | --- |
| Instagram | mautrix/meta | v0.2607.0 | `instagram` | live account (Phase 4) |
| Facebook Messenger | mautrix/meta | v0.2607.0 | — | installs |
| WhatsApp | mautrix/whatsapp | v0.2607.0 | — | installs |
| Telegram | mautrix/telegram | v0.2607.0 | — | installs |
| iMessage | native | — | — | permissions probe |
| Slack | mautrix/slack | v0.2607.0 | `token`, `app` | flows read live |
| X | mautrix/twitter | v0.2606.0 | `cookies` | flows read live |
| LinkedIn | mautrix/linkedin | v0.2604.0 | `cookies` | flows read live |
| Google Messages | mautrix/gmessages | v0.2605.0 | `google` | flows read live |
| Google Voice | mautrix/gvoice | v0.2605.0 | `cookies` | flows read live |

Every hash is taken verbatim from the named tag's own `sha256sums.txt`, and each of the remaining
new binaries was downloaded and verified through `BridgeInstaller` — a pin that has never been
checked against real bytes is not a pin.

Each bridge carries **its own release tag**. The mautrix projects share a calendar-versioning
scheme but not a release train, so the earlier assumption of one version across all of them would
have pointed several downloads at tags that do not exist.

## 1. Automated checks

```sh
swift test && swift build -c release && git diff --check
```

Expect 491 tests passing.

## 2. Install and register every network

```sh
for n in slack x linkedIn googleMessages googleVoice; do
  MimoRuntimeCLI bridge --profile demo --action install --network "$n"
  MimoRuntimeCLI bridge --profile demo --action prepare --network "$n"
done
MimoRuntimeCLI start --profile demo
```

Network names are case-sensitive and match the `Platform` case, so it is `linkedIn`, not
`linkedin`.

Expect one healthy line per bridge:

```
bridge slack  phase=healthy port=52345 pid=… restarts=0 health=healthy
…
```

The bridges and Synapse run side by side on one profile, each with its own directory, database,
loopback port, provisioning secret, registration and supervisor.

## What Phase 6 demonstrated

**The adapter contract generalises.** Five networks were added without changing the installer, the
configuration renderer, the supervisor, the provisioning client, or the login UI. The login engine
draws whatever step a bridge returns, so Slack's token form and X's cookie form both render from
the same code that was written for Instagram.

**Bridge isolation holds under a real fault.** Discord was in the catalog when this ran, installed
and checksum-verified cleanly, then exited immediately on launch. Every other bridge came up
healthy and the homeserver was undisturbed — the failure was reported and stepped over, exactly as
the design requires. It was found by running the thing, not by reasoning about it.

**A pinned expectation is only worth what it was read from.** Five flow lists are now recorded
from live bridges rather than guessed. Facebook Messenger, WhatsApp and Telegram still have empty
lists because no one has run them, and drift detection stays silent there rather than asserting a
guess.

## What Phase 6 did not deliver

- **No network is certified.** Certification means a live account: fresh login, history import,
  send and receive, deep links, offline recovery, disconnect, removal. That needs nine accounts
  on nine networks. Only Instagram has ever been driven with real credentials, and several of
  these networks ban accounts for using unofficial clients.
- **Two networks are listed but disabled, with the reason shown.** Both are blocked on work Mimo
  could plausibly do, so hiding them would misrepresent the roadmap as the product.
  - **Discord** — the current release is still the pre-`bridgev2` architecture and does not speak
    the provisioning protocol every other bridge here uses.
  - **External Matrix** — needs multi-account support, which Mimo does not have.
- **Four networks are not offered at all.** A permanent disabled entry suggests something is
  coming; these are not.
  - **IRC** and **Google Chat** have no route. Their maintained bridges are Python and Node
    projects with no pinned macOS release, so there is nothing to verify before running one.
  - **Google Messages** and **Google Voice** were removed by decision rather than obstacle. Their
    bridges work and keep their catalog entries, so a profile that already runs one still
    attributes its conversations to the right network instead of reporting them as Matrix. They
    simply cannot be added.
- **Credential styles are Mimo's expectation, not the bridge's word.** They describe the flow in
  the picker before anything is running; what actually gets rendered is whatever the bridge returns.
