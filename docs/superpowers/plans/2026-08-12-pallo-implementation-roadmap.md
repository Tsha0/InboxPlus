# Pallo Implementation Roadmap

The approved Pallo design contains several independently risky subsystems. Each phase below gets its own detailed plan, implementation cycle, review, and acceptance gate. A phase may refine later sequencing, but it may not weaken the approved design without a design revision.

1. **Native vertical slice** — SwiftUI app shell, focused domain model, dummy messaging gateway, three-pane inbox, manual contact linking, contact-summary routing, exact-route sending, menu-bar lifecycle, and accessibility tests.
2. **Local Matrix runtime spike** — package and supervise loopback-only Synapse; benchmark SQLite against the design's explicit load and latency gates; select SQLite or bundled PostgreSQL; verify backup, recovery, and clean removal.
3. **Matrix client and bridge contract** — integrate Matrix Rust SDK Swift bindings, encrypted client storage, local Synapse synchronization, application-service dummy bridge, provisioning interface, capabilities, acknowledgements, and event normalization.
4. **Core adapters** — certify and ship iMessage, WhatsApp, Telegram, Instagram DMs, and Facebook Messenger behind the common adapter contract.
5. **Message and media** — native rendering, lazy cache, inline audio/video, verified deep links, unknown-event fallbacks, storage-pressure behavior, and attachment composition.
6. **Extended adapters** — certify Signal, Discord, Slack, X DMs, LinkedIn, Google Messages, Google Chat, Google Voice, external Matrix, IRC, and Bluesky chat.
7. **Production lifecycle and security** — signed service bundles, Keychain policy, launch-at-login, redacted diagnostics, atomic updater, rollback, uninstall flow, SBOM, vulnerability scanning, signing, and notarization.
8. **Release certification** — live-network black-box suite, clean-Mac installation, upgrade matrix, failure injection, performance, accessibility, website artifacts, checksums, release notes, and license inventory.

The first detailed plan is the native vertical slice. It creates testable software without prematurely coupling the UI to Synapse or a particular bridge implementation.

