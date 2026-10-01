# Extended adapters — developer acceptance

The catalog contains five offered networks and two legacy Google bridge descriptors. X, Slack,
and LinkedIn are display-only placeholders: they appear last in Add an account, disabled with
“It's coming soon”, and have no connection implementation or downloadable artifacts.

## Current catalog

| Network | Bridge | Version | Login flows |
| --- | --- | --- | --- |
| Instagram | mautrix/meta | v0.2607.0 | `instagram` |
| Facebook Messenger | mautrix/meta | v0.2607.0 | — |
| WhatsApp | mautrix/whatsapp | v0.2607.0 | — |
| Telegram | mautrix/telegram | v0.2607.0 | — |
| iMessage | native | — | permissions probe |
| Google Messages | mautrix/gmessages | v0.2605.0 | `google` |
| Google Voice | mautrix/gvoice | v0.2605.0 | `cookies` |

Google Messages and Google Voice remain in the catalog for existing profiles but are not offered
in the picker. IRC and Google Chat are not offered. Discord and external Matrix are listed but
unavailable, with their reasons shown.

Each downloadable bridge has its own release tag and checksum. Credential styles describe the
expected setup; the login UI renders the steps returned by the provisioning protocol.

## Automated checks

```sh
swift test
swift build -c release
git diff --check
```

Check that X, Slack, and LinkedIn have no catalog descriptors, cannot start setup, and appear only
as disabled coming-soon entries. Saved records for those networks must be skipped without hiding
supported records in the same profile.

## Legacy Google adapters

```sh
for n in googleMessages googleVoice; do
  InboxPlusRuntimeCLI bridge --profile demo --action install --network "$n"
  InboxPlusRuntimeCLI bridge --profile demo --action prepare --network "$n"
done
InboxPlusRuntimeCLI start --profile demo
```

The bridges and Synapse run side by side on one profile, each with its own directory, database,
loopback port, provisioning secret, registration and supervisor.

Live account verification still requires fresh login, history import, send and receive, deep links,
offline recovery, disconnect, and removal. Only Instagram has been driven with real credentials.
